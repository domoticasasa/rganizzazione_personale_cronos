-- Registry pagina admin + storage insert firmati solo del destinatario.

insert into public.app_page_registry (page_key, label, active)
values ('documenti_firma', 'Documenti da firmare', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

drop policy if exists doc_firma_storage_insert on storage.objects;
create policy doc_firma_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'doc_firma'
    and (
      public.is_doc_firma_admin()
      or exists (
        select 1
        from public.doc_firma_assignments a
        where a.recipient_user_id = public.current_users_id()
          and a.status = 'pending'
          and name = ('assignment/' || a.id::text || '/signed.pdf')
      )
    )
  );
