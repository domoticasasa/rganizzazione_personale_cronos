import pathlib
from datetime import datetime

import pandas as pd


EXCEL_PATH = r"c:\Users\alexandru.cibuc\Desktop\aaa.xlsx"
SHEET = "In essere (2)"
OUT = pathlib.Path(
    r"c:\flutter_projects\organizzazione_personale_cronos - mod\supabase\migrations\20260416154500_refresh_rfi_corsi_exact_from_excel.sql"
)


def norm(v: object) -> str:
    s = str(v if v is not None else "").strip()
    return "" if s.lower() == "nan" else s


def esc(s: str) -> str:
    return s.replace("'", "''")


def parse_date(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, pd.Timestamp):
        return v.strftime("%Y-%m-%d")
    raw = norm(v)
    if not raw:
        return ""
    raw = raw[:19]
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%d/%m/%Y"):
        try:
            return datetime.strptime(raw, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return ""


df = pd.read_excel(EXCEL_PATH, sheet_name=SHEET, header=None)
h1 = df.iloc[1].tolist()
h2 = df.iloc[2].tolist()

first_data_col = 25
group_by_col: dict[int, str] = {}
current = ""
for c in range(first_data_col, len(h1)):
    main = norm(h1[c])
    if main:
        current = " ".join(main.split())
    group_by_col[c] = current

records = []
for r in range(3, len(df)):
    cognome = norm(df.iat[r, 1] if 1 < len(df.columns) else "")
    nome = norm(df.iat[r, 2] if 2 < len(df.columns) else "")
    if not cognome and not nome:
        continue

    by_group: dict[str, dict[str, str]] = {}
    for c in range(first_data_col, len(df.columns)):
        group = norm(group_by_col.get(c, ""))
        if not group:
            continue
        val = norm(df.iat[r, c])
        if not val:
            continue
        sub = norm(h2[c]).upper()
        slot = by_group.setdefault(
            group, {"att": "", "scad": "", "note": ""}
        )
        d = parse_date(val)
        if "SCAD" in sub:
            if d:
                slot["scad"] = d
            else:
                slot["note"] = (slot["note"] + " | " + val).strip(" |")
        elif "DATA ATTESTATO" in sub or "DEFINIZIONE" in sub or "DATA CONSEGNA" in sub:
            if d and not slot["att"]:
                slot["att"] = d
            elif val and not d:
                slot["note"] = (slot["note"] + " | " + val).strip(" |")
        else:
            if d and not slot["att"]:
                slot["att"] = d
            else:
                slot["note"] = (slot["note"] + " | " + val).strip(" |")

    full_cn = f"{cognome} {nome}".strip()
    full_nc = f"{nome} {cognome}".strip()
    for corso, payload in by_group.items():
        if not (payload["att"] or payload["scad"] or payload["note"]):
            continue
        records.append(
            (
                full_cn,
                full_nc,
                corso,
                payload["att"] or None,
                payload["scad"] or None,
                payload["note"] or None,
            )
        )

values_sql = []
for full_cn, full_nc, corso, att, scad, note in records:
    att_sql = f"'{esc(att)}'::date" if att else "NULL"
    scad_sql = f"'{esc(scad)}'::date" if scad else "NULL"
    note_sql = f"'{esc(note)}'" if note else "NULL"
    values_sql.append(
        f"('{esc(full_cn)}','{esc(full_nc)}','{esc(corso)}',{att_sql},{scad_sql},{note_sql})"
    )

sql = [
    "-- Refresh RFI corsi con nomi tab identici all'Excel attuale.",
    "WITH src(full_cn, full_nc, corso, data_attestato, scadenza_attestato, note) AS (",
    "  VALUES",
    "  " + ",\n  ".join(values_sql),
    "), matched AS (",
    "  SELECT DISTINCT ON (s.full_cn, s.corso)",
    "    p.id_uuid::text AS personale_id,",
    "    s.corso,",
    "    s.data_attestato,",
    "    s.scadenza_attestato,",
    "    s.note,",
    "    CASE",
    "      WHEN lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_cn), '\\s+', ' ', 'g')) THEN 0",
    "      ELSE 1",
    "    END AS rank_match",
    "  FROM src s",
    "  JOIN public.personale p ON",
    "       lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_cn), '\\s+', ' ', 'g'))",
    "    OR lower(regexp_replace(trim(p.full_name), '\\s+', ' ', 'g')) = lower(regexp_replace(trim(s.full_nc), '\\s+', ' ', 'g'))",
    "  WHERE p.id_uuid IS NOT NULL AND trim(p.id_uuid::text) <> ''",
    "  ORDER BY s.full_cn, s.corso, rank_match, p.id",
    ")",
    "INSERT INTO public.formazione_rfi_corsi(",
    "  personale_id, corso, data_attestato, scadenza_attestato, note, updated_at",
    ")",
    "SELECT personale_id, corso, data_attestato, scadenza_attestato, note, now()",
    "FROM matched",
    "ON CONFLICT (personale_id, corso)",
    "DO UPDATE SET",
    "  data_attestato = EXCLUDED.data_attestato,",
    "  scadenza_attestato = EXCLUDED.scadenza_attestato,",
    "  note = EXCLUDED.note,",
    "  updated_at = now();",
]

OUT.write_text("\n".join(sql), encoding="utf-8")
print(f"WROTE {OUT}")
print(f"ROWS {len(values_sql)}")
