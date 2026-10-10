-- Sessioni di accesso PC via QR sul telefono (senza Windows Hello / hybrid WebAuthn).
create table if not exists public.auth_qr_sessions (
  id uuid primary key default gen_random_uuid(),
  public_code text not null unique,
  claim_secret text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'claimed', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  approved_at timestamptz,
  claimed_at timestamptz,
  user_auth_id uuid,
  access_token text,
  refresh_token text
);

create index if not exists auth_qr_sessions_code_idx
  on public.auth_qr_sessions (public_code);

create index if not exists auth_qr_sessions_expires_idx
  on public.auth_qr_sessions (expires_at);

alter table public.auth_qr_sessions enable row level security;

comment on table public.auth_qr_sessions is
  'Pairing login desktop↔telefono via QR; accesso solo via edge function service role.';
