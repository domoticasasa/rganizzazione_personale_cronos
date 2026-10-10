-- Anagrafica strutture per programmazione corsi D.Lgs. 81/08.

create table if not exists public.formazione_dlgs_strutture (
  id_uuid uuid primary key default gen_random_uuid(),
  nome text not null,
  indirizzo text not null default '',
  maps_link text not null default '',
  email_outlook text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists formazione_dlgs_strutture_nome_unique
  on public.formazione_dlgs_strutture (lower(trim(nome)));

create index if not exists formazione_dlgs_strutture_active_idx
  on public.formazione_dlgs_strutture (active)
  where active = true;

comment on table public.formazione_dlgs_strutture is
  'Sedi formazione D.Lgs. 81/08 selezionabili in programmazione corso.';

grant select, insert, update, delete on public.formazione_dlgs_strutture to authenticated;

alter table public.formazione_dlgs_strutture enable row level security;

drop policy if exists formazione_dlgs_strutture_select on public.formazione_dlgs_strutture;
create policy formazione_dlgs_strutture_select
on public.formazione_dlgs_strutture
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
  or public.has_custom_page_access('formazione_dlgs_81_08')
);

drop policy if exists formazione_dlgs_strutture_write on public.formazione_dlgs_strutture;
create policy formazione_dlgs_strutture_write
on public.formazione_dlgs_strutture
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
  or public.has_custom_page_access('formazione_dlgs_81_08')
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
  or public.has_custom_page_access('formazione_dlgs_81_08')
);

alter table public.formazione_corsi
  add column if not exists struttura_dlgs_id uuid
    references public.formazione_dlgs_strutture (id_uuid) on delete set null,
  add column if not exists struttura_nome text,
  add column if not exists struttura_indirizzo text,
  add column if not exists struttura_email text;

comment on column public.formazione_corsi.struttura_dlgs_id is
  'Riferimento anagrafica struttura D.Lgs. 81/08 (in presenza).';
comment on column public.formazione_corsi.struttura_nome is
  'Snapshot nome struttura al salvataggio programmazione.';
comment on column public.formazione_corsi.struttura_indirizzo is
  'Snapshot indirizzo struttura al salvataggio programmazione.';
comment on column public.formazione_corsi.struttura_email is
  'Snapshot email struttura (Outlook) al salvataggio programmazione.';
