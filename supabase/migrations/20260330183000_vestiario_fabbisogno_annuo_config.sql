create table if not exists public.vestiario_fabbisogno_annuo_config (
  id integer primary key check (id = 1),
  tshirt integer not null default 1 check (tshirt > 0),
  pantalone integer not null default 1 check (pantalone > 0),
  felpa integer not null default 1 check (felpa > 0),
  giacca integer not null default 1 check (giacca > 0),
  gilet integer not null default 1 check (gilet > 0),
  scarpe integer not null default 1 check (scarpe > 0),
  guanti integer not null default 1 check (guanti > 0),
  updated_at timestamptz not null default now()
);

alter table public.vestiario_fabbisogno_annuo_config
add column if not exists tshirt integer not null default 1 check (tshirt > 0),
add column if not exists pantalone integer not null default 1 check (pantalone > 0),
add column if not exists felpa integer not null default 1 check (felpa > 0),
add column if not exists giacca integer not null default 1 check (giacca > 0),
add column if not exists gilet integer not null default 1 check (gilet > 0),
add column if not exists scarpe integer not null default 1 check (scarpe > 0),
add column if not exists guanti integer not null default 1 check (guanti > 0),
add column if not exists updated_at timestamptz not null default now();

insert into public.vestiario_fabbisogno_annuo_config (
  id, tshirt, pantalone, felpa, giacca, gilet, scarpe, guanti
) values (
  1, 1, 1, 1, 1, 1, 1, 1
)
on conflict (id) do nothing;
