import { createClient } from "jsr:@supabase/supabase-js@2";

const allowedProducts = new Set(["vakt_premium_monthly", "vakt_premium_yearly"]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return json({ error: "Unauthorized" }, 401);

    const supabaseURL = requiredSecret("SUPABASE_URL");
    const userClient = createClient(supabaseURL, requiredSecret("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authorization } },
    });
    const admin = createClient(supabaseURL, requiredSecret("SUPABASE_SERVICE_ROLE_KEY"));
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userData.user.id)}`,
      { headers: { Authorization: `Bearer ${requiredSecret("REVENUECAT_SECRET_API_KEY")}` } },
    );

    if (response.status === 404) {
      await upsertSnapshot(admin, userData.user.id, {
        product_id: null,
        entitlement_active: false,
        will_renew: false,
        purchased_at: null,
        expiration_at: null,
      });
      return json({ active: false, has_purchase_history: false });
    }
    if (!response.ok) throw new Error(`RevenueCat subscriber lookup failed (${response.status})`);

    const payload = await response.json() as RevenueCatSubscriberResponse;
    const subscriptions = Object.entries(payload.subscriber?.subscriptions ?? {})
      .filter(([productID]) => allowedProducts.has(productID));
    const now = Date.now();
    const productID = latestProduct(subscriptions);
    const product = productID ? payload.subscriber?.subscriptions?.[productID] : undefined;
    const environment = product?.is_sandbox === true ? "SANDBOX" : "PRODUCTION";
    const expiration = parseDate(product?.expires_date);
    const active = Boolean(product && (expiration === null || expiration.getTime() > now));
    const purchasedAt = earliestPurchase(subscriptions);

    await upsertSnapshot(admin, userData.user.id, {
      product_id: productID,
      entitlement_active: active,
      will_renew: Boolean(active && !product?.unsubscribe_detected_at),
      purchased_at: purchasedAt?.toISOString() ?? null,
      expiration_at: expiration?.toISOString() ?? null,
      environment,
    });

    return json({
      active,
      has_purchase_history: subscriptions.length > 0,
      product_id: productID,
      environment,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function upsertSnapshot(
  admin: ReturnType<typeof createClient>,
  userID: string,
  values: Record<string, unknown>,
) {
  const { error } = await admin.from("subscription_snapshots").upsert({
    user_id: userID,
    last_event_type: "SERVER_SYNC",
    updated_at: new Date().toISOString(),
    ...values,
  });
  if (error) throw error;
}

function latestProduct(subscriptions: Array<[string, RevenueCatSubscription]>): string | null {
  return subscriptions
    .map(([id, subscription]) => ({ id, date: parseDate(subscription.expires_date)?.getTime() ?? 0 }))
    .sort((left, right) => right.date - left.date)[0]?.id ?? null;
}

function earliestPurchase(subscriptions: Array<[string, RevenueCatSubscription]>): Date | null {
  const values = subscriptions
    .map(([, subscription]) => parseDate(subscription.purchase_date))
    .filter((date): date is Date => date !== null)
    .sort((left, right) => left.getTime() - right.getTime());
  return values[0] ?? null;
}

function parseDate(value?: string | null): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

interface RevenueCatSubscription {
  purchase_date?: string | null;
  expires_date?: string | null;
  unsubscribe_detected_at?: string | null;
  is_sandbox?: boolean;
}

interface RevenueCatSubscriberResponse {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null; product_identifier?: string }>;
    subscriptions?: Record<string, RevenueCatSubscription>;
  };
}

function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
