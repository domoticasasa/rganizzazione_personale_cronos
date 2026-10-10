-- Workflow richieste ferie/permessi: Dipendente -> DT -> Admin.

alter table if exists public.dipendente_assenze
  add column if not exists requester_user_uuid uuid references public.users (id_uuid) on delete set null,
  add column if not exists assigned_dt_user_uuid uuid references public.users (id_uuid) on delete set null,
  add column if not exists workflow_status text not null default 'INVIATA_AL_DT',
  add column if not exists dt_decision_at timestamptz,
  add column if not exists dt_decision_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  add column if not exists dt_comment text,
  add column if not exists admin_decision_at timestamptz,
  add column if not exists admin_decision_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  add column if not exists admin_comment text;

update public.dipendente_assenze
set workflow_status = 'APPROVATA_ADMIN'
where coalesce(trim(workflow_status), '') = '';

alter table if exists public.dipendente_assenze
  drop constraint if exists dipendente_assenze_workflow_status_check;

alter table if exists public.dipendente_assenze
  add constraint dipendente_assenze_workflow_status_check
  check (
    workflow_status in (
      'INVIATA_AL_DT',
      'APPROVATA_DT',
      'RIFIUTATA_DT',
      'APPROVATA_ADMIN',
      'RIFIUTATA_ADMIN'
    )
  );

create index if not exists dipendente_assenze_assigned_dt_idx
  on public.dipendente_assenze (assigned_dt_user_uuid);

create index if not exists dipendente_assenze_requester_idx
  on public.dipendente_assenze (requester_user_uuid);

create index if not exists dipendente_assenze_workflow_idx
  on public.dipendente_assenze (workflow_status);

create or replace function public.current_user_role_norm()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(replace(coalesce(u.role, ''), ' ', '_'))
  from public.users u
  where u.auth_id = auth.uid()
  limit 1
$$;

create or replace function public.current_user_uuid()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.id_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1
$$;

create or replace function public.set_dipendente_assenze_workflow_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uuid uuid;
begin
  v_user_uuid := public.current_user_uuid();
  if tg_op = 'INSERT' then
    if new.requester_user_uuid is null then
      new.requester_user_uuid := v_user_uuid;
    end if;
    if coalesce(trim(new.workflow_status), '') = '' then
      new.workflow_status := 'INVIATA_AL_DT';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_dipendente_assenze_workflow_defaults on public.dipendente_assenze;
create trigger trg_dipendente_assenze_workflow_defaults
before insert on public.dipendente_assenze
for each row execute function public.set_dipendente_assenze_workflow_defaults();

create or replace function public.guard_dipendente_assenze_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_user_uuid uuid;
begin
  v_role := public.current_user_role_norm();
  v_user_uuid := public.current_user_uuid();

  if v_role in ('dt', 'assistente_dt') then
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

  if v_role in ('admin', 'admin_generale', 'admin_pernottamenti', 'admin_trenoaereo', 'admin_dpi', 'admin_formazione') then
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

drop trigger if exists trg_dipendente_assenze_guard_updates on public.dipendente_assenze;
create trigger trg_dipendente_assenze_guard_updates
before update on public.dipendente_assenze
for each row execute function public.guard_dipendente_assenze_updates();

drop policy if exists dipendente_assenze_select on public.dipendente_assenze;
create policy dipendente_assenze_select
on public.dipendente_assenze
for select
to authenticated
using (
  requester_user_uuid = public.current_user_uuid()
  or (
    public.current_user_role_norm() in (
      'dt',
      'assistente_dt',
      'admin',
      'admin_generale',
      'admin_pernottamenti',
      'admin_trenoaereo',
      'admin_dpi',
      'admin_formazione'
    )
  )
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_insert on public.dipendente_assenze;
create policy dipendente_assenze_insert
on public.dipendente_assenze
for insert
to authenticated
with check (
  requester_user_uuid = public.current_user_uuid()
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
    public.current_user_role_norm() in ('dt', 'assistente_dt')
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
    public.current_user_role_norm() in ('dt', 'assistente_dt')
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

drop policy if exists dipendente_assenze_delete on public.dipendente_assenze;
create policy dipendente_assenze_delete
on public.dipendente_assenze
for delete
to authenticated
using (
  (
    requester_user_uuid = public.current_user_uuid()
    and workflow_status in ('RIFIUTATA_DT', 'RIFIUTATA_ADMIN')
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
