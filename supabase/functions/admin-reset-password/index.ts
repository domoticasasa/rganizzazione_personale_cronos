import { createClient } from "npm:@supabase/supabase-js@2";
import {
  clientIp,
  corsHeaders,
  json,
  sendPasswordResetEmail,
} from "../_shared/send_password_reset.ts";

const ADMIN_ROLES = new Set([
  "admin",
  "admin_generale",
  "admin_pernottamenti",
  "admin_trenoaereo",
]);

// Solo admin (prima bastava un JWT valido qualsiasi). Stesso flusso e stesso
// redirect fisso (/password-recovery) del reset self-service.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "unauthorized" }, 401);

    const supaUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );
    const { data: me, error: meErr } = await supaUser.auth.getUser();
    if (meErr || !me?.user) return json({ error: "unauthorized" }, 401);
    const { data: row } = await supaUser
      .from("users")
      .select("role")
      .eq("auth_id", me.user.id)
      .maybeSingle();
    const role = String(row?.role ?? "").trim().toLowerCase();
    if (!ADMIN_ROLES.has(role)) return json({ error: "forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    return await sendPasswordResetEmail({
      email: String(body?.email ?? ""),
      ip: clientIp(req),
    });
  } catch (e) {
    console.error("admin-reset-password ERROR:", e);
    return json({ error: "unexpected_error" }, 500);
  }
});
