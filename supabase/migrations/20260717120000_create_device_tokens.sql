-- Token FCM / device push (Android APK). Edge admin-send-notification legge token + platform.
create table if not exists public.device_tokens (
  id bigserial primary key,
  user_id integer not null references public.users(id) on delete cascade,
  auth_id uuid,
  token text not null,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (token)
);

create index if not exists idx_device_tokens_user_id
  on public.device_tokens(user_id);

create index if not exists idx_device_tokens_auth_id
  on public.device_tokens(auth_id);

create index if not exists idx_device_tokens_platform
  on public.device_tokens(platform);

alter table public.device_tokens enable row level security;

drop policy if exists "device tokens select own" on public.device_tokens;
create policy "device tokens select own"
on public.device_tokens
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = device_tokens.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "device tokens insert own" on public.device_tokens;
create policy "device tokens insert own"
on public.device_tokens
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.id = device_tokens.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "device tokens update own" on public.device_tokens;
create policy "device tokens update own"
on public.device_tokens
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = device_tokens.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = device_tokens.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

drop policy if exists "device tokens delete own" on public.device_tokens;
create policy "device tokens delete own"
on public.device_tokens
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = device_tokens.user_id
      and (u.auth_id = auth.uid() or u.id_uuid = auth.uid())
  )
);

-- Se la tabella esisteva già senza colonne attese, aggiungi in modo idempotente.
alter table public.device_tokens
  add column if not exists auth_id uuid;

alter table public.device_tokens
  add column if not exists platform text;

alter table public.device_tokens
  add column if not exists updated_at timestamptz;

alter table public.device_tokens
  alter column platform set default 'android';

update public.device_tokens
set platform = coalesce(nullif(btrim(platform), ''), 'android')
where platform is null or btrim(platform) = '';

update public.device_tokens
set updated_at = coalesce(updated_at, now())
where updated_at is null;

alter table public.device_tokens
  alter column platform set not null;
