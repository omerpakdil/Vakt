begin;

create table public.referral_campaigns (
    id uuid primary key default gen_random_uuid(),
    inviter_id uuid not null references auth.users(id) on delete cascade,
    code text not null,
    expires_at timestamptz not null,
    created_at timestamptz not null default now(),
    revoked_at timestamptz,

    constraint referral_campaigns_code_format
        check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
    constraint referral_campaigns_code_unique unique (code),
    constraint referral_campaigns_expiry check (expires_at > created_at)
);

create table public.referral_claims (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null references public.referral_campaigns(id) on delete restrict,
    inviter_id uuid not null references auth.users(id) on delete cascade,
    invitee_id uuid not null references auth.users(id) on delete cascade,
    qualifies_for_reward boolean not null default false,
    claimed_at timestamptz not null default now(),

    constraint referral_claims_not_self check (inviter_id <> invitee_id),
    constraint referral_claims_invitee_unique unique (invitee_id)
);

create table public.referral_rewards (
    id uuid primary key default gen_random_uuid(),
    claim_id uuid not null references public.referral_claims(id) on delete restrict,
    inviter_id uuid not null references auth.users(id) on delete cascade,
    invitee_id uuid not null references auth.users(id) on delete cascade,
    source_event_id text not null,
    source_transaction_id text not null,
    status text not null default 'pending',
    eligible_at timestamptz not null,
    expires_at timestamptz not null,
    promotional_offer_id text,
    redemption_started_at timestamptz,
    redeemed_at timestamptz,
    redemption_event_id text,
    rejected_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint referral_rewards_status_check
        check (status in ('pending', 'earned', 'redeeming', 'redeemed', 'rejected', 'expired')),
    constraint referral_rewards_pair_unique unique (inviter_id, invitee_id),
    constraint referral_rewards_source_event_unique unique (source_event_id),
    constraint referral_rewards_source_transaction_unique unique (source_transaction_id),
    constraint referral_rewards_expiry check (expires_at > eligible_at)
);

create table public.subscription_snapshots (
    user_id uuid primary key references auth.users(id) on delete cascade,
    product_id text,
    entitlement_active boolean not null default false,
    will_renew boolean not null default false,
    environment text not null default 'PRODUCTION',
    purchased_at timestamptz,
    expiration_at timestamptz,
    last_event_type text,
    updated_at timestamptz not null default now(),

    constraint subscription_snapshots_environment_check
        check (environment in ('PRODUCTION', 'SANDBOX'))
);

create table public.revenuecat_webhook_events (
    event_id text primary key,
    event_type text not null,
    app_user_id text,
    environment text,
    transaction_id text,
    original_transaction_id text,
    product_id text,
    offer_id text,
    purchased_at timestamptz,
    expiration_at timestamptz,
    payload jsonb not null,
    received_at timestamptz not null default now(),
    processed_at timestamptz,
    processing_error text
);

create index referral_campaigns_inviter_idx
    on public.referral_campaigns (inviter_id, expires_at desc);
create index referral_rewards_inviter_status_idx
    on public.referral_rewards (inviter_id, status, created_at desc);
create index referral_rewards_pending_idx
    on public.referral_rewards (eligible_at)
    where status = 'pending';
create index referral_claims_inviter_idx
    on public.referral_claims (inviter_id, claimed_at desc);

alter table public.referral_campaigns enable row level security;
alter table public.referral_campaigns force row level security;
alter table public.referral_claims enable row level security;
alter table public.referral_claims force row level security;
alter table public.referral_rewards enable row level security;
alter table public.referral_rewards force row level security;
alter table public.subscription_snapshots enable row level security;
alter table public.subscription_snapshots force row level security;
alter table public.revenuecat_webhook_events enable row level security;
alter table public.revenuecat_webhook_events force row level security;

revoke all on table public.referral_campaigns from anon, authenticated;
revoke all on table public.referral_claims from anon, authenticated;
revoke all on table public.referral_rewards from anon, authenticated;
revoke all on table public.subscription_snapshots from anon, authenticated;
revoke all on table public.revenuecat_webhook_events from anon, authenticated;

grant select on table public.referral_campaigns to authenticated;
grant select on table public.referral_claims to authenticated;
grant select on table public.referral_rewards to authenticated;
grant select on table public.subscription_snapshots to authenticated;

create policy "campaign owners read campaigns"
on public.referral_campaigns for select to authenticated
using (inviter_id = (select auth.uid()));

create policy "referral participants read claims"
on public.referral_claims for select to authenticated
using ((select auth.uid()) in (inviter_id, invitee_id));

create policy "reward owners read rewards"
on public.referral_rewards for select to authenticated
using (inviter_id = (select auth.uid()));

create policy "users read own subscription snapshot"
on public.subscription_snapshots for select to authenticated
using (user_id = (select auth.uid()));

create or replace function private.referral_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result text := '';
    position integer;
begin
    for position in 1..8 loop
        result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    return result;
end;
$$;

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

    if not exists (
        select 1 from public.subscription_snapshots s
        where s.user_id = current_user_id
          and s.environment = 'PRODUCTION'
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

create or replace function public.claim_referral_code(input_code text)
returns table (
    claim_id uuid,
    inviter_id uuid,
    inviter_name text,
    inviter_username text,
    qualifies_for_reward boolean,
    friendship_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    campaign public.referral_campaigns;
    existing_claim public.referral_claims;
    created_claim public.referral_claims;
    created_friendship public.friendships;
    has_previous_subscription boolean;
begin
    if current_user_id is null then
        raise exception 'unauthenticated' using errcode = '28000';
    end if;

    select * into campaign
    from public.referral_campaigns c
    where c.code = upper(trim(input_code))
      and c.revoked_at is null
      and c.expires_at > now()
    limit 1;

    if not found then
        raise exception 'invalid_or_expired_code' using errcode = '22023';
    end if;
    if campaign.inviter_id = current_user_id then
        raise exception 'self_referral_not_allowed' using errcode = '22023';
    end if;

    select * into existing_claim
    from public.referral_claims c
    where c.invitee_id = current_user_id;
    if found then
        raise exception 'referral_already_claimed' using errcode = '23505';
    end if;

    select exists (
        select 1 from public.subscription_snapshots s
        where s.user_id = current_user_id
          and s.environment = 'PRODUCTION'
          and s.purchased_at is not null
    ) into has_previous_subscription;

    insert into public.referral_claims (
        campaign_id, inviter_id, invitee_id, qualifies_for_reward
    ) values (
        campaign.id, campaign.inviter_id, current_user_id, not has_previous_subscription
    ) returning * into created_claim;

    select * into created_friendship
    from public.friendships f
    where least(f.requester_id, f.receiver_id) = least(campaign.inviter_id, current_user_id)
      and greatest(f.requester_id, f.receiver_id) = greatest(campaign.inviter_id, current_user_id)
    limit 1;

    if not found then
        insert into public.friendships (requester_id, receiver_id, status)
        values (campaign.inviter_id, current_user_id, 'accepted')
        returning * into created_friendship;
    elsif created_friendship.status = 'pending' then
        update public.friendships
        set status = 'accepted', updated_at = now()
        where id = created_friendship.id
        returning * into created_friendship;
    elsif created_friendship.status = 'blocked' then
        raise exception 'referral_friendship_blocked' using errcode = '42501';
    end if;

    return query
    select created_claim.id, campaign.inviter_id, p.display_name, p.username,
           created_claim.qualifies_for_reward, created_friendship.id
    from public.profiles p
    where p.id = campaign.inviter_id;
end;
$$;

create or replace function public.referral_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'campaign', (
            select to_jsonb(c) from (
                select id, code, expires_at, created_at
                from public.referral_campaigns
                where inviter_id = auth.uid() and revoked_at is null and expires_at > now()
                order by created_at desc limit 1
            ) c
        ),
        'year_count', (
            select count(*) from public.referral_rewards
            where inviter_id = auth.uid()
              and status in ('pending', 'earned', 'redeeming', 'redeemed')
              and created_at >= date_trunc('year', now())
              and created_at < date_trunc('year', now()) + interval '1 year'
        ),
        'claims_waiting', (
            select count(*) from public.referral_claims c
            where c.inviter_id = auth.uid()
              and c.qualifies_for_reward
              and not exists (select 1 from public.referral_rewards r where r.claim_id = c.id)
        ),
        'rewards', coalesce((
            select jsonb_agg(to_jsonb(r) order by r.created_at desc)
            from (
                select id, invitee_id, status, eligible_at, expires_at,
                       promotional_offer_id, redeemed_at, created_at
                from public.referral_rewards
                where inviter_id = auth.uid()
            ) r
        ), '[]'::jsonb)
    );
$$;

create or replace function public.register_referral_purchase(
    input_invitee_id uuid,
    input_source_event_id text,
    input_source_transaction_id text,
    input_purchased_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    claim public.referral_claims;
    issued_count integer;
    eligible_at timestamptz;
begin
    -- Serialize rewards per inviter so concurrent RevenueCat events cannot exceed the annual cap.
    select * into claim
    from public.referral_claims c
    where c.invitee_id = input_invitee_id
      and c.qualifies_for_reward
      and c.claimed_at <= input_purchased_at
    for update;

    if not found then return false; end if;

    perform pg_advisory_xact_lock(hashtextextended(claim.inviter_id::text, 0));

    select count(*) into issued_count
    from public.referral_rewards r
    where r.inviter_id = claim.inviter_id
      and r.status in ('pending', 'earned', 'redeeming', 'redeemed')
      and r.created_at >= date_trunc('year', input_purchased_at)
      and r.created_at < date_trunc('year', input_purchased_at) + interval '1 year';

    if issued_count >= 6 then return false; end if;

    eligible_at := greatest(now(), input_purchased_at) + interval '7 days';

    insert into public.referral_rewards (
        claim_id, inviter_id, invitee_id, source_event_id,
        source_transaction_id, status, eligible_at, expires_at
    ) values (
        claim.id, claim.inviter_id, claim.invitee_id, input_source_event_id,
        input_source_transaction_id, 'pending', eligible_at,
        eligible_at + interval '24 months'
    )
    on conflict do nothing;

    return found;
end;
$$;

create or replace function public.begin_referral_redemption(reward_id uuid)
returns table (id uuid, product_id text, promotional_offer_id text)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    reward public.referral_rewards;
    snapshot public.subscription_snapshots;
    offer_id text;
begin
    if current_user_id is null then
        raise exception 'unauthenticated' using errcode = '28000';
    end if;

    update public.referral_rewards
    set status = 'earned', redemption_started_at = null, updated_at = now()
    where inviter_id = current_user_id and status = 'redeeming'
      and redemption_started_at < now() - interval '15 minutes';

    select * into reward from public.referral_rewards r
    where r.id = reward_id and r.inviter_id = current_user_id for update;
    if not found or reward.status <> 'earned' or reward.expires_at <= now() then
        raise exception 'reward_not_redeemable' using errcode = '22023';
    end if;
    if exists (
        select 1 from public.referral_rewards r
        where r.inviter_id = current_user_id and r.status = 'redeeming'
    ) then
        raise exception 'another_reward_is_redeeming' using errcode = '55000';
    end if;

    select * into snapshot from public.subscription_snapshots s
    where s.user_id = current_user_id and s.environment = 'PRODUCTION';
    if not found
       or not snapshot.entitlement_active
       or (snapshot.expiration_at is not null and snapshot.expiration_at <= now())
       or snapshot.product_id not in ('vakt_premium_monthly', 'vakt_premium_yearly') then
        raise exception 'eligible_subscription_required' using errcode = '42501';
    end if;

    offer_id := case snapshot.product_id
        when 'vakt_premium_monthly' then 'vakt_referral_monthly_1m'
        else 'vakt_referral_yearly_1m'
    end;

    update public.referral_rewards as r
    set status = 'redeeming', promotional_offer_id = offer_id,
        redemption_started_at = now(), updated_at = now()
    where r.id = reward.id;

    return query select reward.id, snapshot.product_id, offer_id;
end;
$$;

create or replace function public.cancel_referral_redemption(reward_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    update public.referral_rewards
    set status = 'earned', redemption_started_at = null, updated_at = now()
    where id = reward_id and inviter_id = auth.uid() and status = 'redeeming';
$$;

revoke all on function public.create_referral_campaign() from public;
revoke all on function public.claim_referral_code(text) from public;
revoke all on function public.referral_dashboard() from public;
revoke all on function public.register_referral_purchase(uuid, text, text, timestamptz) from public;
revoke all on function public.begin_referral_redemption(uuid) from public;
revoke all on function public.cancel_referral_redemption(uuid) from public;
grant execute on function public.create_referral_campaign() to authenticated;
grant execute on function public.claim_referral_code(text) to authenticated;
grant execute on function public.referral_dashboard() to authenticated;
grant execute on function public.register_referral_purchase(uuid, text, text, timestamptz) to service_role;
grant execute on function public.begin_referral_redemption(uuid) to authenticated;
grant execute on function public.cancel_referral_redemption(uuid) to authenticated;

commit;
