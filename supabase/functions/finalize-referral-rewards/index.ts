import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { normalizePushLanguage, referralRewardCopy } from "../_shared/push-localization.ts";

let cachedToken: { value: string; expiresAt: number } | undefined;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (request.headers.get("Authorization") !== `Bearer ${requiredSecret("REFERRAL_CRON_SECRET")}`) {
    return json({ error: "Unauthorized" }, 401);
  }

  const admin = createClient(requiredSecret("SUPABASE_URL"), requiredSecret("SUPABASE_SERVICE_ROLE_KEY"));
  const now = new Date().toISOString();
  await admin.from("referral_rewards").update({ status: "expired", updated_at: now })
    .eq("status", "earned").lte("expires_at", now);

  const { data: rewards, error } = await admin.from("referral_rewards")
    .update({ status: "earned", updated_at: now })
    .eq("status", "pending")
    .lte("eligible_at", now)
    .gt("expires_at", now)
    .select("id,inviter_id");
  if (error) return json({ error: error.message }, 500);

  const userIDs = [...new Set((rewards ?? []).map((reward) => reward.inviter_id))];
  if (userIDs.length) {
    const { data: devices } = await admin.from("device_tokens")
      .select("token,language_code")
      .in("user_id", userIDs);
    await Promise.all((devices ?? []).map((device) =>
      sendPush(device.token, normalizePushLanguage(device.language_code))
    ));
  }
  return json({ finalized: rewards?.length ?? 0 });
});

async function sendPush(
  deviceToken: string,
  language: ReturnType<typeof normalizePushLanguage>,
) {
  const host = Deno.env.get("APNS_ENVIRONMENT") === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await makeAPNSToken()}`,
      "apns-topic": Deno.env.get("APNS_TOPIC") ?? "com.callousity.vakt",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: referralRewardCopy(language),
        sound: "default",
        "thread-id": "vakt-referrals",
      },
      deep_link: "profile",
      event: "referral_reward_earned",
    }),
  });
}

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
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
