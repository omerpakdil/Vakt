import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { normalizePushLanguage, nudgeCopy } from "../_shared/push-localization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

let cachedToken: { value: string; expiresAt: number } | undefined;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return json({ error: "Unauthorized" }, 401);

    const supabaseURL = requiredSecret("SUPABASE_URL");
    const anonKey = requiredSecret("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredSecret("SUPABASE_SERVICE_ROLE_KEY");
    const userClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const admin = createClient(supabaseURL, serviceRoleKey);

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

    const body = await request.json() as { nudge_id?: string };
    if (!body.nudge_id) return json({ error: "nudge_id is required" }, 400);

    const { data: nudge, error: nudgeError } = await admin
      .from("nudges")
      .select("id,from_user_id,to_user_id,prayer_name")
      .eq("id", body.nudge_id)
      .single();
    if (nudgeError || !nudge) return json({ error: "Nudge not found" }, 404);
    if (nudge.from_user_id !== userData.user.id) return json({ error: "Forbidden" }, 403);

    const [{ data: sender }, { data: devices, error: devicesError }] = await Promise.all([
      admin.from("profiles").select("display_name").eq("id", nudge.from_user_id).single(),
      admin.from("device_tokens").select("id,token,language_code").eq("user_id", nudge.to_user_id),
    ]);
    if (devicesError) throw devicesError;
    if (!devices?.length) return json({ delivered: 0, reason: "no_registered_device" });

    const apnsToken = await makeAPNSToken();
    const host = Deno.env.get("APNS_ENVIRONMENT") === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
    const topic = Deno.env.get("APNS_TOPIC") ?? "com.callousity.vakt";
    let delivered = 0;
    const invalidDeviceIDs: string[] = [];
    await Promise.all(devices.map(async (device) => {
      const language = normalizePushLanguage(device.language_code);
      const payload = {
        aps: {
          alert: nudgeCopy(language, sender?.display_name, nudge.prayer_name),
          sound: "default",
          "thread-id": `vakt-${nudge.prayer_name}`,
        },
        deep_link: "prayer",
        prayer: nudge.prayer_name,
        nudge_id: nudge.id,
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

    if (delivered === 0) {
      await admin.from("nudges").delete().eq("id", nudge.id);
      return json({ error: "Notification could not be delivered" }, 502);
    }

    return json({ delivered });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function makeAPNSToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const keyID = requiredSecret("APNS_KEY_ID");
  const teamID = requiredSecret("APNS_TEAM_ID");
  const privateKey = requiredSecret("APNS_PRIVATE_KEY").replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "ES256");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
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
