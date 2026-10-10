-- Dipendente: lettura/download PDF assegnazione solo sui mezzi assegnati a sé.

create or replace function public.is_own_assigned_mezzo_stradale(p_mezzo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.logistica_mezzi_stradali m
    where m.id_uuid = p_mezzo_id
      and m.assegnatario_user_uuid is not null
      and m.assegnatario_user_uuid = (select public.current_user_uuid())
  );
$$;

grant execute on function public.is_own_assigned_mezzo_stradale(uuid)
  to authenticated;

drop policy if exists logistica_assegnazione_mezzi_doc_select
  on public.logistica_assegnazione_mezzi_stradali_documenti;
create policy logistica_assegnazione_mezzi_doc_select
  on public.logistica_assegnazione_mezzi_stradali_documenti
  for select
  to authenticated
  using (
    (select public.is_assegnazione_mezzi_stradali_documenti_reader())
    or (select public.is_own_assigned_mezzo_stradale(mezzo_id))
  );

drop policy if exists logistica_assegnazione_mezzi_doc_storage_select
  on storage.objects;
create policy logistica_assegnazione_mezzi_doc_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_assegnazione_mezzi_stradali_documenti'
    and (
      (select public.is_assegnazione_mezzi_stradali_documenti_reader())
      or exists (
        select 1
        from public.logistica_assegnazione_mezzi_stradali_documenti d
        where d.file_path = name
          and (select public.is_own_assigned_mezzo_stradale(d.mezzo_id))
      )
    )
  );

notify pgrst, 'reload schema';
