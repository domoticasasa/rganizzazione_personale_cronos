-- PDF assegnazione multicard con Assegnazione = MDO.
-- Quando mezzo_targa esce da MDO (o la carta viene cancellata), i PDF spariscono
-- dalla tabella e dallo storage in automatico.

create table if not exists public.logistica_multicard_mdo_assegnazioni (
  id uuid primary key default gen_random_uuid(),
  multicard_id uuid not null
    references public.logistica_multicard (id_uuid) on delete cascade,
  file_path text not null,
  file_name text not null,
  mime_type text,
  file_size integer,
  note text,
  uploaded_at timestamptz not null default timezone('utc', now()),
  uploaded_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint logistica_multicard_mdo_assegnazioni_file_name_nonempty
    check (length(trim(file_name)) > 0)
);

create index if not exists logistica_multicard_mdo_assegnazioni_card_idx
  on public.logistica_multicard_mdo_assegnazioni (multicard_id);

comment on table public.logistica_multicard_mdo_assegnazioni is
  'PDF assegnazione verso dipendente per multicard con assegnazione MDO. '
  'Si cancellano automaticamente se la carta non è più MDO.';

create or replace function public.set_logistica_multicard_mdo_assegnazioni_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_logistica_multicard_mdo_assegnazioni_updated_at
  on public.logistica_multicard_mdo_assegnazioni;
create trigger trg_logistica_multicard_mdo_assegnazioni_updated_at
before update on public.logistica_multicard_mdo_assegnazioni
for each row
execute function public.set_logistica_multicard_mdo_assegnazioni_updated_at();

create or replace function public.is_multicard_mdo_assegnazioni_reader()
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
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione',
    'dt',
    'assistente_dt',
    'logistica'
  )
  or public.has_custom_page_access('multicard_mdo_assegnazioni')
  or public.has_custom_page_access('logistica_multicard')
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica');
$$;

grant execute on function public.is_multicard_mdo_assegnazioni_reader()
  to authenticated;

create or replace function public.can_write_multicard_mdo_assegnazioni()
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
    'logistica'
  )
  or public.has_custom_page_access('multicard_mdo_assegnazioni')
  or public.has_custom_page_access('logistica_multicard')
  or public.has_custom_page_access('logistica');
$$;

grant execute on function public.can_write_multicard_mdo_assegnazioni()
  to authenticated;

grant select, insert, update, delete
  on public.logistica_multicard_mdo_assegnazioni
  to authenticated;

alter table public.logistica_multicard_mdo_assegnazioni
  enable row level security;

drop policy if exists logistica_multicard_mdo_assegnazioni_select
  on public.logistica_multicard_mdo_assegnazioni;
create policy logistica_multicard_mdo_assegnazioni_select
  on public.logistica_multicard_mdo_assegnazioni
  for select
  to authenticated
  using (public.is_multicard_mdo_assegnazioni_reader());

drop policy if exists logistica_multicard_mdo_assegnazioni_insert
  on public.logistica_multicard_mdo_assegnazioni;
create policy logistica_multicard_mdo_assegnazioni_insert
  on public.logistica_multicard_mdo_assegnazioni
  for insert
  to authenticated
  with check (public.can_write_multicard_mdo_assegnazioni());

drop policy if exists logistica_multicard_mdo_assegnazioni_update
  on public.logistica_multicard_mdo_assegnazioni;
create policy logistica_multicard_mdo_assegnazioni_update
  on public.logistica_multicard_mdo_assegnazioni
  for update
  to authenticated
  using (public.can_write_multicard_mdo_assegnazioni())
  with check (public.can_write_multicard_mdo_assegnazioni());

drop policy if exists logistica_multicard_mdo_assegnazioni_delete
  on public.logistica_multicard_mdo_assegnazioni;
create policy logistica_multicard_mdo_assegnazioni_delete
  on public.logistica_multicard_mdo_assegnazioni
  for delete
  to authenticated
  using (public.can_write_multicard_mdo_assegnazioni());

insert into storage.buckets (id, name, public, file_size_limit)
values (
  'logistica_multicard_mdo_assegnazioni',
  'logistica_multicard_mdo_assegnazioni',
  false,
  52428800
)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists logistica_multicard_mdo_assegnazioni_storage_select
  on storage.objects;
create policy logistica_multicard_mdo_assegnazioni_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and public.is_multicard_mdo_assegnazioni_reader()
  );

drop policy if exists logistica_multicard_mdo_assegnazioni_storage_insert
  on storage.objects;
create policy logistica_multicard_mdo_assegnazioni_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and public.can_write_multicard_mdo_assegnazioni()
  );

drop policy if exists logistica_multicard_mdo_assegnazioni_storage_update
  on storage.objects;
create policy logistica_multicard_mdo_assegnazioni_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and public.can_write_multicard_mdo_assegnazioni()
  )
  with check (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and public.can_write_multicard_mdo_assegnazioni()
  );

drop policy if exists logistica_multicard_mdo_assegnazioni_storage_delete
  on storage.objects;
create policy logistica_multicard_mdo_assegnazioni_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'logistica_multicard_mdo_assegnazioni'
    and public.can_write_multicard_mdo_assegnazioni()
  );

-- Cleanup automatico: esce da MDO → cancella PDF (DB + storage).
-- Su DELETE multicard: pulisce storage; le righe vanno via ON DELETE CASCADE.
create or replace function public.purge_multicard_mdo_assegnazioni_on_leave_mdo()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  r record;
  leave_mdo boolean := false;
begin
  if tg_op = 'DELETE' then
    for r in
      select file_path
      from public.logistica_multicard_mdo_assegnazioni
      where multicard_id = old.id_uuid
    loop
      if coalesce(nullif(trim(r.file_path), ''), '') <> ''
         and trim(r.file_path) <> 'pending' then
        delete from storage.objects
        where bucket_id = 'logistica_multicard_mdo_assegnazioni'
          and name = r.file_path;
      end if;
    end loop;
    return old;
  end if;

  leave_mdo :=
    upper(trim(coalesce(old.mezzo_targa, ''))) = 'MDO'
    and upper(trim(coalesce(new.mezzo_targa, ''))) is distinct from 'MDO';

  if leave_mdo then
    for r in
      select file_path
      from public.logistica_multicard_mdo_assegnazioni
      where multicard_id = old.id_uuid
    loop
      if coalesce(nullif(trim(r.file_path), ''), '') <> ''
         and trim(r.file_path) <> 'pending' then
        delete from storage.objects
        where bucket_id = 'logistica_multicard_mdo_assegnazioni'
          and name = r.file_path;
      end if;
    end loop;
    delete from public.logistica_multicard_mdo_assegnazioni
    where multicard_id = old.id_uuid;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_purge_multicard_mdo_assegnazioni
  on public.logistica_multicard;
create trigger trg_purge_multicard_mdo_assegnazioni
before update or delete on public.logistica_multicard
for each row
execute function public.purge_multicard_mdo_assegnazioni_on_leave_mdo();

insert into public.app_page_registry (page_key, label, active)
values (
  'multicard_mdo_assegnazioni',
  'Logistica — Assegnazioni Multicard MDO',
  true
)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
