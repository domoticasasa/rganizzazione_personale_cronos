"""Genera migration: colonne pm/dt su commesse + UPDATE da Excel attribuzione."""

from __future__ import annotations

import pathlib

import openpyxl

EXCEL_PATH = r"c:\Users\alexandru.cibuc\Desktop\logistica\13-Attribuzione commesse 14-05-26.xlsx"
OUT_SQL = (
    pathlib.Path(__file__).resolve().parent.parent
    / "supabase"
    / "migrations"
    / "20260529100000_commesse_pm_dt.sql"
)


def q(s: str) -> str:
    if not s:
        return "NULL"
    return "'" + s.replace("'", "''") + "'"


def main() -> None:
    wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
    ws = wb["Foglio1"]
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    data: dict[str, tuple[str, str]] = {}
    order: list[str] = []
    for r in rows[6:]:
        pm = str(r[0]).strip() if r[0] else ""
        dt = str(r[1]).strip() if r[1] else ""
        code = str(r[2]).strip().upper() if r[2] else ""
        if not code:
            continue
        if code not in data:
            order.append(code)
        data[code] = (pm, dt)

    out: list[str] = []
    out.append("-- Commesse: PM e DT (da 13-Attribuzione commesse 14-05-26.xlsx)")
    out.append("-- Nota: TE-23-24 nel file aveva 2 righe in conflitto: usato ultimo valore.")
    out.append("-- DT puo' contenere piu' DT (es. 'CASTRONOVO (LFM) - CIBUC (TE)').")
    out.append("")
    out.append("alter table public.commesse")
    out.append("  add column if not exists pm text,")
    out.append("  add column if not exists dt text;")
    out.append("")
    for code in order:
        pm, dt = data[code]
        cu = code.replace("'", "''")
        out.append(
            f"update public.commesse set pm={q(pm)}, dt={q(dt)} "
            f"where upper(nome)='{cu}' or upper(nome) like '{cu} %';"
        )

    OUT_SQL.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"WROTE {OUT_SQL}")
    print(f"UPDATES {len(order)}")


if __name__ == "__main__":
    main()
