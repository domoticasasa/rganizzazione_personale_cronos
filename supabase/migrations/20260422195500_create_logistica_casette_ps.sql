create table if not exists public.logistica_casette_ps (
  id_uuid uuid primary key default gen_random_uuid(),
  codice_interno text,
  tipo_cassetta text,
  commessa_id uuid references public.commesse(id_uuid) on delete set null,
  scadenze text,
  ubicazione text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_casette_ps_commessa_idx
  on public.logistica_casette_ps(commessa_id);
create index if not exists logistica_casette_ps_active_idx
  on public.logistica_casette_ps(active);

create or replace function public.set_logistica_casette_ps_audit_fields()
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

drop trigger if exists trg_logistica_casette_ps_audit_fields on public.logistica_casette_ps;
create trigger trg_logistica_casette_ps_audit_fields
before insert or update on public.logistica_casette_ps
for each row execute function public.set_logistica_casette_ps_audit_fields();

alter table public.logistica_casette_ps enable row level security;

drop policy if exists logistica_casette_ps_select_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_select_role_allowed
on public.logistica_casette_ps
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
        'admin_trenoaereo'
      )
  )
);

drop policy if exists logistica_casette_ps_insert_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_insert_role_allowed
on public.logistica_casette_ps
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
        'admin_trenoaereo'
      )
  )
);

drop policy if exists logistica_casette_ps_update_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_update_role_allowed
on public.logistica_casette_ps
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
        'admin_trenoaereo'
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
        'admin_trenoaereo'
      )
  )
);

drop policy if exists logistica_casette_ps_delete_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_delete_role_allowed
on public.logistica_casette_ps
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
        'admin_trenoaereo'
      )
  )
);
