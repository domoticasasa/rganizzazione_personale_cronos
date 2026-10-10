-- Catalogo video YouTube condiviso (visibile a tutti, gestione admin).

create table if not exists public.app_video_links (
  id_uuid uuid primary key default gen_random_uuid(),
  section_title text not null default 'Video',
  title text not null,
  youtube_url text not null,
  youtube_video_id text not null,
  description text,
  featured boolean not null default false,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_app_video_links_section_sort
  on public.app_video_links (section_title, sort_order, title);

comment on table public.app_video_links is
  'Link YouTube per galleria video CRONOS (tutti leggono, admin scrive).';

drop trigger if exists trg_app_video_links_updated_at on public.app_video_links;
create trigger trg_app_video_links_updated_at
before update on public.app_video_links
for each row
execute function public.trg_set_updated_at();

alter table public.app_video_links enable row level security;

grant select on public.app_video_links to authenticated;
grant insert, update, delete on public.app_video_links to authenticated;

drop policy if exists app_video_links_select on public.app_video_links;
create policy app_video_links_select on public.app_video_links
  for select to authenticated
  using (active = true or public.is_cronos_admin_role());

drop policy if exists app_video_links_insert on public.app_video_links;
create policy app_video_links_insert on public.app_video_links
  for insert to authenticated
  with check (public.is_cronos_admin_role());

drop policy if exists app_video_links_update on public.app_video_links;
create policy app_video_links_update on public.app_video_links
  for update to authenticated
  using (public.is_cronos_admin_role())
  with check (public.is_cronos_admin_role());

drop policy if exists app_video_links_delete on public.app_video_links;
create policy app_video_links_delete on public.app_video_links
  for delete to authenticated
  using (public.is_cronos_admin_role());
