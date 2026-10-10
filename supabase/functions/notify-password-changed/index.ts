import { createClient } from "npm:@supabase/supabase-js@2";
import {
  brandedEmailHtml,
  corsHeaders,
  json,
  sendWithResend,
} from "../_shared/send_password_reset.ts";

// Invia "La tua password è stata cambiata" all'utente del JWT (verify_jwt = true).
// L'indirizzo è preso dal token, mai dal body: non si può usare per spam.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const token = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "unauthorized" }, 401);
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } },
    );
    const { data, error } = await sb.auth.getUser();
    const email = data?.user?.email;
    if (error || !email) return json({ error: "unauthorized" }, 401);

    const when = new Date().toLocaleString("it-IT", { timeZone: "Europe/Rome" });
    const supportEmail = (Deno.env.get("SECURITY_CONTACT_EMAIL") || "").trim();
    const contact = supportEmail
      ? `scrivi subito a ${supportEmail} o al tuo amministratore`
      : "avvisa subito il tuo amministratore";
    const sent = await sendWithResend({
      to: email,
      subject: "GESTOPRO360 · La tua password è stata cambiata",
      text:
        `Ciao,\n\nla password del tuo account GESTOPRO360 è stata cambiata il ${when}.\n` +
        "Per sicurezza tutti i dispositivi sono stati disconnessi.\n\n" +
        `Se non sei stato tu, ${contact} e richiedi un nuovo reset dalla pagina di accesso.\n\nGESTOPRO360`,
      html: brandedEmailHtml({
        title: "Password cambiata",
        paragraphs: [
          "Ciao,",
          `la password del tuo account <strong>GESTOPRO360</strong> è stata cambiata il <strong>${when}</strong>.`,
          "Per sicurezza tutti i dispositivi sono stati disconnessi.",
        ],
        footer: `Se non sei stato tu, ${contact} e richiedi un nuovo reset dalla pagina di accesso.`,
      }),
    });
    if (!sent.ok) console.warn("notify-password-changed:", sent.error);
    return json({ ok: true });
  } catch (e) {
    console.error("notify-password-changed", e);
    return json({ ok: true });
  }
});
