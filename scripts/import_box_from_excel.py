from datetime import date, datetime
from pathlib import Path

import openpyxl


def norm(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    s = str(value).strip()
    if s in ("", "--", "-", "N/D"):
        return None
    return s


def sql(value):
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def main():
    repo = Path(r"c:\flutter_projects\organizzazione_personale_cronos - mod")
    xlsx = Path(r"C:\Users\alexandru.cibuc\Desktop\box.xlsx")
    out = repo / "supabase" / "migrations" / "20260422150000_logistica_box_seed_from_excel.sql"

    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    data_rows = rows[2:]

    lines = []
    lines.append("alter table public.logistica_box")
    lines.append("  add column if not exists periodo_trasferimento text,")
    lines.append("  add column if not exists commessa_provenienza text;")
    lines.append("")
    lines.append("delete from public.logistica_box;")
    lines.append("")
    lines.append("insert into public.logistica_box (")
    lines.append("  numero_interno, tipologia, lunghezza_cm, larghezza_cm, altezza_cm, peso_kg,")
    lines.append("  ingressi, vani, ac, matricola, ubicazione, periodo_trasferimento, commessa_provenienza,")
    lines.append("  note, data_acquisto, data_consegna, fornitore, ordine_acquisto, codice_box, nome_box, active")
    lines.append(") values")

    values_sql = []
    for row in data_rows:
        numero_interno = norm(row[0])
        tipologia = norm(row[1])
        lunghezza_cm = norm(row[2])
        larghezza_cm = norm(row[3])
        altezza_cm = norm(row[4])
        peso_kg = norm(row[5])
        ingressi = norm(row[6])
        vani = norm(row[7])
        ac = norm(row[8])
        matricola = norm(row[9])
        commessa_attuale = norm(row[10])
        periodo_trasferimento = norm(row[11])
        commessa_provenienza = norm(row[12])
        note = norm(row[13])
        data_acquisto = norm(row[14])
        data_consegna = norm(row[15])
        fornitore = norm(row[16])
        ordine_acquisto = norm(row[17])

        if numero_interno is None and tipologia is None and commessa_attuale is None:
            continue

        codice_box = numero_interno
        nome_box = tipologia

        values_sql.append(
            "  ("
            + ", ".join(
                [
                    sql(numero_interno),
                    sql(tipologia),
                    sql(lunghezza_cm),
                    sql(larghezza_cm),
                    sql(altezza_cm),
                    sql(peso_kg),
                    sql(ingressi),
                    sql(vani),
                    sql(ac),
                    sql(matricola),
                    sql(commessa_attuale),
                    sql(periodo_trasferimento),
                    sql(commessa_provenienza),
                    sql(note),
                    sql(data_acquisto),
                    sql(data_consegna),
                    sql(fornitore),
                    sql(ordine_acquisto),
                    sql(codice_box),
                    sql(nome_box),
                    "true",
                ]
            )
            + ")"
        )

    lines.append(",\n".join(values_sql) + ";")
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {out} with {len(values_sql)} rows.")


if __name__ == "__main__":
    main()
