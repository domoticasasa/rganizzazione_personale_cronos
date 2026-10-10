-- Evidenze firma in-app: marca temporale server + ledger HMAC (non TSA / non eIDAS).
create extension if not exists pgcrypto with schema extensions;

-- Token timestamp emesso prima dello stamp PDF (ora server vincolante).
create table if not exists public.doc_firma_ts_tokens (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.doc_firma_assignments (id) on delete cascade,
  nonce text not null,
  server_ts timestamptz not null default timezone('utc', now()),
  consumed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists doc_firma_ts_tokens_assign_idx
  on public.doc_firma_ts_tokens (assignment_id, created_at desc);

alter table public.doc_firma_ts_tokens enable row level security;

drop policy if exists doc_firma_ts_tokens_select on public.doc_firma_ts_tokens;
create policy doc_firma_ts_tokens_select
  on public.doc_firma_ts_tokens
  for select
  to authenticated
  using (
    public.is_doc_firma_admin()
    or exists (
      select 1 from public.doc_firma_assignments a
      where a.id = assignment_id
        and a.recipient_user_id = public.current_users_id()
    )
  );

-- Ledger evidenze: sopravvive al purge dei PDF (assignment_id diventa null).
create table if not exists public.doc_firma_evidence (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid references public.doc_firma_assignments (id) on delete set null,
  batch_id uuid,
  event text not null default 'signed',
  original_sha256 text,
  signed_sha256 text,
  page_codes jsonb,
  document_seal text,
  protections jsonb,
  server_ts timestamptz not null,
  ts_token_id uuid,
  ts_nonce text,
  evidence_hmac text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists doc_firma_evidence_batch_idx
  on public.doc_firma_evidence (batch_id, created_at desc);
create index if not exists doc_firma_evidence_assign_idx
  on public.doc_firma_evidence (assignment_id, created_at desc);

alter table public.doc_firma_evidence enable row level security;

drop policy if exists doc_firma_evidence_select on public.doc_firma_evidence;
create policy doc_firma_evidence_select
  on public.doc_firma_evidence
  for select
  to authenticated
  using (
    public.is_doc_firma_admin()
    or (
      assignment_id is not null
      and exists (
        select 1 from public.doc_firma_assignments a
        where a.id = assignment_id
          and a.recipient_user_id = public.current_users_id()
      )
    )
  );

-- Chiave HMAC applicativa (non TSA). Sovrascrivibile via:
--   alter database postgres set app.settings.doc_firma_evidence_key = '...';
create or replace function public.doc_firma_evidence_hmac(p_payload text)
returns text
language plpgsql
immutable
security definer
set search_path = public, extensions
as $$
declare
  v_key text;
begin
  begin
    v_key := nullif(current_setting('app.settings.doc_firma_evidence_key', true), '');
  exception when others then
    v_key := null;
  end;
  if v_key is null then
    v_key := 'cronos-doc-firma-evidence-v1';
  end if;
  return encode(
    extensions.hmac(
      convert_to(p_payload, 'UTF8'),
      convert_to(v_key, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$$;

revoke all on function public.doc_firma_evidence_hmac(text) from public;
grant execute on function public.doc_firma_evidence_hmac(text) to authenticated;

-- Emette marca temporale server da includere nel PDF.
create or replace function public.doc_firma_issue_timestamp(
  p_assignment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer := public.current_users_id();
  v_assign public.doc_firma_assignments%rowtype;
  v_id uuid;
  v_nonce text;
  v_ts timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_assign
  from public.doc_firma_assignments a
  where a.id = p_assignment_id
  for update;

  if v_assign.id is null then
    raise exception 'assignment not found';
  end if;
  if v_assign.recipient_user_id is distinct from v_uid then
    raise exception 'forbidden';
  end if;
  if v_assign.status <> 'pending' then
    raise exception 'assignment not pending';
  end if;
  if v_assign.sign_deadline < timezone('utc', now()) then
    update public.doc_firma_assignments
    set status = 'expired'
    where id = p_assignment_id;
    raise exception 'sign deadline expired';
  end if;

  v_nonce := encode(extensions.gen_random_bytes(16), 'hex');
  v_ts := timezone('utc', now());

  insert into public.doc_firma_ts_tokens (assignment_id, nonce, server_ts)
  values (p_assignment_id, v_nonce, v_ts)
  returning id into v_id;

  return jsonb_build_object(
    'token_id', v_id,
    'nonce', v_nonce,
    'server_ts', v_ts,
    'kind', 'cronos_server_timestamp',
    'note', 'Marca temporale server CRONOS (non TSA RFC3161 / non eIDAS)'
  );
end;
$$;

grant execute on function public.doc_firma_issue_timestamp(uuid) to authenticated;

-- mark_signed: richiede Passkey+OTP e consuma token timestamp; scrive ledger evidenze.
create or replace function public.doc_firma_mark_signed(
  p_assignment_id uuid,
  p_signed_pdf_path text,
  p_signed_pdf_sha256 text,
  p_signature_meta jsonb default '{}'::jsonb
)
returns public.doc_firma_assignments
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid integer := public.current_users_id();
  v_assign public.doc_firma_assignments%rowtype;
  v_otp_ok boolean;
  v_passkey_ok boolean;
  v_meta jsonb := coalesce(p_signature_meta, '{}'::jsonb);
  v_token_id uuid;
  v_token public.doc_firma_ts_tokens%rowtype;
  v_payload text;
  v_hmac text;
  v_evidence_id uuid;
  v_server_ts timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_assign
  from public.doc_firma_assignments a
  where a.id = p_assignment_id
  for update;

  if v_assign.id is null then
    raise exception 'assignment not found';
  end if;
  if v_assign.recipient_user_id is distinct from v_uid then
    raise exception 'forbidden';
  end if;
  if v_assign.status <> 'pending' then
    raise exception 'assignment not pending';
  end if;
  if v_assign.sign_deadline < timezone('utc', now()) then
    update public.doc_firma_assignments
    set status = 'expired'
    where id = p_assignment_id;
    raise exception 'sign deadline expired';
  end if;

  select exists (
    select 1 from public.doc_firma_otp o
    where o.assignment_id = p_assignment_id
      and o.verified_at is not null
      and o.verified_at > timezone('utc', now()) - interval '30 minutes'
  ) into v_otp_ok;

  select exists (
    select 1 from public.doc_firma_passkey_auth p
    where p.assignment_id = p_assignment_id
      and p.verified_at > timezone('utc', now()) - interval '30 minutes'
  ) into v_passkey_ok;

  if not coalesce(v_passkey_ok, false) then
    raise exception 'passkey not verified';
  end if;
  if not coalesce(v_otp_ok, false) then
    raise exception 'otp not verified';
  end if;

  begin
    v_token_id := nullif(trim(v_meta->>'ts_token_id'), '')::uuid;
  exception when others then
    v_token_id := null;
  end;

  if v_token_id is null then
    raise exception 'timestamp token required';
  end if;

  select * into v_token
  from public.doc_firma_ts_tokens t
  where t.id = v_token_id
  for update;

  if v_token.id is null
     or v_token.assignment_id is distinct from p_assignment_id then
    raise exception 'invalid timestamp token';
  end if;
  if v_token.consumed_at is not null then
    raise exception 'timestamp token already used';
  end if;
  if v_token.server_ts < timezone('utc', now()) - interval '30 minutes' then
    raise exception 'timestamp token expired';
  end if;

  update public.doc_firma_ts_tokens
  set consumed_at = timezone('utc', now())
  where id = v_token_id;

  v_server_ts := v_token.server_ts;
  v_payload := concat_ws('|',
    p_assignment_id::text,
    coalesce(v_assign.batch_id::text, ''),
    coalesce(v_meta->>'original_sha256', ''),
    trim(p_signed_pdf_sha256),
    coalesce(v_meta->>'document_seal', ''),
    v_token.id::text,
    v_token.nonce,
    v_server_ts::text
  );
  v_hmac := public.doc_firma_evidence_hmac(v_payload);

  insert into public.doc_firma_evidence (
    assignment_id,
    batch_id,
    event,
    original_sha256,
    signed_sha256,
    page_codes,
    document_seal,
    protections,
    server_ts,
    ts_token_id,
    ts_nonce,
    evidence_hmac,
    payload
  ) values (
    p_assignment_id,
    v_assign.batch_id,
    'signed',
    nullif(v_meta->>'original_sha256', ''),
    trim(p_signed_pdf_sha256),
    v_meta->'page_codes',
    nullif(v_meta->>'document_seal', ''),
    coalesce(v_meta->'protections', '["passkey","otp","signature"]'::jsonb),
    v_server_ts,
    v_token.id,
    v_token.nonce,
    v_hmac,
    jsonb_build_object(
      'kind', 'cronos_server_timestamp',
      'note', 'Marca temporale server CRONOS (non TSA RFC3161 / non eIDAS)',
      'signer_name', v_meta->>'signer_name',
      'signer_email', v_meta->>'signer_email',
      'auth_method', v_meta->>'auth_method',
      'pdf_locked', v_meta->'pdf_locked',
      'payload_canon', v_payload
    )
  ) returning id into v_evidence_id;

  v_meta := v_meta || jsonb_build_object(
    'server_timestamp', v_server_ts,
    'ts_nonce', v_token.nonce,
    'evidence_id', v_evidence_id,
    'evidence_hmac', v_hmac,
    'timestamp_kind', 'cronos_server_timestamp'
  );

  update public.doc_firma_assignments
  set
    status = 'signed',
    signed_at = v_server_ts,
    download_until = v_server_ts + interval '3 days',
    signed_pdf_path = trim(p_signed_pdf_path),
    signed_pdf_sha256 = trim(p_signed_pdf_sha256),
    signature_meta = v_meta
  where id = p_assignment_id
  returning * into v_assign;

  return v_assign;
end;
$$;

grant execute on function public.doc_firma_mark_signed(uuid, text, text, jsonb) to authenticated;

-- Pacchetto evidenze per admin (batch o singola assegnazione).
create or replace function public.doc_firma_list_evidence(
  p_batch_id uuid default null,
  p_assignment_id uuid default null
)
returns setof public.doc_firma_evidence
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_doc_firma_admin() then
    raise exception 'forbidden';
  end if;
  if p_assignment_id is not null then
    return query
      select e.*
      from public.doc_firma_evidence e
      where e.assignment_id = p_assignment_id
         or (e.assignment_id is null and e.payload->>'assignment_id' = p_assignment_id::text)
      order by e.created_at;
    return;
  end if;
  if p_batch_id is null then
    raise exception 'batch_id or assignment_id required';
  end if;
  return query
    select e.*
    from public.doc_firma_evidence e
    where e.batch_id = p_batch_id
    order by e.created_at;
end;
$$;

grant execute on function public.doc_firma_list_evidence(uuid, uuid) to authenticated;

comment on table public.doc_firma_evidence is
  'Ledger evidenze firma (timestamp server + HMAC). Non e'' conservazione AgID ne'' TSA.';
comment on function public.doc_firma_issue_timestamp(uuid) is
  'Emette marca temporale server da stampare sul PDF prima del completeSign.';
