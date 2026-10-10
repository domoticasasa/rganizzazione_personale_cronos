-- Fix verify OTP: digest() non trovato / cast (pgcrypto su schema extensions).

create extension if not exists pgcrypto with schema extensions;

create or replace function public.doc_firma_verify_otp(
  p_assignment_id uuid,
  p_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
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

  -- Allinea allo SHA-256 hex dell'edge (UTF-8)
  v_hash := encode(
    extensions.digest(convert_to(trim(p_code), 'UTF8'), 'sha256'::text),
    'hex'
  );

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
