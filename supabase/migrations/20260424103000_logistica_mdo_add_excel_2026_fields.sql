alter table public.logistica_mdo_ferroviari
  add column if not exists descrizione_rumo text,
  add column if not exists equipment text,
  add column if not exists matricola_costruttore text,
  add column if not exists dt_nome text;

create index if not exists idx_logistica_mdo_dt_nome
  on public.logistica_mdo_ferroviari (dt_nome);

