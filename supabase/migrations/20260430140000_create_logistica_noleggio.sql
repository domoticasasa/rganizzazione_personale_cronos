create table if not exists public.logistica_noleggio (
  id_uuid uuid primary key default gen_random_uuid(),
  commessa text,
  luogo_commessa text,
  fornitore text,
  descrizione text,
  qta_mdo text,
  accessori_1 text,
  qta_1 text,
  accessori_2 text,
  qta_2 text,
  numero_contratto text,
  oda text,
  nolo_dal text,
  nolo_al text,
  stato text,
  utilizzatore text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_noleggio_commessa_idx
  on public.logistica_noleggio(commessa);
create index if not exists logistica_noleggio_contratto_idx
  on public.logistica_noleggio(numero_contratto);
create index if not exists logistica_noleggio_stato_idx
  on public.logistica_noleggio(stato);

create or replace function public.set_logistica_noleggio_audit_fields()
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

drop trigger if exists trg_logistica_noleggio_audit_fields on public.logistica_noleggio;
create trigger trg_logistica_noleggio_audit_fields
before insert or update on public.logistica_noleggio
for each row execute function public.set_logistica_noleggio_audit_fields();

alter table public.logistica_noleggio enable row level security;

drop policy if exists logistica_noleggio_select_role_allowed on public.logistica_noleggio;
create policy logistica_noleggio_select_role_allowed
on public.logistica_noleggio
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
  or public.has_custom_page_access('logistica_noleggio')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_noleggio_insert_role_allowed on public.logistica_noleggio;
create policy logistica_noleggio_insert_role_allowed
on public.logistica_noleggio
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
  or public.has_custom_page_access('logistica_noleggio')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_noleggio_update_role_allowed on public.logistica_noleggio;
create policy logistica_noleggio_update_role_allowed
on public.logistica_noleggio
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
  or public.has_custom_page_access('logistica_noleggio')
  or public.has_custom_page_access('logistica')
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
  or public.has_custom_page_access('logistica_noleggio')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_noleggio_delete_role_allowed on public.logistica_noleggio;
create policy logistica_noleggio_delete_role_allowed
on public.logistica_noleggio
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
  or public.has_custom_page_access('logistica_noleggio')
  or public.has_custom_page_access('logistica')
);
