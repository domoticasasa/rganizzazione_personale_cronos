import base64
import textwrap
from pathlib import Path

pdf = Path(__file__).resolve().parents[1] / "assets" / "Mod.RFP_03_background.pdf"
out = Path(__file__).resolve().parents[1] / "supabase/functions/render-rfp03-pdf/background_pdf.ts"
b64 = base64.b64encode(pdf.read_bytes()).decode("ascii")
chunks = textwrap.wrap(b64, 100)
lines = [
    "// Auto-generated — run: python tools/gen_background_pdf_ts.py",
    "export const BACKGROUND_PDF_B64 = [",
]
lines.extend(f'  "{c}",' for c in chunks)
lines.append('].join("");')
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {out} ({len(chunks)} chunks)")
