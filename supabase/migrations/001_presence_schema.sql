begin;

create extension if not exists pgcrypto with schema extensions;

create table public.prayer_sessions (
    id uuid primary key default gen_random_uuid(),
    prayer_name text not null,
    prayer_date date not null,
    timezone text not null,
    prayer_time_bucket timestamptz not null,
    opens_at timestamptz not null,
    prayer_time timestamptz not null,
    closes_at timestamptz not null,
    created_at timestamptz not null default now(),

    constraint prayer_sessions_prayer_name_check
        check (prayer_name in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
    constraint prayer_sessions_timezone_check
        check (length(timezone) between 1 and 64),
    constraint prayer_sessions_window_check
        check (opens_at < prayer_time and prayer_time < closes_at),
    constraint prayer_sessions_scope_unique
        unique (prayer_name, prayer_date, timezone, prayer_time_bucket)
);

create table public.session_presence (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references public.prayer_sessions(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    client_instance_id uuid not null,
    command_id uuid not null,
    status text not null,
    joined_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '15 minutes'),

    constraint session_presence_status_check
        check (status in ('getting_up', 'making_wudu', 'joining_saf', 'ready', 'praying')),
    constraint session_presence_expiry_check
        check (expires_at > updated_at),
    constraint session_presence_one_user_per_session
        unique (session_id, user_id),
    constraint session_presence_command_unique
        unique (user_id, command_id)
);

create index prayer_sessions_lookup_idx
    on public.prayer_sessions (prayer_name, prayer_date, timezone, prayer_time_bucket);

create index prayer_sessions_window_idx
    on public.prayer_sessions (opens_at, closes_at);

create index session_presence_active_idx
    on public.session_presence (session_id, expires_at);

create index session_presence_user_idx
    on public.session_presence (user_id, session_id);

alter table public.prayer_sessions enable row level security;
alter table public.prayer_sessions force row level security;
alter table public.session_presence enable row level security;
alter table public.session_presence force row level security;

revoke all on table public.prayer_sessions from anon, authenticated;
revoke all on table public.session_presence from anon, authenticated;

create policy "users can insert only their own presence"
on public.session_presence
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "users can delete only their own presence"
on public.session_presence
for delete
to authenticated
using ((select auth.uid()) = user_id);

commit;
