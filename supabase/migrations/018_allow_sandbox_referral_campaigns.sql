begin;

create or replace function public.create_referral_campaign()
returns public.referral_campaigns
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    existing public.referral_campaigns;
    created public.referral_campaigns;
    candidate text;
begin
    if current_user_id is null then
        raise exception 'unauthenticated' using errcode = '28000';
    end if;

    -- Sandbox subscriptions may create campaigns so TestFlight can exercise the
    -- referral flow. Reward creation and redemption remain production-only.
    if not exists (
        select 1 from public.subscription_snapshots s
        where s.user_id = current_user_id
          and s.entitlement_active
          and (s.expiration_at is null or s.expiration_at > now())
    ) then
        raise exception 'active_subscription_required' using errcode = '42501';
    end if;

    select * into existing
    from public.referral_campaigns c
    where c.inviter_id = current_user_id
      and c.revoked_at is null
      and c.expires_at > now()
    order by c.created_at desc
    limit 1;

    if found then return existing; end if;

    loop
        candidate := private.referral_code();
        begin
            insert into public.referral_campaigns (inviter_id, code, expires_at)
            values (current_user_id, candidate, now() + interval '30 days')
            returning * into created;
            return created;
        exception when unique_violation then
            -- Retry the extremely unlikely collision.
        end;
    end loop;
end;
$$;

revoke all on function public.create_referral_campaign() from public;
grant execute on function public.create_referral_campaign() to authenticated;

commit;
