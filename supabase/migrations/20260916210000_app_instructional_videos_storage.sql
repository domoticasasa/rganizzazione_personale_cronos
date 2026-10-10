-- Video istruttivi: file caricati (cellulare) invece di soli link YouTube.

alter table public.app_video_links
  alter column youtube_url drop not null;

alter table public.app_video_links
  alter column youtube_video_id drop not null;

alter table public.app_video_links
  add column if not exists storage_path text,
  add column if not exists file_name text,
  add column if not exists mime_type text,
  add column if not exists file_size bigint;

comment on table public.app_video_links is
  'Video istruttivi CRONOS (file in storage; tutti leggono, admin scrive).';

comment on column public.app_video_links.storage_path is
  'Percorso oggetto nel bucket app_instructional_videos.';

-- Disattiva eventuali soli link YouTube residui (non più riprodotti in app).
update public.app_video_links
set active = false,
    updated_at = now()
where coalesce(trim(storage_path), '') = ''
  and active = true;

insert into storage.buckets (id, name, public, file_size_limit)
values ('app_instructional_videos', 'app_instructional_videos', false, 209715200) -- 200 MiB
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists app_instructional_videos_storage_select on storage.objects;
create policy app_instructional_videos_storage_select
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'app_instructional_videos');

drop policy if exists app_instructional_videos_storage_insert on storage.objects;
create policy app_instructional_videos_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'app_instructional_videos'
    and public.is_cronos_admin_role()
  );

drop policy if exists app_instructional_videos_storage_update on storage.objects;
create policy app_instructional_videos_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'app_instructional_videos'
    and public.is_cronos_admin_role()
  )
  with check (
    bucket_id = 'app_instructional_videos'
    and public.is_cronos_admin_role()
  );

drop policy if exists app_instructional_videos_storage_delete on storage.objects;
create policy app_instructional_videos_storage_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'app_instructional_videos'
    and public.is_cronos_admin_role()
  );
