// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
import { shouldSkipWebPushOrigin } from "../_shared/web_push_origin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

type Payload = {
  message_id?: string;
};

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

    const asServiceRole = jwtRole(jwt) === "service_role";
    let user: { id: string } | null = null;
    if (!asServiceRole) {
      const authClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      const got = await authClient.auth.getUser();
      if (got.error || !got.data.user) return json({ error: "Invalid token" }, 401);
      user = got.data.user;
    }

    const body = (await req.json()) as Payload;
    const messageId = String(body?.message_id || "").trim();
    if (!messageId) return json({ error: "message_id required" }, 400);

    const admin = createClient(supabaseUrl, serviceRole);
    const { data: msg, error: msgErr } = await admin
      .from("app_chat_messages")
      .select(
        "id, sender_user_id, sender_auth_id, sender_name, recipient_user_id, recipient_auth_id, group_id, body, attachment_name, created_at",
      )
      .eq("id", messageId)
      .maybeSingle();
    if (msgErr || !msg) return json({ error: "Message not found" }, 404);

    if (!asServiceRole && String(msg.sender_auth_id) !== user?.id) {
      return json({ error: "Only sender can notify" }, 403);
    }

    const senderUserId = Number(msg.sender_user_id) || 0;
    const senderName = String(msg.sender_name || "Utente").trim() || "Utente";
    const groupId = msg.group_id ? String(msg.group_id).trim() : "";
    const isDm = msg.recipient_user_id != null ||
      (msg.recipient_auth_id != null && String(msg.recipient_auth_id).trim() !== "");

    let recipientIds: number[] = [];
    let groupName = "Gruppo";
    if (isDm) {
      let rid = Number(msg.recipient_user_id) || 0;
      if (rid <= 0 && msg.recipient_auth_id) {
        const { data: byAuth } = await admin
          .from("users")
          .select("id")
          .eq("auth_id", String(msg.recipient_auth_id))
          .maybeSingle();
        rid = Number(byAuth?.id) || 0;
      }
      if (rid > 0 && rid !== senderUserId) recipientIds = [rid];
    } else if (groupId) {
      const resolved = await resolveGroupRecipients(admin, groupId, senderUserId);
      recipientIds = resolved.ids;
      groupName = resolved.name || "Gruppo";
    }

    if (recipientIds.length === 0) {
      return json({ ok: true, skipped: "no recipients", web_pushed: 0, pushed: 0 });
    }

    const preview = buildPreview(msg.body, msg.attachment_name);
    const title = isDm
      ? "GESTOPRO Chat · Privato"
      : `GESTOPRO Chat · ${groupName}`;
    const fullMessage = isDm
      ? `${senderName}: ${preview}`
      : `${senderName} (${groupName}): ${preview}`;

    const pushPayload = {
      title,
      body: fullMessage,
      action: isDm ? "app_chat_dm" : "app_chat_group",
      tag: `app-chat-${isDm ? "dm" : `group-${groupId}`}-${messageId}`,
      url: "/?openChat=1",
      message_id: messageId,
      group_id: groupId || undefined,
      silent: false,
    };

    // Nessun insert in `notifications`: la chat ha badge/FAB/push propri,
    // non deve comparire nella pagina Notifiche.

    const webResult = await sendWebPush(admin, recipientIds, pushPayload);

    const vapidConfigured = Boolean(
      (Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY") || "").trim() &&
        (Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY") || "").trim(),
    );

    return json({
      ok: true,
      recipients: recipientIds.length,
      is_dm: isDm,
      vapid_configured: vapidConfigured,
      web_pushed: webResult.pushed,
      web_subs_found: webResult.found,
    });
  } catch (e) {
    console.error("app-chat-notify ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function buildPreview(body: unknown, attachmentName: unknown): string {
  const text = String(body ?? "").trim();
  if (text) return text.length > 140 ? `${text.slice(0, 137)}…` : text;
  const att = String(attachmentName ?? "").trim();
  if (att) return `Allegato: ${att}`;
  return "Nuovo messaggio";
}

async function resolveGroupRecipients(
  admin: ReturnType<typeof createClient>,
  groupId: string,
  senderUserId: number,
): Promise<{ ids: number[]; name: string }> {
  const { data: group } = await admin
    .from("app_chat_groups")
    .select("name")
    .eq("id", groupId)
    .maybeSingle();
  const name = String(group?.name || "Gruppo").trim() || "Gruppo";

  const { data: members } = await admin
    .from("app_chat_group_members")
    .select("user_id")
    .eq("group_id", groupId);

  const ids = new Set<number>();
  for (const r of members ?? []) {
    const id = Number(r?.user_id);
    if (Number.isFinite(id) && id > 0) ids.add(id);
  }
  ids.delete(senderUserId);
  return { ids: Array.from(ids), name };
}

async function sendWebPush(
  admin: ReturnType<typeof createClient>,
  userIds: number[],
  payload: Record<string, unknown>,
): Promise<{ pushed: number; found: number }> {
  const vapidPublicKey = (Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY") || "").trim();
  let vapidPrivateKey = (Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY") || "")
    .trim()
    .replace(/\\n/g, "\n");
  let vapidMailto = (Deno.env.get("WEB_PUSH_VAPID_SUBJECT") || "mailto:support@cronos.local")
    .trim();
  if (vapidMailto && !vapidMailto.includes(":")) {
    vapidMailto = `mailto:${vapidMailto}`;
  }
  if (!vapidPublicKey || !vapidPrivateKey || userIds.length === 0) {
    return { pushed: 0, found: 0 };
  }

  webpush.setVapidDetails(vapidMailto, vapidPublicKey, vapidPrivateKey);
  const { data: subscriptions } = await admin
    .from("web_push_subscriptions")
    .select("id, endpoint, p256dh, auth, origin")
    .eq("active", true)
    .in("user_id", userIds)
    .limit(500);

  let pushed = 0;
  for (const s of subscriptions ?? []) {
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
        JSON.stringify(payload),
        { TTL: 60 * 60 * 12, urgency: "high" },
      );
      pushed++;
    } catch (err) {
      const code = Number(err?.statusCode ?? 0) || 0;
      console.error("app-chat-notify WEB PUSH fail:", s.id, code, String(err?.body || err));
      if (code === 404 || code === 410) {
        await admin
          .from("web_push_subscriptions")
          .update({ active: false, updated_at: new Date().toISOString() })
          .eq("id", s.id);
      }
    }
  }
  return { pushed, found: (subscriptions ?? []).length };
}
function jwtRole(jwt: string): string {
  try {
    const payload = jwt.split(".")[1] || "";
    const padded = payload.replace(/-/g, "+").replace(/_/g, "/");
    const pad = "=".repeat((4 - (padded.length % 4)) % 4);
    const json = JSON.parse(atob(padded + pad));
    return String(json?.role || "").trim();
  } catch {
    return "";
  }
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
