-- Import persistente fatture QT per mese (verifica carburante).

create table if not exists public.logistica_qt_fattura_import (
  id_uuid uuid primary key default gen_random_uuid(),
  anno integer not null,
  mese integer not null check (mese between 1 and 12),
  file_names text[] not null default '{}',
  avviso text,
  imported_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (anno, mese)
);

create table if not exists public.logistica_qt_fattura_transazione (
  id_uuid uuid primary key default gen_random_uuid(),
  import_id_uuid uuid not null references public.logistica_qt_fattura_import (id_uuid) on delete cascade,
  riga_excel integer,
  numero_carta text not null,
  prodotto text not null,
  data_transazione date not null,
  volume numeric(12, 3) not null,
  importo numeric(12, 2) not null,
  file_sorgente text,
  dedup_key text not null,
  unique (import_id_uuid, dedup_key)
);

create index if not exists logistica_qt_fattura_import_anno_mese_idx
  on public.logistica_qt_fattura_import (anno desc, mese desc);

create index if not exists logistica_qt_fattura_transazione_import_idx
  on public.logistica_qt_fattura_transazione (import_id_uuid);

create or replace function public.is_qt_carburante_verifica_allowed()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  );
$$;

grant execute on function public.is_qt_carburante_verifica_allowed() to authenticated;

alter table public.logistica_qt_fattura_import enable row level security;
alter table public.logistica_qt_fattura_transazione enable row level security;

drop policy if exists logistica_qt_fattura_import_select on public.logistica_qt_fattura_import;
create policy logistica_qt_fattura_import_select
on public.logistica_qt_fattura_import
for select
to authenticated
using (public.is_qt_carburante_verifica_allowed());

drop policy if exists logistica_qt_fattura_import_write on public.logistica_qt_fattura_import;
create policy logistica_qt_fattura_import_write
on public.logistica_qt_fattura_import
for all
to authenticated
using (public.is_qt_carburante_verifica_allowed())
with check (public.is_qt_carburante_verifica_allowed());

drop policy if exists logistica_qt_fattura_transazione_select on public.logistica_qt_fattura_transazione;
create policy logistica_qt_fattura_transazione_select
on public.logistica_qt_fattura_transazione
for select
to authenticated
using (public.is_qt_carburante_verifica_allowed());

drop policy if exists logistica_qt_fattura_transazione_write on public.logistica_qt_fattura_transazione;
create policy logistica_qt_fattura_transazione_write
on public.logistica_qt_fattura_transazione
for all
to authenticated
using (public.is_qt_carburante_verifica_allowed())
with check (public.is_qt_carburante_verifica_allowed());
