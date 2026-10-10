-- Visite mediche RFI: stessa programmazione + PDF dalla struttura da trasmettere al dipendente.

create table if not exists public.visite_mediche_rfi (
  id_uuid uuid primary key default gen_random_uuid(),
  personale_id_uuid uuid not null references public.personale (id_uuid) on delete cascade,
  dipendente_nome text,
  data_visita timestamptz not null,
  luogo_struttura text not null,
  link text,
  note text,
  pdf_file_path text,
  pdf_file_name text,
  pdf_mime_type text,
  pdf_file_size integer,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null
);

create index if not exists visite_mediche_rfi_personale_idx
  on public.visite_mediche_rfi (personale_id_uuid);

create index if not exists visite_mediche_rfi_data_visita_idx
  on public.visite_mediche_rfi (data_visita);

comment on table public.visite_mediche_rfi is
  'Programmazione visite mediche RFI con PDF assegnato dalla struttura.';

drop trigger if exists trg_visite_mediche_rfi_audit_fields on public.visite_mediche_rfi;
create trigger trg_visite_mediche_rfi_audit_fields
before insert or update on public.visite_mediche_rfi
for each row execute function public.set_visite_mediche_audit_fields();

alter table public.visite_mediche_rfi enable row level security;

drop policy if exists visite_mediche_rfi_select on public.visite_mediche_rfi;
create policy visite_mediche_rfi_select
on public.visite_mediche_rfi
for select
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione',
        'admin_vista',
        'logistica'
      )
  )
  or public.visite_mediche_is_own_personale(personale_id_uuid)
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi')
);

drop policy if exists visite_mediche_rfi_insert on public.visite_mediche_rfi;
create policy visite_mediche_rfi_insert
on public.visite_mediche_rfi
for insert
to authenticated
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi')
);

drop policy if exists visite_mediche_rfi_update on public.visite_mediche_rfi;
create policy visite_mediche_rfi_update
on public.visite_mediche_rfi
for update
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi')
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi')
);

drop policy if exists visite_mediche_rfi_delete on public.visite_mediche_rfi;
create policy visite_mediche_rfi_delete
on public.visite_mediche_rfi
for delete
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi')
);

grant select, insert, update, delete on public.visite_mediche_rfi to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('visite_mediche_rfi', 'visite_mediche_rfi', false, 52428800)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

create or replace function public.is_visite_mediche_rfi_pdf_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione',
    'admin_vista',
    'logistica'
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi');
$$;

grant execute on function public.is_visite_mediche_rfi_pdf_reader() to authenticated;

create or replace function public.can_write_visite_mediche_rfi_pdf()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('visite_mediche')
  or public.has_custom_page_access('visite_mediche_rfi');
$$;

grant execute on function public.can_write_visite_mediche_rfi_pdf() to authenticated;

drop policy if exists visite_mediche_rfi_storage_select on storage.objects;
create policy visite_mediche_rfi_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'visite_mediche_rfi'
    and (
      public.is_visite_mediche_rfi_pdf_reader()
      or exists (
        select 1
        from public.visite_mediche_rfi v
        where v.pdf_file_path = name
          and public.visite_mediche_is_own_personale(v.personale_id_uuid)
      )
    )
  );

drop policy if exists visite_mediche_rfi_storage_insert on storage.objects;
create policy visite_mediche_rfi_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'visite_mediche_rfi'
    and public.can_write_visite_mediche_rfi_pdf()
  );

drop policy if exists visite_mediche_rfi_storage_update on storage.objects;
create policy visite_mediche_rfi_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'visite_mediche_rfi'
    and public.can_write_visite_mediche_rfi_pdf()
  )
  with check (
    bucket_id = 'visite_mediche_rfi'
    and public.can_write_visite_mediche_rfi_pdf()
  );

drop policy if exists visite_mediche_rfi_storage_delete on storage.objects;
create policy visite_mediche_rfi_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'visite_mediche_rfi'
    and public.can_write_visite_mediche_rfi_pdf()
  );

-- Pulisce lo storage quando la riga visita RFI viene cancellata.
create or replace function public.purge_visite_mediche_rfi_pdf_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if coalesce(nullif(trim(old.pdf_file_path), ''), '') <> '' then
    delete from storage.objects
    where bucket_id = 'visite_mediche_rfi'
      and name = old.pdf_file_path;
  end if;
  return old;
end;
$$;

drop trigger if exists trg_purge_visite_mediche_rfi_pdf
  on public.visite_mediche_rfi;
create trigger trg_purge_visite_mediche_rfi_pdf
before delete on public.visite_mediche_rfi
for each row
execute function public.purge_visite_mediche_rfi_pdf_on_delete();

insert into public.app_page_registry (page_key, label, active)
values (
  'visite_mediche_rfi',
  'Visite mediche RFI',
  true
)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
