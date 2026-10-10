-- Nominativi rimossi manualmente dalla lista Dislocazione (non re-importati da personale).

create table if not exists public.dislocazione_nominativi_esclusi (
  nominativo_chiave text primary key,
  nominativo_originale text not null,
  escluso_at timestamptz not null default now()
);

comment on table public.dislocazione_nominativi_esclusi is
  'Nomi nascosti dalla griglia Dislocazione Personale (esclusi da merge con personale attivo).';

create index if not exists dislocazione_nominativi_esclusi_escluso_at_idx
  on public.dislocazione_nominativi_esclusi(escluso_at desc);

grant select on public.dislocazione_nominativi_esclusi to authenticated;
grant insert, update, delete on public.dislocazione_nominativi_esclusi to authenticated;

alter table public.dislocazione_nominativi_esclusi enable row level security;

drop policy if exists dislocazione_nominativi_esclusi_select on public.dislocazione_nominativi_esclusi;
create policy dislocazione_nominativi_esclusi_select
on public.dislocazione_nominativi_esclusi
for select to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
);

drop policy if exists dislocazione_nominativi_esclusi_write on public.dislocazione_nominativi_esclusi;
create policy dislocazione_nominativi_esclusi_write
on public.dislocazione_nominativi_esclusi
for all to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role,'')) in (
        'dt','assistente_dt','admin','admin_generale',
        'admin_pernottamenti','admin_trenoaereo','logistica'
      )
  )
);
