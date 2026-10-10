import pathlib
from datetime import datetime

import openpyxl


EXCEL_PATH = r"C:\Users\alexandru.cibuc\Desktop\+MEZZI STRADALI E AUTOCARRI TEST.xlsx"
SHEET_NAME = "Anagrafica"
OUT_SQL = pathlib.Path(
    r"c:\flutter_projects\organizzazione_personale_cronos - mod\supabase\migrations\20260430105500_seed_logistica_mezzi_stradali_from_excel.sql"
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


def parse_date(v: object) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, datetime):
        if v.year < 1950:
            return "NULL"
        return "'" + v.strftime("%Y-%m-%d") + "'"
    s = norm_text(v)
    if not s:
        return "NULL"
    dt = None
    try:
        dt = datetime.strptime(s, "%d/%m/%Y")
    except ValueError:
        try:
            dt = datetime.strptime(s, "%Y-%m-%d")
        except ValueError:
            return "NULL"
    if dt.year < 1950:
        return "NULL"
    return "'" + dt.strftime("%Y-%m-%d") + "'"


def sql_int(v: object) -> str:
    s = norm_text(v)
    if not s:
        return "NULL"
    try:
        return str(int(float(s.replace(",", "."))))
    except ValueError:
        return "NULL"


def is_effective_row(values: list[object]) -> bool:
    return any(norm_text(v) for v in values)


wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
ws = wb[SHEET_NAME]
rows = list(ws.iter_rows(min_row=1, values_only=True))
if not rows:
    raise RuntimeError("Foglio Excel vuoto.")

# Colonne da tracciato Excel (1-based):
# 1 NUMERAZIONE
# 2 TARGA
# 3 MARCA
# 4 MODELLO
# 5 TIPOLOGIA (mezzo)
# 6 ASSEGNATARIO ATTUALE
# 7 PERIODO ASSEGNATARIO ATTUALE
# 8 NOLEGGIATORE
# 9 SCADENZA CONTRATTO
# 10 SCADENZA ASSICURAZIONE
# 11 SCADENZA BOLLI
# 12 SCADENZA REVISIONE
# 13 SCADENZA VERIFICA PERIODICA GRU
# 14 SCADENZA REVISIONE BIENNALE CRONOTACHIGRAFO
# 15 MULTICARD
# 16 TELEPASS
# 17 KIT RUOTA DI SCORTA
# 18 DEPOSITO GOMME
# 19 TIPOLOGIA (gomme)

values_sql: list[str] = []
for raw in rows[1:]:
    vals = list(raw)
    if not is_effective_row(vals):
        continue
    if len(vals) < 19:
        vals.extend([None] * (19 - len(vals)))
    numerazione = vals[0]
    targa = vals[1]
    if norm_text(numerazione) == "" and norm_text(targa) == "":
        continue

    values_sql.append(
        "("
        + ", ".join(
            [
                sql_int(vals[0]),
                sql_text(vals[1]),
                sql_text(vals[2]),
                sql_text(vals[3]),
                sql_text(vals[4]),
                sql_text(vals[5]),
                parse_date(vals[6]),
                sql_text(vals[7]),
                parse_date(vals[8]),
                parse_date(vals[9]),
                parse_date(vals[10]),
                parse_date(vals[11]),
                parse_date(vals[12]),
                parse_date(vals[13]),
                sql_text(vals[14]),
                sql_text(vals[15]),
                sql_text(vals[16]),
                sql_text(vals[17]),
                sql_text(vals[18]),
            ]
        )
        + ")"
    )

if not values_sql:
    raise RuntimeError("Nessun dato utile trovato nel file Excel.")

generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
sql = f"""-- Seed iniziale logistica_mezzi_stradali da +MEZZI STRADALI E AUTOCARRI TEST.xlsx
-- Generato automaticamente il {generated_at}

WITH src(
  numerazione,
  targa,
  marca,
  modello,
  tipologia_mezzo,
  assegnatario_attuale,
  periodo_assegnatario_attuale,
  noleggiatore,
  scadenza_contratto,
  scadenza_assicurazione,
  scadenza_bolli,
  scadenza_revisione,
  scadenza_verifica_periodica_gru,
  scadenza_revisione_biennale_cronotachigrafo,
  multicard,
  telepass,
  kit_ruota_di_scorta,
  deposito_gomme,
  tipologia_gomme
) AS (
  VALUES
  {",\n  ".join(values_sql)}
),
updated AS (
  UPDATE public.logistica_mezzi_stradali t
  SET
    numerazione = s.numerazione::integer,
    marca = s.marca,
    modello = s.modello,
    tipologia_mezzo = s.tipologia_mezzo,
    assegnatario_attuale = s.assegnatario_attuale,
    periodo_assegnatario_attuale = s.periodo_assegnatario_attuale::date,
    noleggiatore = s.noleggiatore,
    scadenza_contratto = s.scadenza_contratto::date,
    scadenza_assicurazione = s.scadenza_assicurazione::date,
    scadenza_bolli = s.scadenza_bolli::date,
    scadenza_revisione = s.scadenza_revisione::date,
    scadenza_verifica_periodica_gru = s.scadenza_verifica_periodica_gru::date,
    scadenza_revisione_biennale_cronotachigrafo = s.scadenza_revisione_biennale_cronotachigrafo::date,
    multicard = s.multicard,
    telepass = s.telepass,
    kit_ruota_di_scorta = s.kit_ruota_di_scorta,
    deposito_gomme = s.deposito_gomme,
    tipologia_gomme = s.tipologia_gomme,
    active = true,
    updated_at = now()
  FROM src s
  WHERE lower(coalesce(t.targa, '')) = lower(coalesce(s.targa, ''))
)
INSERT INTO public.logistica_mezzi_stradali(
  numerazione,
  targa,
  marca,
  modello,
  tipologia_mezzo,
  assegnatario_attuale,
  periodo_assegnatario_attuale,
  noleggiatore,
  scadenza_contratto,
  scadenza_assicurazione,
  scadenza_bolli,
  scadenza_revisione,
  scadenza_verifica_periodica_gru,
  scadenza_revisione_biennale_cronotachigrafo,
  multicard,
  telepass,
  kit_ruota_di_scorta,
  deposito_gomme,
  tipologia_gomme,
  active
)
SELECT
  s.numerazione::integer,
  s.targa,
  s.marca,
  s.modello,
  s.tipologia_mezzo,
  s.assegnatario_attuale,
  s.periodo_assegnatario_attuale::date,
  s.noleggiatore,
  s.scadenza_contratto::date,
  s.scadenza_assicurazione::date,
  s.scadenza_bolli::date,
  s.scadenza_revisione::date,
  s.scadenza_verifica_periodica_gru::date,
  s.scadenza_revisione_biennale_cronotachigrafo::date,
  s.multicard,
  s.telepass,
  s.kit_ruota_di_scorta,
  s.deposito_gomme,
  s.tipologia_gomme,
  true
FROM src s
WHERE NOT EXISTS (
  SELECT 1
  FROM public.logistica_mezzi_stradali t
  WHERE lower(coalesce(t.targa, '')) = lower(coalesce(s.targa, ''))
);
"""

OUT_SQL.write_text(sql, encoding="utf-8")
print(f"WROTE {OUT_SQL}")
print(f"ROWS {len(values_sql)}")
