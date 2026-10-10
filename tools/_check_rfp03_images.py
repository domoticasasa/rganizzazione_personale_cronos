import hashlib
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = [
    ROOT / "assets" / "Mod.RFP_03.xlsx",
    ROOT / "build" / "web" / "assets" / "assets" / "Mod.RFP_03.xlsx",
]

for p in paths:
    if not p.exists():
        print(f"MISSING {p}")
        continue
    print(f"\n=== {p} ({p.stat().st_size} bytes) ===")
    with zipfile.ZipFile(p) as z:
        media = sorted(x for x in z.namelist() if x.startswith("xl/media/"))
        linked = set()
        for n in z.namelist():
            if n.endswith(".rels"):
                txt = z.read(n).decode("utf-8", "ignore")
                linked.update(re.findall(r'Target="\.\./media/([^"]+)"', txt))
        for m in media:
            name = m.split("/")[-1]
            data = z.read(m)
            md5 = hashlib.md5(data).hexdigest()[:8]
            flag = "LINKED" if name in linked else "ORPHAN"
            print(f"  {name:16} {len(data):6} md5={md5} {flag}")

        drawing = z.read("xl/drawings/drawing1.xml").decode("utf-8")
        rels = z.read("xl/drawings/_rels/drawing1.xml.rels").decode("utf-8")
        rid_to_media = dict(re.findall(r'Id="(rId\d+)"[^>]+Target="\.\./media/([^"]+)"', rels))
        for block in re.findall(r"<xdr:twoCellAnchor[\s\S]*?</xdr:twoCellAnchor>", drawing):
            embed = re.search(r'r:embed="([^"]+)"', block)
            if not embed:
                continue
            media_name = rid_to_media.get(embed.group(1), "?")
            from_row = re.search(r"<xdr:from>[\s\S]*?<xdr:row>(\d+)</xdr:row>", block)
            from_col = re.search(r"<xdr:from>[\s\S]*?<xdr:col>(\d+)</xdr:col>", block)
            print(
                f"  anchor {media_name}: col={from_col.group(1) if from_col else '?'} "
                f"row={from_row.group(1) if from_row else '?'}"
            )

out = ROOT / "tools" / "_rfp03_extract"
out.mkdir(exist_ok=True)
p = ROOT / "assets" / "Mod.RFP_03.xlsx"
if p.exists():
    with zipfile.ZipFile(p) as z:
        for img in ["image11.png", "image12.png", "image13.png"]:
            data = z.read(f"xl/media/{img}")
            (out / img).write_bytes(data)
    print(f"\nExtracted to {out}")
