import { createClient } from "npm:@supabase/supabase-js@2";
import { insertAppActivityLog } from "../_shared/app_activity_log.ts";
import { requireAdmin } from "../_shared/require_admin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Sicurezza (10/10/2026): solo admin possono chiamare questa funzione.
  if (req.method !== "OPTIONS") {
    const denied = await requireAdmin(req);
    if (denied) return denied;
  }
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const authId = (body.auth_id ?? "").toString().trim();
    const personaleId = body.personale_id;

    if (!authId) return json({ error: "auth_id required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let targetName = "";
    let targetEmail = "";
    if (personaleId != null && `${personaleId}`.trim() !== "") {
      const { data: p } = await admin
        .from("personale")
        .select("full_name, email")
        .eq("id", personaleId)
        .maybeSingle();
      targetName = String(p?.full_name ?? "").trim();
      targetEmail = String(p?.email ?? "").trim();
    }
    if (!targetName || !targetEmail) {
      const { data: u } = await admin
        .from("users")
        .select("full_name, email")
        .eq("auth_id", authId)
        .maybeSingle();
      if (!targetName) targetName = String(u?.full_name ?? "").trim();
      if (!targetEmail) targetEmail = String(u?.email ?? "").trim();
    }

    // 1) Scollega / elimina personale collegato
    const { error: unlinkErr } = await admin
      .from("personale")
      .update({ user_id: null })
      .eq("user_id", authId);
    if (unlinkErr) {
      console.error("unlink personale by user_id:", unlinkErr.message);
    }

    if (personaleId != null && `${personaleId}`.trim() !== "") {
      const { error: delPersErr } = await admin
        .from("personale")
        .delete()
        .eq("id", personaleId);
      if (delPersErr) {
        console.error("delete personale:", delPersErr.message);
      }
    }

    // 2) Cancella public.users (+ device_tokens che referenziano users.id)
    const { data: userRow } = await admin
      .from("users")
      .select("id")
      .eq("auth_id", authId)
      .maybeSingle();
    if (userRow?.id != null) {
      await admin.from("device_tokens").delete().eq("user_id", userRow.id);
    }

    const { error: delUsersErr, count } = await admin
      .from("users")
      .delete({ count: "exact" })
      .eq("auth_id", authId);
    if (delUsersErr) {
      return json({ error: `users delete: ${delUsersErr.message}` }, 500);
    }

    // 3) Cancella utente Auth (ok anche se già assente)
    const { error: delErr } = await admin.auth.admin.deleteUser(authId);
    if (delErr && !/not found|user not found/i.test(delErr.message ?? "")) {
      return json({ error: delErr.message }, 500);
    }

    const detail = [targetName, targetEmail].filter((s) => s.length > 0).join(" · ")
      || authId;
    await insertAppActivityLog({
      admin,
      authHeader: req.headers.get("Authorization"),
      action: "user_delete",
      detail,
    });

    return json({
      ok: true,
      message: "User deleted successfully",
      users_deleted: count ?? 0,
    });
  } catch (e) {
    console.error("admin-delete-user ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
