-- POS commesse MLD: 4 liste separate (TE, IS, TLC, LFC).
-- Per commesse non MLD si usa lista_mld = '' (default).

alter table public.pos_commessa_lista_meta
  add column if not exists lista_mld text not null default '';

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'pos_commessa_lista_meta_pkey'
      and conrelid = 'public.pos_commessa_lista_meta'::regclass
  ) then
    alter table public.pos_commessa_lista_meta
      drop constraint pos_commessa_lista_meta_pkey;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pos_commessa_lista_meta_pkey'
      and conrelid = 'public.pos_commessa_lista_meta'::regclass
  ) then
    alter table public.pos_commessa_lista_meta
      add constraint pos_commessa_lista_meta_pkey
      primary key (commessa_id, lista_mld);
  end if;
end $$;

alter table public.pos_commessa_dipendenti
  add column if not exists lista_mld text not null default '';

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'pos_commessa_dipendenti_commessa_id_personale_id_key'
      and conrelid = 'public.pos_commessa_dipendenti'::regclass
  ) then
    alter table public.pos_commessa_dipendenti
      drop constraint pos_commessa_dipendenti_commessa_id_personale_id_key;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pos_commessa_dipendenti_commessa_lista_personale_key'
      and conrelid = 'public.pos_commessa_dipendenti'::regclass
  ) then
    alter table public.pos_commessa_dipendenti
      add constraint pos_commessa_dipendenti_commessa_lista_personale_key
      unique (commessa_id, lista_mld, personale_id);
  end if;
end $$;

create index if not exists pos_commessa_dipendenti_commessa_lista_idx
  on public.pos_commessa_dipendenti (commessa_id, lista_mld);

create index if not exists pos_commessa_lista_meta_commessa_lista_idx
  on public.pos_commessa_lista_meta (commessa_id, lista_mld);
