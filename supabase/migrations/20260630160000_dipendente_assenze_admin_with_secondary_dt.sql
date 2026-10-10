-- Admin con ruolo secondario DT: in fase admin (APPROVATA_DT) deve agire come admin,
-- non essere bloccato dal ramo DT del trigger.

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

  -- Decisione admin: solo ruolo primario admin, su richieste già approvate dal DT.
  if public.current_user_role_norm() in (
    'admin', 'admin_generale', 'admin_pernottamenti',
    'admin_trenoaereo', 'admin_dpi', 'admin_formazione'
  ) and old.workflow_status = 'APPROVATA_DT' then
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

  -- Decisione DT: primario o secondario DT, su richieste in attesa DT.
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

  return new;
end;
$$;
