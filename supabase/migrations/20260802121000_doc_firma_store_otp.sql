-- Completa RPC store OTP (mancante nella push precedente se file troncato).
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
