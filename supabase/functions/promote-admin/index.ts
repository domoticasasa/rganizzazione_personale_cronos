import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAdmin } from "../_shared/require_admin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Payload = {
  auth_id: string;
  new_role: string;
};

Deno.serve(async (req) => {
  // Sicurezza (10/10/2026): solo admin possono chiamare questa funzione.
  if (req.method !== "OPTIONS") {
    const denied = await requireAdmin(req, new Set(["admin", "admin_generale"]));
    if (denied) return denied;
  }
  if (req.method === "OPTIONS")
    return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const body = await req.json();
    const authId = body.auth_id;
    const newRole = (body.new_role ?? "").trim().toLowerCase();

    if (!authId) return json({ error: "auth_id required" }, 400);
    if (!newRole) return json({ error: "new_role required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1) Update Auth user
    const { error: authErr } = await admin.auth.admin.updateUserById(authId, {
      user_metadata: { role: newRole },
      app_metadata: { role: newRole }
    });

    if (authErr) return json({ error: authErr.message }, 500);

    // 2) Update public.users
    await admin
      .from("users")
      .update({ role: newRole })
      .eq("auth_id", authId);

    return json({ ok: true, message: "Role updated successfully" });

  } catch (e) {
    console.error("admin-promote-admin ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(b:any, status=200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}