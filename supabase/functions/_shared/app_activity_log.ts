import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Registra create/delete utente nel Log app, con chi ha chiamato la function. */
export async function insertAppActivityLog(opts: {
  admin: SupabaseClient;
  authHeader: string | null;
  action: string;
  detail: string;
}): Promise<void> {
  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const token = (opts.authHeader ?? "").replace(/^Bearer\s+/i, "").trim();

    let authId: string | null = null;
    let userId: number | null = null;
    let fullName = "";
    let username = "";
    let role = "";

    if (url && anon && token.split(".").length === 3) {
      const asUser = createClient(url, anon, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data } = await asUser.auth.getUser();
      authId = data.user?.id ?? null;
      if (authId) {
        const { data: row } = await opts.admin
          .from("users")
          .select("id, full_name, username, role")
          .eq("auth_id", authId)
          .maybeSingle();
        if (row) {
          userId = Number(row.id) || null;
          fullName = String(row.full_name ?? "").trim();
          username = String(row.username ?? "").trim();
          role = String(row.role ?? "").trim();
        }
      }
    }

    await opts.admin.from("app_activity_logs").insert({
      user_id: userId,
      auth_id: authId,
      full_name: fullName || "Sconosciuto",
      username,
      role,
      action: opts.action,
      detail: opts.detail,
    });
  } catch (e) {
    console.error("insertAppActivityLog", e);
  }
}
