"""Estende template dislocazione: 500 righe nominativi (Excel righe 4-503)."""
from __future__ import annotations

import re
import zipfile
from io import BytesIO
from pathlib import Path

FIRST_DATA_ROW = 4
LAST_DATA_ROW = 503  # 500 righe dati

SRC = Path(
    r"c:\Users\alexandru.cibuc\Desktop\logistica\Programma impegno personale mod.xlsx"
)
DST = Path(
    r"c:\flutter_projects\organizzazione_personale_cronos - mod\assets\Programma_impegno_personale_mod.xlsx"
)


def col_letter(n: int) -> str:
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def renumber_row(row_xml: str, new_row: int) -> str:
    def repl(m: re.Match[str]) -> str:
        col = m.group(1)
        return f'r="{col}{new_row}"'

    out = re.sub(r'r="([A-Z]+)\d+"', repl, row_xml)
    out = re.sub(r'<row r="\d+"', f'<row r="{new_row}"', out, count=1)
    return out


def main() -> None:
    src = SRC if SRC.exists() else DST
    with zipfile.ZipFile(src, "r") as zin:
        sheet_path = "xl/worksheets/sheet1.xml"
        xml = zin.read(sheet_path).decode("utf-8")

        m4 = re.search(r'(<row r="4"[^>]*>.*?</row>)', xml, re.S)
        if not m4:
            raise SystemExit("Riga 4 modello non trovata")
        row4 = m4.group(1)

        # Header righe 1-3 + genera righe dati 4..503
        header_end = xml.find(row4)
        sheet_data_close = xml.rfind("</sheetData>")
        if header_end < 0 or sheet_data_close < 0:
            raise SystemExit("sheetData non valido")

        prefix = xml[:header_end]
        suffix = xml[sheet_data_close:]

        data_rows = "".join(renumber_row(row4, r) for r in range(FIRST_DATA_ROW, LAST_DATA_ROW + 1))
        xml = prefix + data_rows + suffix

        last_col = "OS"  # 409 colonne nel template
        new_dim = f"A1:{last_col}{LAST_DATA_ROW}"
        if re.search(r'<dimension[^>]*ref="', xml):
            xml = re.sub(r'(<dimension[^>]*ref=")[^"]+(")', rf"\1{new_dim}\2", xml, count=1)
        else:
            xml = xml.replace(
                "<sheetData>",
                f'<dimension ref="{new_dim}"/>\n<sheetData>',
                1,
            )

        out_buf = BytesIO()
        with zipfile.ZipFile(out_buf, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == sheet_path:
                    data = xml.encode("utf-8")
                zout.writestr(item, data)

    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_bytes(out_buf.getvalue())
    print(f"OK: {DST} — righe dati {FIRST_DATA_ROW}-{LAST_DATA_ROW} ({LAST_DATA_ROW - FIRST_DATA_ROW + 1} nominativi)")


if __name__ == "__main__":
    main()
