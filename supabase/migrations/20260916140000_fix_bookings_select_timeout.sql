-- Fix timeout SELECT su bookings / bookings_treno / bookings_aereo:
-- 1) indici su dt_user_uuid + data
-- 2) helper staff veloce (solo ruoli) + policy senza OR pesanti su custom pages generiche

create index if not exists bookings_dt_user_uuid_start_date_idx
  on public.bookings (dt_user_uuid, start_date desc nulls last);

create index if not exists bookings_start_date_idx
  on public.bookings (start_date desc nulls last);

create index if not exists bookings_treno_dt_user_uuid_data_idx
  on public.bookings_treno (dt_user_uuid, data desc nulls last);

create index if not exists bookings_treno_data_idx
  on public.bookings_treno (data desc nulls last);

create index if not exists bookings_aereo_dt_user_uuid_data_idx
  on public.bookings_aereo (dt_user_uuid, data desc nulls last);

create index if not exists bookings_aereo_data_idx
  on public.bookings_aereo (data desc nulls last);

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
          'dt',
          'assistente_dt',
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
          'dt',
          'assistente_dt',
          'logistica',
          'uqsa',
          'caposquadra'
        )
      )
  );
$$;

revoke all on function public.cronos_is_staff_reader_fast() from public;
grant execute on function public.cronos_is_staff_reader_fast() to authenticated;

drop policy if exists bookings_select on public.bookings;
create policy bookings_select
on public.bookings for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or dt_user_uuid = public.current_user_uuid()
  or public.cronos_is_staff_reader_fast()
  or coalesce(public.has_custom_page_access('pernottamenti'), false)
);

drop policy if exists bookings_treno_select on public.bookings_treno;
create policy bookings_treno_select
on public.bookings_treno for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or dt_user_uuid = public.current_user_uuid()
  or assigned_dt_user_uuid = public.current_user_uuid()
  or public.cronos_is_staff_reader_fast()
  or coalesce(public.has_custom_page_access('treno_aereo'), false)
  or coalesce(public.has_custom_page_access('treni'), false)
);

drop policy if exists bookings_aereo_select on public.bookings_aereo;
create policy bookings_aereo_select
on public.bookings_aereo for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or dt_user_uuid = public.current_user_uuid()
  or assigned_dt_user_uuid = public.current_user_uuid()
  or public.cronos_is_staff_reader_fast()
  or coalesce(public.has_custom_page_access('treno_aereo'), false)
  or coalesce(public.has_custom_page_access('aerei'), false)
);

notify pgrst, 'reload schema';
