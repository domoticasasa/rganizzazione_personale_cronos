-- Branding white-label condiviso (logo, nomi, colori, copyright, sfondi).

create table if not exists public.app_branding (
  id integer primary key check (id = 1),
  brand_name text not null default 'CRONOS',
  product_name text not null default 'GESTOPRO',
  app_title text not null default 'Cronos Gestopro',
  welcome_subtitle text not null default '',
  accent_color text not null default '#1565C0',
  logo_bar_color text not null default '#00AEEF',
  top_bar_color text not null default '#1565C0',
  sidebar_color text not null default '#EEF3FA',
  copyright_short text,
  copyright_full text,
  logo_path text,
  logo_light_path text,
  bg_landscape_path text,
  bg_portrait_path text,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by integer references public.users (id) on delete set null
);

comment on table public.app_branding is
  'Personalizzazione brand organizzazione (singleton id=1), condivisa da tutti gli utenti.';

grant select on public.app_branding to authenticated;
grant insert, update, delete on public.app_branding to authenticated;

alter table public.app_branding enable row level security;

drop policy if exists app_branding_select on public.app_branding;
create policy app_branding_select
on public.app_branding
for select
to authenticated
using (true);

drop policy if exists app_branding_write on public.app_branding;
create policy app_branding_write
on public.app_branding
for all
to authenticated
using (public.is_cronos_admin_role())
with check (public.is_cronos_admin_role());

insert into public.app_branding (id)
values (1)
on conflict (id) do nothing;

-- Storage pubblico per logo/sfondi (URL pubblici; scrittura solo admin).
insert into storage.buckets (id, name, public, file_size_limit)
values ('app_branding', 'app_branding', true, 8388608)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = true;

drop policy if exists app_branding_storage_select on storage.objects;
create policy app_branding_storage_select
  on storage.objects
  for select
  to authenticated, anon
  using (bucket_id = 'app_branding');

drop policy if exists app_branding_storage_insert on storage.objects;
create policy app_branding_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'app_branding'
    and public.is_cronos_admin_role()
  );

drop policy if exists app_branding_storage_update on storage.objects;
create policy app_branding_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'app_branding'
    and public.is_cronos_admin_role()
  )
  with check (
    bucket_id = 'app_branding'
    and public.is_cronos_admin_role()
  );

drop policy if exists app_branding_storage_delete on storage.objects;
create policy app_branding_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'app_branding'
    and public.is_cronos_admin_role()
  );
