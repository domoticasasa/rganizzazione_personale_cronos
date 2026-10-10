-- Fix: niente DELETE diretto su storage.objects (bloccato dal trigger protect_delete).
-- Restituisce i path da rimuovere via Storage API dal client.

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
