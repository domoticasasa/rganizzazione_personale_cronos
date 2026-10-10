-- Notifica automatica al dipendente quando riceve un documento da firmare.

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
      'Hai ricevuto «%s». Hai 3 giorni per firmarlo (OTP via email).',
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
    -- Non bloccare l'invio documento se la notifica fallisce
    raise warning 'doc_firma_notify_assignment: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists trg_doc_firma_notify_assignment on public.doc_firma_assignments;
create trigger trg_doc_firma_notify_assignment
after insert on public.doc_firma_assignments
for each row
execute function public.doc_firma_notify_assignment();

comment on function public.doc_firma_notify_assignment() is
  'Crea notifica in-app per il destinatario all''assegnazione di un documento da firmare.';
