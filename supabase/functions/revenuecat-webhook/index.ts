import { createClient } from "jsr:@supabase/supabase-js@2";

const allowedProducts = new Set(["vakt_premium_monthly", "vakt_premium_yearly"]);
const referralOffers = new Set(["vakt_referral_monthly_1m", "vakt_referral_yearly_1m"]);

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!isAuthorized(request)) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(requiredSecret("SUPABASE_URL"), requiredSecret("SUPABASE_SERVICE_ROLE_KEY"));

  try {
    const envelope = await request.json() as RevenueCatEnvelope;
    const event = envelope.event;
    if (!event?.id || !event.type) return json({ error: "Invalid event" }, 400);

    const stored = await admin.from("revenuecat_webhook_events").insert({
      event_id: event.id,
      event_type: event.type,
      app_user_id: event.app_user_id ?? null,
      environment: event.environment ?? null,
      transaction_id: event.transaction_id ?? null,
      original_transaction_id: event.original_transaction_id ?? null,
      product_id: event.product_id ?? null,
      offer_id: event.offer_code ?? null,
      purchased_at: isoFromMillis(event.purchased_at_ms),
      expiration_at: isoFromMillis(event.expiration_at_ms),
      payload: envelope,
    });
    if (stored.error?.code === "23505") return json({ received: true, duplicate: true });
    if (stored.error) throw stored.error;

    if (event.environment !== "PRODUCTION" || !uuid(event.app_user_id)) {
      await markProcessed(admin, event.id);
      return json({ received: true, ignored: true });
    }

    await updateSnapshot(admin, event);
    await rejectRefundedReward(admin, event);
    await createPendingReward(admin, event);
    await completeRedemption(admin, event);
    await markProcessed(admin, event.id);
    return json({ received: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function updateSnapshot(admin: ReturnType<typeof createClient>, event: RevenueCatEvent) {
  if (!event.app_user_id || !allowedProducts.has(event.product_id ?? "")) return;
  const expiration = isoFromMillis(event.expiration_at_ms);
  const expirationActive = !expiration || new Date(expiration).getTime() > Date.now();
  const inactive = event.type === "EXPIRATION" || event.type === "REFUND";
  const cancelled = event.type === "CANCELLATION";
  const { error } = await admin.from("subscription_snapshots").upsert({
    user_id: event.app_user_id,
    product_id: event.product_id,
    entitlement_active: !inactive && expirationActive,
    will_renew: !inactive && !cancelled,
    environment: "PRODUCTION",
    purchased_at: isoFromMillis(event.purchased_at_ms),
    expiration_at: expiration,
    last_event_type: event.type,
    updated_at: new Date().toISOString(),
  });
  if (error) throw error;
}

async function createPendingReward(admin: ReturnType<typeof createClient>, event: RevenueCatEvent) {
  const paidInitialPurchase = event.type === "INITIAL_PURCHASE" &&
    event.period_type === "NORMAL" &&
    (event.price_in_purchased_currency ?? event.price ?? 0) > 0 &&
    allowedProducts.has(event.product_id ?? "") &&
    (event.entitlement_ids ?? []).includes("premium") &&
    event.app_user_id && event.transaction_id;
  if (!paidInitialPurchase) return;

  const purchasedAt = isoFromMillis(event.purchased_at_ms);
  if (!purchasedAt) return;
  const { error } = await admin.rpc("register_referral_purchase", {
    input_invitee_id: event.app_user_id,
    input_source_event_id: event.id,
    input_source_transaction_id: event.transaction_id,
    input_purchased_at: purchasedAt,
  });
  if (error) throw error;
}

async function rejectRefundedReward(admin: ReturnType<typeof createClient>, event: RevenueCatEvent) {
  if (event.type !== "REFUND" || !event.app_user_id) return;
  await admin.from("referral_rewards").update({
    status: "rejected",
    rejected_reason: "source_purchase_refunded",
    updated_at: new Date().toISOString(),
  }).eq("invitee_id", event.app_user_id).in("status", ["pending", "earned", "redeeming"]);
}

async function completeRedemption(admin: ReturnType<typeof createClient>, event: RevenueCatEvent) {
  if (!event.app_user_id || !event.offer_code || !referralOffers.has(event.offer_code)) return;
  const { data: reward } = await admin.from("referral_rewards")
    .select("id")
    .eq("inviter_id", event.app_user_id)
    .eq("status", "redeeming")
    .eq("promotional_offer_id", event.offer_code)
    .order("redemption_started_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (!reward) return;
  await admin.from("referral_rewards").update({
    status: "redeemed",
    redeemed_at: new Date().toISOString(),
    redemption_event_id: event.id,
    updated_at: new Date().toISOString(),
  }).eq("id", reward.id);
}

async function markProcessed(admin: ReturnType<typeof createClient>, eventID: string) {
  await admin.from("revenuecat_webhook_events")
    .update({ processed_at: new Date().toISOString(), processing_error: null })
    .eq("event_id", eventID);
}

function isAuthorized(request: Request): boolean {
  const configured = requiredSecret("REVENUECAT_WEBHOOK_AUTH");
  const supplied = request.headers.get("Authorization") ?? "";
  return supplied === configured || supplied === `Bearer ${configured}`;
}

interface RevenueCatEnvelope { event?: RevenueCatEvent; api_version?: string }
interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id?: string;
  environment?: string;
  transaction_id?: string;
  original_transaction_id?: string;
  product_id?: string;
  entitlement_ids?: string[];
  period_type?: string;
  purchased_at_ms?: number;
  expiration_at_ms?: number;
  price?: number;
  price_in_purchased_currency?: number;
  offer_code?: string | null;
}

function uuid(value?: string): boolean {
  return Boolean(value?.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i));
}
function isoFromMillis(value?: number): string | null {
  return value ? new Date(value).toISOString() : null;
}
function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
