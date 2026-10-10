-- Ruolo lavorativo in azienda (testo libero, es. «Direttore Tecnico»).
-- Distinto dal ruolo applicativo in users.role (admin / dt / user / …).
alter table public.personale
  add column if not exists ruolo_aziendale text;

comment on column public.personale.ruolo_aziendale is
  'Incarico/ruolo in azienda (testo libero), es. Direttore Tecnico, Caposquadra.';
