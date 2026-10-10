-- Configurazione pagina custom (campi/tabella) e isolamento prenotazioni.

alter table public.app_ui_custom_hubs
  add column if not exists page_config jsonb not null default '{}'::jsonb;

comment on column public.app_ui_custom_hubs.page_config is
  'Schema UI: formFields, tableColumns (etichette, visibilità, ordine).';

alter table public.bookings
  add column if not exists custom_hub_layout_key text;

comment on column public.bookings.custom_hub_layout_key is
  'Se valorizzato, la prenotazione appartiene a una pagina hub custom (layout_key).';

create index if not exists bookings_custom_hub_layout_key_idx
  on public.bookings (custom_hub_layout_key)
  where custom_hub_layout_key is not null;
