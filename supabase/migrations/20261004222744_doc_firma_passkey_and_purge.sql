-- Passkey come alternativa all'OTP per firmare + purge automatico documenti scaduti.

create table if not exists public.doc_firma_passkey_auth (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.doc_firma_assignments (id) on delete cascade,
  verified_at timestamptz not null default timezone('utc', now()),
  constraint doc_firma_passkey_auth_assignment_uidx unique (assignment_id)
);

create index if not exists doc_firma_passkey_auth_verified_idx
  on public.doc_firma_passkey_auth (assignment_id, verified_at desc);

alter table public.doc_firma_passkey_auth enable row level security;

drop policy if exists doc_firma_passkey_auth_select on public.doc_firma_passkey_auth;
create policy doc_firma_passkey_auth_select
  on public.doc_firma_passkey_auth
  for select
  to authenticated
  using (
    public.is_doc_firma_admin()
    or exists (
      select 1
      from public.doc_firma_assignments a
      where a.id = assignment_id
        and a.recipient_user_id = public.current_users_id()
    )
  );

-- Registra verifica Passkey (dopo cerimonia client) entro la finestra di firma.
create or replace function public.doc_firma_record_passkey_auth(
  p_assignment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid integer := public.current_users_id();
  v_assign public.doc_firma_assignments%rowtype;
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

  insert into public.doc_firma_passkey_auth (assignment_id, verified_at)
  values (p_assignment_id, timezone('utc', now()))
  on conflict (assignment_id) do update
    set verified_at = excluded.verified_at;

  return true;
end;
$$;

grant execute on function public.doc_firma_record_passkey_auth(uuid) to authenticated;

-- Completa firma: OTP verificato OPPURE Passkey verificata (30 minuti).
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
  v_passkey_ok boolean;
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

  select exists (
    select 1
    from public.doc_firma_passkey_auth p
    where p.assignment_id = p_assignment_id
      and p.verified_at > timezone('utc', now()) - interval '30 minutes'
  ) into v_passkey_ok;

  if not coalesce(v_otp_ok, false) and not coalesce(v_passkey_ok, false) then
    raise exception 'identity not verified (otp or passkey required)';
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

-- Scade pending + elimina assegnazioni oltre finestra download.
-- I path Storage vengono restituiti al client (delete diretto su storage.objects è bloccato).
drop function if exists public.doc_firma_expire_pending();

create or replace function public.doc_firma_expire_pending()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  n_expired integer := 0;
  n_purged integer := 0;
  r record;
  v_batch uuid;
  v_paths text[] := '{}';
  v_batch_paths text[];
begin
  update public.doc_firma_assignments a
  set status = 'expired'
  where a.status = 'pending'
    and a.sign_deadline < timezone('utc', now());
  get diagnostics n_expired = row_count;

  for r in
    select a.id, a.batch_id, a.signed_pdf_path, b.pdf_path, b.source_path
    from public.doc_firma_assignments a
    left join public.doc_firma_batches b on b.id = a.batch_id
    where (
      a.status = 'expired'
      or (
        a.status in ('signed', 'cancelled')
        and a.download_until is not null
        and a.download_until < timezone('utc', now())
      )
      or (
        a.status = 'cancelled'
        and (
          a.download_until is null
          or a.download_until < timezone('utc', now())
        )
        and (
          a.sign_deadline is null
          or a.sign_deadline < timezone('utc', now())
        )
      )
    )
  loop
    v_paths := array_append(v_paths, 'assignment/' || r.id::text || '/signed.pdf');
    v_paths := array_append(v_paths, 'assignment/' || r.id::text || '/signature.png');
    if r.signed_pdf_path is not null and length(trim(r.signed_pdf_path)) > 0 then
      v_paths := array_append(v_paths, trim(r.signed_pdf_path));
    end if;

    v_batch := r.batch_id;
    delete from public.doc_firma_assignments where id = r.id;
    n_purged := n_purged + 1;

    if v_batch is not null
       and not exists (
         select 1 from public.doc_firma_assignments x where x.batch_id = v_batch
       )
    then
      if r.pdf_path is not null and length(trim(r.pdf_path)) > 0 then
        v_paths := array_append(v_paths, trim(r.pdf_path));
      end if;
      if r.source_path is not null and length(trim(r.source_path)) > 0 then
        v_paths := array_append(v_paths, trim(r.source_path));
      end if;
      v_batch_paths := array[
        'batch/' || v_batch::text || '/original.pdf',
        'batch/' || v_batch::text || '/source'
      ];
      v_paths := v_paths || v_batch_paths;
      delete from public.doc_firma_batches where id = v_batch;
    end if;
  end loop;

  return jsonb_build_object(
    'expired', coalesce(n_expired, 0),
    'purged', coalesce(n_purged, 0),
    'storage_paths', to_jsonb(coalesce(v_paths, '{}'::text[]))
  );
end;
$$;

grant execute on function public.doc_firma_expire_pending() to authenticated;

comment on function public.doc_firma_expire_pending() is
  'Marca pending scaduti, elimina assegnazioni/batch oltre finestra e restituisce path Storage da cancellare via API.';

comment on function public.doc_firma_record_passkey_auth(uuid) is
  'Registra verifica Passkey account come alternativa all''OTP email.';

-- Testo notifica allineato a OTP o Passkey.
create or replace function public.doc_firma_notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select b.title into v_title
  from public.doc_firma_batches b
  where b.id = new.batch_id;

  insert into public.notifications (user_id, title, message, meta, is_read)
  values (
    new.recipient_user_id,
    'Documento da firmare',
    format(
      'Hai ricevuto «%s». Hai 3 giorni per firmarlo (Passkey + OTP + firma).',
      coalesce(nullif(trim(v_title), ''), 'documento')
    ),
    jsonb_build_object(
      'type', 'doc_firma',
      'batch_id', new.batch_id,
      'assignment_id', new.id,
      'action', 'assigned'
    ),
    false
  );

  return new;
exception
  when others then
    raise warning 'doc_firma_notify_assignment: %', sqlerrm;
    return new;
end;
$$;
