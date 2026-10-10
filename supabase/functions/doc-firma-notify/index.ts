// Web Push (best effort) — stesso pattern di admin-send-notification / app-chat-notify.
// Notifica destinatari all'invio di un documento da firmare (in-app + Web Push).
// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
import { shouldSkipWebPushOrigin } from "../_shared/web_push_origin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return json({ error: "Missing bearer token" }, 401);

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const {
      data: { user },
      error: authErr,
    } = await authClient.auth.getUser();
    if (authErr || !user) return json({ error: "Invalid token" }, 401);

    const admin = createClient(supabaseUrl, serviceRole);
    const { data: me } = await admin
      .from("users")
      .select("id, role")
      .eq("auth_id", user.id)
      .maybeSingle();
    if (!me) return json({ error: "User not found" }, 404);

    const role = String(me.role || "").toLowerCase().replace(/\s+/g, "_");
    const isAdmin = [
      "admin",
      "admin_generale",
      "admin_vista",
      "admin_pernottamenti",
      "admin_trenoaereo",
      "admin_dpi",
      "admin_formazione",
      "dt",
      "assistente_dt",
      "uqsa",
    ].includes(role);
    if (!isAdmin) return json({ error: "Forbidden" }, 403);

    const body = await req.json();
    const title = String(body?.title || "Documento da firmare").trim();
    const message = String(
      body?.message ||
        "Hai ricevuto un documento da firmare. Hai 3 giorni (OTP via email).",
    ).trim();
    const userIds = (Array.isArray(body?.user_ids) ? body.user_ids : [])
      .map((v: unknown) => Number(v))
      .filter((n: number) => Number.isFinite(n) && n > 0);
    const batchId = String(body?.batch_id || "").trim();

    if (!userIds.length) return json({ error: "user_ids required" }, 400);

    // Notifica in-app: gestita dal trigger DB su doc_firma_assignments.
    const saved = 0;

    let pushed = 0;
    const pushErrors: { id: number; status: number; message: string }[] = [];
    try {
      const vapidPublicKey = (Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY") || "").trim();
      let vapidPrivateKey = (Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY") || "")
        .trim()
        .replace(/\\n/g, "\n");
      let vapidMailto = (
        Deno.env.get("WEB_PUSH_VAPID_SUBJECT") || "mailto:support@cronos.local"
      ).trim();
      if (vapidMailto && !vapidMailto.includes(":")) {
        vapidMailto = `mailto:${vapidMailto}`;
      }
      if (vapidPublicKey && vapidPrivateKey) {
        webpush.setVapidDetails(vapidMailto, vapidPublicKey, vapidPrivateKey);
        const { data: subscriptions } = await admin
          .from("web_push_subscriptions")
          .select("id, endpoint, p256dh, auth, origin")
          .eq("active", true)
          .in("user_id", userIds);
        const payload = JSON.stringify({
          title,
          body: message,
          type: "doc_firma",
          batch_id: batchId || null,
          tag: batchId ? `doc_firma_${batchId}` : `doc_firma_${Date.now()}`,
          url: "/",
        });
        for (const s of subscriptions || []) {
          const origin = String(s.origin || "").toLowerCase();
          if (shouldSkipWebPushOrigin(origin)) {
            await admin
              .from("web_push_subscriptions")
              .update({ active: false, updated_at: new Date().toISOString() })
              .eq("id", s.id);
            continue;
          }
          try {
            await webpush.sendNotification(
              {
                endpoint: s.endpoint,
                keys: { p256dh: s.p256dh, auth: s.auth },
              },
              payload,
              { TTL: 60 * 60 * 24, urgency: "high" },
            );
            pushed += 1;
          } catch (err) {
            const code = Number(err?.statusCode ?? err?.status ?? 0) || 0;
            const msg = String(err?.body || err?.message || err);
            console.error("doc-firma-notify WEB PUSH fail:", s.id, code, msg);
            if (pushErrors.length < 5) {
              pushErrors.push({
                id: Number(s.id) || 0,
                status: code,
                message: msg.slice(0, 240),
              });
            }
            if (code === 404 || code === 410) {
              await admin
                .from("web_push_subscriptions")
                .update({ active: false, updated_at: new Date().toISOString() })
                .eq("id", s.id);
            }
          }
        }
      } else {
        console.error("doc-firma-notify: VAPID secrets missing");
      }
    } catch (e) {
      console.error("doc-firma-notify push", e);
    }

    return json({ ok: true, saved, pushed, push_errors: pushErrors });
  } catch (e) {
    console.error("doc-firma-notify", e);
    return json({ error: String(e) }, 500);
  }
});
