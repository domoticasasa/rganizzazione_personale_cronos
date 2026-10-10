-- Agenda personale per utente (eventi, note, promemoria, assenze private).

create table if not exists public.user_agenda_entries (
  id uuid primary key default gen_random_uuid(),
  user_id integer not null references public.users (id) on delete cascade,
  kind text not null default 'event'
    check (kind in ('event', 'note', 'reminder', 'absence')),
  title text not null,
  body text not null default '',
  location text not null default '',
  all_day boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  color_hex text not null default '#1565C0',
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'high')),
  completed boolean not null default false,
  assenza_id_uuid uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint user_agenda_entries_title_nonempty check (length(trim(title)) > 0)
);

create index if not exists user_agenda_entries_user_starts_idx
  on public.user_agenda_entries (user_id, starts_at);

create index if not exists user_agenda_entries_user_kind_idx
  on public.user_agenda_entries (user_id, kind);

comment on table public.user_agenda_entries is
  'Agenda personale privata: eventi, note, promemoria, assenze.';

grant select, insert, update, delete on public.user_agenda_entries to authenticated;

alter table public.user_agenda_entries enable row level security;

drop policy if exists user_agenda_entries_own on public.user_agenda_entries;
create policy user_agenda_entries_own
on public.user_agenda_entries
for all
to authenticated
using (user_id = public.cronos_current_user_id())
with check (user_id = public.cronos_current_user_id());
