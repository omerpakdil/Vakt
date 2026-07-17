begin;

alter table public.profiles
add column if not exists is_prayer_status_visible boolean not null default true;

drop policy if exists "prayer statuses visible to owner and friends" on public.prayer_statuses;

create policy "prayer statuses visible to owner and permitted friends"
on public.prayer_statuses
for select
to authenticated
using (
    user_id = (select auth.uid())
    or (
        private.are_friends((select auth.uid()), user_id)
        and exists (
            select 1
            from public.profiles profile
            where profile.id = prayer_statuses.user_id
              and profile.is_prayer_status_visible = true
        )
    )
);

commit;
