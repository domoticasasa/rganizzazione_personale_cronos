-- Bacheca comunicazioni aziendali → tutti gli utenti autenticati.

create table if not exists public.app_bacheca_posts (
  id uuid primary key default gen_random_uuid(),
  titolo text not null,
  corpo text not null default '',
  file_path text,
  file_name text,
  mime_type text,
  file_size integer,
  attivo boolean not null default true,
  published_at timestamptz not null default timezone('utc', now()),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint app_bacheca_posts_titolo_nonempty
    check (length(trim(titolo)) > 0)
);

create index if not exists app_bacheca_posts_published_idx
  on public.app_bacheca_posts (published_at desc);

comment on table public.app_bacheca_posts is
  'Comunicazioni bacheca: lettura per tutti gli autenticati; scrittura admin.';

create or replace function public.set_app_bacheca_posts_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_app_bacheca_posts_updated_at on public.app_bacheca_posts;
create trigger trg_app_bacheca_posts_updated_at
before update on public.app_bacheca_posts
for each row
execute function public.set_app_bacheca_posts_updated_at();

create or replace function public.is_bacheca_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null;
$$;

grant execute on function public.is_bacheca_reader() to authenticated;

create or replace function public.can_write_bacheca()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role_norm(), '') in (
    'admin',
    'admin_generale'
  )
  or public.has_custom_page_access('bacheca');
$$;

grant execute on function public.can_write_bacheca() to authenticated;

alter table public.app_bacheca_posts enable row level security;

drop policy if exists app_bacheca_posts_select on public.app_bacheca_posts;
create policy app_bacheca_posts_select
  on public.app_bacheca_posts
  for select
  to authenticated
  using (public.is_bacheca_reader());

drop policy if exists app_bacheca_posts_insert on public.app_bacheca_posts;
create policy app_bacheca_posts_insert
  on public.app_bacheca_posts
  for insert
  to authenticated
  with check (public.can_write_bacheca());

drop policy if exists app_bacheca_posts_update on public.app_bacheca_posts;
create policy app_bacheca_posts_update
  on public.app_bacheca_posts
  for update
  to authenticated
  using (public.can_write_bacheca())
  with check (public.can_write_bacheca());

drop policy if exists app_bacheca_posts_delete on public.app_bacheca_posts;
create policy app_bacheca_posts_delete
  on public.app_bacheca_posts
  for delete
  to authenticated
  using (public.can_write_bacheca());

insert into storage.buckets (id, name, public, file_size_limit)
values ('app_bacheca', 'app_bacheca', false, 20971520) -- 20 MiB
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists app_bacheca_storage_select on storage.objects;
create policy app_bacheca_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'app_bacheca'
    and public.is_bacheca_reader()
  );

drop policy if exists app_bacheca_storage_insert on storage.objects;
create policy app_bacheca_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'app_bacheca'
    and public.can_write_bacheca()
  );

drop policy if exists app_bacheca_storage_update on storage.objects;
create policy app_bacheca_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'app_bacheca'
    and public.can_write_bacheca()
  )
  with check (
    bucket_id = 'app_bacheca'
    and public.can_write_bacheca()
  );

drop policy if exists app_bacheca_storage_delete on storage.objects;
create policy app_bacheca_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'app_bacheca'
    and public.can_write_bacheca()
  );

insert into public.app_page_registry (page_key, label, active)
values ('bacheca', 'Bacheca comunicazioni', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
