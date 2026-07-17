import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { friendEventCopy, normalizePushLanguage } from "../_shared/push-localization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

let cachedToken: { value: string; expiresAt: number } | undefined;

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

    const body = await request.json() as { friendship_id?: string; event?: string };
    if (!body.friendship_id || !["requested", "accepted"].includes(body.event ?? "")) {
      return json({ error: "Invalid friendship event" }, 400);
    }

    const { data: friendship, error: friendshipError } = await admin
      .from("friendships")
      .select("id,requester_id,receiver_id,status")
      .eq("id", body.friendship_id)
      .single();
    if (friendshipError || !friendship) return json({ error: "Friendship not found" }, 404);

    const isRequest = body.event === "requested";
    const actorID = isRequest ? friendship.requester_id : friendship.receiver_id;
    const recipientID = isRequest ? friendship.receiver_id : friendship.requester_id;
    if (actorID !== userData.user.id) return json({ error: "Forbidden" }, 403);
    if (isRequest && friendship.status !== "pending") return json({ error: "Request is no longer pending" }, 409);
    if (!isRequest && friendship.status !== "accepted") return json({ error: "Friendship is not accepted" }, 409);

    const [{ data: actor }, { data: devices, error: devicesError }] = await Promise.all([
      admin.from("profiles").select("display_name").eq("id", actorID).single(),
      admin.from("device_tokens").select("id,token,language_code").eq("user_id", recipientID),
    ]);
    if (devicesError) throw devicesError;
    if (!devices?.length) return json({ delivered: 0, reason: "no_registered_device" });

    const apnsToken = await makeAPNSToken();
    const host = Deno.env.get("APNS_ENVIRONMENT") === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
    const topic = Deno.env.get("APNS_TOPIC") ?? "com.callousity.vakt";
    const invalidDeviceIDs: string[] = [];
    let delivered = 0;

    await Promise.all(devices.map(async (device) => {
      const language = normalizePushLanguage(device.language_code);
      const alert = friendEventCopy(
        language,
        isRequest ? "requested" : "accepted",
        actor?.display_name,
      );
      const payload = {
        aps: {
          alert,
          sound: "default",
          "thread-id": "vakt-friends",
        },
        deep_link: "circle",
        friendship_id: friendship.id,
        event: body.event,
      };
      const response = await fetch(`${host}/3/device/${device.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${apnsToken}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (response.ok) {
        delivered += 1;
        return;
      }
      const failure = await response.json().catch(() => ({})) as { reason?: string };
      if (response.status === 410 || failure.reason === "BadDeviceToken" || failure.reason === "Unregistered") {
        invalidDeviceIDs.push(device.id);
      }
    }));

    if (invalidDeviceIDs.length) {
      await admin.from("device_tokens").delete().in("id", invalidDeviceIDs);
    }
    return json({ delivered });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function makeAPNSToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;
  const key = await importPKCS8(requiredSecret("APNS_PRIVATE_KEY").replace(/\\n/g, "\n"), "ES256");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: requiredSecret("APNS_KEY_ID") })
    .setIssuer(requiredSecret("APNS_TEAM_ID"))
    .setIssuedAt(now)
    .sign(key);
  cachedToken = { value, expiresAt: now + 50 * 60 };
  return value;
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
