// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function randomCode(len: number): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  let out = "";
  for (let i = 0; i < len; i++) out += alphabet[bytes[i]! % alphabet.length];
  return out;
}

function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!url || !serviceKey) return json({ error: "Server misconfigured" }, 500);

  const admin = createClient(url, serviceKey);
  const body = await req.json().catch(() => ({}));
  const action = String(body?.action ?? "").trim();

  try {
    if (action === "start") {
      const publicCode = randomCode(8);
      const claimSecret = randomSecret();
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      const { data, error } = await admin
        .from("auth_qr_sessions")
        .insert({
          public_code: publicCode,
          claim_secret: claimSecret,
          expires_at: expiresAt,
          status: "pending",
        })
        .select("id, public_code, claim_secret, expires_at")
        .single();
      if (error) throw error;
      return json({
        ok: true,
        id: data.id,
        public_code: data.public_code,
        claim_secret: data.claim_secret,
        expires_at: data.expires_at,
      });
    }

    if (action === "poll") {
      const id = String(body?.id ?? "").trim();
      const claimSecret = String(body?.claim_secret ?? "").trim();
      if (!id || !claimSecret) {
        return json({ error: "id e claim_secret obbligatori" }, 400);
      }
      const { data, error } = await admin
        .from("auth_qr_sessions")
        .select(
          "id, status, expires_at, created_at, access_token, refresh_token, claim_secret",
        )
        .eq("id", id)
        .maybeSingle();
      if (error) throw error;
      if (!data || data.claim_secret !== claimSecret) {
        return json({ error: "Sessione non trovata" }, 404);
      }
      if (
        data.status === "pending" &&
        new Date(data.expires_at).getTime() < Date.now()
      ) {
        await admin
          .from("auth_qr_sessions")
          .update({ status: "expired" })
          .eq("id", id)
          .eq("status", "pending");
        return json({ ok: true, status: "expired" });
      }
      if (data.status === "pending") {
        // Il PC tiene aperto il dialog: rinnova la scadenza (web mobile +
        // impronta possono richiedere più di 5 minuti). Max 30 min dalla creazione.
        const createdAt = new Date(data.created_at ?? data.expires_at).getTime();
        if (Date.now() - createdAt < 30 * 60 * 1000) {
          const extended = new Date(Date.now() + 5 * 60 * 1000).toISOString();
          await admin
            .from("auth_qr_sessions")
            .update({ expires_at: extended })
            .eq("id", id)
            .eq("status", "pending");
        }
        return json({ ok: true, status: "pending" });
      }
      if (data.status === "claimed" || data.status === "cancelled") {
        return json({ ok: true, status: data.status });
      }
      if (data.status === "approved") {
        const access = data.access_token;
        const refresh = data.refresh_token;
        if (!refresh) {
          return json({
            ok: false,
            status: "approved",
            error: "Token refresh assente su sessione approvata",
          }, 500);
        }
        await admin
          .from("auth_qr_sessions")
          .update({
            status: "claimed",
            claimed_at: new Date().toISOString(),
            access_token: null,
            refresh_token: null,
          })
          .eq("id", id)
          .eq("status", "approved");
        return json({
          ok: true,
          status: "approved",
          access_token: access,
          refresh_token: refresh,
        });
      }
      return json({ ok: true, status: data.status });
    }

    if (action === "approve") {
      const publicCode = String(body?.public_code ?? "")
        .trim()
        .toUpperCase();
      if (!publicCode) return json({ error: "public_code obbligatorio" }, 400);

      // Preferisci refresh_token: access JWT può essere scaduto/orfano
      // («session_id claim in JWT does not exist»).
      let accessToken = String(body?.access_token ?? "").trim() || (() => {
        const h = req.headers.get("Authorization") ?? "";
        return h.toLowerCase().startsWith("bearer ")
          ? h.slice(7).trim()
          : "";
      })();
      let refreshToken = String(body?.refresh_token ?? "").trim();
      if (!accessToken || !refreshToken) {
        return json({
          error:
            "Token sessione telefono assenti. Riesegui Accedi sul telefono e riprova.",
        }, 401);
      }

      const userClient = createClient(url, anonKey || serviceKey);
      let userId = "";
      const refreshed = await userClient.auth.refreshSession({
        refresh_token: refreshToken,
      });
      if (!refreshed.error && refreshed.data?.session) {
        accessToken = refreshed.data.session.access_token;
        refreshToken = refreshed.data.session.refresh_token ?? refreshToken;
        userId = refreshed.data.session.user?.id ??
          refreshed.data.user?.id ??
          "";
      }
      if (!userId) {
        const { data: userData, error: userErr } = await userClient.auth
          .getUser(accessToken);
        if (userErr || !userData?.user) {
          return json({
            error:
              "Sessione telefono non valida o scaduta. " +
              "Sul telefono esci, Accedi di nuovo con password, poi conferma il QR.",
          }, 401);
        }
        userId = userData.user.id;
      }

      const { data: row, error: findErr } = await admin
        .from("auth_qr_sessions")
        .select("id, status, expires_at")
        .eq("public_code", publicCode)
        .maybeSingle();
      if (findErr) throw findErr;
      if (!row) return json({ error: "Codice QR non valido o scaduto" }, 404);
      if (new Date(row.expires_at).getTime() < Date.now()) {
        await admin
          .from("auth_qr_sessions")
          .update({ status: "expired" })
          .eq("id", row.id);
        return json({ error: "Codice scaduto. Genera un nuovo QR sul PC." }, 410);
      }
      if (row.status === "approved" || row.status === "claimed") {
        return json({ ok: true, status: row.status, already: true });
      }
      if (row.status !== "pending") {
        return json({ error: `QR non utilizzabile (${row.status}).` }, 409);
      }

      const { error: updErr } = await admin
        .from("auth_qr_sessions")
        .update({
          status: "approved",
          approved_at: new Date().toISOString(),
          user_auth_id: userId,
          access_token: accessToken,
          refresh_token: refreshToken,
        })
        .eq("id", row.id)
        .eq("status", "pending");
      if (updErr) throw updErr;
      return json({ ok: true, status: "approved" });
    }

    if (action === "cancel") {
      const id = String(body?.id ?? "").trim();
      const claimSecret = String(body?.claim_secret ?? "").trim();
      if (!id || !claimSecret) {
        return json({ error: "id e claim_secret obbligatori" }, 400);
      }
      await admin
        .from("auth_qr_sessions")
        .update({ status: "cancelled" })
        .eq("id", id)
        .eq("claim_secret", claimSecret)
        .eq("status", "pending");
      return json({ ok: true });
    }

    return json({ error: "action non valida" }, 400);
  } catch (e) {
    console.error("auth-qr-login", e);
    return json(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
