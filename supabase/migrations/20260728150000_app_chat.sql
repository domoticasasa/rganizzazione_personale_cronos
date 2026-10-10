-- Chat aziendale di gruppo: messaggi + allegati, retention 7 giorni.

create table if not exists public.app_chat_messages (
  id uuid primary key default gen_random_uuid(),
  sender_user_id integer not null references public.users (id) on delete cascade,
  sender_auth_id uuid not null,
  sender_name text not null default '',
  body text,
  reply_to_id uuid references public.app_chat_messages (id) on delete set null,
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  attachment_size integer,
  created_at timestamptz not null default timezone('utc', now()),
  constraint app_chat_messages_body_or_attachment check (
    (body is not null and length(trim(body)) > 0)
    or (attachment_path is not null and length(trim(attachment_path)) > 0)
  )
);

create index if not exists app_chat_messages_created_at_idx
  on public.app_chat_messages (created_at desc);

create index if not exists app_chat_messages_reply_to_idx
  on public.app_chat_messages (reply_to_id)
  where reply_to_id is not null;

comment on table public.app_chat_messages is
  'Chat di gruppo aziendale; messaggi e allegati scadono dopo 7 giorni.';

alter table public.app_chat_messages enable row level security;

drop policy if exists app_chat_messages_select on public.app_chat_messages;
create policy app_chat_messages_select
  on public.app_chat_messages
  for select
  to authenticated
  using (true);

drop policy if exists app_chat_messages_insert on public.app_chat_messages;
create policy app_chat_messages_insert
  on public.app_chat_messages
  for insert
  to authenticated
  with check (sender_auth_id = auth.uid());

-- Realtime
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.app_chat_messages;
    exception
      when duplicate_object then null;
    end;
  end if;
end
$$;

-- Storage bucket allegati (max ~15 MB)
insert into storage.buckets (id, name, public, file_size_limit)
values ('chat_allegati', 'chat_allegati', false, 15728640)
on conflict (id) do update
set file_size_limit = excluded.file_size_limit,
    public = false;

drop policy if exists chat_allegati_select on storage.objects;
create policy chat_allegati_select
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'chat_allegati');

drop policy if exists chat_allegati_insert on storage.objects;
create policy chat_allegati_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat_allegati'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists chat_allegati_delete_own on storage.objects;
create policy chat_allegati_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat_allegati'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Cleanup messaggi + oggetti storage > 7 giorni
create or replace function public.cleanup_app_chat_older_than_7_days()
returns bigint
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_cutoff timestamptz := timezone('utc', now()) - interval '7 days';
  v_paths text[];
  v_deleted bigint := 0;
begin
  select coalesce(array_agg(attachment_path), '{}'::text[])
    into v_paths
  from public.app_chat_messages
  where created_at < v_cutoff
    and attachment_path is not null
    and length(trim(attachment_path)) > 0;

  if cardinality(v_paths) > 0 then
    delete from storage.objects o
    where o.bucket_id = 'chat_allegati'
      and o.name = any (v_paths);
  end if;

  delete from public.app_chat_messages
  where created_at < v_cutoff;

  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

grant execute on function public.cleanup_app_chat_older_than_7_days() to authenticated;

comment on function public.cleanup_app_chat_older_than_7_days() is
  'Elimina messaggi chat e allegati più vecchi di 7 giorni.';

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'cleanup_app_chat_daily'
    ) then
      perform cron.unschedule('cleanup_app_chat_daily');
    end if;

    perform cron.schedule(
      'cleanup_app_chat_daily',
      '15 2 * * *',
      $job$select public.cleanup_app_chat_older_than_7_days();$job$
    );
  end if;
end
$$;
