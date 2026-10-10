"""Genera migration: tabella dislocazione_personale + RLS + import compresso da Excel.

Il file Excel e' un calendario giornaliero (una colonna per giorno).
Comprime giorni consecutivi con lo stesso valore in periodi (dal/al).
Valori tipo 'IS-01-22' -> commessa (lookup su public.commesse), altri -> stato.
"""

from __future__ import annotations

import pathlib
import re
from datetime import datetime

import openpyxl

EXCEL_PATH = r"c:\Users\alexandru.cibuc\Desktop\logistica\23-Programma impegno personale 01-06-26 mod.xlsx"
OUT_SQL = (
    pathlib.Path(__file__).resolve().parent.parent
    / "supabase"
    / "migrations"
    / "20260529110000_dislocazione_personale.sql"
)

CODE_RE = re.compile(r"^[A-Z]+-\d+-\d+$")

DDL = """-- Dislocazione Personale: assegnazione dipendente -> commessa/stato per periodo.

create table if not exists public.dislocazione_personale (
  id_uuid uuid primary key default gen_random_uuid(),
  nominativo text not null,
  abilitazioni text,
  commessa_id uuid references public.commesse(id_uuid) on delete set null,
  stato text,
  data_inizio date,
  data_fine date,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists dislocazione_personale_nominativo_idx
  on public.dislocazione_personale(nominativo);
create index if not exists dislocazione_personale_commessa_idx
  on public.dislocazione_personale(commessa_id);
create index if not exists dislocazione_personale_periodo_idx
  on public.dislocazione_personale(data_inizio, data_fine);

create or replace function public.set_dislocazione_personale_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_dislocazione_personale_audit_fields on public.dislocazione_personale;
create trigger trg_dislocazione_personale_audit_fields
before insert or update on public.dislocazione_personale
for each row execute function public.set_dislocazione_personale_audit_fields();

alter table public.dislocazione_personale enable row level security;

drop policy if exists dislocazione_personale_select on public.dislocazione_personale;
create policy dislocazione_personale_select
on public.dislocazione_personale
for select to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
);

drop policy if exists dislocazione_personale_write on public.dislocazione_personale;
create policy dislocazione_personale_write
on public.dislocazione_personale
for all to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
);

-- Import iniziale (rigenerabile): svuota e ricarica.
delete from public.dislocazione_personale;
"""


def q(s: str) -> str:
    if s is None or str(s).strip() == "":
        return "NULL"
    return "'" + str(s).strip().replace("'", "''") + "'"


def main() -> None:
    wb = openpyxl.load_workbook(EXCEL_PATH, data_only=True)
    ws = wb["Maestranze"]
    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    header_dates = rows[2]
    date_cols: list[tuple[int, datetime]] = [
        (i, header_dates[i])
        for i in range(2, len(header_dates))
        if isinstance(header_dates[i], datetime)
    ]

    records: list[tuple] = []
    for r in rows[3:]:
        if len(r) < 2:
            continue
        nominativo = (str(r[1]).strip() if r[1] else "")
        if not nominativo:
            continue
        abilitazioni = (str(r[0]).strip() if r[0] else "")

        cur_val = None
        cur_start = None
        cur_end = None

        def flush():
            nonlocal cur_val, cur_start, cur_end
            if cur_val is not None:
                is_comm = bool(CODE_RE.match(cur_val))
                records.append(
                    (nominativo, abilitazioni, cur_val, is_comm,
                     cur_start.strftime("%Y-%m-%d"), cur_end.strftime("%Y-%m-%d"))
                )
            cur_val = None
            cur_start = None
            cur_end = None

        for idx, d in date_cols:
            raw = r[idx] if idx < len(r) else None
            if raw is None:
                continue
            v = str(raw).strip()
            if not v:
                continue
            vu = v.upper()
            if cur_val is None:
                cur_val, cur_start, cur_end = vu, d, d
            elif vu == cur_val:
                cur_end = d
            else:
                flush()
                cur_val, cur_start, cur_end = vu, d, d
        flush()

    out: list[str] = [DDL, ""]
    batch_size = 300
    for i in range(0, len(records), batch_size):
        batch = records[i : i + batch_size]
        values = ",\n  ".join(
            f"({q(nm)}, {q(ab)}, {q(val)}, {str(isc).lower()}, {q(dal)}, {q(al)})"
            for (nm, ab, val, isc, dal, al) in batch
        )
        out.append(
            "insert into public.dislocazione_personale\n"
            "  (nominativo, abilitazioni, commessa_id, stato, data_inizio, data_fine)\n"
            "select v.nominativo, v.abilitazioni, c.id_uuid,\n"
            "       case when c.id_uuid is null then v.valore else null end,\n"
            "       v.dal::date, v.al::date\n"
            "from (values\n  " + values + "\n) as v(nominativo, abilitazioni, valore, is_commessa, dal, al)\n"
            "left join lateral (\n"
            "  select id_uuid from public.commesse\n"
            "  where v.is_commessa and (upper(nome) = v.valore or upper(nome) like v.valore || ' %')\n"
            "  order by length(nome) limit 1\n"
            ") c on true;"
        )

    OUT_SQL.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"WROTE {OUT_SQL}")
    print(f"RECORDS {len(records)}")


if __name__ == "__main__":
    main()
