import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

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

    const url = requiredSecret("SUPABASE_URL");
    const userClient = createClient(url, requiredSecret("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await userClient.auth.getUser();
    if (error || !data.user) return json({ error: "Unauthorized" }, 401);

    const body = await request.json() as { authorization_code?: string };
    if (!body.authorization_code) return json({ error: "Apple authorization is required" }, 400);

    const clientID = requiredSecret("APPLE_AUTH_CLIENT_ID");
    const clientSecret = await makeAppleClientSecret(clientID);
    const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientID,
        client_secret: clientSecret,
        code: body.authorization_code,
        grant_type: "authorization_code",
      }),
    });
    const tokens = await tokenResponse.json() as {
      refresh_token?: string;
      access_token?: string;
      error?: string;
    };
    if (!tokenResponse.ok || (!tokens.refresh_token && !tokens.access_token)) {
      return json({ error: tokens.error ?? "Apple authorization could not be validated" }, 400);
    }

    const token = tokens.refresh_token ?? tokens.access_token!;
    const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientID,
        client_secret: clientSecret,
        token,
        token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    if (!revokeResponse.ok) {
      return json({ error: "Apple sign-in authorization could not be revoked" }, 502);
    }

    const admin = createClient(url, requiredSecret("SUPABASE_SERVICE_ROLE_KEY"));
    const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
    if (deleteError) throw deleteError;

    return json({ deleted: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

async function makeAppleClientSecret(clientID: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const privateKey = requiredSecret("APPLE_AUTH_PRIVATE_KEY").replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: requiredSecret("APPLE_AUTH_KEY_ID") })
    .setIssuer(requiredSecret("APPLE_AUTH_TEAM_ID"))
    .setSubject(clientID)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt(now)
    .setExpirationTime(now + 5 * 60)
    .sign(key);
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
