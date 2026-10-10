/**
 * Mod.RFP_03: xlsx → PDF (ExcelTS) con re-iniezione immagini da MS Excel.
 * ExcelTS/ExcelJS spesso non collega i drawing di file salvati con Excel → PDF ~8KB.
 */
(function () {
  window.__cronosRfp03PdfScriptLoaded = true;
  var cached = null;
  var loadPromise = null;
  var lastError = "";

  var CDN_URLS = [
    "https://cdn.jsdelivr.net/npm/@cj-tech-master/excelts@9.5.7/+esm",
    "https://esm.sh/@cj-tech-master/excelts@9.5.7?bundle",
    "https://unpkg.com/@cj-tech-master/excelts@9.5.7/+esm",
  ];
  var JSZIP_URL = "https://cdn.jsdelivr.net/npm/jszip@3.10.1/+esm";

  function pdfUrlFrom(baseUrl) {
    if (baseUrl.indexOf("jsdelivr") >= 0) {
      return "https://cdn.jsdelivr.net/npm/@cj-tech-master/excelts@9.5.7/pdf/+esm";
    }
    if (baseUrl.indexOf("unpkg") >= 0) {
      return "https://unpkg.com/@cj-tech-master/excelts@9.5.7/pdf/+esm";
    }
    return "https://esm.sh/@cj-tech-master/excelts@9.5.7/pdf?bundle";
  }

  function pickExport(mod, name) {
    if (!mod) return null;
    if (mod[name]) return mod[name];
    if (mod.default && mod.default[name]) return mod.default[name];
    return null;
  }

  function loadExcelTs() {
    if (cached) return Promise.resolve(cached);
    if (loadPromise) return loadPromise;

    loadPromise = (async function () {
      var err = null;
      var JSZip = null;
      try {
        var zipMod = await import(JSZIP_URL);
        JSZip = pickExport(zipMod, "default") || zipMod;
      } catch (e) {
        console.warn("[RFP03 PDF] JSZip non disponibile:", e);
      }

      for (var i = 0; i < CDN_URLS.length; i++) {
        try {
          var baseUrl = CDN_URLS[i];
          console.info("[RFP03 PDF] carico ExcelTS da", baseUrl);
          var excelMod = await import(baseUrl);
          var Workbook = pickExport(excelMod, "Workbook");
          var excelToPdf = pickExport(excelMod, "excelToPdf");
          if (!excelToPdf) {
            var pdfMod = await import(pdfUrlFrom(baseUrl));
            excelToPdf = pickExport(pdfMod, "excelToPdf");
          }
          if (!Workbook || !excelToPdf) {
            throw new Error("Workbook/excelToPdf mancanti da " + baseUrl);
          }
          cached = { Workbook: Workbook, excelToPdf: excelToPdf, JSZip: JSZip };
          lastError = "";
          console.info("[RFP03 PDF] ExcelTS pronto");
          return cached;
        } catch (e) {
          err = e;
          lastError = String(e && e.message ? e.message : e);
          console.warn("[RFP03 PDF] load fallito:", lastError);
        }
      }
      throw err || new Error("ExcelTS: impossibile caricare da CDN");
    })();

    loadPromise.catch(function (e) {
      lastError = String(e && e.message ? e.message : e);
    });

    return loadPromise;
  }

  function toArrayBuffer(bytes) {
    if (bytes instanceof ArrayBuffer) return bytes;
    if (ArrayBuffer.isView(bytes)) {
      return bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
      );
    }
    return new Uint8Array(bytes).buffer;
  }

  function asUint8(pdf) {
    if (pdf instanceof Uint8Array) return pdf;
    if (pdf instanceof ArrayBuffer) return new Uint8Array(pdf);
    if (ArrayBuffer.isView(pdf)) {
      return new Uint8Array(
        pdf.buffer.slice(pdf.byteOffset, pdf.byteOffset + pdf.byteLength)
      );
    }
    throw new Error("ExcelTS: output PDF non riconosciuto");
  }

  function countSheetImages(wb) {
    var n = 0;
    try {
      if (typeof wb.eachSheet === "function") {
        wb.eachSheet(function (ws) {
          try {
            if (ws.getImages) n += (ws.getImages() || []).length;
          } catch (_) {}
        });
      }
    } catch (_) {}
    return n;
  }

  function parseRidMap(relsXml) {
    var map = {};
    var re = /Id="(rId\d+)"[^>]*Target="([^"]+)"/g;
    var m;
    while ((m = re.exec(relsXml))) {
      map[m[1]] = m[2].replace(/^\/xl\//, "xl/").replace(/^\.\.\/media\//, "xl/media/");
    }
    re = /Target="([^"]+)"[^>]*Id="(rId\d+)"/g;
    while ((m = re.exec(relsXml))) {
      map[m[2]] = m[1].replace(/^\/xl\//, "xl/").replace(/^\.\.\/media\//, "xl/media/");
    }
    return map;
  }

  function extOf(path) {
    var p = (path || "").toLowerCase();
    if (p.endsWith(".png")) return "png";
    if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "jpeg";
    if (p.endsWith(".gif")) return "gif";
    return "png";
  }

  function u8ToBase64(u8) {
    var s = "";
    var chunk = 0x8000;
    for (var i = 0; i < u8.length; i += chunk) {
      s += String.fromCharCode.apply(null, u8.subarray(i, Math.min(i + chunk, u8.length)));
    }
    return btoa(s);
  }

  /** Re-aggiunge i drawing MS Excel sul foglio se ExcelTS non li ha collegati. */
  async function reinjectImages(mod, wb, xlsxBytes) {
    if (!mod.JSZip) {
      console.warn("[RFP03 PDF] skip reinject: no JSZip");
      return;
    }
    var before = countSheetImages(wb);
    if (before >= 8) {
      console.info("[RFP03 PDF] immagini già presenti:", before);
      return;
    }

    var zip = await mod.JSZip.loadAsync(toArrayBuffer(xlsxBytes));
    var drawingFile = zip.file("xl/drawings/drawing1.xml");
    var relsFile = zip.file("xl/drawings/_rels/drawing1.xml.rels");
    if (!drawingFile || !relsFile) {
      console.warn("[RFP03 PDF] drawing1.xml mancante");
      return;
    }
    var drawingXml = await drawingFile.async("string");
    var relsXml = await relsFile.async("string");
    var ridMap = parseRidMap(relsXml);

    var ws =
      (wb.getWorksheet && (wb.getWorksheet("Mod.RFP") || wb.getWorksheet(1))) ||
      (wb.worksheets && wb.worksheets[0]);
    if (!ws || !ws.addImage || !wb.addImage) {
      console.warn("[RFP03 PDF] worksheet.addImage non disponibile");
      return;
    }

    var anchorRe =
      /<twoCellAnchor[\s\S]*?<from>[\s\S]*?<col>(\d+)<\/col>[\s\S]*?<row>(\d+)<\/row>[\s\S]*?<\/from>[\s\S]*?<to>[\s\S]*?<col>(\d+)<\/col>[\s\S]*?<row>(\d+)<\/row>[\s\S]*?<\/to>[\s\S]*?r:embed="(rId\d+)"[\s\S]*?<\/twoCellAnchor>/g;
    var m;
    var added = 0;
    while ((m = anchorRe.exec(drawingXml))) {
      var c1 = parseInt(m[1], 10);
      var r1 = parseInt(m[2], 10);
      var c2 = parseInt(m[3], 10);
      var r2 = parseInt(m[4], 10);
      var rid = m[5];
      var mediaPath = ridMap[rid];
      if (!mediaPath) continue;
      if (mediaPath.indexOf("xl/media/") !== 0) {
        mediaPath = "xl/media/" + mediaPath.split("/").pop();
      }
      var mediaFile = zip.file(mediaPath);
      if (!mediaFile) {
        console.warn("[RFP03 PDF] media mancante", mediaPath);
        continue;
      }
      var buf = await mediaFile.async("uint8array");
      var ext = extOf(mediaPath);
      var imageId;
      try {
        imageId = wb.addImage({
          base64: u8ToBase64(buf),
          extension: ext,
        });
      } catch (e1) {
        try {
          imageId = wb.addImage({
            buffer: buf,
            extension: ext,
          });
        } catch (e2) {
          console.warn("[RFP03 PDF] addImage fallito", rid, e2);
          continue;
        }
      }
      try {
        ws.addImage(imageId, {
          tl: { col: c1, row: r1 },
          br: { col: Math.max(c1 + 1, c2) + 0.99, row: Math.max(r1 + 1, r2) + 0.99 },
          editAs: "oneCell",
        });
        added++;
      } catch (e3) {
        console.warn("[RFP03 PDF] ws.addImage fallito", rid, e3);
      }
    }
    console.info(
      "[RFP03 PDF] immagini reiniettate:",
      added,
      "totale foglio:",
      countSheetImages(wb)
    );
  }

  function prepareWorkbookForPdf(wb) {
    try {
      var sheets = [];
      if (typeof wb.eachSheet === "function") {
        wb.eachSheet(function (ws) {
          sheets.push(ws);
        });
      } else if (wb.worksheets && wb.worksheets.forEach) {
        wb.worksheets.forEach(function (ws) {
          sheets.push(ws);
        });
      }
      sheets.forEach(function (ws) {
        try {
          ws.views = [
            { state: "normal", showGridLines: false, showRowColHeaders: false },
          ];
        } catch (_) {}
        if (ws.pageSetup) {
          try {
            ws.pageSetup.showGridLines = false;
            ws.pageSetup.printGridlines = false;
            ws.pageSetup.fitToPage = true;
            ws.pageSetup.fitToWidth = 1;
            ws.pageSetup.fitToHeight = 1;
            ws.pageSetup.printArea = "A1:T62";
          } catch (_) {}
        }
      });
    } catch (e) {
      console.warn("[RFP03 PDF] prepareWorkbook:", e);
    }
  }

  window.cronosExcelToPdfReady = function () {
    return loadExcelTs().then(function () {});
  };

  window.cronosExcelToPdfLastError = function () {
    return lastError || "";
  };

  window.cronosExcelToPdf = function (xlsxBytes) {
    return loadExcelTs()
      .then(async function (mod) {
        var buf = toArrayBuffer(xlsxBytes);
        var wb = new mod.Workbook();
        await wb.xlsx.load(buf.slice(0));
        await reinjectImages(mod, wb, xlsxBytes);
        prepareWorkbookForPdf(wb);
        var pdf = asUint8(
          await mod.excelToPdf(wb, {
            showGridLines: false,
            showPageNumbers: false,
          })
        );
        if (!pdf || pdf.length === 0) {
          throw new Error("PDF vuoto da ExcelTS");
        }
        console.info("[RFP03 PDF] ok bytes=", pdf.length);
        return pdf;
      })
      .catch(function (e) {
        lastError = String(e && e.message ? e.message : e);
        console.error("[RFP03 PDF] errore:", lastError);
        throw e;
      });
  };

  loadExcelTs().catch(function () {});
})();
