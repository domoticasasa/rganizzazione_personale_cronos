-- Tratte stradali (km + pedaggio) e impostazioni costo orario / carburante
-- per confrontare viaggio mezzo stradale vs treno/aereo.

create table if not exists public.viaggio_stradale_settings (
  id smallint primary key default 1 check (id = 1),
  costo_orario_eur numeric(10, 2) not null default 25.00,
  prezzo_carburante_eur_litro numeric(8, 3) not null default 1.800,
  toll_eur_per_km_estimate numeric(8, 4) not null default 0.0800,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by integer references public.users (id) on delete set null
);

insert into public.viaggio_stradale_settings (id)
values (1)
on conflict (id) do nothing;

comment on table public.viaggio_stradale_settings is
  'Impostazioni globali: costo orario persona e prezzo carburante per stima viaggio stradale.';

create table if not exists public.viaggio_stradale_tratte (
  id_uuid uuid primary key default gen_random_uuid(),
  origine_tipo text not null check (origine_tipo in ('stazione', 'aeroporto', 'altro')),
  origine_ref_id text,
  origine_nome text not null,
  destinazione_tipo text not null check (destinazione_tipo in ('stazione', 'aeroporto', 'altro')),
  destinazione_ref_id text,
  destinazione_nome text not null,
  km_stradali numeric(10, 2) not null check (km_stradali >= 0),
  pedaggio_eur numeric(10, 2) not null default 0 check (pedaggio_eur >= 0),
  pedaggio_fonte text not null default 'manuale'
    check (pedaggio_fonte in ('manuale', 'stima', 'aggiornato')),
  durata_minuti integer check (durata_minuti is null or durata_minuti >= 0),
  origine_lat double precision,
  origine_lon double precision,
  destinazione_lat double precision,
  destinazione_lon double precision,
  note text,
  last_price_check_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by integer references public.users (id) on delete set null,
  updated_by integer references public.users (id) on delete set null
);

create unique index if not exists viaggio_stradale_tratte_pair_uidx
  on public.viaggio_stradale_tratte (
    lower(origine_tipo),
    lower(origine_nome),
    lower(destinazione_tipo),
    lower(destinazione_nome)
  )
  where active;

create index if not exists viaggio_stradale_tratte_origine_idx
  on public.viaggio_stradale_tratte (origine_tipo, origine_nome);

create index if not exists viaggio_stradale_tratte_dest_idx
  on public.viaggio_stradale_tratte (destinazione_tipo, destinazione_nome);

comment on table public.viaggio_stradale_tratte is
  'Database tratte stazione/aeroporto: km stradali, pedaggio autostrada, durata stimata.';

create or replace function public.set_viaggio_stradale_tratte_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_viaggio_stradale_tratte_updated_at
  on public.viaggio_stradale_tratte;
create trigger trg_viaggio_stradale_tratte_updated_at
before update on public.viaggio_stradale_tratte
for each row execute function public.set_viaggio_stradale_tratte_updated_at();

grant select, insert, update, delete on public.viaggio_stradale_settings to authenticated;
grant select, insert, update, delete on public.viaggio_stradale_tratte to authenticated;

alter table public.viaggio_stradale_settings enable row level security;
alter table public.viaggio_stradale_tratte enable row level security;

drop policy if exists viaggio_stradale_settings_all on public.viaggio_stradale_settings;
create policy viaggio_stradale_settings_all
on public.viaggio_stradale_settings
for all
to authenticated
using (true)
with check (true);

drop policy if exists viaggio_stradale_tratte_all on public.viaggio_stradale_tratte;
create policy viaggio_stradale_tratte_all
on public.viaggio_stradale_tratte
for all
to authenticated
using (true)
with check (true);
