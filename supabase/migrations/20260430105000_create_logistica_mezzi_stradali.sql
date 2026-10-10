create table if not exists public.logistica_mezzi_stradali (
  id_uuid uuid primary key default gen_random_uuid(),
  numerazione integer,
  targa text,
  marca text,
  modello text,
  tipologia_mezzo text,
  assegnatario_attuale text,
  periodo_assegnatario_attuale date,
  noleggiatore text,
  scadenza_contratto date,
  scadenza_assicurazione date,
  scadenza_bolli date,
  scadenza_revisione date,
  scadenza_verifica_periodica_gru date,
  scadenza_revisione_biennale_cronotachigrafo date,
  multicard text,
  telepass text,
  kit_ruota_di_scorta text,
  deposito_gomme text,
  tipologia_gomme text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_mezzi_stradali_numerazione_idx
  on public.logistica_mezzi_stradali(numerazione);
create index if not exists logistica_mezzi_stradali_targa_idx
  on public.logistica_mezzi_stradali(targa);

create or replace function public.set_logistica_mezzi_stradali_audit_fields()
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

drop trigger if exists trg_logistica_mezzi_stradali_audit_fields on public.logistica_mezzi_stradali;
create trigger trg_logistica_mezzi_stradali_audit_fields
before insert or update on public.logistica_mezzi_stradali
for each row execute function public.set_logistica_mezzi_stradali_audit_fields();

alter table public.logistica_mezzi_stradali enable row level security;

drop policy if exists logistica_mezzi_stradali_select_role_allowed on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_select_role_allowed
on public.logistica_mezzi_stradali
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
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_stradali_insert_role_allowed on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_insert_role_allowed
on public.logistica_mezzi_stradali
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
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_stradali_update_role_allowed on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_update_role_allowed
on public.logistica_mezzi_stradali
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
        'logistica',
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
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
        'logistica',
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_stradali_delete_role_allowed on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_delete_role_allowed
on public.logistica_mezzi_stradali
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
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica')
);
