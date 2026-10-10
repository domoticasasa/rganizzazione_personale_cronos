// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type UpdatePayload = {
  personale_id: number;
  full_name?: string;
  email?: string;
  active?: boolean;
  role?: string;
  username?: string;
  password?: string;
  admin_type?: number; // legacy compatibility
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    // 0) Validazione caller (admin roles) usando il bearer token ricevuto.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Missing Authorization bearer token" }, 401);
    }
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token || token.split(".").length !== 3) {
      return json({ error: "Malformed JWT token" }, 401);
    }

    const supaUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );
    const { data: me, error: meErr } = await supaUser.auth.getUser();
    if (meErr || !me?.user) {
      return json({ error: "Invalid session" }, 401);
    }
    const { data: callerRow, error: callerErr } = await supaUser
      .from("users")
      .select("role")
      .eq("auth_id", me.user.id)
      .maybeSingle();
    const callerRole = String(callerRow?.role ?? "").trim().toLowerCase();
    const isAdmin =
      callerRole === "admin" ||
      callerRole === "admin_generale" ||
      callerRole === "admin_pernottamenti" ||
      callerRole === "admin_trenoaereo";
    if (callerErr || !callerRow || !isAdmin) {
      return json({ error: "Forbidden: only admin" }, 403);
    }

    const body = (await req.json()) as UpdatePayload;

    const personaleId = body.personale_id;
    const fullName = (body.full_name ?? "").trim();
    const email = (body.email ?? "").trim().toLowerCase();
    const active = body.active;
    const ruolo = normalizeRole((body.role ?? "").trim().toLowerCase());
    let username = (body.username ?? "").trim();
    const newPassword = (body.password ?? "").trim();

    if (!personaleId) return json({ error: "personale_id required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // -----------------------------------------------
    // 1️⃣ Recupera la riga da "personale"
    // -----------------------------------------------
    const { data: pers, error: persErr } = await admin
      .from("personale")
      .select("id_uuid, full_name, email, active, user_id")
      .eq("id", personaleId)
      .maybeSingle();

    if (persErr) return json({ error: persErr.message }, 500);
    if (!pers) return json({ error: "Personale not found" }, 404);

    const authId = pers.user_id; // può essere NULL (se non ha login)

    // -----------------------------------------------
    // 2️⃣ Update tabella personale
    // -----------------------------------------------
    const updatePersonale: any = {};
    if (fullName) updatePersonale.full_name = fullName;
    if (email) updatePersonale.email = email;
    if (active !== undefined) updatePersonale.active = active;

    if (Object.keys(updatePersonale).length > 0) {
      const { error: upPersErr } = await admin
        .from("personale")
        .update(updatePersonale)
        .eq("id", personaleId);

      if (upPersErr) return json({ error: upPersErr.message }, 500);
    }

    // -----------------------------------------------
    // Se non ha user_id → STOP (solo aggiornamento anagrafica)
    // -----------------------------------------------
    if (!authId) {
      return json({ ok: true, note: "Updated personale only (no login yet)" });
    }

    // -----------------------------------------------
    // 3️⃣ Aggiornamento in AUTH.users (se email o password cambiano)
    // -----------------------------------------------
    if (newPassword || email || fullName || ruolo) {
      const updateAuth: any = {};

      if (newPassword) updateAuth.password = newPassword;
      if (email) updateAuth.email = email;

      // Metadata
      const metadata: any = {};
      if (fullName) metadata.full_name = fullName;
      if (ruolo) metadata.role = ruolo;

      if (Object.keys(metadata).length > 0) {
        updateAuth.user_metadata = metadata;
      }

      const { error: upAuthErr } = await admin.auth.admin.updateUserById(authId, updateAuth);
      if (upAuthErr)
        return json({ error: "Auth update failed", details: upAuthErr.message }, 500);
    }

    // -----------------------------------------------
    // 4️⃣ Aggiornamento in public.users
    // -----------------------------------------------
    // Genera username unico se necessario
    const slugify = (s: string) =>
      s
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9._]/g, "")
        .replace(/\.+/g, ".")
        .replace(/_+/g, "_")
        .replace(/^[_\\.]+|[_\\.]+$/g, "");

    async function usernameFree(u: string) {
      const { data } = await admin.from("users").select("id").eq("username", u).maybeSingle();
      return !data;
    }

    async function ensureUniqueUsername(base: string) {
      const safe = slugify(base || "user") || "user";
      if (await usernameFree(safe)) return safe;
      for (let i = 1; i <= 50; i++) {
        const c = `${safe}_${i}`;
        if (await usernameFree(c)) return c;
      }
      return `user_${crypto.randomUUID().slice(0, 8)}`;
    }

    if (!username && fullName) {
      username = fullName.replace(/\s+/g, ".").toLowerCase();
    }
    if (username) {
      username = await ensureUniqueUsername(username);
    }

    const updateUsers: any = {};
    if (fullName) updateUsers.full_name = fullName;
    if (email) updateUsers.email = email;
    if (ruolo) updateUsers.role = ruolo;
    if (username) updateUsers.username = username;
    if (active !== undefined) updateUsers.active = active;
    const legacyAdminType =
      roleToLegacyAdminType(ruolo) ??
      (body.admin_type !== undefined && body.admin_type !== null
        ? Number(body.admin_type)
        : null);
    if (legacyAdminType !== null) {
      const t = Math.min(3, Math.max(1, legacyAdminType));
      updateUsers.admin_type = t;
    }

    const { error: upU } = await admin
      .from("users")
      .update(updateUsers)
      .eq("auth_id", authId);

    if (upU) return json({ error: upU.message }, 500);

    return json({ ok: true, auth_id: authId, username });
  } catch (e) {
    console.error("admin-update-employee error:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeRole(role: string): string {
  const t = role.trim().toLowerCase().replaceAll(" ", "_").replaceAll("/", "_");
  if (!t) return "";
  if (t === "admin") return "admin_generale";
  if (t === "admin_generale") return "admin_generale";
  if (t === "admin_pernottamenti") return "admin_pernottamenti";
  if (t === "admin_trenoaereo" || t === "admin_treno_aereo") {
    return "admin_trenoaereo";
  }
  if (t.includes("assistente") && t.includes("dt")) return "assistente_dt";
  return t;
}

function roleToLegacyAdminType(role: string): number | null {
  if (role === "admin_generale") return 1;
  if (role === "admin_pernottamenti") return 2;
  if (role === "admin_trenoaereo") return 3;
  return null;
}