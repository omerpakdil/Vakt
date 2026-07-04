begin;

create or replace function private.can_access_presence_topic(topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    session_id uuid;
begin
    if (select auth.uid()) is null then
        return false;
    end if;

    if topic !~ '^saf:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        return false;
    end if;

    session_id := substring(topic from 5)::uuid;

    return exists (
        select 1
        from public.prayer_sessions ps
        where ps.id = session_id
          and now() between ps.opens_at and ps.closes_at
    );
end;
$$;

revoke execute on function private.can_access_presence_topic(text) from public, anon;
grant execute on function private.can_access_presence_topic(text) to authenticated;

drop policy if exists "authenticated users can publish Vakt presence" on realtime.messages;
drop policy if exists "authenticated users can receive Vakt presence" on realtime.messages;

create policy "authenticated users can publish Vakt presence"
on realtime.messages
for insert
to authenticated
with check (
    realtime.messages.extension = 'presence'
    and private.can_access_presence_topic((select realtime.topic()))
);

create policy "authenticated users can receive Vakt presence"
on realtime.messages
for select
to authenticated
using (
    realtime.messages.extension = 'presence'
    and private.can_access_presence_topic((select realtime.topic()))
);

commit;
