-- Commesse: secondo DT in colonna separata.
-- Divide i valori combinati esistenti tipo "CASTRONOVO (LFM) - CIBUC (TE)".

alter table public.commesse
  add column if not exists dt2 text;

update public.commesse
set dt2 = nullif(btrim(split_part(dt, ' - ', 2)), ''),
    dt = nullif(btrim(split_part(dt, ' - ', 1)), '')
where dt like '% - %';
