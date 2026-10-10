-- Follow-up timeout bookings: InitPlan wrap + DT non più global reader + indici personale

create index if not exists bookings_personale_id_start_date_idx
  on public.bookings (personale_id, start_date desc nulls last);

create index if not exists bookings_treno_personale_id_data_idx
  on public.bookings_treno (personale_id, data desc nulls last);

create index if not exists bookings_aereo_personale_id_data_idx
  on public.bookings_aereo (personale_id, data desc nulls last);

-- Staff "globale" senza DT/assistente: i DT vedono solo ownership columns
create or replace function public.cronos_is_staff_reader_fast()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        public.cronos_norm_role(u.role) in (
          'admin',
          'admin_generale',
          'admin_vista',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'admin_treno_aereo',
          'admin_formazione',
          'admin_dpi',
          'logistica',
          'uqsa',
          'caposquadra'
        )
        or public.cronos_norm_role(coalesce(u.secondary_role, '')) in (
          'admin',
          'admin_generale',
          'admin_vista',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'admin_treno_aereo',
          'admin_formazione',
          'admin_dpi',
          'logistica',
          'uqsa',
          'caposquadra'
        )
      )
  );
$$;

drop policy if exists bookings_select on public.bookings;
create policy bookings_select
on public.bookings for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('pernottamenti')), false)
);

drop policy if exists bookings_treno_select on public.bookings_treno;
create policy bookings_treno_select
on public.bookings_treno for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('treni')), false)
);

drop policy if exists bookings_aereo_select on public.bookings_aereo;
create policy bookings_aereo_select
on public.bookings_aereo for select to authenticated
using (
  personale_id = (select public.cronos_my_personale_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or assigned_dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_is_staff_reader_fast())
  or coalesce((select public.has_custom_page_access('treno_aereo')), false)
  or coalesce((select public.has_custom_page_access('aerei')), false)
);

notify pgrst, 'reload schema';
