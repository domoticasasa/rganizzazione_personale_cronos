// Converte Office (xlsx/docx) o passa PDF tramite Gotenberg (LibreOffice).
// Richiede secret GOTENBERG_URL. PDF in ingresso restituito così com'è.
// @ts-nocheck
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

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}

function looksLikePdf(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 5 &&
    bytes[0] === 0x25 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x44 &&
    bytes[3] === 0x46
  );
}

function mimeForName(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".docx")) {
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  if (lower.endsWith(".doc")) return "application/msword";
  if (lower.endsWith(".xlsx")) {
    return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  }
  if (lower.endsWith(".xls")) return "application/vnd.ms-excel";
  return "application/octet-stream";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const fileBase64 = (body?.fileBase64 ?? "").toString().trim();
    const fileName = (body?.fileName ?? "document.xlsx").toString().trim();
    if (!fileBase64) {
      return json({ error: "fileBase64 required" }, 400);
    }

    const bytes = base64ToBytes(fileBase64);
    if (!bytes.length) {
      return json({ error: "empty file" }, 400);
    }

    if (looksLikePdf(bytes) || fileName.toLowerCase().endsWith(".pdf")) {
      return json({ pdfBase64: bytesToBase64(bytes), skipped: true });
    }

    const gotenbergUrl = (Deno.env.get("GOTENBERG_URL") ?? "").replace(/\/$/, "");
    if (!gotenbergUrl) {
      return json({
        error: "gotenberg_not_configured",
        details:
          "Conversione Word/Excel non disponibile. Carica un PDF, oppure configura GOTENBERG_URL (vedi deploy/gotenberg).",
      }, 503);
    }

    const form = new FormData();
    const safeName = fileName.includes(".") ? fileName : `${fileName}.xlsx`;
    form.append(
      "files",
      new Blob([bytes], { type: mimeForName(safeName) }),
      safeName,
    );
    if (safeName.toLowerCase().endsWith(".xlsx") ||
      safeName.toLowerCase().endsWith(".xls")) {
      form.append("singlePageSheets", "true");
    }

    const conv = await fetch(`${gotenbergUrl}/forms/libreoffice/convert`, {
      method: "POST",
      body: form,
    });
    if (!conv.ok) {
      const errText = await conv.text();
      return json(
        { error: "Gotenberg conversion failed", details: errText.slice(0, 500) },
        502,
      );
    }

    const pdfBytes = new Uint8Array(await conv.arrayBuffer());
    if (!pdfBytes.length || !looksLikePdf(pdfBytes)) {
      return json({ error: "empty pdf output" }, 502);
    }

    return json({ pdfBase64: bytesToBase64(pdfBytes) });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
