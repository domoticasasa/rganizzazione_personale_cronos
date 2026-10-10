create table if not exists public.web_push_subscriptions (
  id bigserial primary key,
  user_id integer not null references public.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (endpoint),
  unique (user_id, endpoint)
);

create index if not exists idx_web_push_subscriptions_user_id
  on public.web_push_subscriptions(user_id);

create index if not exists idx_web_push_subscriptions_active
  on public.web_push_subscriptions(active);

alter table public.web_push_subscriptions enable row level security;

drop policy if exists "web push select own" on public.web_push_subscriptions;
create policy "web push select own"
on public.web_push_subscriptions
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = web_push_subscriptions.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "web push insert own" on public.web_push_subscriptions;
create policy "web push insert own"
on public.web_push_subscriptions
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.id = web_push_subscriptions.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "web push update own" on public.web_push_subscriptions;
create policy "web push update own"
on public.web_push_subscriptions
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = web_push_subscriptions.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = web_push_subscriptions.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "web push delete own" on public.web_push_subscriptions;
create policy "web push delete own"
on public.web_push_subscriptions
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = web_push_subscriptions.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);
