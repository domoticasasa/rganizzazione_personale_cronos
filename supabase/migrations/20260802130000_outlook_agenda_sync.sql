-- Outlook sync + avvisi agenda personale

alter table public.user_agenda_entries
  add column if not exists reminder_enabled boolean not null default false,
  add column if not exists reminder_minutes_before integer,
  add column if not exists outlook_event_id text,
  add column if not exists outlook_etag text,
  add column if not exists outlook_last_modified timestamptz,
  add column if not exists sync_origin text not null default 'cronos'
    check (sync_origin in ('cronos', 'outlook'));

alter table public.user_agenda_entries
  drop constraint if exists user_agenda_entries_reminder_minutes_nonneg;

alter table public.user_agenda_entries
  add constraint user_agenda_entries_reminder_minutes_nonneg
  check (
    reminder_minutes_before is null
    or reminder_minutes_before >= 0
  );

create unique index if not exists user_agenda_entries_user_outlook_event_uidx
  on public.user_agenda_entries (user_id, outlook_event_id)
  where outlook_event_id is not null;

create table if not exists public.user_outlook_connections (
  user_id integer primary key references public.users (id) on delete cascade,
  access_token text not null,
  refresh_token text not null,
  token_expires_at timestamptz not null,
  graph_user_id text,
  graph_display_name text,
  graph_email text,
  last_sync_at timestamptz,
  delta_link text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.user_outlook_connections is
  'Token Microsoft Graph per sync agenda personale ↔ Outlook (per utente).';

grant select, insert, update, delete on public.user_outlook_connections to authenticated;

alter table public.user_outlook_connections enable row level security;

drop policy if exists user_outlook_connections_own on public.user_outlook_connections;
create policy user_outlook_connections_own
on public.user_outlook_connections
for all
to authenticated
using (user_id = public.cronos_current_user_id())
with check (user_id = public.cronos_current_user_id());
