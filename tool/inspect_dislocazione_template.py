import re
import zipfile
from pathlib import Path

p = Path(r"c:\flutter_projects\organizzazione_personale_cronos - mod\assets\Programma_impegno_personale_mod.xlsx")
with zipfile.ZipFile(p) as z:
    xml = z.read("xl/worksheets/sheet1.xml").decode("utf-8")

print("len", len(xml))
dim = re.search(r'<dimension[^>]*ref="([^"]+)"', xml)
print("dim", dim.group(1) if dim else None)
rows = [int(x) for x in re.findall(r'<row r="(\d+)"', xml)]
print("rows", len(rows), "min", min(rows), "max", max(rows))
cells = re.findall(r'<c r="([A-Z]+\d+)"', xml)
print("cells", len(cells))
m = re.search(r"(<row r=\"4\"[^>]*>.*?</row>)", xml, re.S)
if m:
    s = m.group(1)
    print("row4 cells", len(re.findall(r"<c r=", s)))
    print(s[:500])
