alter table public.estintori
  alter column codice_interno drop not null,
  alter column ubicazione drop not null,
  alter column tipo drop not null;
