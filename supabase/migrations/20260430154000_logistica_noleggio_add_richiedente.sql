alter table if exists public.logistica_noleggio
  add column if not exists richiedente text;

create index if not exists logistica_noleggio_richiedente_idx
  on public.logistica_noleggio(richiedente);
