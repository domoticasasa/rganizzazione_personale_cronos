-- Firma richiede entrambe le verifiche: Passkey E OTP (entro 30 minuti).

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

  if not coalesce(v_passkey_ok, false) then
    raise exception 'passkey not verified';
  end if;

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

comment on function public.doc_firma_mark_signed(uuid, text, text, jsonb) is
  'Completa firma solo se Passkey e OTP sono entrambi verificati (30 minuti).';

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
