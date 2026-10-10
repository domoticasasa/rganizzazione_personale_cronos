-- Una toast Cronos per evento: disattiva le subscription della scheda Chrome (apex).
-- Resta attiva solo https://www.gestopro360.it (PWA GESTOPRO360).

update public.web_push_subscriptions
set active = false,
    updated_at = timezone('utc', now())
where active = true
  and origin is not null
  and (
    origin ilike 'https://gestopro360.it%'
    or origin ilike 'http://gestopro360.it%'
  )
  and origin not ilike '%://www.gestopro360.it%';
