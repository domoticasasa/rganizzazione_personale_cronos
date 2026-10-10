-- Il dipendente assegnatario può leggere/scaricare i PDF assegnazione delle sue Multicard MDO.

create or replace function public.is_own_assigned_multicard(p_multicard_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.logistica_multicard c
    join public.users u on u.auth_id = auth.uid()
    where c.id_uuid = p_multicard_id
      and (
        (
          c.assegnatario_user_uuid is not null
          and c.assegnatario_user_uuid = u.id_uuid
        )
        or (
          coalesce(nullif(trim(c.assegnatario_attuale), ''), '') <> ''
          and lower(regexp_replace(trim(c.assegnatario_attuale), '\s+', ' ', 'g'))
            = lower(regexp_replace(trim(coalesce(u.full_name, '')), '\s+', ' ', 'g'))
        )
      )
  );
$$;

grant execute on function public.is_own_assigned_multicard(uuid) to authenticated;

drop policy if exists logistica_multicard_mdo_assegnazioni_select
  on public.logistica_multicard_mdo_assegnazioni;
create policy logistica_multicard_mdo_assegnazioni_select
  on public.logistica_multicard_mdo_assegnazioni
  for select
  to authenticated
  using (
    public.is_multicard_mdo_assegnazioni_reader()
    or public.is_own_assigned_multicard(multicard_id)
  );

drop policy if exists logistica_multicard_mdo_assegnazioni_storage_select
  on storage.objects;
create policy logistica_multicard_mdo_assegnazioni_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and (
      public.is_multicard_mdo_assegnazioni_reader()
      or exists (
        select 1
        from public.logistica_multicard_mdo_assegnazioni d
        where d.file_path = name
          and public.is_own_assigned_multicard(d.multicard_id)
      )
    )
  );

notify pgrst, 'reload schema';
