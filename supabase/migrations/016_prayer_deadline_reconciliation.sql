create table public.prayer_deadlines (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    prayer_date date not null,
    prayer_name text not null,
    timezone text not null,
    prayer_at timestamptz not null,
    closes_at timestamptz not null,
    state text not null default 'pending',
    resolved_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint prayer_deadlines_prayer_name_check
        check (prayer_name in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
    constraint prayer_deadlines_timezone_check
        check (length(timezone) between 1 and 64),
    constraint prayer_deadlines_state_check
        check (state in ('pending', 'prayed', 'missed')),
    constraint prayer_deadlines_order_check
        check (closes_at > prayer_at),
    constraint prayer_deadlines_resolution_check
        check ((state = 'pending') = (resolved_at is null)),
    constraint prayer_deadlines_user_day_prayer_unique
        unique (user_id, prayer_date, prayer_name)
);

create index prayer_deadlines_pending_idx
    on public.prayer_deadlines (closes_at)
    where state = 'pending';

alter table public.prayer_deadlines enable row level security;
alter table public.prayer_deadlines force row level security;

revoke all on table public.prayer_deadlines from anon, authenticated;
grant select, insert, update on table public.prayer_deadlines to authenticated;

create policy "users read own prayer deadlines"
on public.prayer_deadlines
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "users insert own prayer deadlines"
on public.prayer_deadlines
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "users update pending prayer deadlines"
on public.prayer_deadlines
for update
to authenticated
using (user_id = (select auth.uid()) and state = 'pending')
with check (user_id = (select auth.uid()));

create or replace function private.reconcile_overdue_prayer_deadlines(
    target_user_id uuid default null,
    reconciliation_time timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
    reconciled_count integer;
begin
    with overdue as (
        select deadline.*
        from public.prayer_deadlines deadline
        where deadline.state = 'pending'
          and deadline.closes_at <= reconciliation_time
          and (target_user_id is null or deadline.user_id = target_user_id)
        for update skip locked
    ), unresolved as (
        select overdue.*
        from overdue
        left join public.prayer_statuses status
          on status.user_id = overdue.user_id
         and status.prayer_date = overdue.prayer_date
         and status.prayer_name = overdue.prayer_name
        where status.id is null
           or status.status in ('preparing', 'not_marked')
    ), inserted_statuses as (
        insert into public.prayer_statuses (
            user_id, prayer_date, prayer_name, timezone, status, marked_at
        )
        select user_id, prayer_date, prayer_name, timezone, 'not_marked', reconciliation_time
        from unresolved
        on conflict (user_id, prayer_date, prayer_name)
        do update set
            status = 'not_marked',
            marked_at = excluded.marked_at,
            updated_at = now()
        where prayer_statuses.status in ('preparing', 'not_marked')
        returning user_id, prayer_date, prayer_name
    ), inserted_makeup as (
        insert into public.makeup_prayers (
            user_id, original_prayer_date, prayer_name, timezone, status, completed_at
        )
        select user_id, prayer_date, prayer_name, timezone, 'open', null
        from unresolved
        on conflict (user_id, original_prayer_date, prayer_name)
        do update set
            status = 'open',
            completed_at = null
        returning id
    ), resolved as (
        update public.prayer_deadlines deadline
        set state = case
                when exists (
                    select 1 from public.prayer_statuses status
                    where status.user_id = deadline.user_id
                      and status.prayer_date = deadline.prayer_date
                      and status.prayer_name = deadline.prayer_name
                      and status.status in ('prayed_on_time', 'prayed_later', 'made_up')
                ) then 'prayed'
                else 'missed'
            end,
            resolved_at = reconciliation_time,
            updated_at = now()
        where deadline.id in (select id from overdue)
        returning id
    )
    select count(*) into reconciled_count from resolved;

    return reconciled_count;
end;
$$;

revoke all on function private.reconcile_overdue_prayer_deadlines(uuid, timestamptz)
    from public, anon, authenticated;

create or replace function public.reconcile_my_overdue_prayers()
returns integer
language sql
security definer
set search_path = public, private
as $$
    select private.reconcile_overdue_prayer_deadlines((select auth.uid()), now());
$$;

revoke all on function public.reconcile_my_overdue_prayers() from public, anon;
grant execute on function public.reconcile_my_overdue_prayers() to authenticated;

create extension if not exists pg_cron with schema extensions;

select cron.schedule(
    'vakt-reconcile-overdue-prayers',
    '*/5 * * * *',
    $$select private.reconcile_overdue_prayer_deadlines(null, now());$$
)
where not exists (
    select 1 from cron.job where jobname = 'vakt-reconcile-overdue-prayers'
);
