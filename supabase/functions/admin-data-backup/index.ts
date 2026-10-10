import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "cronos_data_backups";
const REPLICA_BUCKET = "cronos_data_backups_replica";
const INSERT_BATCH = 250;
const RESTORE_PHRASE = "RIPRISTINA";

class HttpError extends Error {
  status: number;
  constructor(status: number, msg: string) {
    super(msg);
    this.status = status;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

type Body = {
  action?: "list" | "run" | "manifest" | "restore";
  backup_date?: string;
  confirm_password?: string;
  confirm_phrase?: string;
  /** primary = bucket principale; secondary = replica / S3 */
  source?: "primary" | "secondary";
};

type S3Config = {
  endpoint: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  region: string;
  provider: string;
};

function isAdminGenerale(role: string): boolean {
  const r = role.trim().toLowerCase();
  return r === "admin" || r === "admin_generale";
}

function assertDate(d: string): string {
  const s = d.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new HttpError(400, "backup_date deve essere YYYY-MM-DD");
  }
  return s;
}

function parseSource(raw: unknown): "primary" | "secondary" {
  const s = String(raw ?? "primary").trim().toLowerCase();
  if (s === "secondary" || s === "replica" || s === "secondaria") {
    return "secondary";
  }
  return "primary";
}

function readS3Config(): S3Config | null {
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

async function s3GetObject(cfg: S3Config, objectKey: string): Promise<string> {
  const client = new AwsClient({
    accessKeyId: cfg.accessKey,
    secretAccessKey: cfg.secretKey,
    region: cfg.region,
    service: "s3",
  });
  const base = cfg.endpoint.replace(/\/$/, "");
  const url = `${base}/${cfg.bucket}/${objectKey}`;
  const res = await client.fetch(url, { method: "GET" });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(
      `S3 GET ${objectKey}: HTTP ${res.status} ${txt.slice(0, 200)}`,
    );
  }
  return await res.text();
}

async function s3ListPrefix(cfg: S3Config, prefix: string): Promise<string[]> {
  const client = new AwsClient({
    accessKeyId: cfg.accessKey,
    secretAccessKey: cfg.secretKey,
    region: cfg.region,
    service: "s3",
  });
  const base = cfg.endpoint.replace(/\/$/, "");
  const pref = prefix.endsWith("/") ? prefix : `${prefix}/`;
  const url =
    `${base}/${cfg.bucket}?list-type=2&prefix=${
      encodeURIComponent(pref)
    }&delimiter=/`;
  const res = await client.fetch(url, { method: "GET" });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`S3 LIST ${pref}: HTTP ${res.status} ${txt.slice(0, 200)}`);
  }
  const xml = await res.text();
  const names: string[] = [];
  const re = /<Key>([^<]+)<\/Key>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const key = m[1];
    const file = key.slice(pref.length);
    if (file && !file.includes("/")) names.push(file);
  }
  return names;
}

type StorageReader = {
  label: string;
  downloadText: (path: string) => Promise<string>;
  listNames: (prefix: string) => Promise<string[]>;
};

// deno-lint-ignore no-explicit-any
function primaryReader(admin: any): StorageReader {
  return {
    label: "primaria (cronos_data_backups)",
    async downloadText(path) {
      const { data, error } = await admin.storage.from(BUCKET).download(path);
      if (error || !data) {
        throw new HttpError(404, error?.message || `File non trovato: ${path}`);
      }
      return await data.text();
    },
    async listNames(prefix) {
      const { data, error } = await admin.storage
        .from(BUCKET)
        .list(prefix, { limit: 500 });
      if (error) throw new HttpError(500, error.message);
      return (data ?? []).map((f: { name: string }) => f.name);
    },
  };
}

// deno-lint-ignore no-explicit-any
function replicaReader(admin: any): StorageReader {
  return {
    label: "secondaria (cronos_data_backups_replica)",
    async downloadText(path) {
      const { data, error } = await admin.storage
        .from(REPLICA_BUCKET)
        .download(path);
      if (error || !data) {
        throw new HttpError(
          404,
          error?.message || `File non trovato in replica: ${path}`,
        );
      }
      return await data.text();
    },
    async listNames(prefix) {
      const { data, error } = await admin.storage
        .from(REPLICA_BUCKET)
        .list(prefix, { limit: 500 });
      if (error) throw new HttpError(500, error.message);
      return (data ?? []).map((f: { name: string }) => f.name);
    },
  };
}

function s3Reader(cfg: S3Config): StorageReader {
  return {
    label: `secondaria (${cfg.provider})`,
    async downloadText(path) {
      try {
        return await s3GetObject(cfg, path);
      } catch (e) {
        throw new HttpError(404, e instanceof Error ? e.message : String(e));
      }
    },
    async listNames(prefix) {
      try {
        return await s3ListPrefix(cfg, prefix);
      } catch (e) {
        throw new HttpError(500, e instanceof Error ? e.message : String(e));
      }
    },
  };
}

async function resolveReader(
  // deno-lint-ignore no-explicit-any
  admin: any,
  source: "primary" | "secondary",
  backupDate: string,
): Promise<StorageReader> {
  if (source === "primary") return primaryReader(admin);

  const replica = replicaReader(admin);
  try {
    await replica.downloadText(`daily/${backupDate}/_manifest.json`);
    return replica;
  } catch {
    // fallthrough to S3
  }

  const s3 = readS3Config();
  if (s3) return s3Reader(s3);

  throw new HttpError(
    404,
    `Copia secondaria non trovata per ${backupDate} `
      + `(né bucket replica né S3/R2 configurato).`,
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      throw new HttpError(401, "Missing Authorization bearer token");
    }
    const token = authHeader.replace("Bearer ", "").trim();
    if (!token || token.split(".").length !== 3) {
      throw new HttpError(401, "Malformed JWT token");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const supaUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: me, error: meErr } = await supaUser.auth.getUser();
    if (meErr || !me?.user) throw new HttpError(401, "Invalid session");

    const { data: callerRow, error: roleErr } = await supaUser
      .from("users")
      .select("role, email, full_name")
      .eq("auth_id", me.user.id)
      .single();
    if (roleErr || !callerRow) {
      throw new HttpError(403, "Caller not found in public.users");
    }

    if (!isAdminGenerale(String(callerRow.role ?? ""))) {
      throw new HttpError(
        403,
        "Forbidden: solo admin generale può gestire i backup",
      );
    }

    const body = (await req.json().catch(() => ({}))) as Body;
    const action = String(body.action || "list").trim();
    const source = parseSource(body.source);

    const admin = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === "list") {
      const { data, error } = await admin
        .from("data_backup_runs")
        .select(
          "id, backup_date, started_at, finished_at, ok, tables_count, rows_count, "
            + "storage_prefix, error_message, secondary_ok, secondary_provider, "
            + "secondary_error",
        )
        .order("backup_date", { ascending: false })
        .limit(40);
      if (error) throw new HttpError(500, error.message);
      return json({
        ok: true,
        runs: data ?? [],
        secondary_bucket: REPLICA_BUCKET,
        primary_bucket: BUCKET,
      });
    }

    const confirmPassword = String(body.confirm_password || "");
    if (!confirmPassword) {
      throw new HttpError(400, "confirm_password required");
    }

    const callerEmail =
      (me.user.email || String(callerRow.email || "")).trim();
    if (!callerEmail) {
      throw new HttpError(400, "Email admin assente: impossibile confermare");
    }
    const { error: pwErr } = await createClient(supabaseUrl, anonKey).auth
      .signInWithPassword({
        email: callerEmail,
        password: confirmPassword,
      });
    if (pwErr) {
      throw new HttpError(403, "Password admin non corretta");
    }

    if (action === "run") {
      const res = await fetch(
        `${supabaseUrl}/functions/v1/daily-data-backup`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${serviceRole}`,
            apikey: serviceRole,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            source: "admin-data-backup",
            triggered_by: me.user.id,
          }),
        },
      );
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new HttpError(
          res.status,
          (payload as { error?: string })?.error ||
            `Backup fallito (${res.status})`,
        );
      }
      return json({ ok: true, ...(payload as Record<string, unknown>) });
    }

    if (action === "manifest") {
      const backupDate = assertDate(String(body.backup_date || ""));
      const reader = await resolveReader(admin, source, backupDate);
      const path = `daily/${backupDate}/_manifest.json`;
      const text = await reader.downloadText(path);
      const manifest = JSON.parse(text);
      return json({
        ok: true,
        backup_date: backupDate,
        source,
        source_label: reader.label,
        manifest,
      });
    }

    if (action === "restore") {
      const backupDate = assertDate(String(body.backup_date || ""));
      const phrase = String(body.confirm_phrase || "").trim().toUpperCase();
      if (phrase !== RESTORE_PHRASE) {
        throw new HttpError(
          400,
          `Per confermare digita esattamente «${RESTORE_PHRASE}»`,
        );
      }

      const reader = await resolveReader(admin, source, backupDate);
      const prefix = `daily/${backupDate}`;
      const names = await reader.listNames(prefix);
      const tableFiles = names.filter(
        (n) => n.endsWith(".json") && n !== "_manifest.json",
      );
      if (tableFiles.length === 0) {
        throw new HttpError(
          404,
          `Nessun file tabella nella copia ${source} del ${backupDate}`,
        );
      }

      const { data: truncated, error: truncErr } = await admin.rpc(
        "_admin_backup_truncate_public_tables",
      );
      if (truncErr) throw new HttpError(500, truncErr.message);

      const restored: { table: string; rows: number }[] = [];
      const errors: { table: string; error: string }[] = [];

      for (const fileName of tableFiles.sort()) {
        const table = fileName.replace(/\.json$/i, "");
        try {
          const text = await reader.downloadText(`${prefix}/${fileName}`);
          const rows = JSON.parse(text) as Record<string, unknown>[];
          if (!Array.isArray(rows)) {
            throw new Error("JSON non è un array");
          }
          if (rows.length === 0) {
            restored.push({ table, rows: 0 });
            continue;
          }
          for (let i = 0; i < rows.length; i += INSERT_BATCH) {
            const chunk = rows.slice(i, i + INSERT_BATCH);
            const { error: insErr } = await admin.from(table).insert(chunk);
            if (insErr) {
              throw new Error(insErr.message);
            }
          }
          restored.push({ table, rows: rows.length });
        } catch (e) {
          errors.push({
            table,
            error: e instanceof Error ? e.message : String(e),
          });
        }
      }

      return json({
        ok: errors.length === 0,
        backup_date: backupDate,
        source,
        source_label: reader.label,
        truncated_tables: truncated ?? [],
        restored,
        errors: errors.length ? errors : undefined,
        tables_ok: restored.length,
        tables_failed: errors.length,
      });
    }

    throw new HttpError(
      400,
      "action must be list, run, manifest or restore",
    );
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("admin-data-backup", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});
