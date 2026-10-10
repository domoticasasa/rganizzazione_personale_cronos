import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cronos-backup-secret",
};

const RETENTION_DAYS = 60; // 10/10/2026: allineato al contratto (60 giorni)
const PAGE_SIZE = 1000;
const BUCKET = "cronos_data_backups";
const REPLICA_BUCKET = "cronos_data_backups_replica";
const REPLICA_PROVIDER = "supabase-replica";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function romeDateString(d = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Rome",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

function addDaysRome(isoDate: string, delta: number): string {
  const [y, m, d] = isoDate.split("-").map((x) => Number(x));
  const utc = Date.UTC(y, m - 1, d + delta);
  return romeDateString(new Date(utc));
}

function authorize(req: Request): boolean {
  const secret = (Deno.env.get("DAILY_BACKUP_SECRET") ?? "").trim();
  const headerSecret = (req.headers.get("x-cronos-backup-secret") ?? "").trim();
  if (secret && headerSecret && headerSecret === secret) return true;

  const auth = req.headers.get("Authorization") ?? "";
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (
    serviceRole &&
    auth.startsWith("Bearer ") &&
    auth.slice(7).trim() === serviceRole
  ) {
    return true;
  }
  return false;
}

type SecondaryConfig = {
  endpoint: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  region: string;
  provider: string;
};

function readSecondaryConfig(): SecondaryConfig | null {
  const endpoint = (Deno.env.get("BACKUP_S3_ENDPOINT") ?? "").trim();
  const bucket = (Deno.env.get("BACKUP_S3_BUCKET") ?? "").trim();
  const accessKey = (Deno.env.get("BACKUP_S3_ACCESS_KEY_ID") ?? "").trim();
  const secretKey = (Deno.env.get("BACKUP_S3_SECRET_ACCESS_KEY") ?? "").trim();
  const region = (Deno.env.get("BACKUP_S3_REGION") ?? "auto").trim() || "auto";
  const provider =
    (Deno.env.get("BACKUP_S3_PROVIDER") ?? "").trim() || "s3-compatible";
  if (!endpoint || !bucket || !accessKey || !secretKey) return null;
  return { endpoint, bucket, accessKey, secretKey, region, provider };
}

async function mirrorObjectS3(
  cfg: SecondaryConfig,
  objectKey: string,
  body: string | Uint8Array,
  contentType: string,
): Promise<void> {
  const client = new AwsClient({
    accessKeyId: cfg.accessKey,
    secretAccessKey: cfg.secretKey,
    region: cfg.region,
    service: "s3",
  });
  const base = cfg.endpoint.replace(/\/$/, "");
  const url = `${base}/${cfg.bucket}/${objectKey}`;
  const res = await client.fetch(url, {
    method: "PUT",
    headers: { "Content-Type": contentType },
    body,
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(
      `secondary ${objectKey}: HTTP ${res.status} ${txt.slice(0, 200)}`,
    );
  }
}

async function fetchAllRows(
  // deno-lint-ignore no-explicit-any
  client: any,
  table: string,
): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await client
      .from(table)
      .select("*")
      .range(from, from + PAGE_SIZE - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    const batch = (data ?? []) as Record<string, unknown>[];
    out.push(...batch);
    if (batch.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
  }
  return out;
}

async function purgeOldDailyFolders(
  // deno-lint-ignore no-explicit-any
  admin: any,
  bucket: string,
  cutoff: string,
): Promise<string[]> {
  const { data: listed, error: listErr } = await admin.storage
    .from(bucket)
    .list("daily", { limit: 200, sortBy: { column: "name", order: "asc" } });
  if (listErr) throw new Error(`list ${bucket}/daily: ${listErr.message}`);

  const deletedPrefixes: string[] = [];
  for (const entry of listed ?? []) {
    const name = (entry.name ?? "").trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(name)) continue;
    if (name >= cutoff) continue;

    const folder = `daily/${name}`;
    const { data: files, error: filesErr } = await admin.storage
      .from(bucket)
      .list(folder, { limit: 500 });
    if (filesErr) throw new Error(`list ${folder}: ${filesErr.message}`);
    const paths = (files ?? [])
      .map((f: { name: string }) => `${folder}/${f.name}`)
      .filter((p: string) => !p.endsWith("/"));
    if (paths.length > 0) {
      const { error: delErr } = await admin.storage.from(bucket).remove(paths);
      if (delErr) throw new Error(`delete ${folder}: ${delErr.message}`);
    }
    deletedPrefixes.push(`${bucket}:${folder}`);
  }
  return deletedPrefixes;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!authorize(req)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const backupDate = romeDateString();
  const prefix = `daily/${backupDate}`;
  const startedAt = new Date().toISOString();
  const s3Cfg = readSecondaryConfig();
  const useReplica = s3Cfg == null;
  const secondaryProvider = s3Cfg?.provider ?? REPLICA_PROVIDER;

  let triggerSource = "unknown";
  try {
    const body = await req.json().catch(() => ({}));
    triggerSource = String((body as { source?: string })?.source ?? "unknown")
      .trim()
      .slice(0, 60) || "unknown";
  } catch {
    triggerSource = "unknown";
  }

  await admin.from("data_backup_runs").upsert(
    {
      backup_date: backupDate,
      started_at: startedAt,
      finished_at: null,
      ok: null,
      tables_count: null,
      rows_count: null,
      storage_prefix: prefix,
      error_message: null,
      secondary_ok: null,
      secondary_provider: secondaryProvider,
      secondary_error: null,
      trigger_source: triggerSource,
    },
    { onConflict: "backup_date" },
  );

  try {
    const { data: tableNames, error: tablesErr } = await admin.rpc(
      "_backup_list_public_tables",
    );
    if (tablesErr) throw new Error(tablesErr.message);
    const tables = (tableNames as string[] | null) ?? [];

    let totalRows = 0;
    const tableStats: { table: string; rows: number }[] = [];
    let secondaryError: string | null = null;
    let secondaryOk = true;

    async function mirrorSecondary(
      path: string,
      body: string,
    ): Promise<void> {
      if (s3Cfg) {
        await mirrorObjectS3(s3Cfg, path, body, "application/json");
        return;
      }
      const { error } = await admin.storage
        .from(REPLICA_BUCKET)
        .upload(path, new Blob([body], { type: "application/json" }), {
          upsert: true,
          contentType: "application/json",
        });
      if (error) throw new Error(`replica ${path}: ${error.message}`);
    }

    for (const table of tables) {
      const rows = await fetchAllRows(admin, table);
      totalRows += rows.length;
      tableStats.push({ table, rows: rows.length });

      const body = JSON.stringify(rows);
      const path = `${prefix}/${table}.json`;
      const { error: upErr } = await admin.storage
        .from(BUCKET)
        .upload(path, new Blob([body], { type: "application/json" }), {
          upsert: true,
          contentType: "application/json",
        });
      if (upErr) throw new Error(`upload ${table}: ${upErr.message}`);

      if (secondaryOk) {
        try {
          await mirrorSecondary(path, body);
        } catch (e) {
          secondaryOk = false;
          secondaryError = e instanceof Error ? e.message : String(e);
        }
      }
    }

    const manifest = {
      backup_date: backupDate,
      created_at: new Date().toISOString(),
      timezone: "Europe/Rome",
      retention_days: RETENTION_DAYS,
      tables: tableStats,
      tables_count: tables.length,
      rows_count: totalRows,
      secondary: {
        provider: secondaryProvider,
        mode: useReplica ? "supabase-replica-bucket" : "s3-compatible",
        ok: secondaryOk,
        error: secondaryError,
      },
    };
    const manifestBody = JSON.stringify(manifest, null, 2);
    const { error: manErr } = await admin.storage
      .from(BUCKET)
      .upload(
        `${prefix}/_manifest.json`,
        new Blob([manifestBody], { type: "application/json" }),
        { upsert: true, contentType: "application/json" },
      );
    if (manErr) throw new Error(`manifest: ${manErr.message}`);

    if (secondaryOk) {
      try {
        await mirrorSecondary(`${prefix}/_manifest.json`, manifestBody);
      } catch (e) {
        secondaryOk = false;
        secondaryError = e instanceof Error ? e.message : String(e);
      }
    }

    const cutoff = addDaysRome(backupDate, -RETENTION_DAYS);
    const deletedPrefixes = await purgeOldDailyFolders(admin, BUCKET, cutoff);
    if (useReplica) {
      try {
        deletedPrefixes.push(
          ...(await purgeOldDailyFolders(admin, REPLICA_BUCKET, cutoff)),
        );
      } catch (e) {
        // Retention replica non bloccante.
        console.warn("replica retention", e);
      }
    }

    const finishedAt = new Date().toISOString();
    await admin.from("data_backup_runs").upsert(
      {
        backup_date: backupDate,
        started_at: startedAt,
        finished_at: finishedAt,
        ok: true,
        tables_count: tables.length,
        rows_count: totalRows,
        storage_prefix: prefix,
        error_message: null,
        secondary_ok: secondaryOk,
        secondary_provider: secondaryProvider,
        secondary_error: secondaryError?.slice(0, 2000) ?? null,
        trigger_source: triggerSource,
      },
      { onConflict: "backup_date" },
    );

    return json({
      ok: true,
      backup_date: backupDate,
      storage_prefix: prefix,
      tables_count: tables.length,
      rows_count: totalRows,
      deleted_prefixes: deletedPrefixes,
      retention_days: RETENTION_DAYS,
      secondary: {
        configured: true,
        provider: secondaryProvider,
        ok: secondaryOk,
        error: secondaryError,
      },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await admin.from("data_backup_runs").upsert(
      {
        backup_date: backupDate,
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        ok: false,
        storage_prefix: prefix,
        error_message: msg.slice(0, 2000),
        trigger_source: triggerSource,
      },
      { onConflict: "backup_date" },
    );
    return json({ ok: false, error: msg }, 500);
  }
});
