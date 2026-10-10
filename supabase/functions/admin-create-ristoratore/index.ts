// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

type CreateRistoratorePayload = {
  email: string;
  password?: string;
  username?: string;
  full_name?: string;
  structure_id_uuid: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ADMIN_ROLES = new Set([
  "admin",
  "admin_generale",
  "admin_pernottamenti",
  "admin_trenoaereo",
  "admin_dpi",
  "admin_formazione",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token) return json({ error: "Missing Authorization" }, 401);

    const supaUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );
    const { data: me } = await supaUser.auth.getUser();
    if (!me?.user) return json({ error: "Invalid token" }, 401);

    const meta = me.user.app_metadata ?? me.user.user_metadata;
    const callerRole = String(meta?.role ?? "").toLowerCase().trim();
    if (!ADMIN_ROLES.has(callerRole)) {
      return json({ error: "Solo admin" }, 403);
    }

    const body = (await req.json()) as CreateRistoratorePayload;
    const email = (body.email ?? "").toLowerCase().trim();
    const password = (body.password ?? "").trim();
    const fullName = (body.full_name ?? "").trim();
    const structureId = (body.structure_id_uuid ?? "").trim();
    let rawUsername = (body.username ?? "").trim();
    const ruolo = "ristoratore";

    if (!email) return json({ error: "Email required" }, 400);
    if (!structureId) return json({ error: "structure_id_uuid required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: structure } = await admin
      .from("structures")
      .select("id_uuid, name, is_ristorante, active")
      .eq("id_uuid", structureId)
      .maybeSingle();

    if (!structure?.id_uuid) {
      return json({ error: "Ristorante non trovato" }, 404);
    }
    if (structure.is_ristorante !== true) {
      return json({ error: "La struttura non è marcata come RISTORANTE" }, 400);
    }

    const slugify = (s: string) =>
      s
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9._]/g, "")
        .replace(/\.+/g, ".")
        .replace(/_+/g, "_")
        .replace(/^[_\.]+|[_\.]+$/g, "");

    async function usernameFree(u: string) {
      const { data } = await admin
        .from("users")
        .select("id")
        .eq("username", u)
        .maybeSingle();
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
          (u) => (u.email ?? "").toLowerCase() === emailLower,
        );
        if (found) return found.id;
        if (!data || data.users.length < 200) break;
      }
      return null;
    }

    let authId = (await findAuthByEmail(email)) ?? "";

    if (!authId) {
      const createRes = await admin.auth.admin.createUser({
        email,
        password: password || undefined,
        email_confirm: true,
        user_metadata: { full_name: fullName || email, role: ruolo },
        app_metadata: { role: ruolo },
      });
      if (!createRes.data?.user || createRes.error) {
        return json(
          {
            error: "Impossibile creare utente Auth",
            details: createRes.error?.message ?? "createUser failed",
          },
          500,
        );
      }
      authId = createRes.data.user.id;
    } else if (password) {
      const { error: updErr } = await admin.auth.admin.updateUserById(authId, {
        password,
        app_metadata: { role: ruolo },
      });
      if (updErr) return json({ error: updErr.message }, 500);
    } else {
      await admin.auth.admin.updateUserById(authId, {
        app_metadata: { role: ruolo },
      });
    }

    if (!rawUsername) {
      const base = fullName
        ? fullName.replace(/\s+/g, ".")
        : email.split("@")[0];
      rawUsername = await ensureUniqueUsername(base);
    } else {
      rawUsername = await ensureUniqueUsername(rawUsername);
    }

    const up = {
      auth_id: authId,
      email,
      username: rawUsername,
      full_name: fullName || email,
      role: ruolo,
      active: true,
      must_change_password: password ? true : false,
    };

    const { data: existPU } = await admin
      .from("users")
      .select("id, id_uuid")
      .eq("auth_id", authId)
      .maybeSingle();

    let userIdUuid: string;
    if (!existPU) {
      const { data: inserted, error: insErr } = await admin
        .from("users")
        .insert(up)
        .select("id_uuid")
        .single();
      if (insErr || !inserted?.id_uuid) {
        return json({ error: insErr?.message ?? "users insert failed" }, 500);
      }
      userIdUuid = inserted.id_uuid;
    } else {
      await admin.from("users").update(up).eq("auth_id", authId);
      userIdUuid = existPU.id_uuid;
    }

    const { data: existingOp } = await admin
      .from("buoni_pasto_operatori")
      .select("id_uuid")
      .eq("user_id_uuid", userIdUuid)
      .maybeSingle();

    if (existingOp?.id_uuid) {
      await admin
        .from("buoni_pasto_operatori")
        .update({ structure_id_uuid: structureId, attivo: true })
        .eq("id_uuid", existingOp.id_uuid);
    } else {
      await admin.from("buoni_pasto_operatori").insert({
        structure_id_uuid: structureId,
        user_id_uuid: userIdUuid,
        attivo: true,
      });
    }

    return json(
      {
        ok: true,
        auth_id: authId,
        user_id_uuid: userIdUuid,
        username: rawUsername,
        structure_name: structure.name,
      },
      200,
    );
  } catch (e) {
    console.error("admin-create-ristoratore error", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
