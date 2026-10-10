// Invia OTP email per firma documento (doc_firma).
// Secrets: RESEND_API_KEY (opzionale), DOC_FIRMA_FROM_EMAIL (default noreply).
// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

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

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function randomOtp(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1000000;
  return String(n).padStart(6, "0");
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

    const body = await req.json();
    const assignmentId = String(body?.assignment_id || "").trim();
    if (!assignmentId) return json({ error: "assignment_id required" }, 400);

    const admin = createClient(supabaseUrl, serviceRole);

    const { data: assign, error: aErr } = await admin
      .from("doc_firma_assignments")
      .select(
        "id, status, sign_deadline, recipient_user_id, batch_id, doc_firma_batches(title)",
      )
      .eq("id", assignmentId)
      .maybeSingle();
    if (aErr || !assign) return json({ error: "Assignment not found" }, 404);
    if (assign.status !== "pending") {
      return json({ error: "Assignment not pending" }, 400);
    }
    if (new Date(assign.sign_deadline).getTime() < Date.now()) {
      await admin
        .from("doc_firma_assignments")
        .update({ status: "expired" })
        .eq("id", assignmentId);
      return json({ error: "Sign deadline expired" }, 400);
    }

    const { data: me } = await admin
      .from("users")
      .select("id, email, full_name, role")
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

    if (Number(me.id) !== Number(assign.recipient_user_id) && !isAdmin) {
      return json({ error: "Forbidden" }, 403);
    }

    const { data: recipient } = await admin
      .from("users")
      .select("id, email, full_name")
      .eq("id", assign.recipient_user_id)
      .maybeSingle();

    let email = String(recipient?.email || "").trim();
    if (!email) {
      const { data: pers } = await admin
        .from("personale")
        .select("email")
        .eq("user_id", String(recipient?.id || ""))
        .limit(1)
        .maybeSingle();
      email = String(pers?.email || "").trim();
    }
    if (!email || !email.includes("@")) {
      return json({ error: "Nessuna email sul dipendente" }, 400);
    }

    const code = randomOtp();
    const codeHash = await sha256Hex(code);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    const { error: storeErr } = await authClient.rpc("doc_firma_store_otp", {
      p_assignment_id: assignmentId,
      p_code_hash: codeHash,
      p_expires_at: expiresAt,
    });
    if (storeErr) {
      // Fallback service role insert
      const { error: insErr } = await admin.from("doc_firma_otp").insert({
        assignment_id: assignmentId,
        code_hash: codeHash,
        expires_at: expiresAt,
      });
      if (insErr) {
        return json({ error: "OTP store failed", details: String(insErr.message) }, 500);
      }
    }

    const title =
      (assign.doc_firma_batches as { title?: string } | null)?.title ||
      "Documento";
    const fromEmail =
      (Deno.env.get("DOC_FIRMA_FROM_EMAIL") || "noreply@cronosrail.com").trim();
    const resendKey = (Deno.env.get("RESEND_API_KEY") || "").trim();

    let emailed = false;
    let emailError: string | null = null;
    if (resendKey) {
      const mailRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: fromEmail,
          to: [email],
          subject: `Codice firma documento — ${title}`,
          text:
            `Ciao ${recipient?.full_name || ""},\n\n` +
            `Il tuo codice per firmare «${title}» è: ${code}\n` +
            `Valido 10 minuti.\n\n` +
            `Se non hai richiesto tu la firma, ignora questa email.\n` +
            `CRONOS GESTOPRO`,
          html:
            `<p>Ciao ${recipient?.full_name || ""},</p>` +
            `<p>Il tuo codice per firmare <strong>${title}</strong> è:</p>` +
            `<p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p>` +
            `<p>Valido 10 minuti.</p>` +
            `<p>CRONOS GESTOPRO</p>`,
        }),
      });
      emailed = mailRes.ok;
      if (!mailRes.ok) {
        const t = await mailRes.text();
        emailError = `Resend ${mailRes.status}: ${t.slice(0, 200)}`;
        console.error("Resend fail", mailRes.status, t);
      }
    } else {
      emailError = "RESEND_API_KEY non configurata";
      console.error("doc-firma-send-otp: missing RESEND_API_KEY");
    }

    // Fallback: notifica in-app con il codice se email non inviata
    if (!emailed) {
      await admin.from("notifications").insert({
        user_id: assign.recipient_user_id,
        title: "Codice firma documento",
        message: `Codice OTP per «${title}»: ${code} (valido 10 minuti).`,
        meta: {
          type: "doc_firma_otp",
          assignment_id: assignmentId,
          skip_os_push: true,
        },
        is_read: false,
      });
    }

    const masked = email.replace(/(.{2}).+(@.+)/, "$1***$2");
    return json({
      ok: true,
      emailed,
      delivery: emailed ? "email" : "notification",
      email_masked: masked,
      expires_at: expiresAt,
      ...(emailError && !emailed ? { email_error: emailError } : {}),
    });
  } catch (e) {
    console.error("doc-firma-send-otp", e);
    return json({ error: String(e) }, 500);
  }
});
