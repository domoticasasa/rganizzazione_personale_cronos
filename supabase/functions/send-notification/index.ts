// Supabase Edge Function (runtime Deno). L'IDE segna errori perché non usa Deno; in deploy funziona.
// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

type Payload = {
  user_ids: number[];
  booking_id: number;
  title: string;
  // Nota: in app usiamo anche azioni custom (es. dt_approval_required).
  action: string;
  message?: string;        // se presente, usato come corpo notifica (es. per treno/aereo)
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response(null, { status: 204, headers: corsHeaders });

  // Endpoint deprecato: evitare doppio invio tramite due function distinte.
  // Canale ufficiale unico: admin-send-notification.
  return json(
    {
      error: "Function deprecated",
      details: "Use admin-send-notification instead of send-notification.",
    },
    410
  );

  try {
    const body = (await req.json()) as Payload;

    // VALIDAZIONI
    if (!body.user_ids?.length)
      return json({ error: "user_ids required" }, 400);
    if (!body.booking_id)
      return json({ error: "booking_id required" }, 400);
    if (!body.title)
      return json({ error: "title required" }, 400);

    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // =====================================================================
    // BLOCCO WORKFLOW: se è una "create" su treno/aereo in stato INVIATA_AL_DT
    // allora NON dobbiamo notificare gli admin (la richiesta deve arrivare solo al DT).
    // Questo blocco è server-side così siamo sicuri al 100% anche se qualche client
    // invoca ancora la notifica "create".
    // =====================================================================
    try {
      const act = String(body.action || "").toLowerCase().trim();
      if (act === "create") {
        // Non fidiamoci del titolo: controlliamo SEMPRE se questo booking_id
        // esiste in treno/aereo e se è in workflow "INVIATA_AL_DT".
        const { data: bt } = await supa
          .from("bookings_treno")
          .select("workflow_status")
          .eq("id", body.booking_id)
          .maybeSingle();
        const { data: ba } = await supa
          .from("bookings_aereo")
          .select("workflow_status")
          .eq("id", body.booking_id)
          .maybeSingle();

        const ws = (bt?.workflow_status ?? ba?.workflow_status ?? "")
          .toString()
          .toUpperCase()
          .trim();
        if (ws === "INVIATA_AL_DT" || ws === "RIFIUTATA_DAL_DT") {
          return json({
            ok: true,
            saved: 0,
            tokens_found: 0,
            pushed: 0,
            skipped: "workflow_status blocks create notifications for admin",
            workflow_status: ws,
          });
        }
      }
    } catch (_e) {
      // Non bloccare mai la function per questo controllo: se fallisce, continua il flusso normale.
    }

    let fullMessage: string;
    let creatorName = "N/D";
    let targetName = "N/D";
    let bookingType = "N/D";
    let bookingDate = "N/D";

    if (body.message) {
      fullMessage = body.message;
    } else {
      //
      // 1️⃣ RECUPERO PRENOTAZIONE (tabella bookings = pernottamenti, se esiste)
      //    Per treni/aerei può NON esistere: in quel caso NON è errore bloccante.
      //
      const { data: booking, error: bErr } = await supa
        .from("bookings")
        .select("id, start_date, end_date, camera_tipo, personale_id, updated_by")
        .eq("id", body.booking_id)
        .maybeSingle();

      if (booking?.updated_by) {
        const { data: u } = await supa
          .from("users")
          .select("full_name")
          .eq("id_uuid", booking.updated_by) // updated_by è uuid → confronta con users.id_uuid
          .maybeSingle();
        if (u?.full_name) creatorName = u.full_name;
      }

      const personaleId = booking?.personale_id;
      if (personaleId) {
        const { data: p } = await supa
          .from("personale")
          .select("full_name")
          .eq("id_uuid", personaleId)
          .maybeSingle();
        if (!p?.full_name) {
          const { data: p2 } = await supa
            .from("personale")
            .select("full_name")
            .eq("id", personaleId)
            .maybeSingle();
          if (p2?.full_name) targetName = p2.full_name;
        } else {
          targetName = p.full_name;
        }
      }

      bookingType = booking?.camera_tipo ?? "N/D";
      bookingDate = booking?.start_date
        ? new Date(booking.start_date).toLocaleDateString("it-IT")
        : "N/D";

    const actionVerb =
      body.action === "create" ? "ha creato" : body.action === "update" ? "ha modificato" : body.action === "delete" ? "ha cancellato" : "ha aggiornato";

      // Se non conosciamo il nome di chi ha fatto l'azione,
      // usiamo una frase neutra senza "Utente sconosciuto" o simili.
      const headerLine =
        creatorName && creatorName !== "N/D"
          ? `${creatorName} ${actionVerb} una prenotazione`
          : `È stata ${actionVerb} una prenotazione`;

      fullMessage =
        `${headerLine}\n` +
        `Per: ${targetName}\n` +
        `Tipo: ${bookingType}\n` +
        `Data: ${bookingDate}`;
    }

    //
    // 4️⃣ INSERISCO NOTIFICHE, UNA PER OGNI DESTINATARIO
    //
    // Dedup: evitare duplicati recenti
    const bookingIdStr = String(body.booking_id);
    const actionStr = String(body.action || "").toLowerCase().trim();
    const dedupSinceIso = new Date(Date.now() - 10_000).toISOString(); // 10s

    for (const uid of body.user_ids) {
      const { data: existing } = await supa
        .from("notifications")
        .select("id")
        .eq("user_id", uid)
        .filter("meta->>booking_id", "eq", bookingIdStr)
        .filter("meta->>action", "eq", actionStr)
        .gt("created_at", dedupSinceIso)
        .limit(1);

      if ((existing ?? []).length > 0) continue;

      await supa.from("notifications").insert({
        user_id: uid,
        title: body.title,
        message: fullMessage,
        meta: {
          booking_id: body.booking_id,
          creator: creatorName,
          target: targetName,
          type: bookingType,
          date: bookingDate,
          action: body.action,
          skip_os_push: true,
        },
        is_read: false,
      });
    }
    return json({
      ok: true,
      saved: body.user_ids.length,
    });

  } catch (e) {
    console.error("send-notification ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});
function json(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
