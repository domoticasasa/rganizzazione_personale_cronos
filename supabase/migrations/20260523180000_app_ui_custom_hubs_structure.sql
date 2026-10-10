-- Tipo struttura e etichette slot per pagine hub custom.

alter table public.app_ui_custom_hubs
  add column if not exists structure_type text not null default 'home';

alter table public.app_ui_custom_hubs
  add column if not exists slot_labels jsonb not null default '[]'::jsonb;

comment on column public.app_ui_custom_hubs.structure_type is
  'prenotazioni | home | formazioni | alert';

comment on column public.app_ui_custom_hubs.slot_labels is
  'Array JSON [{key, label}] sezioni/pulsanti vuoti della pagina.';
