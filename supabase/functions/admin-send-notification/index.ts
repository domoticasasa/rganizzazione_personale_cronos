// Supabase Edge Function (runtime Deno). L'IDE segna errori perché non usa Deno; in deploy funziona.
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
  user_ids: number[];
  booking_id: number;
  title: string;
  action: string; // supporta anche action custom (dt_approval_required, ecc.)
  message?: string;
  booking_type?: string;
  /** users.id_uuid dell'utente che esegue l'azione (sessione). Ha priorità su booking.updated_by. */
  actor_id_uuid?: string;
  /** Solo Web Push (nessun insert su notifications). Per cron SQL. */
  push_only?: boolean;
  /** Non escludere admin_generale (test, invio esplicito a user_ids). */
  force_all_recipients?: boolean;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const body = (await req.json()) as Payload;

    if (!body.user_ids?.length) return json({ error: "user_ids required" }, 400);
    // Coerce a numeri (PostgREST .in su user_id è più affidabile con number[]).
    body.user_ids = (Array.isArray(body.user_ids) ? body.user_ids : [])
      .map((v) => Number(v))
      .filter((n) => Number.isFinite(n) && n > 0);
    if (!body.user_ids.length) return json({ error: "user_ids required" }, 400);
    if (!body.booking_id) return json({ error: "booking_id required" }, 400);
    if (!body.title) return json({ error: "title required" }, 400);

    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const bookingTypeRaw = String(body.booking_type ?? "").toLowerCase().trim();
    const titleLower = String(body.title ?? "").toLowerCase().trim();
    const bookingTypeHint =
      bookingTypeRaw === "treno" || bookingTypeRaw === "aereo" ||
        bookingTypeRaw === "pernottamento" || bookingTypeRaw === "pernottamenti"
        ? bookingTypeRaw
        : "";

    // =====================================================================
    // BLOCCO WORKFLOW: una richiesta "INVIATA_AL_DT" NON deve notificare gli admin
    // anche se qualcuno invoca ancora la notifica "create".
    // =====================================================================
    try {
      const act = String(body.action || "").toLowerCase().trim();
      if (act === "create") {
        let ws = "";
        if (bookingTypeHint === "treno") {
          const { data: bt } = await supa
            .from("bookings_treno")
            .select("workflow_status")
            .eq("id", body.booking_id)
            .maybeSingle();
          ws = (bt?.workflow_status ?? "").toString();
        } else if (bookingTypeHint === "aereo") {
          const { data: ba } = await supa
            .from("bookings_aereo")
            .select("workflow_status")
            .eq("id", body.booking_id)
            .maybeSingle();
          ws = (ba?.workflow_status ?? "").toString();
        } else {
          // fallback legacy se booking_type non arriva.
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
          const trenoWs = (bt?.workflow_status ?? "").toString();
          const aereoWs = (ba?.workflow_status ?? "").toString();
          if (titleLower.includes("aereo")) {
            ws = aereoWs || trenoWs;
          } else if (titleLower.includes("treno")) {
            ws = trenoWs || aereoWs;
          } else {
            ws = trenoWs || aereoWs;
          }
        }
        ws = ws
          .toString()
          .toUpperCase()
          .trim();
        // Decidere via Supabase (no hardcode) se questo workflow_status
        // deve BLOCCARE le notifiche agli admin su action=create.
        let shouldSkipAdmin = false;
        try {
          const { data: skipRow } = await supa
            .from("notification_admin_create_skip_workflow_statuses")
            .select("workflow_status")
            .eq("action_key", "create")
            .eq("workflow_status", ws)
            .eq("enabled", true)
            .maybeSingle();
          shouldSkipAdmin = !!skipRow;
        } catch (_e) {
          // fail-safe: se la tabella non esiste o la query fallisce, continuiamo senza skip.
        }

        if (shouldSkipAdmin) {
          return json({
            ok: true,
            saved: 0,
            tokens_found: 0,
            pushed: 0,
            skipped: "workflow_status blocks create notifications for admin (Supabase controlled)",
            workflow_status: ws,
          });
        }
      }
    } catch (_e) {}

    const fmtDdMmYyyy = (value: unknown): string => {
      if (!value) return "N/D";
      const d = new Date(String(value));
      if (Number.isNaN(d.getTime())) return "N/D";
      const dd = String(d.getDate()).padStart(2, "0");
      const mm = String(d.getMonth() + 1).padStart(2, "0");
      const yyyy = String(d.getFullYear());
      return `${dd}-${mm}-${yyyy}`;
    };

    async function resolveUserIdFromAny(rawValue: unknown): Promise<number | null> {
      const raw = String(rawValue ?? "").trim();
      if (!raw) return null;

      const asInt = Number(raw);
      if (!Number.isNaN(asInt) && asInt > 0) {
        const byId = await supa.from("users").select("id").eq("id", asInt).maybeSingle();
        if (byId?.data?.id) return Number(byId.data.id);
      }

      const byUuid = await supa.from("users").select("id").eq("id_uuid", raw).maybeSingle();
      if (byUuid?.data?.id) return Number(byUuid.data.id);

      const byAuth = await supa.from("users").select("id").eq("auth_id", raw).maybeSingle();
      if (byAuth?.data?.id) return Number(byAuth.data.id);

      return null;
    }

    async function resolvePersonaleToUserId(personaleAny: unknown): Promise<number | null> {
      const raw = String(personaleAny ?? "").trim();
      if (!raw) return null;

      // personale_id puo' essere uuid oppure id int.
      let pers: any = null;
      const byUuid = await supa
        .from("personale")
        .select("user_id")
        .eq("id_uuid", raw)
        .maybeSingle();
      pers = byUuid?.data ?? null;

      if (!pers) {
        const asInt = Number(raw);
        if (!Number.isNaN(asInt) && asInt > 0) {
          const byId = await supa
            .from("personale")
            .select("user_id")
            .eq("id", asInt)
            .maybeSingle();
          pers = byId?.data ?? null;
        }
      }

      if (!pers?.user_id) return null;
      return await resolveUserIdFromAny(pers.user_id);
    }

    let fullMessage: string;
    let creatorName = "N/D";
    let targetName = "N/D";
    let bookingType = "N/D";
    let bookingDate = "N/D";

    if (body.message) {
      fullMessage = body.message;
    } else {
      // Per treni/aerei il record NON è in `bookings`, ma in `bookings_treno` / `bookings_aereo`.
      // Qui costruiamo un messaggio coerente per tutti i casi.

      let bookingHotel: any = null;
      let bookingTreno: any = null;
      let bookingAereo: any = null;
      if (bookingTypeHint === "treno") {
        const btRes = await supa
          .from("bookings_treno")
          .select("*")
          .eq("id", body.booking_id)
          .maybeSingle();
        bookingTreno = btRes?.data ?? null;
      } else if (bookingTypeHint === "aereo") {
        const baRes = await supa
          .from("bookings_aereo")
          .select("*")
          .eq("id", body.booking_id)
          .maybeSingle();
        bookingAereo = baRes?.data ?? null;
      } else if (bookingTypeHint === "pernottamento" || bookingTypeHint === "pernottamenti") {
        const bhRes = await supa
          .from("bookings")
          .select("*")
          .eq("id", body.booking_id)
          .maybeSingle();
        bookingHotel = bhRes?.data ?? null;
      } else {
        const [bhRes, btRes, baRes] = await Promise.all([
          supa
            .from("bookings")
            .select("*")
            .eq("id", body.booking_id)
            .maybeSingle(),
          supa
            .from("bookings_treno")
            .select("*")
            .eq("id", body.booking_id)
            .maybeSingle(),
          supa
            .from("bookings_aereo")
            .select("*")
            .eq("id", body.booking_id)
            .maybeSingle(),
        ]);
        bookingHotel = bhRes?.data ?? null;
        bookingTreno = btRes?.data ?? null;
        bookingAereo = baRes?.data ?? null;
        const matches =
          (bookingTreno ? 1 : 0) + (bookingAereo ? 1 : 0) + (bookingHotel ? 1 : 0);
        if (matches > 1) {
          if (titleLower.includes("aereo")) {
            bookingTreno = null;
            bookingHotel = null;
          } else if (titleLower.includes("treno")) {
            bookingAereo = null;
            bookingHotel = null;
          } else if (titleLower.includes("pernott")) {
            bookingTreno = null;
            bookingAereo = null;
          }
        }
      }

      const anyBooking = bookingTreno ?? bookingAereo ?? bookingHotel;

      // Chi ha eseguito l'azione (client autenticato): priorità su updated_by del record.
      // Esempio: admin treno conferma ma updated_by è ancora l'assistente DT che aveva inserito la richiesta.
      const actorUuidArg = String(body.actor_id_uuid ?? "").trim();
      if (actorUuidArg) {
        const { data: actorRow } = await supa
          .from("users")
          .select("full_name")
          .eq("id_uuid", actorUuidArg)
          .maybeSingle();
        if (actorRow?.full_name) creatorName = actorRow.full_name;
      }

      // creatorName da record solo se non già risolto da actor_id_uuid
      if (creatorName === "N/D") {
        const updatedBy =
          anyBooking?.updated_by ??
          anyBooking?.updatedBy ??
          anyBooking?.updated_by_user_id ??
          null;
        if (updatedBy) {
          const raw = String(updatedBy).trim();
          let u: any = null;
          if (raw) {
            // 1) prova uuid
            const byUuid = await supa
              .from("users")
              .select("full_name")
              .eq("id_uuid", raw)
              .maybeSingle();
            u = byUuid?.data ?? null;

            // 2) prova auth_id
            if (!u) {
              const byAuth = await supa
                .from("users")
                .select("full_name")
                .eq("auth_id", raw)
                .maybeSingle();
              u = byAuth?.data ?? null;
            }

            // 3) prova users.id (int)
            if (!u) {
              const asInt = Number(raw);
              if (!Number.isNaN(asInt)) {
                const byId = await supa
                  .from("users")
                  .select("full_name")
                  .eq("id", asInt)
                  .maybeSingle();
                u = byId?.data ?? null;
              }
            }
          }
          if (u?.full_name) creatorName = u.full_name;
        }
      }

      // targetName: personale_id può essere uuid o id int (legacy)
      const personaleId =
        anyBooking?.personale_id ??
        anyBooking?.personaleId ??
        anyBooking?.personale ??
        null;
      if (personaleId) {
        const raw = String(personaleId).trim();
        let p: any = null;
        if (raw) {
          const byUuid = await supa
            .from("personale")
            .select("full_name")
            .eq("id_uuid", raw)
            .maybeSingle();
          p = byUuid?.data ?? null;

          if (!p) {
            const asInt = Number(raw);
            if (!Number.isNaN(asInt)) {
              const byId = await supa
                .from("personale")
                .select("full_name")
                .eq("id", asInt)
                .maybeSingle();
              p = byId?.data ?? null;
            }
          }
        }
        if (p?.full_name) targetName = p.full_name;
      }

      // Tipo/Data: stessa priorità treno > aereo > hotel (coerente con anyBooking).
      if (bookingTreno) {
        bookingType =
          bookingTreno?.viaggio_tipo ??
          bookingTreno?.viaggioTipo ??
          bookingTreno?.tipo ??
          "N/D";
        const dateRaw = bookingTreno?.data ?? bookingTreno?.date ?? null;
        bookingDate = fmtDdMmYyyy(dateRaw);
      } else if (bookingAereo) {
        bookingType =
          bookingAereo?.viaggio_tipo ??
          bookingAereo?.viaggioTipo ??
          bookingAereo?.tipo ??
          "N/D";
        const dateRaw = bookingAereo?.data ?? bookingAereo?.date ?? null;
        bookingDate = fmtDdMmYyyy(dateRaw);
      } else if (bookingHotel) {
        const cameraTipo =
          bookingHotel?.camera_tipo ??
          bookingHotel?.cameraType ??
          bookingHotel?.tipo ??
          bookingHotel?.tipo_prenotazione ??
          "N/D";
        const dateRaw =
          bookingHotel?.start_date ??
          bookingHotel?.data ??
          bookingHotel?.date ??
          null;
        bookingType = cameraTipo;
        bookingDate = fmtDdMmYyyy(dateRaw);
      }

      const actionKey = String(body.action || "").toLowerCase().trim();
      const actionVerb = actionKey === "create"
        ? "ha creato"
        : actionKey === "update"
        ? "ha modificato"
        : actionKey === "delete"
        ? "ha cancellato"
        : actionKey === "dt_approved" || actionKey === "approved" || actionKey === "approve"
        ? "ha approvato"
        : actionKey === "dt_rejected" || actionKey === "rejected" || actionKey === "reject"
        ? "ha rifiutato"
        : actionKey === "confirm" || actionKey === "confirmed" || actionKey === "conferma"
        ? "ha confermato"
        : "ha aggiornato";

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

    // Dedup: alcune azioni lato client possono invocare la function due volte.
    // Evitiamo di inserire duplicati recenti sulla stessa combo (user_id, booking_id, action).
    const bookingIdStr = String(body.booking_id);
    const actionStr = String(body.action || "").toLowerCase().trim();

    // ====== ESTENSIONE DESTINATARI TR / AEREO / PERNOTTI ======
    // TR/AEREO (bookings_treno, bookings_aereo):
    // - SEMPRE personale (personale_id -> personale.user_id -> users.id)
    // - update/delete SEMPRE richiedente (requested_by_user_id)
    // - update/delete SEMPRE dt selezionato (dt_user_uuid -> users.id)
    //
    // PERNOTTI (bookings):
    // - SEMPRE personale
    // - update/delete: anche assistente creatore (updated_by) se è `assistente_dt` e
    //   è autorizzato dal DT selezionato tramite `assistente_dt_permissions`.
    try {
      const extra = new Set<number>();

      let bt: any = null;
      let ba: any = null;
      let bp: any = null;
      if (bookingTypeHint === "treno") {
        const btRes = await supa
          .from("bookings_treno")
          .select("personale_id, dt_user_uuid, requested_by_user_id")
          .eq("id", body.booking_id)
          .maybeSingle();
        bt = btRes?.data ?? null;
      } else if (bookingTypeHint === "aereo") {
        const baRes = await supa
          .from("bookings_aereo")
          .select("personale_id, dt_user_uuid, requested_by_user_id")
          .eq("id", body.booking_id)
          .maybeSingle();
        ba = baRes?.data ?? null;
      } else if (bookingTypeHint === "pernottamento" || bookingTypeHint === "pernottamenti") {
        const bpRes = await supa
          .from("bookings")
          .select("personale_id, dt_user_uuid, updated_by")
          .eq("id", body.booking_id)
          .maybeSingle();
        bp = bpRes?.data ?? null;
      } else {
        const [btRes, baRes, bpRes] = await Promise.all([
          supa
            .from("bookings_treno")
            .select("personale_id, dt_user_uuid, requested_by_user_id")
            .eq("id", body.booking_id)
            .maybeSingle(),
          supa
            .from("bookings_aereo")
            .select("personale_id, dt_user_uuid, requested_by_user_id")
            .eq("id", body.booking_id)
            .maybeSingle(),
          supa
            .from("bookings")
            .select("personale_id, dt_user_uuid, updated_by")
            .eq("id", body.booking_id)
            .maybeSingle(),
        ]);
        bt = btRes?.data ?? null;
        ba = baRes?.data ?? null;
        bp = bpRes?.data ?? null;
        const matches = (bt ? 1 : 0) + (ba ? 1 : 0) + (bp ? 1 : 0);
        if (matches > 1) {
          if (titleLower.includes("aereo")) {
            bt = null;
            bp = null;
          } else if (titleLower.includes("treno")) {
            ba = null;
            bp = null;
          } else if (titleLower.includes("pernott")) {
            bt = null;
            ba = null;
          }
        }
      }

      const booking = bt ?? ba;
      if (booking) {
        const personaleId = booking.personale_id;
        const dtUserUuid = booking.dt_user_uuid;
        const requestedByUserId = booking.requested_by_user_id;

        // Personale: personale.personale_id (uuid) -> personale.user_id (auth_id) -> users.id (int)
        if (personaleId) {
          const userId = await resolvePersonaleToUserId(personaleId);
          if (userId != null) extra.add(userId);
        }

        // Richiedente: requested_by_user_id (users.id) — anche su rifiuto DT (dt_rejected).
        if (
          (actionStr === "update" ||
            actionStr === "delete" ||
            actionStr === "dt_rejected") &&
          requestedByUserId != null
        ) {
          extra.add(Number(requestedByUserId));
        }

        // DT selezionato: dt_user_uuid (uuid) -> users.id (int)
        if (dtUserUuid) {
          const duId = await resolveUserIdFromAny(dtUserUuid);
          if (duId != null) {
            // update/delete + richiesta in attesa DT (se il client omette l'id, lo recuperiamo dal booking)
            if (
              actionStr === "update" ||
              actionStr === "delete" ||
              actionStr === "dt_approval_required"
            ) {
              extra.add(duId);
            }
          }
        }

        // Assistenti autorizzati per il DT selezionato:
        // su update/delete notifica anche loro (non solo requested_by_user_id).
        if ((actionStr === "update" || actionStr === "delete") && dtUserUuid) {
          const { data: perms } = await supa
            .from("assistente_dt_permissions")
            .select("assistant_user_id")
            .eq("grantor_dt_user_uuid", dtUserUuid);
          for (const p of perms ?? []) {
            const aid = Number(p?.assistant_user_id);
            if (!Number.isNaN(aid) && aid > 0) extra.add(aid);
          }
        }
      }

      // --- PERNOTTI (bookings) ---
      if (bp) {
        const personaleId = bp.personale_id;
        const dtUserUuid = bp.dt_user_uuid;
        const creatorUuid = bp.updated_by; // UUID creator (DT o Assistente DT)

        // Personale: personale_id -> personale.user_id(auth) -> users.id
        if (personaleId) {
          const userId = await resolvePersonaleToUserId(personaleId);
          if (userId != null) extra.add(userId);
        }

        // Assistente creatore: su update/delete notifica l'assistente autorizzato
        if (actionStr === "update" || actionStr === "delete") {
          if (dtUserUuid && creatorUuid) {
            const { data: creator } = await supa
              .from("users")
              .select("id, role")
              .eq("id_uuid", creatorUuid)
              .maybeSingle();

            const creatorRole = (creator?.role ?? "").toString().toLowerCase().trim();
            if (creator?.id && creatorRole === "assistente_dt") {
              const { data: perm } = await supa
                .from("assistente_dt_permissions")
                .select("id")
                .eq("grantor_dt_user_uuid", dtUserUuid)
                .eq("assistant_user_id", creator.id)
                .maybeSingle();

              if (perm) extra.add(creator.id);
            }
          }
        }

        // (opzionale ma sicuro) dt selezionato su update/delete
        if ((actionStr === "update" || actionStr === "delete") && dtUserUuid) {
          const duId = await resolveUserIdFromAny(dtUserUuid);
          if (duId != null) extra.add(duId);
        }
      }

      const merged = Array.from(new Set([...(body.user_ids ?? []), ...Array.from(extra)]));
      body.user_ids = merged;
    } catch (_e) {
      // se fallisce la risoluzione extra, usiamo i destinatari originali
    }

    // Blocco esplicito: filtro admin_generale controllato da Supabase.
    // (Legacy semantica: se actionStr è presente nella lista, il filtro non viene applicato.)
    let skipAdminGeneraleFilter = false;
    const forceAllRecipients =
      body.force_all_recipients === true ||
      body.push_only === true ||
      actionStr.startsWith("test");
    try {
      const { data: skipRow } = await supa
        .from("notification_admin_generale_filter_skip_actions")
        .select("action_key")
        .eq("action_key", actionStr)
        .eq("enabled", true)
        .maybeSingle();
      skipAdminGeneraleFilter = !!skipRow;
    } catch (_e) {
      // fail-safe: mantieni comportamento legacy (filtro applicato) se tabella/query non disponibili.
      skipAdminGeneraleFilter = false;
    }
    if (forceAllRecipients) {
      skipAdminGeneraleFilter = true;
    }

    if (body.user_ids.length > 0 && !skipAdminGeneraleFilter) {
      try {
        const { data: recips } = await supa
          .from("users")
          .select("id, role, admin_type")
          .in("id", body.user_ids);
        const allowed = new Set<number>();
        for (const r of recips ?? []) {
          const id = Number(r?.id);
          if (Number.isNaN(id) || id <= 0) continue;
          const role = String(r?.role ?? "").toLowerCase().trim();
          const adminType = Number(r?.admin_type ?? 0);
          const isGeneralAdmin =
            role === "admin_generale" || (role === "admin" && adminType === 1);
          if (!isGeneralAdmin) allowed.add(id);
        }
        body.user_ids = body.user_ids.filter((id) => allowed.has(Number(id)));
      } catch (_e) {
        // fail-safe: in caso di errore non alteriamo i destinatari originali
      }
    }

    const dedupSinceIso = new Date(Date.now() - 10_000).toISOString(); // 10s
    const pushOnly = body.push_only === true;
    let savedCount = 0;

    if (!pushOnly) {
      for (const uid of body.user_ids) {
        const { data: existing } = await supa
          .from("notifications")
          .select("id")
          .eq("user_id", uid)
          // JSONB meta -> booking_id / action
          .filter("meta->>booking_id", "eq", bookingIdStr)
          .filter("meta->>action", "eq", actionStr)
          .eq("title", body.title)
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
        savedCount += 1;
      }
    }

    let webPushed = 0;
    let webSubsFound = 0;
    const webPushErrors: { id: number; status: number; message: string }[] = [];
    let vapidConfigured = false;
    try {
      const vapidPublicKey = (Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY") || "").trim();
      let vapidPrivateKey = (Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY") || "")
        .trim()
        .replace(/\\n/g, "\n");
      let vapidMailto = (Deno.env.get("WEB_PUSH_VAPID_SUBJECT") || "mailto:support@cronos.local").trim();
      if (vapidMailto && !vapidMailto.includes(":")) {
        vapidMailto = `mailto:${vapidMailto}`;
      }
      vapidConfigured = !!(vapidPublicKey && vapidPrivateKey);
      if (vapidConfigured && body.user_ids.length > 0) {
        webpush.setVapidDetails(vapidMailto, vapidPublicKey, vapidPrivateKey);
        const { data: subscriptions, error: subErr } = await supa
          .from("web_push_subscriptions")
          .select("id, endpoint, p256dh, auth, origin")
          .eq("active", true)
          .in("user_id", body.user_ids)
          .limit(500);
        if (subErr) {
          console.error("admin-send-notification WEB PUSH select error:", subErr);
          webPushErrors.push({
            id: 0,
            status: 0,
            message: `select: ${subErr.message || String(subErr)}`,
          });
        }
        webSubsFound = (subscriptions ?? []).length;
        for (const s of subscriptions ?? []) {
          const origin = String(s.origin || "").toLowerCase();
          if (shouldSkipWebPushOrigin(origin)) {
            await supa
              .from("web_push_subscriptions")
              .update({ active: false, updated_at: new Date().toISOString() })
              .eq("id", s.id);
            continue;
          }
          try {
            await webpush.sendNotification(
              {
                endpoint: s.endpoint,
                keys: {
                  p256dh: s.p256dh,
                  auth: s.auth,
                },
              },
              JSON.stringify({
                title: body.title,
                body: fullMessage,
                booking_id: body.booking_id,
                action: body.action,
                tag: String(body.action || body.booking_id || `cronos-${Date.now()}`),
                url: "/",
              }),
              {
                TTL: 60 * 60 * 24,
                urgency: "high",
              },
            );
            webPushed++;
          } catch (err) {
            const code = Number(err?.statusCode ?? err?.statusCode ?? 0) ||
              Number((err as { statusCode?: number })?.statusCode ?? 0);
            const msg = String(err?.body || err?.message || err);
            console.error(
              "admin-send-notification WEB PUSH send failed:",
              `id=${s.id}`,
              `status=${code}`,
              msg,
            );
            if (webPushErrors.length < 5) {
              webPushErrors.push({
                id: Number(s.id) || 0,
                status: code,
                message: msg.slice(0, 240),
              });
            }
            if (code === 404 || code === 410) {
              await supa
                .from("web_push_subscriptions")
                .update({ active: false, updated_at: new Date().toISOString() })
                .eq("id", s.id);
            }
          }
        }
      } else if (!vapidConfigured) {
        console.error("admin-send-notification WEB PUSH skipped: VAPID secrets missing");
      }
    } catch (webPushErr) {
      console.error("admin-send-notification WEB PUSH ERROR:", String(webPushErr));
      webPushErrors.push({
        id: 0,
        status: 0,
        message: String(webPushErr).slice(0, 240),
      });
    }

    return json({
      ok: true,
      saved: pushOnly ? 0 : savedCount,
      push_only: pushOnly,
      web_pushed: webPushed,
      web_subs_found: webSubsFound,
      vapid_configured: vapidConfigured,
      vapid_public_prefix: vapidConfigured
        ? ((Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY") || "").trim().slice(0, 12))
        : "",
      web_push_errors: webPushErrors,
    });
  } catch (e) {
    console.error("admin-send-notification ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
