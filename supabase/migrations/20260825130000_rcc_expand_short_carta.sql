-- Righe RCC con frammento OCR (es. «6») → numero multicard intero del mezzo.

update public.logistica_rcc_carburante r
set
  n_carta_carburante = regexp_replace(trim(m.multicard), '[^0-9]', '', 'g'),
  updated_at = timezone('utc', now())
from public.logistica_mezzi_stradali m
where r.mezzo_stradale_id_uuid = m.id_uuid
  and length(regexp_replace(coalesce(r.n_carta_carburante, ''), '[^0-9]', '', 'g')) < 12
  and length(regexp_replace(coalesce(m.multicard, ''), '[^0-9]', '', 'g')) >= 12;
