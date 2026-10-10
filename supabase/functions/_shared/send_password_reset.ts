import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Recupero password GESTOPRO360.
 * - Risposta SEMPRE identica ({ ok: true }) -> nessuna enumerazione email.
 * - Redirect fisso lato server (allow-list), il valore del client è ignorato.
 * - Rate limit base in memoria (per isolate): per email e per IP.
 * - Email in italiano brandizzata via Resend (template condiviso).
 */

// --- Rate limit (best-effort: la memoria è per istanza della funzione) ---
const EMAIL_MIN_INTERVAL_MS = 60_000; // 1 richiesta/minuto per email
const EMAIL_MAX_PER_HOUR = 5;
const IP_MAX_PER_15MIN = 10;
const emailHits = new Map<string, number[]>();
const ipHits = new Map<string, number[]>();

function hit(map: Map<string, number[]>, key: string, windowMs: number): number[] {
  const now = Date.now();
  const arr = (map.get(key) ?? []).filter((t) => now - t < windowMs);
  map.set(key, arr);
  return arr;
}

function isRateLimited(email: string, ip: string): boolean {
  const now = Date.now();
  const e = hit(emailHits, email, 3_600_000);
  const i = hit(ipHits, ip, 900_000);
  const lastE = e.length ? e[e.length - 1] : 0;
  const limited = (now - lastE < EMAIL_MIN_INTERVAL_MS) ||
    e.length >= EMAIL_MAX_PER_HOUR ||
    (ip !== "unknown" && i.length >= IP_MAX_PER_15MIN);
  // Conteggiamo anche le richieste bloccate per l'IP (anti-scansione).
  i.push(now);
  if (!limited) e.push(now);
  return limited;
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Risposta unica per ogni esito (inviata, utente inesistente, limite, errore). */
export const GENERIC_OK = () => json({ ok: true });

// --- Redirect: allow-list fissa lato server ---
const RECOVERY_LANDING = "https://gestopro360.it/password-recovery";
const ALLOWED_LANDINGS = new Set([
  "https://gestopro360.it/password-recovery",
  "https://www.gestopro360.it/password-recovery",
]);

function landingBase(): string {
  const env = (Deno.env.get("RESET_PASSWORD_REDIRECT_URL") || "").trim();
  return ALLOWED_LANDINGS.has(env) ? env : RECOVERY_LANDING;
}

/** Link sulla nostra app: gli scanner della mail non bruciano il token su /verify. */
function recoveryLandingUrl(hashedToken: string): string {
  const u = new URL(landingBase());
  u.searchParams.set("token_hash", hashedToken);
  u.searchParams.set("type", "recovery");
  return u.toString();
}

export function clientIp(req: Request): string {
  const xf = req.headers.get("x-forwarded-for") || "";
  return (xf.split(",")[0] || req.headers.get("cf-connecting-ip") || "unknown")
    .trim() || "unknown";
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!
  );
}

/** Layout email GESTOPRO360 (stesso stile di supabase/templates/recovery.html). */
export function brandedEmailHtml(args: {
  title: string;
  paragraphs: string[];
  button?: { label: string; url: string };
  footer: string;
}): string {
  const ps = args.paragraphs
    .map((p) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.5;color:#1f2933">${p}</p>`)
    .join("");
  const btn = args.button
    ? `<p style="margin:22px 0"><a href="${escapeHtml(args.button.url)}" style="display:inline-block;padding:12px 22px;background:#0d47a1;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:700;font-size:15px">${args.button.label}</a></p>`
    : "";
  return `<!doctype html><html lang="it"><body style="margin:0;background:#f2f5f9;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden">
<tr><td style="background:#0d47a1;padding:18px 24px;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:1px">GESTOPRO360</td></tr>
<tr><td style="padding:26px 24px">
<h1 style="margin:0 0 16px;font-size:20px;color:#0d47a1">${args.title}</h1>
${ps}${btn}
<p style="margin:18px 0 0;font-size:12px;line-height:1.5;color:#6b7280">${args.footer}</p>
</td></tr>
<tr><td style="background:#f8fafc;padding:14px 24px;font-size:11px;color:#9ca3af">Email automatica di GESTOPRO360 · non rispondere a questo messaggio.</td></tr>
</table></td></tr></table></body></html>`;
}

export async function sendWithResend(args: {
  to: string;
  subject: string;
  text: string;
  html: string;
}): Promise<{ ok: boolean; error?: string }> {
  const resendKey = (Deno.env.get("RESEND_API_KEY") || "").trim();
  if (!resendKey) return { ok: false, error: "RESEND_API_KEY missing" };
  const fromEmail = (Deno.env.get("PASSWORD_RESET_FROM_EMAIL") ||
    Deno.env.get("DOC_FIRMA_FROM_EMAIL") ||
    "noreply@cronosrail.com").trim();
  const fromName = (Deno.env.get("PASSWORD_RESET_FROM_NAME") || "GESTOPRO360").trim();
  // RESEND_API_URL: solo per test locali (mock); default API reale.
  const apiUrl = (Deno.env.get("RESEND_API_URL") || "https://api.resend.com/emails").trim();
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${fromName} <${fromEmail}>`,
      to: [args.to],
      subject: args.subject,
      text: args.text,
      html: args.html,
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    return { ok: false, error: `Resend ${res.status}: ${t.slice(0, 240)}` };
  }
  return { ok: true };
}

function recoveryEmail(link: string) {
  const subject = "GESTOPRO360 · Imposta una nuova password";
  const text =
    "Ciao,\n\nabbiamo ricevuto una richiesta di reimpostazione della password del tuo account GESTOPRO360.\n\n" +
    `Apri questo link nel browser per scegliere una nuova password:\n${link}\n\n` +
    "Il link vale 60 minuti e si può usare una sola volta.\n" +
    "Se non hai chiesto tu il reset, ignora questa email: la tua password resta invariata.\n\nGESTOPRO360";
  const html = brandedEmailHtml({
    title: "Imposta una nuova password",
    paragraphs: [
      "Ciao,",
      "abbiamo ricevuto una richiesta di reimpostazione della password del tuo account <strong>GESTOPRO360</strong>.",
      "Premi il pulsante e scegli una nuova password (almeno 10 caratteri, con lettere e numeri).",
    ],
    button: { label: "Imposta nuova password", url: link },
    footer:
      "Il link vale <strong>60 minuti</strong> e si può usare una sola volta. " +
      "Se non hai chiesto tu il reset, ignora questa email: la tua password resta invariata.",
  });
  return { subject, text, html };
}

export async function sendPasswordResetEmail(args: {
  email: string;
  ip?: string;
}): Promise<Response> {
  const email = args.email.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email)) return GENERIC_OK();

  if (isRateLimited(email, args.ip ?? "unknown")) {
    console.warn("password-reset rate limited", { ip: args.ip });
    return GENERIC_OK();
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    // Senza Resend: invio diretto con la mail Auth (template recovery.html).
    // NB: non chiamare generateLink prima, altrimenti GoTrue applica
    // max_frequency e rifiuta l'invio ("only request this after N seconds").
    if (!(Deno.env.get("RESEND_API_KEY") || "").trim()) {
      const { error: eAuth } = await admin.auth.resetPasswordForEmail(email, {
        redirectTo: landingBase(),
      });
      if (eAuth) console.warn("resetPasswordForEmail", eAuth.message);
      return GENERIC_OK();
    }
    const { data, error } = await admin.auth.admin.generateLink({
      type: "recovery",
      email,
      options: { redirectTo: landingBase() },
    });
    if (error) {
      // Utente inesistente o altro: nessuna differenza verso il client.
      console.warn("generateLink", error.message);
      return GENERIC_OK();
    }
    const props = (data as {
      properties?: { action_link?: string; hashed_token?: string };
    })?.properties;
    const hashedToken = (props?.hashed_token || "").trim();
    if (!hashedToken) {
      console.error("generateLink: hashed_token mancante");
      return GENERIC_OK();
    }
    const mail = recoveryEmail(recoveryLandingUrl(hashedToken));
    const sent = await sendWithResend({ to: email, ...mail });
    if (!sent.ok) {
      // Niente fallback Auth qui: il token appena generato farebbe scattare
      // il limite di frequenza di GoTrue. Errore da monitorare nei log.
      console.error("Resend KO: email di recupero NON inviata:", sent.error);
    }
  } catch (e) {
    console.error("sendPasswordResetEmail", e);
  }
  return GENERIC_OK();
}
