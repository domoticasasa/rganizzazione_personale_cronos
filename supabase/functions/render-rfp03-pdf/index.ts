// PDF Mod.RFP_03: sfondo Excel + overlay dati compilati (identico al template).
// @ts-nocheck
import JSZip from "npm:jszip@3.10.1";
import * as XLSX from "npm:xlsx@0.18.5";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";
import cellCoords from "./cell_coords.json" with { type: "json" };
import { BACKGROUND_PDF_B64 } from "./background_pdf.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PAYLOAD_REFS = [
  "B13", "B16", "K16", "N18", "R18", "D37", "D38", "D40", "E40",
  "C44", "D49", "N46", "E46",
];

const RED = rgb(192 / 255, 0, 0);
const BLACK = rgb(0, 0, 0);
const WHITE = rgb(1, 1, 1);

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
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

function readCells(xlsxBytes: Uint8Array): Record<string, string> {
  const wb = XLSX.read(xlsxBytes, { type: "array", cellDates: false });
  const name = wb.SheetNames.includes("Mod.RFP")
    ? "Mod.RFP"
    : wb.SheetNames[0];
  const ws = wb.Sheets[name];
  const out: Record<string, string> = {};
  for (const ref of PAYLOAD_REFS) {
    const c = ws[ref];
    out[ref] = c ? String(c.w ?? c.v ?? "").trim() : "";
  }
  return out;
}

type Rect = { x: number; y: number; w: number; h: number };

function rect(key: string): Rect {
  return cellCoords.cells[key];
}

function paintWhite(page, r: Rect, pad = 1) {
  page.drawRectangle({
    x: r.x - pad,
    y: r.y - pad,
    width: r.w + pad * 2,
    height: r.h + pad * 2,
    color: WHITE,
    borderWidth: 0,
  });
}

function drawCentered(
  page,
  r: Rect,
  text: string,
  font,
  size: number,
  color = BLACK,
  bold = false,
) {
  if (!text) return;
  const f = bold ? font.bold : font.reg;
  const tw = f.widthOfTextAtSize(text, size);
  const th = size;
  page.drawText(text, {
    x: r.x + Math.max(2, (r.w - tw) / 2),
    y: r.y + (r.h - th) / 2,
    size,
    font: f,
    color,
  });
}

function drawLeft(
  page,
  r: Rect,
  text: string,
  font,
  size: number,
  color = BLACK,
  bold = false,
) {
  if (!text) return;
  const f = bold ? font.bold : font.reg;
  page.drawText(text, {
    x: r.x + 3,
    y: r.y + (r.h - size) / 2,
    size,
    font: f,
    color,
  });
}

async function buildPdf(cells: Record<string, string>): Promise<Uint8Array> {
  const bgBytes = base64ToBytes(BACKGROUND_PDF_B64);
  const bgDoc = await PDFDocument.load(bgBytes);
  const pdf = await PDFDocument.create();
  const [tpl] = await pdf.copyPages(bgDoc, [0]);
  const page = pdf.addPage(tpl);

  const font = {
    reg: await pdf.embedFont(StandardFonts.Helvetica),
    bold: await pdf.embedFont(StandardFonts.HelveticaBold),
  };

  const nomeDip = cells.D49 || "Dipendente";
  const intro =
    cells.B13 ||
    `Il Sottoscritto ${nomeDip} chiede autorizzazione a usufruire di:`;
  const dataRichiesta = cells.B16 || "";
  const giorni = cells.K16 || "";
  const dal = cells.N18 || "";
  const al = cells.R18 || "";
  const dataLabel =
    cells.C44 ||
    (dataRichiesta ? `Data richiesta: ${dataRichiesta}` : "");
  const firmaDatore =
    cells.N46 || "Firma Datore Lavoro: LUCA VIVIAN";

  // Intro dipendente
  paintWhite(page, rect("B13"));
  drawLeft(page, rect("B13"), intro, font, 9, BLACK, true);

  // Riga riepilogo DATA / N° GIORNI
  if (dataRichiesta) {
    paintWhite(page, rect("B16"));
    drawCentered(page, rect("B16"), dataRichiesta, font, 9, BLACK, true);
  }
  if (giorni) {
    paintWhite(page, rect("K16"));
    drawCentered(page, rect("K16"), giorni, font, 9, BLACK, true);
  }

  // Prima riga tabella
  if (giorni) {
    paintWhite(page, rect("K18"));
    drawCentered(page, rect("K18"), giorni, font, 8.5, BLACK, true);
  }
  if (dal) {
    paintWhite(page, rect("N18"));
    drawCentered(page, rect("N18"), dal, font, 8.5, BLACK, true);
  }
  if (al) {
    paintWhite(page, rect("R18"));
    drawCentered(page, rect("R18"), al, font, 8.5, BLACK, true);
  }

  // Tipo assenza: ● rosso sulla riga selezionata
  const tipoRows = [
    { key: "D37", row: "D37" },
    { key: "D38", row: "D38" },
    { key: "D40", row: "D40" },
  ];
  for (const t of tipoRows) {
    const sel =
      (cells[t.key] || "").toUpperCase() === "X" ||
      (cells[t.key] || "").includes("●");
    if (!sel) continue;
    const r = rect(t.row);
    paintWhite(page, { x: r.x, y: r.y, w: 14, h: r.h }, 0.5);
    page.drawText("●", {
      x: r.x + 2,
      y: r.y + (r.h - 10) / 2,
      size: 10,
      font: font.bold,
      color: RED,
    });
  }
  if (cells.E40) {
    paintWhite(page, rect("E40"));
    drawLeft(page, rect("E40"), cells.E40, font, 8.5);
  }

  // Data richiesta
  if (dataLabel) {
    paintWhite(page, rect("C44"));
    drawLeft(page, rect("C44"), dataLabel, font, 9, RED, true);
  }

  // Firme
  paintWhite(page, rect("N46"));
  drawLeft(page, rect("N46"), firmaDatore, font, 8, BLACK, true);

  paintWhite(page, rect("D49"));
  drawCentered(page, rect("D49"), nomeDip, font, 9, BLACK, true);

  if (cells.E46) {
    paintWhite(page, rect("E46"));
    drawLeft(page, rect("E46"), cells.E46, font, 7);
  }

  return pdf.save();
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
    if (!fileBase64) return json({ error: "fileBase64 required" }, 400);

    const xlsxBytes = base64ToBytes(fileBase64);
    if (!xlsxBytes.length) return json({ error: "empty file" }, 400);

    const cells = readCells(xlsxBytes);
    const pdfBytes = await buildPdf(cells);
    return json({ pdfBase64: bytesToBase64(pdfBytes) });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
