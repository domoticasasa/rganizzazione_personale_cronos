-- Storico assegnatari (4 passaggi) per mezzi stradali, multicard e telepass.

create table if not exists public.logistica_asset_assegnatari_storico (
  id_uuid uuid primary key default gen_random_uuid(),
  tipo_asset text not null
    check (tipo_asset in ('mezzo_stradale', 'multicard', 'telepass')),
  identificativo text not null,
  passaggio smallint not null check (passaggio between 1 and 4),
  assegnatario text,
  periodo_dal date,
  periodo_al date,
  note text,
  mezzo_targa text,
  mezzo_id_uuid uuid references public.logistica_mezzi_stradali(id_uuid) on delete set null,
  multicard_id_uuid uuid,
  field_timestamps jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  constraint logistica_asset_assegnatari_storico_unique
    unique (tipo_asset, identificativo, passaggio)
);

create index if not exists logistica_asset_assegnatari_storico_tipo_idx
  on public.logistica_asset_assegnatari_storico(tipo_asset);
create index if not exists logistica_asset_assegnatari_storico_ident_idx
  on public.logistica_asset_assegnatari_storico(identificativo);

do $$
begin
  if to_regclass('public.logistica_multicard') is not null then
    alter table public.logistica_asset_assegnatari_storico
      drop constraint if exists logistica_asset_assegnatari_storico_multicard_fk;
    alter table public.logistica_asset_assegnatari_storico
      add constraint logistica_asset_assegnatari_storico_multicard_fk
      foreign key (multicard_id_uuid) references public.logistica_multicard(id_uuid)
      on delete set null;
  end if;
end $$;

create or replace function public.set_logistica_asset_assegnatari_storico_audit_fields()
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
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_logistica_asset_assegnatari_storico_audit on public.logistica_asset_assegnatari_storico;
create trigger trg_logistica_asset_assegnatari_storico_audit
before insert or update on public.logistica_asset_assegnatari_storico
for each row execute function public.set_logistica_asset_assegnatari_storico_audit_fields();

drop trigger if exists trg_logistica_asset_assegnatari_storico_field_timestamps
  on public.logistica_asset_assegnatari_storico;
create trigger trg_logistica_asset_assegnatari_storico_field_timestamps
before insert or update on public.logistica_asset_assegnatari_storico
for each row execute function public.set_field_timestamps();

alter table public.logistica_asset_assegnatari_storico enable row level security;

drop policy if exists logistica_asset_assegnatari_storico_select on public.logistica_asset_assegnatari_storico;
create policy logistica_asset_assegnatari_storico_select
on public.logistica_asset_assegnatari_storico for select to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica',
        'dipendente', 'dipendenti', 'user'
      )
  )
  or public.has_custom_page_access('logistica_assegnatari_storico')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_asset_assegnatari_storico_write on public.logistica_asset_assegnatari_storico;
create policy logistica_asset_assegnatari_storico_write
on public.logistica_asset_assegnatari_storico for all to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('logistica_assegnatari_storico')
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
  or public.has_custom_page_access('logistica_assegnatari_storico')
  or public.has_custom_page_access('logistica')
);

insert into public.app_page_registry (page_key, label, active)
values ('logistica_assegnatari_storico', 'Logistica - Storico assegnatari', true)
on conflict (page_key) do update
set label = excluded.label, active = true;
