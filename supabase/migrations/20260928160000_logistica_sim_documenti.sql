-- PDF assegnazione SIM: upload manuale (niente generazione automatica).

create table if not exists public.logistica_sim_documenti (
  id uuid primary key default gen_random_uuid(),
  sim_id uuid not null
    references public.logistica_sim (id_uuid) on delete cascade,
  file_path text not null,
  file_name text not null,
  mime_type text,
  file_size integer,
  note text,
  uploaded_at timestamptz not null default timezone('utc', now()),
  uploaded_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint logistica_sim_doc_file_name_nonempty
    check (length(trim(file_name)) > 0)
);

create index if not exists logistica_sim_doc_sim_idx
  on public.logistica_sim_documenti (sim_id);

comment on table public.logistica_sim_documenti is
  'PDF assegnazione SIM/linea telefonica. Upload manuale admin/logistica.';

create or replace function public.set_logistica_sim_doc_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_logistica_sim_doc_updated_at
  on public.logistica_sim_documenti;
create trigger trg_logistica_sim_doc_updated_at
before update on public.logistica_sim_documenti
for each row
execute function public.set_logistica_sim_doc_updated_at();

create or replace function public.is_logistica_sim_documenti_reader()
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
  or public.has_custom_page_access('sim_telefoni')
  or public.has_custom_page_access('logistica');
$$;

grant execute on function public.is_logistica_sim_documenti_reader()
  to authenticated;

create or replace function public.can_write_logistica_sim_documenti()
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
    'admin_formazione',
    'logistica'
  )
  or public.has_custom_page_access('sim_telefoni');
$$;

grant execute on function public.can_write_logistica_sim_documenti()
  to authenticated;

grant select, insert, update, delete
  on public.logistica_sim_documenti
  to authenticated;

alter table public.logistica_sim_documenti
  enable row level security;

drop policy if exists logistica_sim_doc_select
  on public.logistica_sim_documenti;
create policy logistica_sim_doc_select
  on public.logistica_sim_documenti
  for select
  to authenticated
  using (public.is_logistica_sim_documenti_reader());

drop policy if exists logistica_sim_doc_insert
  on public.logistica_sim_documenti;
create policy logistica_sim_doc_insert
  on public.logistica_sim_documenti
  for insert
  to authenticated
  with check (public.can_write_logistica_sim_documenti());

drop policy if exists logistica_sim_doc_update
  on public.logistica_sim_documenti;
create policy logistica_sim_doc_update
  on public.logistica_sim_documenti
  for update
  to authenticated
  using (public.can_write_logistica_sim_documenti())
  with check (public.can_write_logistica_sim_documenti());

drop policy if exists logistica_sim_doc_delete
  on public.logistica_sim_documenti;
create policy logistica_sim_doc_delete
  on public.logistica_sim_documenti
  for delete
  to authenticated
  using (public.can_write_logistica_sim_documenti());

insert into storage.buckets (id, name, public, file_size_limit)
values (
  'logistica_sim_documenti',
  'logistica_sim_documenti',
  false,
  52428800
)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists logistica_sim_doc_storage_select
  on storage.objects;
create policy logistica_sim_doc_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'logistica_sim_documenti'
    and public.is_logistica_sim_documenti_reader()
  );

drop policy if exists logistica_sim_doc_storage_insert
  on storage.objects;
create policy logistica_sim_doc_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'logistica_sim_documenti'
    and public.can_write_logistica_sim_documenti()
  );

drop policy if exists logistica_sim_doc_storage_update
  on storage.objects;
create policy logistica_sim_doc_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'logistica_sim_documenti'
    and public.can_write_logistica_sim_documenti()
  )
  with check (
    bucket_id = 'logistica_sim_documenti'
    and public.can_write_logistica_sim_documenti()
  );

drop policy if exists logistica_sim_doc_storage_delete
  on storage.objects;
create policy logistica_sim_doc_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'logistica_sim_documenti'
    and public.can_write_logistica_sim_documenti()
  );

notify pgrst, 'reload schema';
