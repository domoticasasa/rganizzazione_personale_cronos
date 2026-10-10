-- Colori chrome: barra superiore + barra laterale.

alter table public.app_branding
  add column if not exists top_bar_color text not null default '#1565C0';

alter table public.app_branding
  add column if not exists sidebar_color text not null default '#EEF3FA';

comment on column public.app_branding.top_bar_color is
  'Colore AppBar classica / fascia top rail / tint top bar GESTOPRO.';

comment on column public.app_branding.sidebar_color is
  'Colore sfondo barra laterale (rail classica / sidebar GESTOPRO).';
