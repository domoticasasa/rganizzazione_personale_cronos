-- Riattiva subscription Web Push spente da vecchi logout
-- (ora la subscription resta attiva anche a tab chiusa / dopo logout).

update public.web_push_subscriptions
set
  active = true,
  updated_at = timezone('utc', now())
where active = false
  and endpoint is not null
  and length(trim(endpoint)) > 0
  and coalesce(p256dh, '') <> ''
  and coalesce(auth, '') <> '';
