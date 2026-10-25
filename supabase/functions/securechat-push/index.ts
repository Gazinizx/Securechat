import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function googleAccessToken(account: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = encodeJson({ alg: "RS256", typ: "JWT" });
  const claim = encodeJson({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: account.token_uri || "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const unsigned = header + "." + claim;
  const pem = account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = unsigned + "." + base64Url(signature);
  const tokenResponse = await fetch(account.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenJson = await tokenResponse.json();
  if (!tokenResponse.ok || typeof tokenJson.access_token !== "string") {
    throw new Error("Google OAuth token request failed: " + JSON.stringify(tokenJson));
  }
  return tokenJson.access_token;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  try {
    const authHeader = request.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "content-type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const accountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!accountRaw) throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON secret is missing");

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "content-type": "application/json" } });

    const body = await request.json();
    const receiverId = String(body.receiver_id || "");
    const conversationId = String(body.conversation_id || "");
    const kind = String(body.kind || "");
    if (!receiverId || !conversationId || !["message", "call"].includes(kind) || receiverId === user.id) {
      return new Response(JSON.stringify({ error: "Invalid request" }), { status: 400, headers: { ...corsHeaders, "content-type": "application/json" } });
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: members, error: memberError } = await admin
      .from("conversation_members").select("user_id").eq("conversation_id", conversationId).in("user_id", [user.id, receiverId]);
    if (memberError) throw memberError;
    const memberIds = new Set((members || []).map((row: { user_id: string }) => row.user_id));
    if (!memberIds.has(user.id) || !memberIds.has(receiverId)) {
      return new Response(JSON.stringify({ error: "Not a member of this conversation" }), { status: 403, headers: { ...corsHeaders, "content-type": "application/json" } });
    }

    const { data: tokens, error: tokenError } = await admin.from("push_tokens").select("token,platform").eq("user_id", receiverId);
    if (tokenError) throw tokenError;
    if (!tokens?.length) return new Response(JSON.stringify({ sent: 0, reason: "No registered devices" }), { status: 200, headers: { ...corsHeaders, "content-type": "application/json" } });

    const account = JSON.parse(accountRaw) as Record<string, string>;
    const accessToken = await googleAccessToken(account);
    const projectId = account.project_id;
    if (!projectId) throw new Error("Firebase service account project_id is missing");
    const title = kind === "call" ? "Gelen arama" : "Securechat";
    const messageBody = kind === "call"
      ? (body.video === true ? "Görüntülü arama" : "Sesli arama")
      : "Yeni şifreli mesaj";
    let sent = 0;
    const invalidTokens: string[] = [];
    for (const row of tokens as Array<{ token: string; platform: string }>) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
        body: JSON.stringify({
          message: {
            token: row.token,
            notification: { title, body: messageBody },
            data: { kind, conversation_id: conversationId, sender_id: user.id, receiver_id: receiverId, video: String(body.video === true) },
            android: { priority: "HIGH", notification: { channel_id: "securechat_messages", sound: "default", priority: "HIGH" } },
            apns: { headers: { "apns-priority": "10" }, payload: { aps: { alert: { title, body: messageBody }, sound: "default", badge: 1, "content-available": 1 } } },
          },
        }),
      });
      const responseBody = await response.json().catch(() => ({}));
      if (response.ok) sent++;
      else {
        const errorText = JSON.stringify(responseBody);
        if (errorText.includes("UNREGISTERED") || errorText.includes("registration-token-not-registered")) invalidTokens.push(row.token);
        console.error("FCM delivery failed:", response.status, errorText);
      }
    }
    if (invalidTokens.length) await admin.from("push_tokens").delete().in("token", invalidTokens);
    return new Response(JSON.stringify({ sent, attempted: tokens.length }), { status: 200, headers: { ...corsHeaders, "content-type": "application/json" } });
  } catch (error) {
    console.error("securechat-push failed:", error);
    return new Response(JSON.stringify({ error: "Push delivery failed" }), { status: 500, headers: { ...corsHeaders, "content-type": "application/json" } });
  }
});
