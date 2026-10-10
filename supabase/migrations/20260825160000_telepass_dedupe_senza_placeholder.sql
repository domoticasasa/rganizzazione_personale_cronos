-- «SENZA» / «SENZA TELEPASS» non sono codici Telepass: non creare né
-- sincronizzare righe Gestione Telepass. Pulisce i doppioni già nati dal seed.

create or replace function public.logistica_telepass_is_empty(p_raw text)
returns boolean
language sql
immutable
as $$
  select case
    when nullif(trim(coalesce(p_raw, '')), '') is null then true
    when lower(trim(p_raw)) in ('--', '-', '—', 'n/a', 'na', 'nessuno', 'nessuna') then true
    when lower(trim(p_raw)) like '%no telepass%' then true
    when lower(trim(p_raw)) ~ '^senza([[:space:]:].*)?$' then true
    else false
  end;
$$;

comment on function public.logistica_telepass_is_empty(text) is
  'True se il valore non è un codice Telepass (vuoto, --, SENZA, SENZA TELEPASS, …).';

-- Togli placeholder dai mezzi: non sono numeri dispositivo.
update public.logistica_mezzi_stradali
set telepass = null
where public.logistica_telepass_is_empty(telepass)
  and nullif(trim(telepass), '') is not null;

-- Elimina righe Gestione Telepass senza codice reale.
delete from public.logistica_telepass t
where public.logistica_telepass_is_empty(t.telepass);

-- Un solo record per codice Telepass (tiene l'aggiornamento più recente).
delete from public.logistica_telepass t
where t.id_uuid not in (
  select distinct on (public.logistica_normalize_telepass_key(x.telepass)) x.id_uuid
  from public.logistica_telepass x
  where not public.logistica_telepass_is_empty(x.telepass)
  order by
    public.logistica_normalize_telepass_key(x.telepass),
    x.updated_at desc nulls last,
    x.created_at desc nulls last,
    x.id_uuid desc
);

drop index if exists public.logistica_telepass_key_uidx;
create unique index logistica_telepass_key_uidx
  on public.logistica_telepass (public.logistica_normalize_telepass_key(telepass))
  where not public.logistica_telepass_is_empty(telepass);
