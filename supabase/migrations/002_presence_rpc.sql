begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.require_authenticated_user()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    caller_id uuid := (select auth.uid());
begin
    if caller_id is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;
    return caller_id;
end;
$$;

create or replace function private.is_valid_timezone(value text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from pg_catalog.pg_timezone_names
        where name = value
    );
$$;

create or replace function public.resolve_prayer_session(
    p_prayer_name text,
    p_prayer_date date,
    p_timezone text,
    p_expected_prayer_time timestamptz
)
returns table (
    id uuid,
    prayer_name text,
    prayer_date date,
    timezone text,
    opens_at timestamptz,
    prayer_time timestamptz,
    closes_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid;
    bucket timestamptz;
begin
    caller_id := private.require_authenticated_user();

    if p_prayer_name not in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha') then
        raise exception 'invalid prayer name' using errcode = '22023';
    end if;

    if not private.is_valid_timezone(p_timezone) then
        raise exception 'invalid timezone' using errcode = '22023';
    end if;

    if (p_expected_prayer_time at time zone p_timezone)::date <> p_prayer_date then
        raise exception 'prayer date does not match timezone' using errcode = '22023';
    end if;

    if p_expected_prayer_time < now() - interval '2 hours'
       or p_expected_prayer_time > now() + interval '36 hours' then
        raise exception 'prayer time is outside the allowed window' using errcode = '22023';
    end if;

    bucket := date_bin(
        interval '15 minutes',
        p_expected_prayer_time + interval '7 minutes 30 seconds',
        timestamptz '2001-01-01 00:00:00+00'
    );

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            p_prayer_name || ':' || p_prayer_date::text || ':' || p_timezone || ':' || bucket::text,
            0
        )
    );

    insert into public.prayer_sessions (
        prayer_name,
        prayer_date,
        timezone,
        prayer_time_bucket,
        opens_at,
        prayer_time,
        closes_at
    )
    values (
        p_prayer_name,
        p_prayer_date,
        p_timezone,
        bucket,
        bucket - interval '30 minutes',
        bucket,
        bucket + interval '90 minutes'
    )
    on conflict (prayer_name, prayer_date, timezone, prayer_time_bucket) do nothing;

    return query
    select
        ps.id,
        ps.prayer_name,
        ps.prayer_date,
        ps.timezone,
        ps.opens_at,
        ps.prayer_time,
        ps.closes_at
    from public.prayer_sessions ps
    where ps.prayer_name = p_prayer_name
      and ps.prayer_date = p_prayer_date
      and ps.timezone = p_timezone
      and ps.prayer_time_bucket = bucket
    limit 1;
end;
$$;

create or replace function public.upsert_session_presence(
    p_session_id uuid,
    p_client_instance_id uuid,
    p_command_id uuid,
    p_status text
)
returns table (
    lease_id uuid,
    session_id uuid,
    status text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid;
begin
    caller_id := private.require_authenticated_user();

    if p_status not in ('getting_up', 'making_wudu', 'joining_saf', 'ready', 'praying') then
        raise exception 'invalid presence status' using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.prayer_sessions ps
        where ps.id = p_session_id
          and now() between ps.opens_at and ps.closes_at
    ) then
        raise exception 'prayer session is not open' using errcode = 'P0002';
    end if;

    insert into public.session_presence (
        session_id,
        user_id,
        client_instance_id,
        command_id,
        status,
        joined_at,
        updated_at,
        expires_at
    )
    values (
        p_session_id,
        caller_id,
        p_client_instance_id,
        p_command_id,
        p_status,
        now(),
        now(),
        now() + interval '15 minutes'
    )
    on conflict (session_id, user_id) do update
    set client_instance_id = excluded.client_instance_id,
        command_id = excluded.command_id,
        status = excluded.status,
        updated_at = now(),
        expires_at = now() + interval '15 minutes';

    return query
    select sp.id, sp.session_id, sp.status, sp.expires_at
    from public.session_presence sp
    where sp.session_id = p_session_id
      and sp.user_id = caller_id;
end;
$$;

create or replace function public.refresh_session_presence(
    p_lease_id uuid,
    p_status text
)
returns table (
    lease_id uuid,
    session_id uuid,
    status text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid;
begin
    caller_id := private.require_authenticated_user();

    if p_status not in ('getting_up', 'making_wudu', 'joining_saf', 'ready', 'praying') then
        raise exception 'invalid presence status' using errcode = '22023';
    end if;

    return query
    update public.session_presence sp
    set status = p_status,
        updated_at = now(),
        expires_at = now() + interval '15 minutes'
    from public.prayer_sessions ps
    where sp.id = p_lease_id
      and sp.user_id = caller_id
      and sp.session_id = ps.id
      and now() between ps.opens_at and ps.closes_at
      and sp.expires_at > now()
    returning sp.id, sp.session_id, sp.status, sp.expires_at;

    if not found then
        raise exception 'presence lease is unavailable' using errcode = 'P0002';
    end if;
end;
$$;

create or replace function public.leave_session_presence(p_lease_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid;
    deleted_count integer;
begin
    caller_id := private.require_authenticated_user();

    delete from public.session_presence sp
    where sp.id = p_lease_id
      and sp.user_id = caller_id;

    get diagnostics deleted_count = row_count;
    return deleted_count > 0;
end;
$$;

create or replace function public.get_session_presence_snapshot(p_session_id uuid)
returns table (
    session_id uuid,
    getting_up integer,
    making_wudu integer,
    joining_saf integer,
    ready integer,
    praying integer,
    observed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform private.require_authenticated_user();

    if not exists (select 1 from public.prayer_sessions ps where ps.id = p_session_id) then
        raise exception 'prayer session is unavailable' using errcode = 'P0002';
    end if;

    return query
    select
        p_session_id,
        count(*) filter (where sp.status = 'getting_up')::integer,
        count(*) filter (where sp.status = 'making_wudu')::integer,
        count(*) filter (where sp.status = 'joining_saf')::integer,
        count(*) filter (where sp.status = 'ready')::integer,
        count(*) filter (where sp.status = 'praying')::integer,
        now()
    from public.session_presence sp
    where sp.session_id = p_session_id
      and sp.expires_at > now();
end;
$$;

revoke execute on function private.require_authenticated_user() from public, anon;
revoke execute on function private.is_valid_timezone(text) from public, anon;
grant execute on function private.require_authenticated_user() to authenticated;
grant execute on function private.is_valid_timezone(text) to authenticated;

revoke execute on function public.resolve_prayer_session(text, date, text, timestamptz) from public, anon;
revoke execute on function public.upsert_session_presence(uuid, uuid, uuid, text) from public, anon;
revoke execute on function public.refresh_session_presence(uuid, text) from public, anon;
revoke execute on function public.leave_session_presence(uuid) from public, anon;
revoke execute on function public.get_session_presence_snapshot(uuid) from public, anon;

grant execute on function public.resolve_prayer_session(text, date, text, timestamptz) to authenticated;
grant execute on function public.upsert_session_presence(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.refresh_session_presence(uuid, text) to authenticated;
grant execute on function public.leave_session_presence(uuid) to authenticated;
grant execute on function public.get_session_presence_snapshot(uuid) to authenticated;

commit;
