alter table public.logistica_box
  add column if not exists numero_interno text,
  add column if not exists tipologia text,
  add column if not exists lunghezza_cm text,
  add column if not exists larghezza_cm text,
  add column if not exists altezza_cm text,
  add column if not exists peso_kg text,
  add column if not exists ingressi text,
  add column if not exists vani text,
  add column if not exists ac text,
  add column if not exists data_acquisto date,
  add column if not exists data_consegna date,
  add column if not exists fornitore text,
  add column if not exists ordine_acquisto text;
