// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

type Payload = {
  subscription?: {
    endpoint?: string;
    keys?: {
      p256dh?: string;
      auth?: string;
    };
  };
  user_agent?: string;
  origin?: string;
  action?: "subscribe" | "unsubscribe";
};

function isCanonicalPushOrigin(origin: string): boolean {
  const o = origin.trim().toLowerCase();
  if (!o) return false;
  try {
    const u = new URL(o);
    const h = u.hostname;
    if (h === "localhost" || h === "127.0.0.1") return true;
    if (h === "www.gestopro360.it") return true;
    return false;
  } catch {
    return false;
  }
}

function isPreviewOrNonCanonicalOrigin(origin: string): boolean {
  const o = origin.trim().toLowerCase();
  if (!o) return false;
  if (o.includes("pages.dev")) return true;
  return !isCanonicalPushOrigin(o);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return json({ error: "Missing bearer token" }, 401);

    const authClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: { Authorization: `Bearer ${jwt}` },
      },
    });
    const {
      data: { user },
      error: authErr,
    } = await authClient.auth.getUser();
    if (authErr || !user) return json({ error: "Invalid token" }, 401);

    const adminClient = createClient(supabaseUrl, serviceRole);

    const body = (await req.json()) as Payload;
    const action = String(body?.action || "subscribe").toLowerCase().trim();
    const endpoint = String(body?.subscription?.endpoint || "").trim();
    const originRaw = String(body?.origin || req.headers.get("Origin") || "")
      .trim()
      .slice(0, 300);

    if (!endpoint) return json({ error: "Missing subscription.endpoint" }, 400);

    // Logout / revoke: basta JWT valido + endpoint di QUESTO browser.
    // Non richiede resolve users (utile con 2 account / email ambigua).
    if (action === "unsubscribe") {
      await adminClient
        .from("web_push_subscriptions")
        .update({ active: false, updated_at: new Date().toISOString() })
        .eq("endpoint", endpoint);
      return json({ ok: true, action: "unsubscribe" });
    }

    // Preview Cloudflare / host non prod: non registrare (evita N toast).
    if (originRaw && isPreviewOrNonCanonicalOrigin(originRaw)) {
      await adminClient
        .from("web_push_subscriptions")
        .update({ active: false, updated_at: new Date().toISOString() })
        .eq("endpoint", endpoint);
      return json({
        ok: false,
        skipped: true,
        reason: "non_canonical_origin",
        origin: originRaw,
      });
    }

    const appUserId = await resolveAppUserId(adminClient, user);
    if (!appUserId) {
      return json(
        {
          error: "App user not found",
          hint:
            "Collega auth_id (o id_uuid) in public.users. " +
            "Con 2 account sulla stessa email non usiamo il match per email.",
        },
        404,
      );
    }

    const p256dh = String(body?.subscription?.keys?.p256dh || "").trim();
    const auth = String(body?.subscription?.keys?.auth || "").trim();
    if (!p256dh || !auth) {
      return json({ error: "Missing subscription keys" }, 400);
    }

    // Upsert per endpoint: stesso browser può passare da account A → B
    // (user_id aggiornato). Altri endpoint dello stesso user restano attivi.
    await adminClient.from("web_push_subscriptions").upsert(
      {
        user_id: appUserId,
        endpoint,
        p256dh,
        auth,
        active: true,
        user_agent: String(body?.user_agent || "").trim().slice(0, 500),
        origin: originRaw || null,
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "endpoint" },
    );

    // Pulizia: preview Cloudflare + scheda Chrome su apex (duplica la PWA www).
    await adminClient
      .from("web_push_subscriptions")
      .update({ active: false, updated_at: new Date().toISOString() })
      .eq("user_id", appUserId)
      .eq("active", true)
      .ilike("origin", "%pages.dev%");
    await adminClient
      .from("web_push_subscriptions")
      .update({ active: false, updated_at: new Date().toISOString() })
      .eq("user_id", appUserId)
      .eq("active", true)
      .ilike("origin", "https://gestopro360.it%");

    const { count } = await adminClient
      .from("web_push_subscriptions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", appUserId)
      .eq("active", true);

    return json({
      ok: true,
      action: "subscribe",
      user_id: appUserId,
      active_devices: count ?? null,
    });
  } catch (e) {
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

/**
 * Risolve public.users.id dall'auth Supabase.
 * Mai .maybeSingle() su email se ci sono 2 account (stesso utente, 2 login).
 */
async function resolveAppUserId(
  adminClient: ReturnType<typeof createClient>,
  user: { id: string; email?: string | null },
): Promise<number> {
  const { data: byAuth } = await adminClient
    .from("users")
    .select("id")
    .eq("auth_id", user.id)
    .maybeSingle();
  const authId = Number(byAuth?.id ?? 0);
  if (authId > 0) return authId;

  const { data: byUuid } = await adminClient
    .from("users")
    .select("id")
    .eq("id_uuid", user.id)
    .maybeSingle();
  const uuidId = Number(byUuid?.id ?? 0);
  if (uuidId > 0) return uuidId;

  const email = (user.email || "").trim();
  if (!email) return 0;

  const { data: rows } = await adminClient
    .from("users")
    .select("id, auth_id, id_uuid")
    .eq("email", email)
    .limit(5);

  const list = rows ?? [];
  if (list.length === 0) return 0;
  if (list.length === 1) return Number(list[0].id ?? 0);

  // Ambiguo: due (o più) righe users con la stessa email → non indovinare.
  console.error(
    "web-push-subscribe: email ambigua, collega auth_id",
    email,
    list.map((r) => r.id),
  );
  return 0;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
