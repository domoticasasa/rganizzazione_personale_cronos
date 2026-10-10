create table if not exists public.logistica_mdo_ferroviari (
  id_uuid uuid primary key default gen_random_uuid(),
  matricola_interna text,
  codice_identificativo_targa_rfi text,
  descrizione_mezzo text,
  descrizione_rumo text,
  modello text,
  equipment text,
  matricola_costruttore text,
  anno_immatricolazione text,
  anno_acquisto text,
  costo_storico numeric,
  acquistato_da text,
  stato_acquisto text,
  proprietario text,
  costo_giornaliero_2023 numeric,
  costo_giornaliero_2024 numeric,
  cantiere_attuale text,
  commessa text,
  stato text,
  cantiere_precedente text,
  commessa_precedente text,
  periodo text,
  note_disponibilita text,
  note_generali text,
  fca_check boolean not null default false,
  fca_checked_at timestamptz,
  fca_checked_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_mdo_ferroviari_matricola_idx
  on public.logistica_mdo_ferroviari(matricola_interna);
create index if not exists logistica_mdo_ferroviari_fca_check_idx
  on public.logistica_mdo_ferroviari(fca_check);

create or replace function public.set_logistica_mdo_ferroviari_audit_fields()
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

drop trigger if exists trg_logistica_mdo_ferroviari_audit_fields on public.logistica_mdo_ferroviari;
create trigger trg_logistica_mdo_ferroviari_audit_fields
before insert or update on public.logistica_mdo_ferroviari
for each row execute function public.set_logistica_mdo_ferroviari_audit_fields();

alter table public.logistica_mdo_ferroviari enable row level security;

drop policy if exists logistica_mdo_ferroviari_select_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_select_role_allowed
on public.logistica_mdo_ferroviari
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

drop policy if exists logistica_mdo_ferroviari_insert_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_insert_role_allowed
on public.logistica_mdo_ferroviari
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

drop policy if exists logistica_mdo_ferroviari_update_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_update_role_allowed
on public.logistica_mdo_ferroviari
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

drop policy if exists logistica_mdo_ferroviari_delete_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_delete_role_allowed
on public.logistica_mdo_ferroviari
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
