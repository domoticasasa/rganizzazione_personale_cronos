create table if not exists public.logistica_attrezzature (
  id_uuid uuid primary key default gen_random_uuid(),
  codice_cronos text,
  assegnatario text,
  famiglia_attrezzi text,
  marca text,
  descrizione_articolo text,
  serial_number text,
  modello text,
  oda text,
  data_oda text,
  posizione text,
  ddt text,
  stato_valore text,
  note text,
  commessa_id uuid references public.commesse(id_uuid) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_attrezzature_commessa_idx
  on public.logistica_attrezzature(commessa_id);
create index if not exists logistica_attrezzature_codice_idx
  on public.logistica_attrezzature(codice_cronos);
create index if not exists logistica_attrezzature_serial_idx
  on public.logistica_attrezzature(serial_number);

create or replace function public.set_logistica_attrezzature_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid
    into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_logistica_attrezzature_audit_fields on public.logistica_attrezzature;
create trigger trg_logistica_attrezzature_audit_fields
before insert or update on public.logistica_attrezzature
for each row execute function public.set_logistica_attrezzature_audit_fields();

alter table public.logistica_attrezzature enable row level security;

drop policy if exists logistica_attrezzature_select_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_select_role_allowed
on public.logistica_attrezzature
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_insert_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_insert_role_allowed
on public.logistica_attrezzature
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_update_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_update_role_allowed
on public.logistica_attrezzature
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_delete_role_allowed on public.logistica_attrezzature;
create policy logistica_attrezzature_delete_role_allowed
on public.logistica_attrezzature
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);
