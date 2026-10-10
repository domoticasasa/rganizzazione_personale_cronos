-- Password opzionale impostata dall'admin all'invio (testo libero).
-- Si salva solo l'hash; verifica via RPC.

alter table public.doc_firma_batches
  add column if not exists access_password_hash text,
  add column if not exists has_access_password boolean not null default false;

comment on column public.doc_firma_batches.access_password_hash is
  'SHA-256 hex della password accesso documento (opzionale).';
comment on column public.doc_firma_batches.has_access_password is
  'True se l''admin ha impostato una password di accesso per i firmatari.';

create or replace function public.doc_firma_verify_access_password(
  p_batch_id uuid,
  p_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid integer := public.current_users_id();
  v_batch public.doc_firma_batches%rowtype;
  v_hash text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_batch
  from public.doc_firma_batches b
  where b.id = p_batch_id;

  if v_batch.id is null then
    raise exception 'batch not found';
  end if;

  if not coalesce(v_batch.has_access_password, false)
     or coalesce(trim(v_batch.access_password_hash), '') = '' then
    return true;
  end if;

  -- Destinatario del batch oppure admin
  if not public.is_doc_firma_admin()
     and not exists (
       select 1
       from public.doc_firma_assignments a
       where a.batch_id = p_batch_id
         and a.recipient_user_id = v_uid
     ) then
    raise exception 'forbidden';
  end if;

  v_hash := encode(digest(trim(p_password), 'sha256'), 'hex');
  return v_hash = v_batch.access_password_hash;
end;
$$;

grant execute on function public.doc_firma_verify_access_password(uuid, text) to authenticated;
