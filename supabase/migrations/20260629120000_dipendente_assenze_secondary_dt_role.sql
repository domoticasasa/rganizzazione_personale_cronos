-- DT / Assistente DT anche come ruolo secondario (secondary_role).

create or replace function public.current_user_secondary_role_norm()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(replace(coalesce(u.secondary_role, ''), ' ', '_'))
  from public.users u
  where u.auth_id = auth.uid()
  limit 1
$$;

create or replace function public.user_has_dt_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in ('dt', 'assistente_dt')
      or coalesce(public.current_user_secondary_role_norm(), '') in ('dt', 'assistente_dt')
$$;

create or replace function public.guard_dipendente_assenze_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uuid uuid;
begin
  v_user_uuid := public.current_user_uuid();

  if public.user_has_dt_role() then
    if old.workflow_status <> 'INVIATA_AL_DT' then
      raise exception 'Richiesta non più modificabile dal DT.';
    end if;
    if coalesce(old.assigned_dt_user_uuid::text, '') <> coalesce(v_user_uuid::text, '') then
      raise exception 'Richiesta non assegnata a questo DT.';
    end if;
    if old.data_dal is distinct from new.data_dal
       or old.data_al is distinct from new.data_al
       or old.prolungato_fino_al is distinct from new.prolungato_fino_al
       or old.tipo_assenza is distinct from new.tipo_assenza
       or old.personale_id_uuid is distinct from new.personale_id_uuid then
      raise exception 'Il DT non può modificare date o dipendente.';
    end if;
    if new.workflow_status not in ('APPROVATA_DT', 'RIFIUTATA_DT') then
      raise exception 'Stato non valido per decisione DT.';
    end if;
    if new.workflow_status = 'RIFIUTATA_DT' and coalesce(trim(new.dt_comment), '') = '' then
      raise exception 'Commento obbligatorio per rifiuto DT.';
    end if;
    new.dt_decision_at := now();
    new.dt_decision_by_user_uuid := v_user_uuid;
    return new;
  end if;

  if public.current_user_role_norm() in (
    'admin', 'admin_generale', 'admin_pernottamenti',
    'admin_trenoaereo', 'admin_dpi', 'admin_formazione'
  ) then
    if old.workflow_status <> 'APPROVATA_DT' then
      raise exception 'L''admin può decidere solo richieste approvate dal DT.';
    end if;
    if new.workflow_status not in ('APPROVATA_ADMIN', 'RIFIUTATA_ADMIN') then
      raise exception 'Stato non valido per decisione admin.';
    end if;
    if new.workflow_status = 'RIFIUTATA_ADMIN' and coalesce(trim(new.admin_comment), '') = '' then
      raise exception 'Commento obbligatorio per rifiuto admin.';
    end if;
    new.admin_decision_at := now();
    new.admin_decision_by_user_uuid := v_user_uuid;
    return new;
  end if;

  return new;
end;
$$;

drop policy if exists dipendente_assenze_select on public.dipendente_assenze;
create policy dipendente_assenze_select
on public.dipendente_assenze
for select
to authenticated
using (
  requester_user_uuid = public.current_user_uuid()
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

drop policy if exists dipendente_assenze_update on public.dipendente_assenze;
create policy dipendente_assenze_update
on public.dipendente_assenze
for update
to authenticated
using (
  (
    public.user_has_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
    and workflow_status = 'INVIATA_AL_DT'
  )
  or (
    public.current_user_role_norm() in (
      'admin',
      'admin_generale',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_dpi',
      'admin_formazione'
    )
    and workflow_status = 'APPROVATA_DT'
  )
  or public.has_custom_page_access('dipendente_assenze')
)
with check (
  (
    public.user_has_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
    and workflow_status in ('APPROVATA_DT', 'RIFIUTATA_DT')
  )
  or (
    public.current_user_role_norm() in (
      'admin',
      'admin_generale',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_dpi',
      'admin_formazione'
    )
    and workflow_status in ('APPROVATA_ADMIN', 'RIFIUTATA_ADMIN')
  )
  or public.has_custom_page_access('dipendente_assenze')
);
