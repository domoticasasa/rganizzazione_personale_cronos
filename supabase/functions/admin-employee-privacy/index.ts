// Audit legale A5 (10/10/2026): esportazione e cancellazione dei dati di UN
// dipendente (GDPR artt. 15, 17, 20). Solo admin con permessi di scrittura.
//
// POST { action: "export" | "purge", personale_id_uuid: string,
//        include_signed_documents?: boolean }
// - export: JSON con tutti i dati + URL firmati (1 ora) dei file in storage.
// - purge : cancella visite mediche (righe + PDF), assenze, attestati (righe +
//           file), azzera le posizioni GPS (buoni pasto, viaggi mezzi) e i token
//           notifiche. Con include_signed_documents=true elimina anche i PDF
//           firmati (doc_firma). Account e anagrafica si eliminano poi con
//           "Gestione dipendenti" (funzione admin-delete-user).
//
// NON ancora deployata: vedi CHECKLIST_modifiche_legali.md
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { insertAppActivityLog } from "../_shared/app_activity_log.ts";

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
  "admin_treno_aereo",
  "admin_formazione",
  "admin_dpi",
]);

type Row = Record<string, unknown>;
type FileRef = { bucket: string; path: string; source: string };

// Tabelle per personale_id_uuid (nome colonna) esportate.
const EXPORT_TABLES: Array<{ table: string; col: string }> = [
  { table: "dipendente_assenze", col: "personale_id_uuid" },
  { table: "visite_mediche_programmazione", col: "personale_id_uuid" },
  { table: "visite_mediche_rfi", col: "personale_id_uuid" },
  { table: "uqsa_attestati", col: "personale_id" },
  { table: "buoni_pasto_registrazioni", col: "personale_id_uuid" },
  { table: "logistica_mezzi_stradali_viaggi", col: "personale_id_uuid" },
  { table: "doc_firma_assignments", col: "personale_id" },
  { table: "dislocazione_personale", col: "personale_id_uuid" },
];

const SENSITIVE_KEY = /pass|hash|secret|otp|token/i;

function scrub(r: Row): Row {
  const out: Row = {};
  for (const [k, v] of Object.entries(r)) {
    if (!SENSITIVE_KEY.test(k)) out[k] = v;
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // --- verifica chiamante admin ---
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return json({ error: "missing auth" }, 401);
    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller.user) return json({ error: "invalid auth" }, 401);
    const { data: callerRow } = await admin
      .from("users")
      .select("role")
      .eq("auth_id", caller.user.id)
      .maybeSingle();
    const role = String(callerRow?.role ?? "").toLowerCase().trim()
      .replace(/[ /]/g, "_");
    if (!ADMIN_ROLES.has(role)) return json({ error: "Only admin" }, 403);

    const body = await req.json();
    const action = String(body.action ?? "").trim();
    const pid = String(body.personale_id_uuid ?? "").trim();
    const includeSigned = body.include_signed_documents === true;
    if (!pid) return json({ error: "personale_id_uuid required" }, 400);

    const { data: pers, error: persErr } = await admin
      .from("personale")
      .select("*")
      .eq("id_uuid", pid)
      .maybeSingle();
    if (persErr) return json({ error: persErr.message }, 500);
    if (!pers) return json({ error: "dipendente non trovato" }, 404);

    const authId = String((pers as Row).user_id ?? "").trim();
    const fullName = String((pers as Row).full_name ?? "").trim();

    if (action === "export") {
      const data: Record<string, unknown> = { personale: scrub(pers as Row) };
      let userRow: Row | null = null;
      if (authId) {
        const { data: u } = await admin
          .from("users").select("*").eq("auth_id", authId).maybeSingle();
        userRow = (u as Row) ?? null;
        if (userRow) data.users = scrub(userRow);
      }
      for (const t of EXPORT_TABLES) {
        data[t.table] = await selectSafe(admin, t.table, t.col, pid);
      }
      if (userRow?.id != null) {
        data.device_tokens_count = (await selectSafe(
          admin, "device_tokens", "user_id", userRow.id,
        )).length;
      }
      const files = collectFiles(data, true);
      const signed: Array<FileRef & { url: string | null }> = [];
      for (const f of files) {
        const { data: s } = await admin.storage.from(f.bucket)
          .createSignedUrl(f.path, 3600);
        signed.push({ ...f, url: s?.signedUrl ?? null });
      }
      await insertAppActivityLog({
        admin, authHeader, action: "privacy_export_dipendente",
        detail: fullName || pid,
      });
      return json({
        ok: true,
        generated_at: new Date().toISOString(),
        personale_id_uuid: pid,
        data,
        files: signed,
      });
    }

    if (action === "purge") {
      const report: Record<string, unknown> = {};
      const data: Record<string, unknown> = {};
      for (const t of ["visite_mediche_rfi", "uqsa_attestati", "doc_firma_assignments"]) {
        const col = EXPORT_TABLES.find((e) => e.table === t)!.col;
        data[t] = await selectSafe(admin, t, col, pid);
      }
      const files = collectFiles(data, includeSigned);
      const removed: string[] = [];
      const byBucket = new Map<string, string[]>();
      for (const f of files) {
        byBucket.set(f.bucket, [...(byBucket.get(f.bucket) ?? []), f.path]);
      }
      for (const [bucket, paths] of byBucket) {
        const { error } = await admin.storage.from(bucket).remove(paths);
        if (error) report[`storage_${bucket}_error`] = error.message;
        else removed.push(...paths.map((p) => `${bucket}/${p}`));
      }
      report.files_removed = removed.length;

      report.visite_mediche_rfi = await deleteSafe(admin, "visite_mediche_rfi", "personale_id_uuid", pid);
      report.visite_mediche_programmazione = await deleteSafe(admin, "visite_mediche_programmazione", "personale_id_uuid", pid);
      report.dipendente_assenze = await deleteSafe(admin, "dipendente_assenze", "personale_id_uuid", pid);
      report.uqsa_attestati = await deleteSafe(admin, "uqsa_attestati", "personale_id", pid);
      if (includeSigned) {
        report.doc_firma_signed_pdf = await updateSafe(
          admin, "doc_firma_assignments", "personale_id", pid,
          { signed_pdf_path: null },
        );
      }
      report.gps_buoni_pasto = await updateSafe(
        admin, "buoni_pasto_registrazioni", "personale_id_uuid", pid,
        { latitudine: null, longitudine: null },
      );
      report.gps_viaggi_mezzi = await updateSafe(
        admin, "logistica_mezzi_stradali_viaggi", "personale_id_uuid", pid,
        { lat_inizio: null, lon_inizio: null, lat_fine: null, lon_fine: null },
      );
      if (authId) {
        const { data: u } = await admin
          .from("users").select("id").eq("auth_id", authId).maybeSingle();
        if (u?.id != null) {
          report.device_tokens = await deleteSafe(admin, "device_tokens", "user_id", u.id);
        }
      }
      await insertAppActivityLog({
        admin, authHeader, action: "privacy_purge_dipendente",
        detail: fullName || pid,
      });
      return json({ ok: true, report });
    }

    return json({ error: "action must be export or purge" }, 400);
  } catch (e) {
    console.error("admin-employee-privacy ERROR:", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

function collectFiles(data: Record<string, unknown>, includeSigned: boolean): FileRef[] {
  const out: FileRef[] = [];
  const rows = (k: string) => (Array.isArray(data[k]) ? data[k] as Row[] : []);
  for (const r of rows("visite_mediche_rfi")) {
    const p = String(r.pdf_file_path ?? "").trim();
    if (p) out.push({ bucket: "visite_mediche_rfi", path: p, source: "visite_mediche_rfi" });
  }
  for (const r of rows("uqsa_attestati")) {
    const p = String(r.file_path ?? "").trim();
    if (p) out.push({ bucket: "uqsa_attestati", path: p, source: "uqsa_attestati" });
  }
  if (includeSigned) {
    for (const r of rows("doc_firma_assignments")) {
      const p = String(r.signed_pdf_path ?? "").trim();
      if (p) out.push({ bucket: "doc_firma", path: p, source: "doc_firma_assignments" });
    }
  }
  return out;
}

async function selectSafe(
  admin: SupabaseClient, table: string, col: string, value: unknown,
): Promise<Row[]> {
  const { data, error } = await admin.from(table).select("*").eq(col, value);
  if (error) {
    console.warn(`select ${table}:`, error.message);
    return [];
  }
  return ((data ?? []) as Row[]).map(scrub);
}

async function deleteSafe(
  admin: SupabaseClient, table: string, col: string, value: unknown,
): Promise<number | string> {
  const { error, count } = await admin.from(table)
    .delete({ count: "exact" }).eq(col, value);
  return error ? `errore: ${error.message}` : (count ?? 0);
}

async function updateSafe(
  admin: SupabaseClient, table: string, col: string, value: unknown, patch: Row,
): Promise<number | string> {
  const { error, count } = await admin.from(table)
    .update(patch, { count: "exact" }).eq(col, value);
  return error ? `errore: ${error.message}` : (count ?? 0);
}

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
