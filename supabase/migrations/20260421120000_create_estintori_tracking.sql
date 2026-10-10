create extension if not exists pgcrypto;

create table if not exists public.estintori (
  id_uuid uuid primary key default gen_random_uuid(),
  codice_interno text not null,
  matricola text,
  struttura_id uuid references public.structures(id_uuid) on delete set null,
  ubicazione text not null,
  piano text,
  tipo text not null,
  agente_estinguente text,
  capacita_kg numeric(8,2),
  produttore text,
  modello text,
  data_installazione date,
  data_ultima_sorveglianza date,
  data_ultimo_controllo date,
  data_ultima_revisione date,
  data_ultimo_collaudo date,
  prossima_sorveglianza date,
  prossimo_controllo date,
  prossima_revisione date,
  prossimo_collaudo date,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists estintori_codice_interno_uidx
  on public.estintori (lower(codice_interno));

create index if not exists estintori_struttura_idx on public.estintori(struttura_id);
create index if not exists estintori_active_idx on public.estintori(active);
create index if not exists estintori_prossime_scadenze_idx
  on public.estintori(prossima_sorveglianza, prossimo_controllo, prossima_revisione, prossimo_collaudo);

create or replace function public.set_estintori_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_estintori_updated_at on public.estintori;
create trigger trg_estintori_updated_at
before update on public.estintori
for each row execute function public.set_estintori_updated_at();

alter table public.estintori enable row level security;

drop policy if exists estintori_select_authenticated on public.estintori;
create policy estintori_select_authenticated
on public.estintori
for select
to authenticated
using (true);

drop policy if exists estintori_write_authenticated on public.estintori;
create policy estintori_write_authenticated
on public.estintori
for all
to authenticated
using (true)
with check (true);
