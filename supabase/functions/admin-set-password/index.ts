// supabase/functions/admin-set-password/index.ts
import { createClient } from "npm:@supabase/supabase-js@2";

const USERS = "users";
const USERS_AUTH_ID_COL = "auth_id";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    //
    // 1) JWT del chiamante (deve essere admin)
    //
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer "))
      throw new HttpError(401, "Missing Authorization bearer token");

    const token = authHeader.replace("Bearer ", "").trim();
    if (!token || token.split(".").length !== 3)
      throw new HttpError(401, "Malformed JWT token");

    //
    // 2) Client utente → valida sessione con RLS
    //
    const supaUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );

    const { data: me, error: meErr } = await supaUser.auth.getUser();
    if (meErr || !me?.user)
      throw new HttpError(401, "Invalid session");

    //
    // 3) Check ADMIN in public.users
    //
    const { data: callerRow, error: roleErr } = await supaUser
      .from(USERS)
      .select("role")
      .eq(USERS_AUTH_ID_COL, me.user.id)
      .single();

    if (roleErr || !callerRow)
      throw new HttpError(403, "Caller not found in public.users");

    const role = String(callerRow.role ?? "").trim().toLowerCase();

    console.log("admin-set-password :: caller", {
      auth_id: me.user.id,
      role,
    });

    const isAdmin =
      role === "admin" ||
      role === "admin_generale" ||
      role === "admin_pernottamenti" ||
      role === "admin_trenoaereo";
    if (!isAdmin)
      throw new HttpError(403, "Forbidden: only admin");

    //
    // 4) Body (new_password OR password; auth_id OR email)
    //
    const body = (await req.json()) as {
      auth_id?: string;
      email?: string;
      new_password?: string;
      password?: string;
    };

    const rawPw = body.new_password ?? body.password;
    // Nessun trim silenzioso; stesse regole dell'app (PasswordPolicy).
    const newPassword = String(rawPw ?? "");
    if (
      newPassword.length < 10 ||
      newPassword !== newPassword.trim() ||
      !/[A-Za-z\u00C0-\u00FF]/.test(newPassword) ||
      !/\d/.test(newPassword)
    )
      throw new HttpError(
        400,
        "password_policy: min 10 caratteri, lettere e numeri, senza spazi iniziali/finali",
      );

    let targetAuthId = (body.auth_id ?? "").trim();
    const email = (body.email ?? "").trim().toLowerCase();

    //
    // 5) Admin client (service role)
    //
    const supaAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    //
    // 6) Se manca auth_id → tenta lookup veloce in public.users
    //
    if (!targetAuthId && email) {
      const { data: row, error: rowErr } = await supaAdmin
        .from(USERS)
        .select("auth_id")
        .eq("email", email) // volendo: .ilike("email", email)
        .maybeSingle();

      if (rowErr)
        throw new HttpError(500, `public.users lookup: ${rowErr.message}`);

      if (row?.auth_id)
        targetAuthId = row.auth_id;
    }

    // Se ancora non ho auth_id → errore chiaro
    if (!targetAuthId)
      throw new HttpError(400, "auth_id or email required");

    //
    // 7) Aggiorna password via admin.updateUserById
    //
    const { error: updErr } = await supaAdmin.auth.admin.updateUserById(
      targetAuthId,
      { password: newPassword }
    );

    if (updErr)
      throw new HttpError(500, `auth update: ${updErr.message}`);

    //
    // 8) (AGGIUNTO) Imposta must_change_password = TRUE nel profilo pubblico
    //    Così l'utente, al prossimo login, dovrà cambiare la password.
    //
    const { error: flagErr } = await supaAdmin
      .from(USERS)
      .update({ must_change_password: true })
      .eq(USERS_AUTH_ID_COL, targetAuthId);

    if (flagErr)
      throw new HttpError(500, `flag update: ${flagErr.message}`);

    return json({ ok: true, updated: true, must_change_password: true }, 200);

  } catch (e) {
    if (e instanceof HttpError)
      return json({ error: e.message }, e.status);

    console.error("admin-set-password :: unexpected", e);
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});
