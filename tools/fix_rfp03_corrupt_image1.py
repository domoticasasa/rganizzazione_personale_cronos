"""Rimuove image1.jpeg corrotto dal template Mod.RFP_03 (strisce accanto a SOA GROUP)."""
import io
import re
import zipfile
from pathlib import Path
from zipfile import ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
XLSX = ROOT / "assets" / "Mod.RFP_03.xlsx"


def main() -> None:
    with zipfile.ZipFile(XLSX) as z:
        drawing = z.read("xl/drawings/drawing1.xml").decode("utf-8")
        rels = z.read("xl/drawings/_rels/drawing1.xml.rels").decode("utf-8")

    rid_match = re.search(
        r'Id="(rId\d+)"[^>]+Target="\.\./media/image1\.jpeg"',
        rels,
    )
    if not rid_match:
        print("image1.jpeg non trovato nelle relazioni.")
        return
    rid = rid_match.group(1)
    print(f"Rimuovo anchor {rid} -> image1.jpeg")

    parts = re.split(r"(<xdr:twoCellAnchor[\s\S]*?</xdr:twoCellAnchor>)", drawing)
    kept = []
    removed = 0
    for part in parts:
        if part.startswith("<xdr:twoCellAnchor") and f'r:embed="{rid}"' in part:
            removed += 1
            continue
        kept.append(part)
    new_drawing = "".join(kept)

    new_rels = re.sub(
        rf'<Relationship Id="{rid}"[^>]*/>\s*',
        "",
        rels,
    )

    buf = io.BytesIO()
    with zipfile.ZipFile(XLSX) as zin, zipfile.ZipFile(buf, "w", ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "xl/drawings/drawing1.xml":
                data = new_drawing.encode("utf-8")
            elif item.filename == "xl/drawings/_rels/drawing1.xml.rels":
                data = new_rels.encode("utf-8")
            zout.writestr(item, data)

    out_path = ROOT / "assets" / "Mod.RFP_03_fixed.xlsx"
    out_path.write_bytes(buf.getvalue())
    try:
        XLSX.write_bytes(buf.getvalue())
        print(f"Fatto: rimossi {removed} anchor. File: {XLSX}")
    except OSError as e:
        print(f"Impossibile sovrascrivere {XLSX} ({e}).")
        print(f"Salvato come {out_path} — chiudi Excel e rinomina manualmente.")
    else:
        out_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
