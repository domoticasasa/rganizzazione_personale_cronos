import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAdmin } from "../_shared/require_admin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
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
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Helper: slugify username
    const slugify = (s: string) =>
      s.toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9._]/g, "")
        .replace(/\.+/g, ".")
        .replace(/_+/g, "_")
        .replace(/^[_\\.]+|[_\\.]+$/g, "");

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
        const c = `${safe}_${i}`;
        if (await usernameFree(c)) return c;
      }
      return `user_${crypto.randomUUID().slice(0, 8)}`;
    }

    // ---------------------------------------------------
    // 1️⃣ LEGGI TUTTI GLI UTENTI DA AUTH (MAX 2000)
    // ---------------------------------------------------
    const allAuth = [];
    for (let page = 1; page <= 10; page++) {
      const { data } = await admin.auth.admin.listUsers({
        page,
        perPage: 200,
      });
      allAuth.push(...data.users);
      if (data.users.length < 200) break;
    }

    // ---------------------------------------------------
    // 2️⃣ CREA RIGHE MANCANTI IN public.users
    // ---------------------------------------------------
    for (const au of allAuth) {
      const { data: pu } = await admin
        .from("users")
        .select("id")
        .eq("auth_id", au.id)
        .maybeSingle();

      if (!pu) {
        const base = au.raw_user_meta_data?.full_name || au.email || "user";
        const username = await ensureUniqueUsername(base.toLowerCase().replace(/\s+/g, "."));

        await admin.from("users").insert({
          auth_id: au.id,
          email: au.email,
          full_name: au.raw_user_meta_data?.full_name || au.email,
          username,
          role: au.raw_user_meta_data?.role || "user",
          active: true,
          must_change_password: false,
        });
      }
    }

    // ---------------------------------------------------
    // 3️⃣ COLLEGA personale.user_id basato su email
    // ---------------------------------------------------
    const { data: personale } = await admin.from("personale").select("*");

    for (const p of personale ?? []) {
      if (!p.email) continue;
      if (p.user_id) continue; // già collegato

      const { data: usr } = await admin
        .from("users")
        .select("auth_id")
        .eq("email", p.email.toLowerCase())
        .maybeSingle();

      if (usr?.auth_id) {
        await admin
          .from("personale")
          .update({ user_id: usr.auth_id })
          .eq("id_uuid", p.id_uuid);
      }
    }

    // ---------------------------------------------------
    // 4️⃣ RIPARA username mancanti in public.users
    // ---------------------------------------------------
    const { data: users } = await admin.from("users").select("*");

    for (const u of users ?? []) {
      if (!u.username || u.username.trim() === "") {
        const base =
          (u.full_name || u.email || "user")
            .toLowerCase()
            .replace(/\s+/g, ".") || "user";

        const username = await ensureUniqueUsername(base);

        await admin.from("users").update({ username }).eq("id", u.id);
      }
    }

    // ---------------------------------------------------
    // 5️⃣ SINCRONIZZA EMAIL TRA public.users E personale
    // ---------------------------------------------------
    for (const p of personale ?? []) {
      if (!p.user_id) continue;

      const { data: u } = await admin
        .from("users")
        .select("email")
        .eq("auth_id", p.user_id)
        .maybeSingle();

      if (u?.email && u.email !== p.email) {
        await admin.from("personale").update({ email: u.email }).eq("id_uuid", p.id_uuid);
      }
    }

    return json({ ok: true, message: "Sync completato con successo." });
  } catch (e) {
    console.error("admin-sync-users ERROR", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}