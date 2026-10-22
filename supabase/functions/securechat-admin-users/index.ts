import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const respond = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond(405, { error: "Method not allowed" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return respond(500, { error: "Server auth configuration is missing" });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return respond(401, { error: "Authentication required" });
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await userClient.auth.getUser(authHeader.slice(7));
  if (userError || !userData.user) return respond(401, { error: "Invalid session" });

  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: adminRow, error: adminError } = await adminClient.schema("private").from("app_admins").select("user_id").eq("user_id", userData.user.id).maybeSingle();
  if (adminError || !adminRow) return respond(403, { error: "Administrator permission required" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return respond(400, { error: "Invalid JSON body" }); }
  const action = body.action;
  const username = typeof body.username === "string" ? body.username.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const userId = typeof body.user_id === "string" ? body.user_id : "";

  if (action === "create") {
    if (!/^[a-z0-9_]{3,32}$/.test(username)) return respond(400, { error: "Username must be 3-32 chars: a-z, 0-9, underscore" });
    if (password.length < 10) return respond(400, { error: "New passwords must be at least 10 characters" });
    const { data: existing } = await adminClient.from("profiles").select("id").eq("username", username).maybeSingle();
    if (existing) return respond(409, { error: "Username already exists" });
    const { data, error } = await adminClient.auth.admin.createUser({ email: username + "@securechat.invalid", password, email_confirm: true, user_metadata: { username } });
    if (error || !data.user) return respond(400, { error: error?.message ?? "Could not create account" });
    return respond(200, { user_id: data.user.id, username });
  }
  if (action === "delete") {
    if (!userId || userId === userData.user.id) return respond(400, { error: "Specify another user; deleting the current administrator is not allowed" });
    const { error } = await adminClient.auth.admin.deleteUser(userId);
    if (error) return respond(400, { error: error.message });
    return respond(200, { deleted: true });
  }
  if (action === "change_password") {
    if (password.length < 10) return respond(400, { error: "New passwords must be at least 10 characters" });
    const targetId = userId || userData.user.id;
    if (targetId !== userData.user.id) {
      const { data: target } = await adminClient.auth.admin.getUserById(targetId);
      if (!target.user) return respond(404, { error: "User not found" });
    }
    const { error } = await adminClient.auth.admin.updateUserById(targetId, { password });
    if (error) return respond(400, { error: error.message });
    return respond(200, { updated: true });
  }
  return respond(400, { error: "Unsupported action" });
});
