-- Documenti mezzi d'opera ferroviari (più file per tipo; niente sostituzione automatica).

create table if not exists public.logistica_mdo_documenti (
  id uuid primary key default gen_random_uuid(),
  mdo_id uuid not null references public.logistica_mdo_ferroviari (id_uuid) on delete cascade,
  doc_tipo text not null check (doc_tipo in (
    'cdc_allegato_j',
    'libro_bordo_allegato_l',
    'diario_manutenzione_allegato_k',
    'targa_identificativa',
    'certificato_va',
    'controllo_periodico_33m_allegato_k',
    'verifica_quinquennale_allegato_p',
    'mum',
    'inail_terrazzino',
    'inail_gru'
  )),
  file_path text not null,
  file_name text not null,
  mime_type text,
  file_size integer,
  note text,
  uploaded_at timestamptz not null default timezone('utc', now()),
  uploaded_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint logistica_mdo_documenti_file_name_nonempty
    check (length(trim(file_name)) > 0)
);

create index if not exists logistica_mdo_documenti_mdo_tipo_idx
  on public.logistica_mdo_documenti (mdo_id, doc_tipo);

comment on table public.logistica_mdo_documenti is
  'Allegati per mezzo ferroviario. Più file per tipo; i vecchi si cancellano a mano.';

create or replace function public.set_logistica_mdo_documenti_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_logistica_mdo_documenti_updated_at
  on public.logistica_mdo_documenti;
create trigger trg_logistica_mdo_documenti_updated_at
before update on public.logistica_mdo_documenti
for each row
execute function public.set_logistica_mdo_documenti_updated_at();

create or replace function public.is_mdo_documenti_reader()
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
  or public.has_custom_page_access('mdo_ferroviari_documenti')
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica');
$$;

grant execute on function public.is_mdo_documenti_reader() to authenticated;

create or replace function public.can_write_mdo_documenti()
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
  or public.has_custom_page_access('mdo_ferroviari_documenti')
  or public.has_custom_page_access('mdo_ferroviari')
  or public.has_custom_page_access('logistica');
$$;

grant execute on function public.can_write_mdo_documenti() to authenticated;

grant select, insert, update, delete on public.logistica_mdo_documenti to authenticated;

alter table public.logistica_mdo_documenti enable row level security;

drop policy if exists logistica_mdo_documenti_select on public.logistica_mdo_documenti;
create policy logistica_mdo_documenti_select
  on public.logistica_mdo_documenti
  for select
  to authenticated
  using (public.is_mdo_documenti_reader());

drop policy if exists logistica_mdo_documenti_insert on public.logistica_mdo_documenti;
create policy logistica_mdo_documenti_insert
  on public.logistica_mdo_documenti
  for insert
  to authenticated
  with check (public.can_write_mdo_documenti());

drop policy if exists logistica_mdo_documenti_update on public.logistica_mdo_documenti;
create policy logistica_mdo_documenti_update
  on public.logistica_mdo_documenti
  for update
  to authenticated
  using (public.can_write_mdo_documenti())
  with check (public.can_write_mdo_documenti());

drop policy if exists logistica_mdo_documenti_delete on public.logistica_mdo_documenti;
create policy logistica_mdo_documenti_delete
  on public.logistica_mdo_documenti
  for delete
  to authenticated
  using (public.can_write_mdo_documenti());

insert into storage.buckets (id, name, public, file_size_limit)
values ('logistica_mdo_documenti', 'logistica_mdo_documenti', false, 20971520)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists logistica_mdo_documenti_storage_select on storage.objects;
create policy logistica_mdo_documenti_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_mdo_documenti'
    and public.is_mdo_documenti_reader()
  );

drop policy if exists logistica_mdo_documenti_storage_insert on storage.objects;
create policy logistica_mdo_documenti_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'logistica_mdo_documenti'
    and public.can_write_mdo_documenti()
  );

drop policy if exists logistica_mdo_documenti_storage_update on storage.objects;
create policy logistica_mdo_documenti_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'logistica_mdo_documenti'
    and public.can_write_mdo_documenti()
  )
  with check (
    bucket_id = 'logistica_mdo_documenti'
    and public.can_write_mdo_documenti()
  );

drop policy if exists logistica_mdo_documenti_storage_delete on storage.objects;
create policy logistica_mdo_documenti_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'logistica_mdo_documenti'
    and public.can_write_mdo_documenti()
  );

insert into public.app_page_registry (page_key, label, active)
values (
  'mdo_ferroviari_documenti',
  'Logistica — Documenti MDO ferroviari',
  true
)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
