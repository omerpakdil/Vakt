-- Subscription access may only be granted through App Store purchase mechanisms.
revoke execute on function public.create_referral_campaign() from authenticated;
revoke execute on function public.claim_referral_code(text) from authenticated;
revoke execute on function public.referral_dashboard() from authenticated;
revoke execute on function public.begin_referral_redemption(uuid) from authenticated;
revoke execute on function public.cancel_referral_redemption(uuid) from authenticated;
revoke execute on function public.register_referral_purchase(uuid, text, text, timestamptz) from service_role;

update public.referral_rewards
set
    status = 'rejected',
    rejected_reason = 'program_retired_for_app_store_compliance',
    updated_at = now()
where status in ('pending', 'earned', 'redeeming');
