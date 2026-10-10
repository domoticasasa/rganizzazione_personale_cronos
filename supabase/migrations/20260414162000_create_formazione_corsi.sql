-- Corsi formazione dipendenti (replica struttura file "CORSI DI FORMAZIONE.xlsx")

create table if not exists public.formazione_corsi (
  id bigserial primary key,
  personale_id uuid not null references public.personale(id_uuid) on delete cascade,
  anno integer,
  data date,
  oda text,
  ente text,
  corso text not null,
  primo_rilascio_aggiornamento text,
  attestato text,
  data_attestato date,
  scadenza_attestato date,
  corso_prenotato text,
  prima_data date,
  seconda_data date,
  orario text,
  modalita text,
  dimessi text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists formazione_corsi_unique_key
  on public.formazione_corsi (personale_id, corso, data_attestato);

create index if not exists formazione_corsi_personale_idx
  on public.formazione_corsi (personale_id);

create index if not exists formazione_corsi_scadenza_idx
  on public.formazione_corsi (scadenza_attestato);

create or replace function public.set_formazione_corsi_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_formazione_corsi_updated_at
on public.formazione_corsi;

create trigger trg_formazione_corsi_updated_at
before update on public.formazione_corsi
for each row
execute function public.set_formazione_corsi_updated_at();

alter table public.formazione_corsi enable row level security;

drop policy if exists formazione_corsi_admin_read on public.formazione_corsi;
create policy formazione_corsi_admin_read
on public.formazione_corsi
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti', 'admin_trenoaereo')
  )
);

drop policy if exists formazione_corsi_admin_write on public.formazione_corsi;
create policy formazione_corsi_admin_write
on public.formazione_corsi
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti', 'admin_trenoaereo')
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'admin_pernottamenti', 'admin_trenoaereo')
  )
);

drop policy if exists formazione_corsi_dipendente_read_own on public.formazione_corsi;
create policy formazione_corsi_dipendente_read_own
on public.formazione_corsi
for select
to authenticated
using (
  exists (
    select 1
    from public.personale p
    left join public.users me on me.auth_id = auth.uid()
    where p.id_uuid = formazione_corsi.personale_id
      and (
        p.user_id::text = auth.uid()::text
        or (me.id is not null and p.user_id::text = me.id::text)
        or (me.id_uuid is not null and p.user_id::text = me.id_uuid::text)
      )
  )
);

