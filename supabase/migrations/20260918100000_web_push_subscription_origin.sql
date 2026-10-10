-- Traccia l'origine della subscription Web Push (prod vs preview pages.dev).
-- Serve a non fan-out N toast per lo stesso messaggio chat.

alter table public.web_push_subscriptions
  add column if not exists origin text;

create index if not exists idx_web_push_subscriptions_origin
  on public.web_push_subscriptions (origin)
  where active = true;

comment on column public.web_push_subscriptions.origin is
  'location.origin al momento della subscribe (es. https://www.gestopro360.it)';

-- Disattiva TUTTE le subscription attive: le preview pages.dev non hanno
-- origin etichettata e non si possono filtrare dall'endpoint FCM.
-- Al prossimo accesso su www.gestopro360.it il client ri-registra solo prod.
update public.web_push_subscriptions
set
  active = false,
  updated_at = timezone('utc', now())
where active = true;
