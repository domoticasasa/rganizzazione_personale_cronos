-- Fix timeout Programmazioni corsi RFI (Postgres 57014):
-- 1) InitPlan wrap sulle policy RLS (staff/my-personale valutati 1 volta, non per riga)
-- 2) Indice su field_key programmazione
-- 3) RPC definer che legge solo i track con data programmazione

create index if not exists formazione_rfi_records_field_key_idx
  on public.formazione_rfi_records (field_key);

create index if not exists formazione_rfi_records_prog_field_personale_idx
  on public.formazione_rfi_records (field_key, personale_id)
  where field_key in (
    'data_programmazione_dal',
    'data_programmazione_al',
    'data_programmazione_corso'
  );

-- personale: evita N chiamate a cronos_is_staff_reader()
drop policy if exists personale_select_own_or_staff on public.personale;
create policy personale_select_own_or_staff
on public.personale for select to authenticated
using (
  public.personale_belongs_to_current_auth(personale)
  or (select public.cronos_is_staff_reader())
);

-- formazione_rfi_records
drop policy if exists formazione_rfi_records_select on public.formazione_rfi_records;
create policy formazione_rfi_records_select
on public.formazione_rfi_records for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_id())
  or (select public.cronos_is_staff_reader())
);

-- formazioni (stesso pattern, usata dalla programmazione D.Lgs.)
drop policy if exists formazioni_select on public.formazioni;
create policy formazioni_select
on public.formazioni for select to authenticated
using (
  utente_id = coalesce((select public.current_user_uuid())::text, '')
  or utente_id = coalesce((select public.cronos_my_personale_uuid())::text, '')
  or utente_id = coalesce((select public.cronos_my_personale_id())::text, '')
  or (select public.cronos_is_staff_reader())
);

-- Payload celle EAV solo per corsi con data programmazione (dal o legacy).
create or replace function public.formazione_rfi_programmazione_records(
  p_only_personale_uuid uuid default null
)
returns table (
  personale_id integer,
  personale_uuid uuid,
  track_key text,
  field_key text,
  value_date date,
  value_text text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff boolean := coalesce((select public.cronos_is_staff_reader()), false);
  v_my_id integer := (select public.cronos_my_personale_id());
  v_filter_id integer := null;
begin
  if p_only_personale_uuid is not null then
    select p.id
      into v_filter_id
    from public.personale p
    where p.id_uuid = p_only_personale_uuid
    limit 1;

    if v_filter_id is null then
      return;
    end if;

    if not v_staff and (v_my_id is null or v_filter_id is distinct from v_my_id) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  elsif not v_staff then
    v_filter_id := v_my_id;
    if v_filter_id is null then
      return;
    end if;
  end if;

  return query
  with programmed as (
    select distinct r.personale_id, r.track_key
    from public.formazione_rfi_records r
    where r.field_key in (
      'data_programmazione_dal',
      'data_programmazione_corso'
    )
      and (
        r.value_date is not null
        or nullif(btrim(coalesce(r.value_text, '')), '') is not null
      )
      and (v_filter_id is null or r.personale_id = v_filter_id)
  )
  select
    r.personale_id,
    p.id_uuid as personale_uuid,
    r.track_key,
    r.field_key,
    r.value_date,
    r.value_text
  from public.formazione_rfi_records r
  join programmed pr
    on pr.personale_id = r.personale_id
   and pr.track_key = r.track_key
  join public.personale p
    on p.id = r.personale_id
  order by r.personale_id, r.track_key, r.field_key;
end;
$$;

revoke all on function public.formazione_rfi_programmazione_records(uuid) from public;
grant execute on function public.formazione_rfi_programmazione_records(uuid) to authenticated;

notify pgrst, 'reload schema';
