-- Archivio attestati per dipendente (RFI e D.Lgs. 81/08): file, data caricamento, scadenza.

create extension if not exists pgcrypto;

create table if not exists public.uqsa_attestati (
  id uuid primary key default gen_random_uuid(),
  personale_id uuid not null references public.personale (id_uuid) on delete cascade,
  tipo text not null check (tipo in ('rfi', 'l81')),
  titolo text not null,
  file_path text not null,
  file_name text not null,
  mime_type text,
  file_size integer,
  data_scadenza date,
  uploaded_at timestamptz not null default timezone('utc', now()),
  uploaded_by_user_id integer references public.users (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uqsa_attestati_titolo_nonempty check (length(trim(titolo)) > 0),
  constraint uqsa_attestati_file_name_nonempty check (length(trim(file_name)) > 0)
);

create index if not exists uqsa_attestati_personale_idx
  on public.uqsa_attestati (personale_id, tipo);

create index if not exists uqsa_attestati_scadenza_idx
  on public.uqsa_attestati (data_scadenza);

comment on table public.uqsa_attestati is
  'File attestati formazione per dipendente: RFI e D.Lgs. 81/08.';

create or replace function public.set_uqsa_attestati_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_uqsa_attestati_updated_at on public.uqsa_attestati;
create trigger trg_uqsa_attestati_updated_at
before update on public.uqsa_attestati
for each row
execute function public.set_uqsa_attestati_updated_at();

create or replace function public.is_uqsa_attestati_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_formazione',
    'admin_pernottamenti',
    'admin_dpi',
    'admin_trenoaereo',
    'dt',
    'assistente_dt',
    'uqsa'
  )
  or public.has_custom_page_access('attestati_dipendenti')
  or public.has_custom_page_access('uqsa');
$$;

grant execute on function public.is_uqsa_attestati_admin() to authenticated;

create or replace function public.can_write_uqsa_attestati()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale',
    'admin_formazione',
    'admin_pernottamenti',
    'uqsa'
  )
  or public.has_custom_page_access('attestati_dipendenti');
$$;

grant execute on function public.can_write_uqsa_attestati() to authenticated;

create or replace function public.uqsa_attestati_is_own(p_personale_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.personale p
    left join public.users me on me.auth_id = auth.uid()
    where p.id_uuid = p_personale_id
      and (
        p.user_id::text = auth.uid()::text
        or (me.id is not null and p.user_id::text = me.id::text)
        or (me.id_uuid is not null and p.user_id::text = me.id_uuid::text)
      )
  );
$$;

grant execute on function public.uqsa_attestati_is_own(uuid) to authenticated;

grant select, insert, update, delete on public.uqsa_attestati to authenticated;

alter table public.uqsa_attestati enable row level security;

drop policy if exists uqsa_attestati_select on public.uqsa_attestati;
create policy uqsa_attestati_select
  on public.uqsa_attestati
  for select
  to authenticated
  using (
    public.is_uqsa_attestati_admin()
    or public.uqsa_attestati_is_own(personale_id)
  );

drop policy if exists uqsa_attestati_insert on public.uqsa_attestati;
create policy uqsa_attestati_insert
  on public.uqsa_attestati
  for insert
  to authenticated
  with check (public.can_write_uqsa_attestati());

drop policy if exists uqsa_attestati_update on public.uqsa_attestati;
create policy uqsa_attestati_update
  on public.uqsa_attestati
  for update
  to authenticated
  using (public.can_write_uqsa_attestati())
  with check (public.can_write_uqsa_attestati());

drop policy if exists uqsa_attestati_delete on public.uqsa_attestati;
create policy uqsa_attestati_delete
  on public.uqsa_attestati
  for delete
  to authenticated
  using (public.can_write_uqsa_attestati());

insert into storage.buckets (id, name, public, file_size_limit)
values ('uqsa_attestati', 'uqsa_attestati', false, 20971520)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists uqsa_attestati_storage_select on storage.objects;
create policy uqsa_attestati_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'uqsa_attestati'
    and (
      public.is_uqsa_attestati_admin()
      or exists (
        select 1
        from public.uqsa_attestati a
        where a.file_path = name
          and public.uqsa_attestati_is_own(a.personale_id)
      )
    )
  );

drop policy if exists uqsa_attestati_storage_insert on storage.objects;
create policy uqsa_attestati_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'uqsa_attestati'
    and public.can_write_uqsa_attestati()
  );

drop policy if exists uqsa_attestati_storage_update on storage.objects;
create policy uqsa_attestati_storage_update
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'uqsa_attestati' and public.can_write_uqsa_attestati())
  with check (bucket_id = 'uqsa_attestati' and public.can_write_uqsa_attestati());

drop policy if exists uqsa_attestati_storage_delete on storage.objects;
create policy uqsa_attestati_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'uqsa_attestati' and public.can_write_uqsa_attestati());

insert into public.app_page_registry (page_key, label, active)
values
  (
    'attestati_dipendenti',
    'UQSA — Attestati (RFI e D.Lgs. 81/08)',
    true
  )
on conflict (page_key) do update
set label = excluded.label,
    active = true;
