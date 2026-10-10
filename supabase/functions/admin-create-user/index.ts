// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { insertAppActivityLog } from "../_shared/app_activity_log.ts";
import { requireAdmin } from "../_shared/require_admin.ts";

type CreatePayload = {
  email: string;
  password?: string;
  username?: string;
  full_name?: string;
  personale_id: number;
  role?: string;
  admin_type?: number; // legacy compatibility
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Sicurezza (10/10/2026): solo admin possono chiamare questa funzione.
  if (req.method !== "OPTIONS") {
    const denied = await requireAdmin(req);
    if (denied) return denied;
  }
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const body = (await req.json()) as CreatePayload;

    const email = (body.email ?? "").toLowerCase().trim();
    const password = (body.password ?? "").trim();
    const fullName = (body.full_name ?? "").trim();
    const ruolo = normalizeRole((body.role ?? "user").trim().toLowerCase());
    const personaleId = body.personale_id;
    let rawUsername = (body.username ?? "").trim();

    if (!email) return json({ error: "Email required" }, 400);
    if (!personaleId) return json({ error: "personale_id required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Helper slug for username
    const slugify = (s: string) =>
      s.toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9._]/g, "")
        .replace(/\.+/g, ".")
        .replace(/_+/g, "_")
        .replace(/^[_\.]+|[_\.]+$/g, "");

    async function usernameFree(u: string) {
      const { data } = await admin.from("users").select("id").eq("username", u).maybeSingle();
      return !data;
    }

    async function ensureUniqueUsername(base: string) {
      const safe = slugify(base || "user") || "user";
      if (await usernameFree(safe)) return safe;
      for (let i = 1; i <= 50; i++) {
        const candidate = `${safe}_${i}`;
        if (await usernameFree(candidate)) return candidate;
      }
      return `user_${crypto.randomUUID().slice(0, 8)}`;
    }

    async function findAuthByEmail(emailLower: string): Promise<string | null> {
      for (let page = 1; page <= 10; page++) {
        const { data } = await admin.auth.admin.listUsers({ page, perPage: 200 });
        const found = data?.users?.find(
          (u) => (u.email ?? "").toLowerCase() === emailLower
        );
        if (found) return found.id;
        if (!data || data.users.length < 200) break;
      }
      return null;
    }

    async function authUserExists(id: string): Promise<boolean> {
      const trimmed = (id ?? "").trim();
      if (!trimmed) return false;
      const { data, error } = await admin.auth.admin.getUserById(trimmed);
      return !error && !!data?.user;
    }

    async function clearStalePublicUserRow(emailLower: string) {
      const { data: row } = await admin
        .from("users")
        .select("id, auth_id")
        .eq("email", emailLower)
        .maybeSingle();
      if (!row?.id) return;
      const aid = (row.auth_id ?? "").toString().trim();
      if (!aid || (await authUserExists(aid))) return;
      await admin.from("users").delete().eq("id", row.id);
    }

    async function applyPassword(authId: string, pw: string): Promise<string | null> {
      if (!pw) return null;
      const { error } = await admin.auth.admin.updateUserById(authId, {
        password: pw,
      });
      return error?.message ?? null;
    }

    async function createAuthUser(): Promise<{ authId: string | null; error: string | null }> {
      const createRes = await admin.auth.admin.createUser({
        email,
        password: password || undefined,
        email_confirm: true,
        user_metadata: { full_name: fullName || email, role: ruolo },
        app_metadata: { role: ruolo },
      });

      if (createRes.data?.user && !createRes.error) {
        return { authId: createRes.data.user.id, error: null };
      }

      const errMsg = (createRes.error?.message ?? "").toLowerCase();
      const alreadyRegistered =
        errMsg.includes("already") ||
        errMsg.includes("registered") ||
        errMsg.includes("exists");

      const retryExisting = await findAuthByEmail(email);
      if (retryExisting) {
        const updErr = password ? await applyPassword(retryExisting, password) : null;
        if (updErr) return { authId: null, error: updErr };
        return { authId: retryExisting, error: null };
      }

      if (alreadyRegistered) {
        return {
          authId: null,
          error: createRes.error?.message ?? "User already registered",
        };
      }

      return {
        authId: null,
        error: createRes.error?.message ?? "createUser failed",
      };
    }

    // 1) Fonte attendibile: Auth (non public.users con auth_id obsoleto)
    await clearStalePublicUserRow(email);
    let authId = (await findAuthByEmail(email)) ?? "";

    const { data: existingPU } = await admin
      .from("users")
      .select("id, auth_id")
      .eq("email", email)
      .maybeSingle();

    if (!authId && existingPU?.auth_id) {
      const legacy = existingPU.auth_id.toString().trim();
      if (await authUserExists(legacy)) authId = legacy;
    }

    // 2) Crea in Auth se assente
    if (!authId) {
      const created = await createAuthUser();
      if (!created.authId) {
        const msg = created.error ?? "createUser failed";
        if (msg.toLowerCase().includes("already") || msg.toLowerCase().includes("registered")) {
          return json({ error: "Email già registrata in autenticazione", details: msg }, 409);
        }
        return json({ error: "Impossibile creare utente Auth", details: msg }, 500);
      }
      authId = created.authId;
    } else if (password) {
      const updErr = await applyPassword(authId, password);
      if (updErr) {
        const msg = updErr.toLowerCase();
        if (msg.includes("not found")) {
          await clearStalePublicUserRow(email);
          const created = await createAuthUser();
          if (!created.authId) {
            return json(
              { error: "auth update: User not found", details: created.error ?? updErr },
              500,
            );
          }
          authId = created.authId;
        } else {
          return json({ error: "auth update", details: updErr }, 500);
        }
      }
    }

    // 4) Username
    if (!rawUsername) {
      const base = fullName ? fullName.replace(/\s+/g, ".") : email.split("@")[0];
      rawUsername = await ensureUniqueUsername(base);
    } else {
      rawUsername = await ensureUniqueUsername(rawUsername);
    }

    // 5) Upsert public.users
    const adminType =
      roleToLegacyAdminType(ruolo) ??
      (body.admin_type != null ? Number(body.admin_type) : null);
    const up: Record<string, unknown> = {
      auth_id: authId,
      email,
      username: rawUsername,
      full_name: fullName || email,
      role: ruolo,
      active: true,
      must_change_password: password ? true : false,
    };
    if (adminType != null) {
      (up as any).admin_type = Math.min(3, Math.max(1, adminType));
    }

    const { data: exist2 } = await admin
      .from("users")
      .select("id")
      .eq("auth_id", authId)
      .maybeSingle();

    if (!exist2) await admin.from("users").insert(up);
    else await admin.from("users").update(up).eq("auth_id", authId);

    // 6) Collega personale
    await admin.from("personale").update({ user_id: authId, email }).eq("id", personaleId);

    await insertAppActivityLog({
      admin,
      authHeader: req.headers.get("Authorization"),
      action: "user_create",
      detail: ["Login", fullName || email, email, ruolo ? `ruolo ${ruolo}` : ""]
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
        .join(" · "),
    });

    return json({ ok: true, auth_id: authId, username: rawUsername }, 200);

  } catch (e) {
    console.error("admin-create-user error", e);
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
  if (t === "admin") return "admin_generale";
  if (t === "admin_generale") return "admin_generale";
  if (t === "admin_pernottamenti") return "admin_pernottamenti";
  if (t === "admin_trenoaereo" || t === "admin_treno_aereo") {
    return "admin_trenoaereo";
  }
  if (t.includes("assistente") && t.includes("dt")) return "assistente_dt";
  return t || "user";
}

function roleToLegacyAdminType(role: string): number | null {
  if (role === "admin_generale") return 1;
  if (role === "admin_pernottamenti") return 2;
  if (role === "admin_trenoaereo") return 3;
  return null;
}