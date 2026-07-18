begin;

alter table public.profiles
add column if not exists profile_completed_at timestamptz;

drop policy if exists "profiles visible to owner and friends" on public.profiles;

create policy "completed profiles are discoverable"
on public.profiles
for select
to authenticated
using (
    id = (select auth.uid())
    or profile_completed_at is not null
);

create or replace function public.available_usernames(candidates text[])
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
    select normalized.candidate
    from (
        select lower(trim(value)) as candidate, position
        from unnest(candidates) with ordinality as input(value, position)
    ) normalized
    where (select auth.uid()) is not null
      and normalized.candidate ~ '^[a-z0-9_]{3,24}$'
      and not exists (
          select 1
          from public.profiles profile
          where profile.username = normalized.candidate
            and profile.id <> (select auth.uid())
      )
    order by normalized.position
    limit 3;
$$;

revoke all on function public.available_usernames(text[]) from public, anon;
grant execute on function public.available_usernames(text[]) to authenticated;

commit;
