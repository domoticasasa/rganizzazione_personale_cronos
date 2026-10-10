import {
  clientIp,
  corsHeaders,
  GENERIC_OK,
  json,
  sendPasswordResetEmail,
} from "../_shared/send_password_reset.ts";

// Pubblica (verify_jwt = false). Risponde SEMPRE { ok: true }: nessun dettaglio
// su esistenza email, limiti o errori. Il redirectTo del client è ignorato.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  try {
    const body = await req.json().catch(() => ({}));
    return await sendPasswordResetEmail({
      email: String(body?.email ?? ""),
      ip: clientIp(req),
    });
  } catch (e) {
    console.error("request-password-reset", e);
    return GENERIC_OK();
  }
});
