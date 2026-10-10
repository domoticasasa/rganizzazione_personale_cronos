-- Anagrafica strutture RFI / DOIT per programmazione corsi (nome, indirizzo, link Maps).

create table if not exists public.formazione_rfi_strutture (
  id_uuid uuid primary key default gen_random_uuid(),
  nome text not null,
  indirizzo text not null default '',
  maps_link text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists formazione_rfi_strutture_nome_unique
  on public.formazione_rfi_strutture (lower(trim(nome)));

create index if not exists formazione_rfi_strutture_active_idx
  on public.formazione_rfi_strutture (active)
  where active = true;

comment on table public.formazione_rfi_strutture is
  'Sedi DOIT / strutture RFI selezionabili in programmazione formazione.';

grant select, insert, update, delete on public.formazione_rfi_strutture to authenticated;

alter table public.formazione_rfi_strutture enable row level security;

drop policy if exists formazione_rfi_strutture_select on public.formazione_rfi_strutture;
create policy formazione_rfi_strutture_select
on public.formazione_rfi_strutture
for select
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_formazione',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'uqsa',
        'dt',
        'assistente_dt'
      )
  )
  or public.has_custom_page_access('formazione_rfi')
);

drop policy if exists formazione_rfi_strutture_write on public.formazione_rfi_strutture;
create policy formazione_rfi_strutture_write
on public.formazione_rfi_strutture
for all
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('formazione_rfi')
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('formazione_rfi')
);
