import pathlib
from datetime import datetime

import openpyxl


EXCEL_PATH = r"C:\Users\alexandru.cibuc\Desktop\ELENCO NOLI WC_TEST_REV01.xlsx"
SHEET_NAME = "Foglio1"
OUT_SQL = pathlib.Path(
    r"c:\flutter_projects\organizzazione_personale_cronos - mod\supabase\migrations\20260430141000_seed_logistica_noleggio_from_excel.sql"
)


def norm_text(v: object) -> str:
    if v is None:
        return ""
    s = str(v).replace("\n", " ").strip()
    if s.lower() in ("nan", "#n/a"):
        return ""
    return " ".join(s.split())


def sql_text(v: object) -> str:
    s = norm_text(v)
    if not s:
        return "NULL"
    return "'" + s.replace("'", "''") + "'"


def smart_text(v: object) -> str:
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d")
    return norm_text(v)


wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
ws = wb[SHEET_NAME]
rows = list(ws.iter_rows(min_row=1, values_only=True))
if not rows:
    raise RuntimeError("Foglio Excel vuoto.")

values_sql: list[str] = []
for raw in rows[1:]:
    vals = list(raw)
    if len(vals) < 16:
        vals.extend([None] * (16 - len(vals)))
    commessa = smart_text(vals[0])
    descrizione = smart_text(vals[3])
    contratto = smart_text(vals[9])
    if not any([commessa, descrizione, contratto]):
        continue
    values_sql.append(
        "("
        + ", ".join(
            [
                sql_text(smart_text(vals[0])),
                sql_text(smart_text(vals[1])),
                sql_text(smart_text(vals[2])),
                sql_text(smart_text(vals[3])),
                sql_text(smart_text(vals[4])),
                sql_text(smart_text(vals[5])),
                sql_text(smart_text(vals[6])),
                sql_text(smart_text(vals[7])),
                sql_text(smart_text(vals[8])),
                sql_text(smart_text(vals[9])),
                sql_text(smart_text(vals[10])),
                sql_text(smart_text(vals[11])),
                sql_text(smart_text(vals[12])),
                sql_text(smart_text(vals[13])),
                sql_text(smart_text(vals[14])),
                sql_text(smart_text(vals[15])),
            ]
        )
        + ")"
    )

if not values_sql:
    raise RuntimeError("Nessun dato utile trovato nel file Excel.")

generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
sql = f"""-- Seed iniziale logistica_noleggio da ELENCO NOLI WC_TEST_REV01.xlsx
-- Generato automaticamente il {generated_at}

WITH src(
  commessa,
  luogo_commessa,
  fornitore,
  descrizione,
  qta_mdo,
  accessori_1,
  qta_1,
  accessori_2,
  qta_2,
  numero_contratto,
  oda,
  nolo_dal,
  nolo_al,
  stato,
  utilizzatore,
  note
) AS (
  VALUES
  {",\n  ".join(values_sql)}
),
updated AS (
  UPDATE public.logistica_noleggio t
  SET
    luogo_commessa = s.luogo_commessa,
    fornitore = s.fornitore,
    descrizione = s.descrizione,
    qta_mdo = s.qta_mdo,
    accessori_1 = s.accessori_1,
    qta_1 = s.qta_1,
    accessori_2 = s.accessori_2,
    qta_2 = s.qta_2,
    oda = s.oda,
    nolo_dal = s.nolo_dal,
    nolo_al = s.nolo_al,
    stato = s.stato,
    utilizzatore = s.utilizzatore,
    note = s.note,
    active = true,
    updated_at = now()
  FROM src s
  WHERE lower(coalesce(t.commessa, '')) = lower(coalesce(s.commessa, ''))
    and lower(coalesce(t.descrizione, '')) = lower(coalesce(s.descrizione, ''))
    and lower(coalesce(t.numero_contratto, '')) = lower(coalesce(s.numero_contratto, ''))
)
INSERT INTO public.logistica_noleggio(
  commessa,
  luogo_commessa,
  fornitore,
  descrizione,
  qta_mdo,
  accessori_1,
  qta_1,
  accessori_2,
  qta_2,
  numero_contratto,
  oda,
  nolo_dal,
  nolo_al,
  stato,
  utilizzatore,
  note,
  active
)
SELECT
  s.commessa,
  s.luogo_commessa,
  s.fornitore,
  s.descrizione,
  s.qta_mdo,
  s.accessori_1,
  s.qta_1,
  s.accessori_2,
  s.qta_2,
  s.numero_contratto,
  s.oda,
  s.nolo_dal,
  s.nolo_al,
  s.stato,
  s.utilizzatore,
  s.note,
  true
FROM src s
WHERE NOT EXISTS (
  SELECT 1
  FROM public.logistica_noleggio t
  WHERE lower(coalesce(t.commessa, '')) = lower(coalesce(s.commessa, ''))
    and lower(coalesce(t.descrizione, '')) = lower(coalesce(s.descrizione, ''))
    and lower(coalesce(t.numero_contratto, '')) = lower(coalesce(s.numero_contratto, ''))
);
"""

OUT_SQL.write_text(sql, encoding="utf-8")
print(f"WROTE {OUT_SQL}")
print(f"ROWS {len(values_sql)}")
