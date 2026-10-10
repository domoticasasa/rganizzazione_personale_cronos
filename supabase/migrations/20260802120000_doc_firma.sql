-- Documenti da firmare (admin → dipendenti): OTP email, 3g firma + 3g download.

create extension if not exists pgcrypto;

create table if not exists public.doc_firma_batches (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  created_by_user_id integer not null references public.users (id) on delete restrict,
  original_file_name text not null,
  original_mime text,
  source_path text,
  pdf_path text not null,
  pdf_sha256 text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint doc_firma_batches_title_nonempty check (length(trim(title)) > 0)
);

create index if not exists doc_firma_batches_created_at_idx
  on public.doc_firma_batches (created_at desc);
create index if not exists doc_firma_batches_created_by_idx
  on public.doc_firma_batches (created_by_user_id);

comment on table public.doc_firma_batches is
  'Invio documenti da firmare: un PDF per batch, N assegnazioni dipendenti.';

create table if not exists public.doc_firma_assignments (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.doc_firma_batches (id) on delete cascade,
  personale_id uuid references public.personale (id_uuid) on delete set null,
  recipient_user_id integer not null references public.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'signed', 'expired', 'cancelled')),
  sent_at timestamptz not null default timezone('utc', now()),
  sign_deadline timestamptz not null,
  signed_at timestamptz,
  download_until timestamptz,
  signed_pdf_path text,
  signed_pdf_sha256 text,
  signature_meta jsonb not null default '{}'::jsonb,
  cancelled_at timestamptz,
  cancelled_by_user_id integer references public.users (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint doc_firma_assignments_batch_recipient_unique unique (batch_id, recipient_user_id)
);

create index if not exists doc_firma_assignments_recipient_idx
  on public.doc_firma_assignments (recipient_user_id, status);
create index if not exists doc_firma_assignments_batch_idx
  on public.doc_firma_assignments (batch_id);
create index if not exists doc_firma_assignments_sign_deadline_idx
  on public.doc_firma_assignments (sign_deadline)
  where status = 'pending';

comment on table public.doc_firma_assignments is
  'Assegnazione documento a un dipendente: 3 giorni per firmare, 3 per scaricare.';

create table if not exists public.doc_firma_otp (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.doc_firma_assignments (id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0,
  verified_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists doc_firma_otp_assignment_idx
  on public.doc_firma_otp (assignment_id, created_at desc);

-- Helpers ruolo admin-like per documenti
create or replace function public.is_doc_firma_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione',
    'dt',
    'assistente_dt',
    'uqsa'
  );
$$;

grant execute on function public.is_doc_firma_admin() to authenticated;

create or replace function public.current_users_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select u.id
  from public.users u
  where u.auth_id = auth.uid()
  limit 1
$$;

grant execute on function public.current_users_id() to authenticated;

-- Marca scaduti (pending oltre sign_deadline)
create or replace function public.doc_firma_expire_pending()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.doc_firma_assignments a
  set status = 'expired'
  where a.status = 'pending'
    and a.sign_deadline < timezone('utc', now());
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.doc_firma_expire_pending() to authenticated;

-- Verifica OTP (hash SHA-256 hex del codice)
create or replace function public.doc_firma_verify_otp(
  p_assignment_id uuid,
  p_code text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer := public.current_users_id();
  v_row public.doc_firma_otp%rowtype;
  v_hash text;
  v_assign public.doc_firma_assignments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_assign
  from public.doc_firma_assignments a
  where a.id = p_assignment_id;

  if v_assign.id is null then
    raise exception 'assignment not found';
  end if;

  if v_assign.recipient_user_id is distinct from v_uid
     and not public.is_doc_firma_admin() then
    raise exception 'forbidden';
  end if;

  if v_assign.status <> 'pending' then
    raise exception 'assignment not pending';
  end if;

  if v_assign.sign_deadline < timezone('utc', now()) then
    update public.doc_firma_assignments
    set status = 'expired'
    where id = p_assignment_id and status = 'pending';
    raise exception 'sign deadline expired';
  end if;

  select * into v_row
  from public.doc_firma_otp o
  where o.assignment_id = p_assignment_id
    and o.verified_at is null
  order by o.created_at desc
  limit 1;

  if v_row.id is null then
    raise exception 'otp not found';
  end if;

  if v_row.expires_at < timezone('utc', now()) then
    raise exception 'otp expired';
  end if;

  if v_row.attempts >= 5 then
    raise exception 'otp locked';
  end if;

  v_hash := encode(digest(trim(p_code), 'sha256'), 'hex');

  update public.doc_firma_otp
  set attempts = attempts + 1
  where id = v_row.id;

  if v_hash <> v_row.code_hash then
    return false;
  end if;

  update public.doc_firma_otp
  set verified_at = timezone('utc', now())
  where id = v_row.id;

  return true;
end;
$$;

grant execute on function public.doc_firma_verify_otp(uuid, text) to authenticated;

-- Completa firma (dopo OTP + upload PDF firmato)
create or replace function public.doc_firma_mark_signed(
  p_assignment_id uuid,
  p_signed_pdf_path text,
  p_signed_pdf_sha256 text,
  p_signature_meta jsonb default '{}'::jsonb
)
returns public.doc_firma_assignments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer := public.current_users_id();
  v_assign public.doc_firma_assignments%rowtype;
  v_otp_ok boolean;
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
    select 1
    from public.doc_firma_otp o
    where o.assignment_id = p_assignment_id
      and o.verified_at is not null
      and o.verified_at > timezone('utc', now()) - interval '30 minutes'
  ) into v_otp_ok;

  if not coalesce(v_otp_ok, false) then
    raise exception 'otp not verified';
  end if;

  update public.doc_firma_assignments
  set
    status = 'signed',
    signed_at = timezone('utc', now()),
    download_until = timezone('utc', now()) + interval '3 days',
    signed_pdf_path = trim(p_signed_pdf_path),
    signed_pdf_sha256 = trim(p_signed_pdf_sha256),
    signature_meta = coalesce(p_signature_meta, '{}'::jsonb)
  where id = p_assignment_id
  returning * into v_assign;

  return v_assign;
end;
$$;

grant execute on function public.doc_firma_mark_signed(uuid, text, text, jsonb) to authenticated;

-- Cancella (admin) prima della scadenza download / se pending
create or replace function public.doc_firma_cancel_assignment(p_assignment_id uuid)
returns public.doc_firma_assignments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer := public.current_users_id();
  v_assign public.doc_firma_assignments%rowtype;
begin
  if not public.is_doc_firma_admin() then
    raise exception 'forbidden';
  end if;

  select * into v_assign
  from public.doc_firma_assignments a
  where a.id = p_assignment_id
  for update;

  if v_assign.id is null then
    raise exception 'assignment not found';
  end if;

  if v_assign.status = 'cancelled' then
    return v_assign;
  end if;

  if v_assign.status = 'signed'
     and v_assign.download_until is not null
     and v_assign.download_until < timezone('utc', now()) then
    raise exception 'download window closed';
  end if;

  if v_assign.status = 'expired' then
    raise exception 'already expired';
  end if;

  update public.doc_firma_assignments
  set
    status = 'cancelled',
    cancelled_at = timezone('utc', now()),
    cancelled_by_user_id = v_uid
  where id = p_assignment_id
  returning * into v_assign;

  return v_assign;
end;
$$;

grant execute on function public.doc_firma_cancel_assignment(uuid) to authenticated;

alter table public.doc_firma_batches enable row level security;
alter table public.doc_firma_assignments enable row level security;
alter table public.doc_firma_otp enable row level security;

drop policy if exists doc_firma_batches_select on public.doc_firma_batches;
create policy doc_firma_batches_select
  on public.doc_firma_batches
  for select
  to authenticated
  using (
    public.is_doc_firma_admin()
    or exists (
      select 1
      from public.doc_firma_assignments a
      where a.batch_id = doc_firma_batches.id
        and a.recipient_user_id = public.current_users_id()
    )
  );

drop policy if exists doc_firma_batches_insert on public.doc_firma_batches;
create policy doc_firma_batches_insert
  on public.doc_firma_batches
  for insert
  to authenticated
  with check (
    public.is_doc_firma_admin()
    and created_by_user_id = public.current_users_id()
  );

drop policy if exists doc_firma_batches_update on public.doc_firma_batches;
create policy doc_firma_batches_update
  on public.doc_firma_batches
  for update
  to authenticated
  using (public.is_doc_firma_admin())
  with check (public.is_doc_firma_admin());

drop policy if exists doc_firma_assignments_select on public.doc_firma_assignments;
create policy doc_firma_assignments_select
  on public.doc_firma_assignments
  for select
  to authenticated
  using (
    public.is_doc_firma_admin()
    or recipient_user_id = public.current_users_id()
  );

drop policy if exists doc_firma_assignments_insert on public.doc_firma_assignments;
create policy doc_firma_assignments_insert
  on public.doc_firma_assignments
  for insert
  to authenticated
  with check (public.is_doc_firma_admin());

drop policy if exists doc_firma_assignments_update on public.doc_firma_assignments;
create policy doc_firma_assignments_update
  on public.doc_firma_assignments
  for update
  to authenticated
  using (
    public.is_doc_firma_admin()
    or recipient_user_id = public.current_users_id()
  )
  with check (
    public.is_doc_firma_admin()
    or recipient_user_id = public.current_users_id()
  );

-- OTP: solo service role / edge (security definer inserts) — deny direct client
drop policy if exists doc_firma_otp_deny on public.doc_firma_otp;
create policy doc_firma_otp_deny
  on public.doc_firma_otp
  for all
  to authenticated
  using (false)
  with check (false);

-- Storage bucket
insert into storage.buckets (id, name, public, file_size_limit)
values ('doc_firma', 'doc_firma', false, 52428800)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists doc_firma_storage_select on storage.objects;
create policy doc_firma_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'doc_firma'
    and (
      public.is_doc_firma_admin()
      or exists (
        select 1
        from public.doc_firma_assignments a
        join public.doc_firma_batches b on b.id = a.batch_id
        where a.recipient_user_id = public.current_users_id()
          and (
            b.pdf_path = name
            or a.signed_pdf_path = name
          )
          and a.status in ('pending', 'signed')
          and (
            a.status = 'pending'
            or (
              a.status = 'signed'
              and a.download_until is not null
              and a.download_until >= timezone('utc', now())
            )
          )
      )
    )
  );

drop policy if exists doc_firma_storage_insert on storage.objects;
create policy doc_firma_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'doc_firma'
    and (
      public.is_doc_firma_admin()
      or name like ('assignment/' || '%' || '/signed.pdf')
    )
  );

drop policy if exists doc_firma_storage_update on storage.objects;
create policy doc_firma_storage_update
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'doc_firma' and public.is_doc_firma_admin())
  with check (bucket_id = 'doc_firma' and public.is_doc_firma_admin());

drop policy if exists doc_firma_storage_delete on storage.objects;
create policy doc_firma_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'doc_firma' and public.is_doc_firma_admin());

-- Inserimento OTP (JWT del dipendente)
create or replace function public.doc_firma_store_otp(
  p_assignment_id uuid,
  p_code_hash text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_assign public.doc_firma_assignments%rowtype;
  v_uid integer := public.current_users_id();
begin
  select * into v_assign
  from public.doc_firma_assignments
  where id = p_assignment_id;

  if v_assign.id is null then
    raise exception 'assignment not found';
  end if;

  if v_assign.recipient_user_id is distinct from v_uid
     and not public.is_doc_firma_admin() then
    raise exception 'forbidden';
  end if;

  if v_assign.status <> 'pending' then
    raise exception 'assignment not pending';
  end if;

  insert into public.doc_firma_otp (assignment_id, code_hash, expires_at)
  values (p_assignment_id, p_code_hash, p_expires_at)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.doc_firma_store_otp(uuid, text, timestamptz) to authenticated;
