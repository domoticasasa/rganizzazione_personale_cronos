-- Fix INSERT bookings / treno / aereo: DT e assistente devono poter creare
-- prenotazioni per altri (personale_id != self). Aggiunge anche InitPlan.

drop policy if exists bookings_insert on public.bookings;
create policy bookings_insert
on public.bookings for insert to authenticated
with check (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or (select public.cronos_is_staff_writer())
  or coalesce((select public.has_custom_page_access('pernottamenti')), false)
);

-- Assistente DT: deve poter leggere le righe appena inserite (RETURNING)
-- anche se dt_user_uuid e' del DT assegnato, non il proprio.
drop policy if exists bookings_select on public.bookings;
create policy bookings_select
on public.bookings for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role('assistente_dt'))
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('pernottamenti')), false)
);

drop policy if exists bookings_update on public.bookings;
create policy bookings_update
on public.bookings for update to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or (select public.cronos_is_staff_writer())
  or coalesce((select public.has_custom_page_access('pernottamenti')), false)
)
with check (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or (select public.cronos_is_staff_writer())
  or coalesce((select public.has_custom_page_access('pernottamenti')), false)
);

drop policy if exists bookings_treno_insert on public.bookings_treno;
create policy bookings_treno_insert
on public.bookings_treno for insert to authenticated
with check (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or (select public.cronos_is_staff_writer())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('treni')), false)
);

drop policy if exists bookings_treno_select on public.bookings_treno;
create policy bookings_treno_select
on public.bookings_treno for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role('assistente_dt'))
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('treni')), false)
);

drop policy if exists bookings_aereo_insert on public.bookings_aereo;
create policy bookings_aereo_insert
on public.bookings_aereo for insert to authenticated
with check (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or (select public.cronos_is_staff_writer())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('aerei')), false)
);

drop policy if exists bookings_aereo_select on public.bookings_aereo;
create policy bookings_aereo_select
on public.bookings_aereo for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role('assistente_dt'))
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('aerei')), false)
);

notify pgrst, 'reload schema';
