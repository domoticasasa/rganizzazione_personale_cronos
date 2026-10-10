import { createClient } from "npm:@supabase/supabase-js@2";

/** Ruoli admin con permessi di scrittura (come canMutateAsAdmin in Dart). */
export const ADMIN_WRITE_ROLES = new Set([
  "admin",
  "admin_generale",
  "admin_pernottamenti",
  "admin_trenoaereo",
  "admin_treno_aereo",
  "admin_formazione",
  "admin_dpi",
]);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

/**
 * Verifica che il chiamante sia un admin con permessi di scrittura
 * (public.users.role). Ritorna una Response 401/403 se non autorizzato,
 * altrimenti null. `allowed` restringe ulteriormente i ruoli.
 */
export async function requireAdmin(
  req: Request,
  allowed: Set<string> = ADMIN_WRITE_ROLES,
): Promise<Response | null> {
  const token = (req.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: cors });
  }
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: me, error } = await admin.auth.getUser(token);
  if (error || !me?.user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: cors });
  }
  const { data: row } = await admin
    .from("users")
    .select("role")
    .eq("auth_id", me.user.id)
    .maybeSingle();
  const role = String(row?.role ?? "").trim().toLowerCase().replace(/[ /]/g, "_");
  if (!allowed.has(role)) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403, headers: cors });
  }
  return null;
}
