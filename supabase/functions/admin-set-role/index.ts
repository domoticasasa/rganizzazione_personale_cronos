import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    // JWT dell’admin
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) return json({ error: "Missing Authorization" }, 401);

    // Valido admin
    const supaUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );
    const { data: me } = await supaUser.auth.getUser();
    if (!me?.user) return json({ error: "Invalid token" }, 401);

    const meta = me.user.app_metadata ?? me.user.user_metadata;
    const role = String(meta?.role ?? "").toLowerCase().trim();
    const isAdmin =
      role === "admin" ||
      role === "admin_generale" ||
      role === "admin_pernottamenti" ||
      role === "admin_trenoaereo";
    if (!isAdmin) return json({ error: "Only admin" }, 403);

    // Body
    const body = await req.json();
    const authId = String(body.auth_id ?? "").trim();
    const newRole = String(body.role ?? "").trim().toLowerCase();

    if (!authId) return json({ error: "auth_id required" }, 400);
    if (!newRole) return json({ error: "role required" }, 400);

    // Client service-role
    const supaAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Aggiorna Auth (metadati ufficiali)
    const { error: updErr } = await supaAdmin.auth.admin.updateUserById(authId, {
      app_metadata: { role: newRole }
    });

    if (updErr) return json({ error: updErr.message }, 500);

    // Aggiorna anche public.users.role (se esiste)
    try {
      await supaAdmin.from("users")
        .update({ role: newRole })
        .eq("auth_id", authId);
    } catch (_) {}

    return json({ ok: true }, 200);

  } catch (e) {
    console.error("error", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders }
  });
}