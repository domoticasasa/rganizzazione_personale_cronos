-- Riga libera in fondo al tesserino (anteprima app + PDF ISO ID-1).
alter table public.personale
  add column if not exists tesserino_extra_etichetta text,
  add column if not exists tesserino_extra_testo text;

comment on column public.personale.tesserino_extra_etichetta is
  'Etichetta opzionale per la riga aggiuntiva sul tesserino (es. QUALIFICA:).';
comment on column public.personale.tesserino_extra_testo is
  'Testo libero della riga aggiuntiva sul tesserino (app e PDF).';
