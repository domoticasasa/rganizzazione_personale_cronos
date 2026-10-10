-- Giacca estiva = articolo distinto «giacca_leggera» (invernale resta «giacca»).

alter table public.vestiario_fabbisogno_annuo_config
add column if not exists giacca_leggera_estivo integer not null default 1;

update public.vestiario_fabbisogno_annuo_config
set
  giacca_leggera_estivo = coalesce(
    giacca_leggera_estivo,
    giacca_estivo,
    giacca,
    1
  )
where id = 1;

-- Magazzino: righe «giacca» estive diventano giacca leggera (stock unificato su stagione estivo).
insert into public.vestiario_magazzino (
  stagione,
  articolo,
  taglia,
  quantita,
  quantita_ordinata,
  quantita_arrivata_totale
)
select
  e.stagione,
  'giacca_leggera',
  e.taglia,
  e.quantita,
  e.quantita_ordinata,
  e.quantita_arrivata_totale
from public.vestiario_magazzino e
where e.articolo = 'giacca'
  and e.stagione = 'estivo'
  and not exists (
    select 1
    from public.vestiario_magazzino g
    where g.stagione = e.stagione
      and g.articolo = 'giacca_leggera'
      and g.taglia = e.taglia
  );

delete from public.vestiario_magazzino
where articolo = 'giacca'
  and stagione = 'estivo';
