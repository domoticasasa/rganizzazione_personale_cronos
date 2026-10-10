-- Gestione Telepass (lista dedicata, sincronizzata con Mezzi Stradali).

create table if not exists public.logistica_telepass (
  id_uuid uuid primary key default gen_random_uuid(),
  telepass text not null,
  mezzo_targa text,
  assegnatario_attuale text,
  assegnatario_user_uuid uuid references public.users(id_uuid) on delete set null,
  periodo_assegnatario_attuale date,
  data_fine_assegnatario_attuale date,
  note text,
  field_timestamps jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_telepass_mezzo_targa_idx
  on public.logistica_telepass (mezzo_targa);
create index if not exists logistica_telepass_telepass_lower_idx
  on public.logistica_telepass (lower(trim(telepass)));

comment on table public.logistica_telepass is
  'Dispositivi Telepass; sincronizzati con logistica_mezzi_stradali.telepass e assegnatario.';

create or replace function public.logistica_normalize_telepass_key(p_raw text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(coalesce(p_raw, ''))), '');
$$;

create or replace function public.set_logistica_telepass_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid := coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid := coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_logistica_telepass_audit_fields on public.logistica_telepass;
create trigger trg_logistica_telepass_audit_fields
before insert or update on public.logistica_telepass
for each row execute function public.set_logistica_telepass_audit_fields();

drop trigger if exists trg_logistica_telepass_field_timestamps on public.logistica_telepass;
create trigger trg_logistica_telepass_field_timestamps
before insert or update on public.logistica_telepass
for each row execute function public.set_field_timestamps();

alter table public.logistica_telepass enable row level security;

drop policy if exists logistica_telepass_select_role_allowed on public.logistica_telepass;
create policy logistica_telepass_select_role_allowed
on public.logistica_telepass for select to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_telepass')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_telepass_insert_role_allowed on public.logistica_telepass;
create policy logistica_telepass_insert_role_allowed
on public.logistica_telepass for insert to authenticated
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_telepass')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_telepass_update_role_allowed on public.logistica_telepass;
create policy logistica_telepass_update_role_allowed
on public.logistica_telepass for update to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_telepass')
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_telepass')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_telepass_delete_role_allowed on public.logistica_telepass;
create policy logistica_telepass_delete_role_allowed
on public.logistica_telepass for delete to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_telepass')
  or public.has_custom_page_access('logistica')
);

-- Sync assegnatario/targa da Mezzi Stradali → Gestione Telepass.
create or replace function public.trg_logistica_mezzi_sync_telepass_assignee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_targa text := nullif(trim(coalesce(new.targa, '')), '');
  v_key text;
begin
  if v_targa is null then
    return new;
  end if;

  if to_regclass('public.logistica_telepass') is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if coalesce(new.assegnatario_attuale, '') is not distinct from coalesce(old.assegnatario_attuale, '')
       and coalesce(new.assegnatario_user_uuid::text, '') is not distinct from coalesce(old.assegnatario_user_uuid::text, '')
       and new.periodo_assegnatario_attuale is not distinct from old.periodo_assegnatario_attuale
       and new.data_fine_assegnatario_attuale is not distinct from old.data_fine_assegnatario_attuale
       and coalesce(new.telepass, '') is not distinct from coalesce(old.telepass, '') then
      return new;
    end if;
  end if;

  update public.logistica_telepass t
  set
    assegnatario_attuale = new.assegnatario_attuale,
    assegnatario_user_uuid = new.assegnatario_user_uuid,
    periodo_assegnatario_attuale = new.periodo_assegnatario_attuale,
    data_fine_assegnatario_attuale = new.data_fine_assegnatario_attuale,
    mezzo_targa = new.targa,
    updated_at = now()
  where lower(trim(coalesce(t.mezzo_targa, ''))) = lower(v_targa);

  v_key := public.logistica_normalize_telepass_key(new.telepass);
  if v_key is not null and not public.logistica_telepass_is_empty(new.telepass) then
    update public.logistica_telepass t
    set
      assegnatario_attuale = new.assegnatario_attuale,
      assegnatario_user_uuid = new.assegnatario_user_uuid,
      periodo_assegnatario_attuale = new.periodo_assegnatario_attuale,
      data_fine_assegnatario_attuale = new.data_fine_assegnatario_attuale,
      mezzo_targa = new.targa,
      telepass = trim(new.telepass),
      updated_at = now()
    where public.logistica_normalize_telepass_key(t.telepass) = v_key;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_sync_telepass_assignee
  on public.logistica_mezzi_stradali;

create trigger trg_logistica_mezzi_sync_telepass_assignee
after insert or update of
  targa,
  telepass,
  assegnatario_attuale,
  assegnatario_user_uuid,
  periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale
on public.logistica_mezzi_stradali
for each row
execute function public.trg_logistica_mezzi_sync_telepass_assignee();

create or replace function public.trg_logistica_telepass_storico_register()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mezzo_id uuid;
begin
  if public.logistica_telepass_is_empty(new.telepass) then
    return new;
  end if;

  select m.id_uuid into v_mezzo_id
  from public.logistica_mezzi_stradali m
  where lower(trim(coalesce(m.targa, ''))) = lower(trim(coalesce(new.mezzo_targa, '')))
  limit 1;

  perform public.ensure_logistica_asset_assegnatari_storico(
    'telepass',
    trim(new.telepass),
    new.mezzo_targa,
    v_mezzo_id,
    null
  );

  return new;
end;
$$;

drop trigger if exists trg_logistica_telepass_storico_register on public.logistica_telepass;
create trigger trg_logistica_telepass_storico_register
after insert or update of telepass, mezzo_targa
on public.logistica_telepass
for each row
execute function public.trg_logistica_telepass_storico_register();

-- Seed da mezzi stradali esistenti.
insert into public.logistica_telepass (
  telepass,
  mezzo_targa,
  assegnatario_attuale,
  assegnatario_user_uuid,
  periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale
)
select
  trim(m.telepass),
  trim(m.targa),
  nullif(trim(m.assegnatario_attuale), ''),
  m.assegnatario_user_uuid,
  m.periodo_assegnatario_attuale,
  m.data_fine_assegnatario_attuale
from public.logistica_mezzi_stradali m
where not public.logistica_telepass_is_empty(m.telepass)
  and nullif(trim(m.targa), '') is not null
  and not exists (
    select 1
    from public.logistica_telepass t
    where public.logistica_normalize_telepass_key(t.telepass)
        = public.logistica_normalize_telepass_key(m.telepass)
  );

-- Allinea assegnatari esistenti (per chiave telepass o targa).
with mezzo_tp as (
  select
    m.targa,
    trim(m.telepass) as telepass,
    m.assegnatario_attuale,
    m.assegnatario_user_uuid,
    m.periodo_assegnatario_attuale,
    m.data_fine_assegnatario_attuale,
    public.logistica_normalize_telepass_key(m.telepass) as tp_key
  from public.logistica_mezzi_stradali m
  where not public.logistica_telepass_is_empty(m.telepass)
    and nullif(trim(m.targa), '') is not null
)
update public.logistica_telepass t
set
  assegnatario_attuale = b.assegnatario_attuale,
  assegnatario_user_uuid = b.assegnatario_user_uuid,
  periodo_assegnatario_attuale = b.periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale = b.data_fine_assegnatario_attuale,
  mezzo_targa = b.targa,
  updated_at = now()
from mezzo_tp b
where public.logistica_normalize_telepass_key(t.telepass) = b.tp_key
   or lower(trim(coalesce(t.mezzo_targa, ''))) = lower(trim(b.targa));
