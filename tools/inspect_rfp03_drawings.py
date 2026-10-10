import re
import zipfile
from pathlib import Path

p = Path(r"c:\flutter_projects\organizzazione_personale_cronos - mod\assets\Mod.RFP_03.xlsx")
with zipfile.ZipFile(p) as z:
    drawing = z.read("xl/drawings/drawing1.xml").decode("utf-8")
    rels = z.read("xl/drawings/_rels/drawing1.xml.rels").decode("utf-8")
    print("RELS:")
    print(rels)
    print("\nANCHORS:")
    for block in re.findall(r"<xdr:twoCellAnchor[\s\S]*?</xdr:twoCellAnchor>", drawing):
        embed = re.search(r'r:embed="([^"]+)"', block)
        from_col = re.search(r'<xdr:from>[\s\S]*?<xdr:col>(\d+)</xdr:col>', block)
        from_row = re.search(r'<xdr:from>[\s\S]*?<xdr:row>(\d+)</xdr:row>', block)
        to_col = re.search(r'<xdr:to>[\s\S]*?<xdr:col>(\d+)</xdr:col>', block)
        to_row = re.search(r'<xdr:to>[\s\S]*?<xdr:row>(\d+)</xdr:row>', block)
        ext = re.search(r'<xdr:ext cx="(\d+)" cy="(\d+)"', block)
        rid = embed.group(1) if embed else "?"
        rname = re.search(rf'Id="{rid}"[^>]+Target="([^"]+)"', rels)
        print(
            f"  {rname.group(1) if rname else rid}: "
            f"from col={from_col.group(1) if from_col else '?'} row={from_row.group(1) if from_row else '?'} "
            f"to col={to_col.group(1) if to_col else '?'} row={to_row.group(1) if to_row else '?'} "
            f"ext={ext.group(1) if ext else '?'}x{ext.group(2) if ext else '?'}"
        )

    styles = z.read("xl/styles.xml").decode("utf-8")
    fills = re.findall(r"<fill>[\s\S]*?</fill>", styles)
    print(f"\nFILLS count: {len(fills)}")
    for i, f in enumerate(fills[:15]):
        rgb = re.search(r'rgb="([A-F0-9]+)"', f)
        theme = re.search(r'theme="(\d+)"', f)
        print(f"  fill{i}: rgb={rgb.group(1) if rgb else None} theme={theme.group(1) if theme else None}")
