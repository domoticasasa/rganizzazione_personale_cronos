import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
  action?: "list_passkeys" | "reset_passkeys";
  auth_id?: string;
  /** Password dell'admin chiamante (conferma). */
  confirm_password?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
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

    const role = String(callerRow.role ?? "").trim().toLowerCase();
    if (role !== "admin" && role !== "admin_generale") {
      throw new HttpError(
        403,
        "Forbidden: solo admin generale può resettare le Passkey",
      );
    }

    const body = (await req.json()) as Body;
    const action = String(body.action || "").trim();
    const targetAuthId = String(body.auth_id || "").trim();
    const confirmPassword = String(body.confirm_password || "");

    if (!targetAuthId) throw new HttpError(400, "auth_id required");
    if (!confirmPassword) {
      throw new HttpError(400, "confirm_password required");
    }

    // Re-auth admin: password corrente obbligatoria.
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

    const admin = createClient(supabaseUrl, serviceRole, {
      auth: {
        // @ts-expect-error experimental passkey admin API
        experimental: { passkey: true },
      },
    });

    if (action === "list_passkeys") {
      const passkeys = await listPasskeys(admin, supabaseUrl, serviceRole, targetAuthId);
      return json({
        ok: true,
        auth_id: targetAuthId,
        count: passkeys.length,
        passkeys,
      });
    }

    if (action === "reset_passkeys") {
      const passkeys = await listPasskeys(admin, supabaseUrl, serviceRole, targetAuthId);
      let deleted = 0;
      const errors: string[] = [];
      for (const pk of passkeys) {
        try {
          await deletePasskey(
            admin,
            supabaseUrl,
            serviceRole,
            targetAuthId,
            pk.id,
          );
          deleted++;
        } catch (e) {
          errors.push(`${pk.id}: ${String(e)}`);
        }
      }
      return json({
        ok: errors.length === 0,
        auth_id: targetAuthId,
        found: passkeys.length,
        deleted,
        errors: errors.length ? errors : undefined,
      });
    }

    throw new HttpError(400, "action must be list_passkeys or reset_passkeys");
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("admin-reset-passkeys", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

type PasskeyRow = {
  id: string;
  friendly_name?: string | null;
  created_at?: string | null;
  last_used_at?: string | null;
};

async function listPasskeys(
  admin: ReturnType<typeof createClient>,
  supabaseUrl: string,
  serviceRole: string,
  userId: string,
): Promise<PasskeyRow[]> {
  try {
    // SDK admin (se disponibile nella versione deployata).
    const api = (admin.auth as { admin?: { passkey?: {
      listPasskeys: (args: { userId: string }) => Promise<{
        data: PasskeyRow[] | null;
        error: { message?: string } | null;
      }>;
    } } }).admin?.passkey;
    if (api?.listPasskeys) {
      const { data, error } = await api.listPasskeys({ userId });
      if (error) throw new Error(error.message || "listPasskeys failed");
      return Array.isArray(data) ? data : [];
    }
  } catch (e) {
    console.warn("admin.passkey.listPasskeys fallback REST", e);
  }

  const res = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}/passkeys`,
    {
      headers: {
        apikey: serviceRole,
        Authorization: `Bearer ${serviceRole}`,
      },
    },
  );
  if (!res.ok) {
    const txt = await res.text();
    throw new HttpError(res.status, `list passkeys: ${txt.slice(0, 240)}`);
  }
  const body = await res.json();
  if (Array.isArray(body)) return body as PasskeyRow[];
  if (Array.isArray(body?.passkeys)) return body.passkeys as PasskeyRow[];
  if (Array.isArray(body?.data)) return body.data as PasskeyRow[];
  return [];
}

async function deletePasskey(
  admin: ReturnType<typeof createClient>,
  supabaseUrl: string,
  serviceRole: string,
  userId: string,
  passkeyId: string,
): Promise<void> {
  try {
    const api = (admin.auth as { admin?: { passkey?: {
      deletePasskey: (args: {
        userId: string;
        passkeyId: string;
      }) => Promise<{ error: { message?: string } | null }>;
    } } }).admin?.passkey;
    if (api?.deletePasskey) {
      const { error } = await api.deletePasskey({ userId, passkeyId });
      if (error) throw new Error(error.message || "deletePasskey failed");
      return;
    }
  } catch (e) {
    console.warn("admin.passkey.deletePasskey fallback REST", e);
  }

  const res = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}/passkeys/${encodeURIComponent(passkeyId)}`,
    {
      method: "DELETE",
      headers: {
        apikey: serviceRole,
        Authorization: `Bearer ${serviceRole}`,
      },
    },
  );
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`delete passkey: ${txt.slice(0, 240)}`);
  }
}
