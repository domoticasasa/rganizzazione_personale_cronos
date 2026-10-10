-- MDO Proprietà (mezzi e accessori) — struttura da MdO_Proprietà.xlsx
create table if not exists public.logistica_mdo_proprieta (
  id_uuid uuid primary key default gen_random_uuid(),
  codifica_gruppo text not null,
  codifica text,
  is_mezzo_principale boolean not null default false,
  ordine int not null default 1,
  tipologia text,
  matricola text,
  definizione_classe_mezzo text,
  numero_serie text,
  dichiarazione_conformita_ce text,
  scadenza_verifica_periodica date,
  ubicazione text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_mdo_proprieta_gruppo_idx
  on public.logistica_mdo_proprieta(codifica_gruppo, ordine);
create index if not exists logistica_mdo_proprieta_matricola_idx
  on public.logistica_mdo_proprieta(matricola);

create or replace function public.set_logistica_mdo_proprieta_audit_fields()
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

drop trigger if exists trg_logistica_mdo_proprieta_audit_fields on public.logistica_mdo_proprieta;
create trigger trg_logistica_mdo_proprieta_audit_fields
before insert or update on public.logistica_mdo_proprieta
for each row execute function public.set_logistica_mdo_proprieta_audit_fields();

alter table public.logistica_mdo_proprieta enable row level security;

drop policy if exists logistica_mdo_proprieta_select_role_allowed on public.logistica_mdo_proprieta;
create policy logistica_mdo_proprieta_select_role_allowed
on public.logistica_mdo_proprieta
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
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('logistica_mdo_proprieta')
);

drop policy if exists logistica_mdo_proprieta_insert_role_allowed on public.logistica_mdo_proprieta;
create policy logistica_mdo_proprieta_insert_role_allowed
on public.logistica_mdo_proprieta
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
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('logistica_mdo_proprieta')
);

drop policy if exists logistica_mdo_proprieta_update_role_allowed on public.logistica_mdo_proprieta;
create policy logistica_mdo_proprieta_update_role_allowed
on public.logistica_mdo_proprieta
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
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('logistica_mdo_proprieta')
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
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('logistica_mdo_proprieta')
);

drop policy if exists logistica_mdo_proprieta_delete_role_allowed on public.logistica_mdo_proprieta;
create policy logistica_mdo_proprieta_delete_role_allowed
on public.logistica_mdo_proprieta
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
  or public.has_custom_page_access('logistica')
  or public.has_custom_page_access('logistica_mdo_proprieta')
);

insert into public.app_page_registry (page_key, label, active)
values
  ('logistica_mdo_proprieta', 'Logistica - MDO Proprietà', true),
  ('mdo_proprieta', 'MDO Proprietà', true)
on conflict (page_key) do update
set label = excluded.label,
    active = excluded.active;

-- Seed da MdO_Proprietà.xlsx (Foglio MDO)
insert into public.logistica_mdo_proprieta (
  codifica_gruppo,
  codifica,
  is_mezzo_principale,
  ordine,
  tipologia,
  matricola,
  definizione_classe_mezzo,
  numero_serie,
  dichiarazione_conformita_ce,
  scadenza_verifica_periodica,
  ubicazione
)
values
  ('MdO1', 'MdO1', true, 1, 'ESCAVATORE VOLVO EC15D - 15Q.LI', 'VCE0C15DE00001525', 'ESCAVATORE VOLVO 15Q.LI', NULL, NULL, NULL, 'SEDE'),
  ('MdO1', NULL, false, 2, 'BENNA 400MM', '00327374', 'SC 36 L400', 'COD. 00105119001-11', NULL, NULL, NULL),
  ('MdO1', NULL, false, 3, 'BENNA DA 200MM', '00388546', 'SC 35 L250', NULL, NULL, NULL, NULL),
  ('MdO1', NULL, false, 4, 'MARTELLO ATCS0055', 'S85501202756', 'S85', NULL, 'N. 5496 DEL 03/02/2020', NULL, NULL),
  ('MdO2', 'MdO2', true, 1, 'CARRELLO ELEVATORE LINDE E35/600H', 'H2X388E00329', 'CARRELLO ELEVATORE', NULL, NULL, '2023-04-21', 'SEDE'),
  ('MdO3', 'MdO3', true, 1, 'BOBCAT CASE 430', 'JAF00430N8M479565', 'BOBCAT - PALA CARICATRICE', NULL, 'N. N8M479565 DEL 11/03/2008', NULL, 'TORRE ANNUNZIATA'),
  ('MdO4', 'MdO4', true, 1, 'ESCAVATORE CASE CX50B - 50Q.LI', 'N8GN10027', 'ESCAVATORE CASE 50 Q.LI', NULL, 'N. N8GN10027 DEL 28/11/2008', NULL, 'MILANO CENTRALE'),
  ('MdO4', NULL, false, 2, 'MARTELLONE', NULL, NULL, NULL, NULL, NULL, NULL),
  ('MdO4', NULL, false, 3, 'BENNA DA 800MM', 'CX50B/54', 'Benna da 800mm S/N CX50B/54', NULL, NULL, NULL, NULL),
  ('MdO4', NULL, false, 4, 'BENNA DA 1400MM', 'CX51B/54', 'Benna da 1400mm S/N CX51B/54', NULL, NULL, NULL, NULL),
  ('MdO4', NULL, false, 5, 'BENNA DA 500MM', 'CX 17B/50', 'Benna da 500mm S/N CX 17B/50 da 500mm', NULL, NULL, NULL, NULL),
  ('MdO4', NULL, false, 6, 'BENNA DA 300MM', 'S/N 01.04,00,30', 'Benna da 300mm S/N 01.04,00,30', NULL, NULL, NULL, NULL),
  ('MdO5', 'MdO5', true, 1, 'ESCAVATORE KOMATSU PC16R-3HS - 16 Q.LI', 'F73053', 'ESCAVATORE KOMATSU 16 Q.LI', 'PC16R-3HS', NULL, NULL, 'TORRE ANNUNZIATA'),
  ('MdO5', NULL, false, 2, 'BENNA DA 200MM', 'TARGHETTA ASSENTE', 'BENNA 20CM - COD. 000505900111', '00299934', NULL, NULL, NULL),
  ('MdO5', NULL, false, 3, 'BENNA DA 600MM', 'TARGHETTA ASSENTE', 'BENNA 60CM', '00209538', NULL, NULL, NULL),
  ('MdO5', NULL, false, 4, 'BENNA DA 800MM', 'TARGHETTA ASSENTE', 'BENNA 80CM', '00294264', NULL, NULL, NULL),
  ('MdO5', NULL, false, 5, 'MARTELLO', 'TARGHETTA ASSENTE', 'MARTELLO ATCS0009', 'BES074039', NULL, NULL, NULL);
