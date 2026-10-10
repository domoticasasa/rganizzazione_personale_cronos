-- Trasferimenti MDO ferroviari (in corso / completati / annullati)

create table if not exists public.logistica_mdo_trasferimenti (
  id_uuid uuid primary key default gen_random_uuid(),
  mdo_id uuid not null references public.logistica_mdo_ferroviari (id_uuid) on delete cascade,
  mdo_label text not null default '',
  matricola_interna text not null default '',
  targa_rfi text not null default '',
  commessa_origine text not null default '',
  cantiere_origine text not null default '',
  commessa_destinazione text not null,
  cantiere_destinazione text,
  aggiorna_cantiere boolean not null default true,
  -- 'giorno' | 'settimana'
  periodo_tipo text not null default 'giorno'
    check (periodo_tipo in ('giorno', 'settimana')),
  data_inizio date not null,
  data_fine date not null,
  -- 'in_corso' | 'completato' | 'annullato'
  stato text not null default 'in_corso'
    check (stato in ('in_corso', 'completato', 'annullato')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  completed_at timestamptz,
  cancelled_at timestamptz,
  constraint logistica_mdo_trasferimenti_date_range check (data_fine >= data_inizio)
);

create index if not exists logistica_mdo_trasferimenti_stato_idx
  on public.logistica_mdo_trasferimenti (stato);
create index if not exists logistica_mdo_trasferimenti_mdo_idx
  on public.logistica_mdo_trasferimenti (mdo_id);
create index if not exists logistica_mdo_trasferimenti_date_idx
  on public.logistica_mdo_trasferimenti (data_inizio, data_fine);

-- Al massimo un trasferimento in corso per mezzo.
create unique index if not exists logistica_mdo_trasferimenti_one_in_corso_per_mdo
  on public.logistica_mdo_trasferimenti (mdo_id)
  where stato = 'in_corso';

create or replace function public.set_logistica_mdo_trasferimenti_audit_fields()
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

drop trigger if exists trg_logistica_mdo_trasferimenti_audit_fields
  on public.logistica_mdo_trasferimenti;
create trigger trg_logistica_mdo_trasferimenti_audit_fields
before insert or update on public.logistica_mdo_trasferimenti
for each row execute function public.set_logistica_mdo_trasferimenti_audit_fields();

alter table public.logistica_mdo_trasferimenti enable row level security;

drop policy if exists logistica_mdo_trasferimenti_select_role_allowed
  on public.logistica_mdo_trasferimenti;
create policy logistica_mdo_trasferimenti_select_role_allowed
on public.logistica_mdo_trasferimenti
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
        'logistica',
        'admin_vista'
      )
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('dislocazione')
);

drop policy if exists logistica_mdo_trasferimenti_insert_role_allowed
  on public.logistica_mdo_trasferimenti;
create policy logistica_mdo_trasferimenti_insert_role_allowed
on public.logistica_mdo_trasferimenti
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('dislocazione')
);

drop policy if exists logistica_mdo_trasferimenti_update_role_allowed
  on public.logistica_mdo_trasferimenti;
create policy logistica_mdo_trasferimenti_update_role_allowed
on public.logistica_mdo_trasferimenti
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('dislocazione')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('dislocazione')
);

drop policy if exists logistica_mdo_trasferimenti_delete_role_allowed
  on public.logistica_mdo_trasferimenti;
create policy logistica_mdo_trasferimenti_delete_role_allowed
on public.logistica_mdo_trasferimenti
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('dislocazione')
);

grant select, insert, update, delete
  on public.logistica_mdo_trasferimenti to authenticated;

drop trigger if exists trg_app_activity_log on public.logistica_mdo_trasferimenti;
create trigger trg_app_activity_log
after insert or update or delete on public.logistica_mdo_trasferimenti
for each row execute function public.trg_log_app_activity();
