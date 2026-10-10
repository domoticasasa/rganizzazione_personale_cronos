import pathlib
from datetime import datetime

import pandas as pd


EXCEL_PATH = r"c:\Users\alexandru.cibuc\Desktop\aaa.xlsx"
SHEET_NAME = "In essere (2)"
OUT_SQL = pathlib.Path(
    r"c:\flutter_projects\organizzazione_personale_cronos - mod\supabase\migrations\20260416170000_reimport_formazione_rfi_records_full_excel.sql"
)


def norm_text(v: object) -> str:
    s = str(v if v is not None else "").replace("\n", " ").strip()
    if s.lower() == "nan":
        return ""
    return " ".join(s.split())


def esc(s: str) -> str:
    return s.replace("'", "''")


def parse_iso_date(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, pd.Timestamp):
        return v.strftime("%Y-%m-%d")
    raw = norm_text(v)
    if not raw:
        return ""

    raw_short = raw[:19]
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%d/%m/%Y"):
        try:
            return datetime.strptime(raw_short, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return ""


df = pd.read_excel(EXCEL_PATH, sheet_name=SHEET_NAME, header=None)
h_top = df.iloc[1].tolist()
h_sub = df.iloc[2].tolist()

group_by_col: dict[int, str] = {}
current_group = ""
for c in range(3, len(df.columns)):
    top = norm_text(h_top[c])
    if top:
        current_group = top
    group_by_col[c] = current_group

rows_sql: list[str] = []
row_id = 0
for r in range(3, len(df)):
    cognome = norm_text(df.iat[r, 1] if 1 < len(df.columns) else "")
    nome = norm_text(df.iat[r, 2] if 2 < len(df.columns) else "")
    if not cognome and not nome:
        continue

    full_cn = f"{cognome} {nome}".strip()
    full_nc = f"{nome} {cognome}".strip()
    for c in range(3, len(df.columns)):
        track = norm_text(group_by_col.get(c, ""))
        if not track:
            continue
        field = norm_text(h_sub[c]) or f"COL_{c}"
        raw_value = df.iat[r, c]
        text_value = norm_text(raw_value)
        if not text_value:
            continue
        iso_date = parse_iso_date(raw_value)
        row_id += 1
        date_sql = f"'{esc(iso_date)}'::date" if iso_date else "NULL"
        text_sql = f"'{esc(text_value)}'"
        rows_sql.append(
            f"({row_id},'{esc(full_cn)}','{esc(full_nc)}','{esc(track)}','{esc(field)}',{date_sql},{text_sql})"
        )

if not rows_sql:
    raise RuntimeError("Nessun dato utile trovato nel file Excel.")

sql = f"""-- Reimport completo RFI da Excel aggiornato (tab/sottocolonne come file).
ALTER TABLE public.formazione_rfi_records
  ADD COLUMN IF NOT EXISTS value_text text;

DELETE FROM public.formazione_rfi_records
WHERE source_file = 'aaa.xlsx';

WITH src(row_id, full_cn, full_nc, track_key, field_key, value_date, value_text) AS (
  VALUES
  {",\n  ".join(rows_sql)}
), candidates AS (
  SELECT
    s.row_id,
    p.id AS personale_id,
    s.track_key,
    s.field_key,
    s.value_date,
    s.value_text,
    CASE
      WHEN lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) =
           lower(regexp_replace(trim(s.full_cn), '\\s+', ' ', 'g')) THEN 0
      ELSE 1
    END AS match_rank
  FROM src s
  JOIN public.personale p ON
       lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) =
       lower(regexp_replace(trim(s.full_cn), '\\s+', ' ', 'g'))
    OR lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) =
       lower(regexp_replace(trim(s.full_nc), '\\s+', ' ', 'g'))
), resolved AS (
  SELECT DISTINCT ON (row_id)
    personale_id, track_key, field_key, value_date, value_text
  FROM candidates
  ORDER BY row_id, match_rank, personale_id
)
INSERT INTO public.formazione_rfi_records(
  personale_id, track_key, field_key, value_date, value_text, source_file, updated_at
)
SELECT
  personale_id, track_key, field_key, value_date, value_text, 'aaa.xlsx', now()
FROM resolved
ON CONFLICT (personale_id, track_key, field_key)
DO UPDATE SET
  value_date = EXCLUDED.value_date,
  value_text = EXCLUDED.value_text,
  source_file = EXCLUDED.source_file,
  updated_at = now();
"""

OUT_SQL.write_text(sql, encoding="utf-8")
print(f"WROTE {OUT_SQL}")
print(f"SRC_ROWS {len(rows_sql)}")
