// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

const CATEGORIES = new Set([
  "phishing",
  "account_compromesso",
  "dispositivo_perso",
  "malware",
  "accesso_non_autorizzato",
  "altro",
]);
const SEVERITIES = new Set(["bassa", "media", "alta", "critica"]);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clip(s: unknown, max: number): string {
  return String(s ?? "").trim().slice(0, max);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    // Honeypot anti-bot
    if (clip(body?.website, 80).length > 0) {
      return json({ ok: true });
    }

    const title = clip(body?.title, 200);
    const description = clip(body?.description, 4000);
    const reporterName = clip(body?.reporter_name, 120);
    const category = clip(body?.category, 40) || "altro";
    const severity = clip(body?.severity, 20) || "media";
    const phone = clip(body?.reporter_phone ?? body?.phone, 40);
    const deviceInfo = clip(body?.device_info, 300);
    const locationInfo = clip(body?.location_info, 300);

    if (title.length < 3 || description.length < 8) {
      return json(
        { error: "Titolo e descrizione sono obbligatori (min. 3 e 8 caratteri)." },
        400,
      );
    }
    if (reporterName.length < 2) {
      return json({ error: "Indica il tuo nome o un contatto." }, 400);
    }
    if (!CATEGORIES.has(category)) {
      return json({ error: "Categoria non valida" }, 400);
    }
    if (!SEVERITIES.has(severity)) {
      return json({ error: "Gravità non valida" }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) {
      return json({ error: "Server misconfigured" }, 500);
    }

    const supa = createClient(url, serviceKey);

    const { data: inserted, error: insertErr } = await supa
      .from("security_incident_reports")
      .insert({
        reporter_name: reporterName,
        reporter_role: "pubblico",
        reporter_phone: phone,
        category,
        severity,
        title,
        description,
        device_info: deviceInfo,
        location_info: locationInfo,
        status: "aperto",
        is_public_submit: true,
      })
      .select("id_uuid")
      .maybeSingle();

    if (insertErr) {
      console.error("security-incident-public insert", insertErr);
      return json({ error: "Salvataggio non riuscito" }, 500);
    }

    // Notifica admin / logistica (best effort).
    try {
      const { data: admins } = await supa
        .from("users")
        .select("id, role")
        .or("role.eq.admin,role.eq.admin_generale,role.eq.logistica");
      const ids = (admins ?? [])
        .map((e: { id?: number }) => Number(e?.id))
        .filter((n: number) => Number.isFinite(n) && n > 0);
      if (ids.length) {
        const bookingId =
          (Date.now() & 0x7fffffff) || Math.floor(Math.random() * 1e8);
        await fetch(`${url}/functions/v1/admin-send-notification`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${serviceKey}`,
            apikey: serviceKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            user_ids: ids,
            booking_id: bookingId,
            action: "security_incident",
            title: `Segnalazione sicurezza: ${title}`,
            message:
              `${reporterName} (fuori login) ha segnalato un incidente ` +
              `(${category}, gravità ${severity}). ` +
              `Apri Impostazioni → Incidenti sicurezza.`,
            booking_type: "security_incident",
          }),
        });
      }
    } catch (e) {
      console.error("security-incident-public notify", e);
    }

    return json({ ok: true, id: inserted?.id_uuid ?? null });
  } catch (e) {
    console.error("security-incident-public", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});
