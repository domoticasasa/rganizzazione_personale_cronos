-- Workflow ferie/permessi: inserimento solo DT/assistente DT; dipendente vede per personale_id_uuid.

create or replace function public.personale_visible_to_current_user(p_personale_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.personale p
    join public.users u on u.auth_id = auth.uid()
    where p.id_uuid = p_personale_uuid
      and (
        nullif(trim(p.user_id::text), '') = u.auth_id::text
        or nullif(trim(p.user_id::text), '') = u.id::text
        or nullif(trim(p.user_id::text), '') = u.id_uuid::text
      )
  )
$$;

drop policy if exists dipendente_assenze_select on public.dipendente_assenze;
create policy dipendente_assenze_select
on public.dipendente_assenze
for select
to authenticated
using (
  requester_user_uuid = public.current_user_uuid()
  or public.personale_visible_to_current_user(personale_id_uuid)
  or (
    public.user_has_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
  )
  or public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_insert on public.dipendente_assenze;
create policy dipendente_assenze_insert
on public.dipendente_assenze
for insert
to authenticated
with check (
  (
    coalesce(segnalazione_admin, false) = true
    and public.current_user_role_norm() in (
      'admin',
      'admin_generale',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_dpi',
      'admin_formazione'
    )
  )
  or (
    coalesce(segnalazione_admin, false) = false
    and upper(coalesce(tipo_assenza, '')) in ('FERIE', 'PERMESSO')
    and public.user_has_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
    and personale_id_uuid is not null
    and requester_user_uuid is not null
    and workflow_status = 'APPROVATA_DT'
  )
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_delete on public.dipendente_assenze;
create policy dipendente_assenze_delete
on public.dipendente_assenze
for delete
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('dipendente_assenze')
);
