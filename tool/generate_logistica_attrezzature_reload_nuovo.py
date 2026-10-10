"""Genera migration SQL: svuota logistica_attrezzature e ricarica dal nuovo Excel."""

from __future__ import annotations

import pathlib
from datetime import date, datetime

import openpyxl

EXCEL_PATH = r"c:\Users\alexandru.cibuc\Desktop\Nuovo Foglio di lavoro di Microsoft Excel.xlsx"
OUT_SQL = (
    pathlib.Path(__file__).resolve().parent.parent
    / "supabase"
    / "migrations"
    / "20260529090000_reload_logistica_attrezzature_nuovo.sql"
)

SHEET = "Foglio1"


def norm_text(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, datetime):
        return v.strftime("%d/%m/%Y")
    if isinstance(v, date):
        return v.strftime("%d/%m/%Y")
    s = str(v).strip()
    if s.lower() == "nan":
        return ""
    # collassa righe vuote multiple ma conserva gli a-capo significativi
    lines = [ln.strip() for ln in s.splitlines()]
    lines = [ln for ln in lines if ln]
    return "\n".join(lines)


def norm_name(v: object) -> str:
    """Assegnatario: nome singolo, spazi normalizzati, niente a-capo."""
    s = norm_text(v).replace("\n", " ")
    return " ".join(s.split())


def sql_text(s: str) -> str:
    if not s:
        return "NULL"
    return "'" + s.replace("'", "''") + "'"


def main() -> None:
    wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
    ws = wb[SHEET]
    rows = list(ws.iter_rows(values_only=True))
    wb.close()
    if not rows:
        raise RuntimeError("File Excel vuoto.")

    # Colonne: CODICE CRONOS, NUOVO CODICE, ASSEGNATARIO, FAMIGLIA ATTREZZI,
    # MARCA, DESCRIZIONE ARTICOLO, SERIAL NUMBER, MODELLO, NOTE
    values: list[str] = []
    for raw in rows[1:]:
        cells = list(raw) + [None] * (9 - len(raw))
        codice = norm_text(cells[0])
        assegnatario = norm_name(cells[2])
        famiglia = norm_text(cells[3])
        marca = norm_name(cells[4])
        descrizione = norm_text(cells[5])
        serial = norm_text(cells[6])
        modello = norm_text(cells[7])
        note = norm_text(cells[8])
        if not any([codice, assegnatario, famiglia, descrizione, serial, modello]):
            continue
        values.append(
            "("
            + ", ".join(
                [
                    sql_text(codice),
                    sql_text(assegnatario),
                    sql_text(famiglia),
                    sql_text(marca),
                    sql_text(descrizione),
                    sql_text(serial),
                    sql_text(modello),
                    sql_text(note),
                ]
            )
            + ")"
        )

    if not values:
        raise RuntimeError("Nessuna riga utile nel file Excel.")

    batch_size = 200
    insert_blocks: list[str] = []
    for i in range(0, len(values), batch_size):
        batch = values[i : i + batch_size]
        insert_blocks.append(
            "INSERT INTO public.logistica_attrezzature(\n"
            "  codice_cronos, assegnatario, famiglia_attrezzi, marca,\n"
            "  descrizione_articolo, serial_number, modello, note, active\n"
            ")\nSELECT\n"
            "  v.codice_cronos, v.assegnatario, v.famiglia_attrezzi, v.marca,\n"
            "  v.descrizione_articolo, v.serial_number, v.modello, v.note, true\n"
            "FROM (VALUES\n  "
            + ",\n  ".join(batch)
            + "\n) AS v(\n"
            "  codice_cronos, assegnatario, famiglia_attrezzi, marca,\n"
            "  descrizione_articolo, serial_number, modello, note\n"
            ");"
        )

    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    sql = f"""-- Ricarica completa logistica_attrezzature dal nuovo Excel
-- Generato automaticamente il {generated_at}
-- Totale righe: {len(values)}

DELETE FROM public.logistica_attrezzature;

{chr(10).join(insert_blocks)}
"""
    OUT_SQL.write_text(sql, encoding="utf-8")
    print(f"WROTE {OUT_SQL}")
    print(f"TOTAL_ROWS {len(values)}")


if __name__ == "__main__":
    main()
