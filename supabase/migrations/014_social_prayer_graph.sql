begin;

create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    username text not null,
    avatar_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint profiles_display_name_length
        check (char_length(display_name) between 1 and 48),
    constraint profiles_username_format
        check (username ~ '^[a-z0-9_]{3,24}$'),
    constraint profiles_username_unique unique (username)
);

create table public.friendships (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null references auth.users(id) on delete cascade,
    receiver_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint friendships_status_check
        check (status in ('pending', 'accepted', 'blocked')),
    constraint friendships_not_self
        check (requester_id <> receiver_id)
);

create table public.prayer_statuses (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    prayer_date date not null,
    prayer_name text not null,
    timezone text not null,
    status text not null,
    marked_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint prayer_statuses_prayer_name_check
        check (prayer_name in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
    constraint prayer_statuses_status_check
        check (status in ('preparing', 'prayed_on_time', 'prayed_later', 'not_marked', 'made_up')),
    constraint prayer_statuses_timezone_check
        check (length(timezone) between 1 and 64),
    constraint prayer_statuses_user_day_prayer_unique
        unique (user_id, prayer_date, prayer_name)
);

create table public.makeup_prayers (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    original_prayer_date date not null,
    prayer_name text not null,
    timezone text not null,
    status text not null default 'open',
    created_at timestamptz not null default now(),
    completed_at timestamptz,

    constraint makeup_prayers_prayer_name_check
        check (prayer_name in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
    constraint makeup_prayers_status_check
        check (status in ('open', 'completed')),
    constraint makeup_prayers_timezone_check
        check (length(timezone) between 1 and 64),
    constraint makeup_prayers_completed_state_check
        check ((status = 'completed') = (completed_at is not null)),
    constraint makeup_prayers_user_day_prayer_unique
        unique (user_id, original_prayer_date, prayer_name)
);

create table public.nudges (
    id uuid primary key default gen_random_uuid(),
    from_user_id uuid not null references auth.users(id) on delete cascade,
    to_user_id uuid not null references auth.users(id) on delete cascade,
    prayer_date date not null,
    prayer_name text not null,
    created_at timestamptz not null default now(),

    constraint nudges_prayer_name_check
        check (prayer_name in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
    constraint nudges_not_self
        check (from_user_id <> to_user_id),
    constraint nudges_once_per_prayer
        unique (from_user_id, to_user_id, prayer_date, prayer_name)
);

create table public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    platform text not null default 'ios',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint device_tokens_platform_check
        check (platform in ('ios')),
    constraint device_tokens_token_unique
        unique (token)
);

create index friendships_requester_idx on public.friendships (requester_id, status);
create index friendships_receiver_idx on public.friendships (receiver_id, status);
create unique index friendships_pair_unique_idx
    on public.friendships (least(requester_id, receiver_id), greatest(requester_id, receiver_id));
create index prayer_statuses_user_date_idx on public.prayer_statuses (user_id, prayer_date);
create index makeup_prayers_user_status_idx on public.makeup_prayers (user_id, status, original_prayer_date);
create index nudges_to_user_idx on public.nudges (to_user_id, created_at desc);
create index device_tokens_user_idx on public.device_tokens (user_id);

create or replace function private.are_friends(left_user_id uuid, right_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
              (f.requester_id = left_user_id and f.receiver_id = right_user_id)
              or (f.requester_id = right_user_id and f.receiver_id = left_user_id)
          )
    );
$$;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.friendships enable row level security;
alter table public.friendships force row level security;
alter table public.prayer_statuses enable row level security;
alter table public.prayer_statuses force row level security;
alter table public.makeup_prayers enable row level security;
alter table public.makeup_prayers force row level security;
alter table public.nudges enable row level security;
alter table public.nudges force row level security;
alter table public.device_tokens enable row level security;
alter table public.device_tokens force row level security;

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.friendships from anon, authenticated;
revoke all on table public.prayer_statuses from anon, authenticated;
revoke all on table public.makeup_prayers from anon, authenticated;
revoke all on table public.nudges from anon, authenticated;
revoke all on table public.device_tokens from anon, authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert, update on public.prayer_statuses to authenticated;
grant select, insert, update on public.makeup_prayers to authenticated;
grant select, insert on public.nudges to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;

create policy "profiles visible to owner and friends"
on public.profiles
for select
to authenticated
using (
    id = (select auth.uid())
    or private.are_friends((select auth.uid()), id)
);

create policy "users insert own profile"
on public.profiles
for insert
to authenticated
with check (id = (select auth.uid()));

create policy "users update own profile"
on public.profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "friendships visible to participants"
on public.friendships
for select
to authenticated
using ((select auth.uid()) in (requester_id, receiver_id));

create policy "users request friendship"
on public.friendships
for insert
to authenticated
with check (requester_id = (select auth.uid()) and status = 'pending');

create policy "participants update friendship"
on public.friendships
for update
to authenticated
using ((select auth.uid()) in (requester_id, receiver_id))
with check ((select auth.uid()) in (requester_id, receiver_id));

create policy "participants delete friendship"
on public.friendships
for delete
to authenticated
using ((select auth.uid()) in (requester_id, receiver_id));

create policy "prayer statuses visible to owner and friends"
on public.prayer_statuses
for select
to authenticated
using (
    user_id = (select auth.uid())
    or private.are_friends((select auth.uid()), user_id)
);

create policy "users insert own prayer status"
on public.prayer_statuses
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "users update own prayer status"
on public.prayer_statuses
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "makeup prayers are private"
on public.makeup_prayers
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "users insert own makeup prayers"
on public.makeup_prayers
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "users update own makeup prayers"
on public.makeup_prayers
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "nudges visible to participants"
on public.nudges
for select
to authenticated
using ((select auth.uid()) in (from_user_id, to_user_id));

create policy "friends can send nudges"
on public.nudges
for insert
to authenticated
with check (
    from_user_id = (select auth.uid())
    and private.are_friends(from_user_id, to_user_id)
);

create policy "users manage own device tokens"
on public.device_tokens
for all
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

commit;
