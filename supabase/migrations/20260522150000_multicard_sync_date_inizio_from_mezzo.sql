-- Allinea data inizio/fine assegnatario sulle multicard dal mezzo collegato (come telepass).

update public.logistica_multicard c
set
  periodo_assegnatario_attuale = m.periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale = coalesce(
    c.data_fine_assegnatario_attuale,
    m.data_fine_assegnatario_attuale
  )
from public.logistica_mezzi_stradali m
where lower(trim(coalesce(c.mezzo_targa, ''))) = lower(trim(coalesce(m.targa, '')))
  and nullif(trim(coalesce(c.mezzo_targa, '')), '') is not null
  and m.periodo_assegnatario_attuale is not null
  and (
    c.periodo_assegnatario_attuale is null
    or c.periodo_assegnatario_attuale is distinct from m.periodo_assegnatario_attuale
  );
