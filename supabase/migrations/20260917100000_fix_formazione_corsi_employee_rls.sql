-- Fix Programmazione Formazioni (e pagine employee): RLS leggera e affidabile.
-- Prima: EXISTS per-riga su users/personale → lenti / vuoti in vista dipendente.
-- Ora: InitPlan + cronos_my_personale_uuid / cronos_is_staff_reader.

-- =========================
-- formazione_corsi (D.Lgs.)
-- =========================
drop policy if exists formazione_corsi_admin_read on public.formazione_corsi;
drop policy if exists formazione_corsi_dt_read_all on public.formazione_corsi;
drop policy if exists formazione_corsi_dipendente_read_own on public.formazione_corsi;
drop policy if exists formazione_corsi_custom_role_read on public.formazione_corsi;
drop policy if exists formazione_corsi_alert_dashboard_read on public.formazione_corsi;
drop policy if exists formazione_corsi_staff_select on public.formazione_corsi;
drop policy if exists formazione_corsi_own_select on public.formazione_corsi;

-- Staff (admin*, dt, assistente_dt, formazione, …) vede tutta la griglia
create policy formazione_corsi_staff_select
on public.formazione_corsi
for select
to authenticated
using (
  (select public.cronos_is_staff_reader())
  or coalesce((select public.has_custom_page_access('formazione_dlgs_81_08')), false)
  or coalesce((select public.has_custom_page_access('formazione')), false)
  or coalesce((select public.has_custom_page_access('uqsa')), false)
);

-- Dipendente: solo i propri corsi (uuid anagrafica)
create policy formazione_corsi_own_select
on public.formazione_corsi
for select
to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
);

-- RPC stabile per elenco programmazione del dipendente corrente (o uuid richiesto se staff)
create or replace function public.formazione_corsi_programmazione_rows(
  p_only_personale_uuid uuid default null
)
returns setof public.formazione_corsi
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff boolean := coalesce((select public.cronos_is_staff_reader()), false);
  v_my uuid := (select public.cronos_my_personale_uuid());
  v_filter uuid := null;
begin
  if p_only_personale_uuid is not null then
    v_filter := p_only_personale_uuid;
    if not v_staff and (v_my is null or v_filter is distinct from v_my) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  elsif not v_staff then
    v_filter := v_my;
  end if;

  if v_filter is null and not v_staff then
    return;
  end if;

  return query
  select c.*
  from public.formazione_corsi c
  where c.prima_data is not null
    and (v_filter is null or c.personale_id = v_filter)
  order by c.prima_data asc nulls last, c.corso asc nulls last;
end;
$$;

revoke all on function public.formazione_corsi_programmazione_rows(uuid) from public;
grant execute on function public.formazione_corsi_programmazione_rows(uuid) to authenticated;

-- =========================
-- visite_mediche (employee pages)
-- =========================
drop policy if exists visite_mediche_select on public.visite_mediche_programmazione;
create policy visite_mediche_select
on public.visite_mediche_programmazione
for select
to authenticated
using (
  personale_id_uuid = (select public.cronos_my_personale_uuid())
  or (select public.cronos_is_staff_reader())
  or coalesce((select public.has_custom_page_access('visite_mediche')), false)
);

-- =========================
-- Index utile per employee filter
-- =========================
create index if not exists formazione_corsi_personale_prima_data_idx
  on public.formazione_corsi (personale_id, prima_data)
  where prima_data is not null;

notify pgrst, 'reload schema';
