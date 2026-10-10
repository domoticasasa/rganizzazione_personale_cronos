-- =============================================================================
-- RLS: abilita policy sulle tabelle public ancora senza RLS + helper ruoli.
-- Ruoli: dipendente (solo propri dati), DT/assistente (lettura ampia + write
-- mirata su treno/aereo), admin (scrittura), admin_vista (sola lettura).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.cronos_norm_role(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(replace(replace(coalesce(p, ''), ' ', '_'), '/', '_'));
$$;

create or replace function public.cronos_has_role(variadic p_roles text[])
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
        public.cronos_norm_role(u.role) = any (
          select public.cronos_norm_role(x) from unnest(p_roles) as t(x)
        )
        or public.cronos_norm_role(u.secondary_role) = any (
          select public.cronos_norm_role(x) from unnest(p_roles) as t(x)
        )
      )
  );
$$;

-- Lettura staff: admin* (incluso admin_vista), DT, logistica, uqsa, custom pages.
create or replace function public.cronos_is_staff_reader()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cronos_has_role(
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
  or coalesce(public.has_custom_page_access('logistica'), false)
  or coalesce(public.has_custom_page_access('uqsa'), false)
  or coalesce(public.has_custom_page_access('dpi'), false)
  or coalesce(public.has_custom_page_access('formazione'), false)
  or coalesce(public.has_custom_page_access('pernottamenti'), false)
  or coalesce(public.has_custom_page_access('treno_aereo'), false);
$$;

-- Scrittura: come staff reader ma SENZA admin_vista.
create or replace function public.cronos_is_staff_writer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cronos_has_role(
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'admin_formazione',
    'admin_dpi',
    'logistica',
    'uqsa',
    'caposquadra'
  )
  or coalesce(public.has_custom_page_access('logistica'), false)
  or coalesce(public.has_custom_page_access('uqsa'), false)
  or coalesce(public.has_custom_page_access('dpi'), false)
  or coalesce(public.has_custom_page_access('formazione'), false)
  or coalesce(public.has_custom_page_access('pernottamenti'), false)
  or coalesce(public.has_custom_page_access('treno_aereo'), false);
$$;

create or replace function public.cronos_is_admin_writer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cronos_has_role(
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'admin_formazione',
    'admin_dpi'
  );
$$;

create or replace function public.cronos_is_dt_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cronos_has_role('dt', 'assistente_dt');
$$;

create or replace function public.cronos_my_personale_uuid()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id_uuid
  from public.personale p
  where public.personale_belongs_to_current_auth(p)
  order by coalesce(p.active, true) desc, p.id desc
  limit 1;
$$;

create or replace function public.cronos_my_personale_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.personale p
  where public.personale_belongs_to_current_auth(p)
  order by coalesce(p.active, true) desc, p.id desc
  limit 1;
$$;

-- Evita fallimenti quando users ha RLS: la funzione legge users in definer.
create or replace function public.has_custom_page_access(p_page_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    join public.app_custom_roles acr
      on lower(acr.role_key) = lower(coalesce(u.role, ''))
     and acr.active = true
    join public.app_custom_role_pages arp
      on lower(arp.role_key) = lower(acr.role_key)
     and lower(arp.page_key) = lower(p_page_key)
     and arp.can_view = true
    where u.auth_id = auth.uid()
  )
  or exists (
    select 1
    from public.users u
    join public.app_custom_roles acr
      on lower(acr.role_key) = lower(coalesce(u.secondary_role, ''))
     and acr.active = true
    join public.app_custom_role_pages arp
      on lower(arp.role_key) = lower(acr.role_key)
     and lower(arp.page_key) = lower(p_page_key)
     and arp.can_view = true
    where u.auth_id = auth.uid()
  );
$$;

revoke all on function public.cronos_norm_role(text) from public;
revoke all on function public.cronos_has_role(text[]) from public;
revoke all on function public.cronos_is_staff_reader() from public;
revoke all on function public.cronos_is_staff_writer() from public;
revoke all on function public.cronos_is_admin_writer() from public;
revoke all on function public.cronos_is_dt_role() from public;
revoke all on function public.cronos_my_personale_uuid() from public;
revoke all on function public.cronos_my_personale_id() from public;

grant execute on function public.cronos_norm_role(text) to authenticated;
grant execute on function public.cronos_has_role(text[]) to authenticated;
grant execute on function public.cronos_is_staff_reader() to authenticated;
grant execute on function public.cronos_is_staff_writer() to authenticated;
grant execute on function public.cronos_is_admin_writer() to authenticated;
grant execute on function public.cronos_is_dt_role() to authenticated;
grant execute on function public.cronos_my_personale_uuid() to authenticated;
grant execute on function public.cronos_my_personale_id() to authenticated;
grant execute on function public.has_custom_page_access(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Macro: applica SELECT staff / WRITE staff / DENY anon pattern
-- ---------------------------------------------------------------------------

-- USERS
alter table public.users enable row level security;

drop policy if exists users_select_self_or_staff on public.users;
create policy users_select_self_or_staff
on public.users for select to authenticated
using (
  auth_id = auth.uid()
  or public.cronos_is_staff_reader()
);

drop policy if exists users_update_self_or_admin on public.users;
create policy users_update_self_or_admin
on public.users for update to authenticated
using (
  auth_id = auth.uid()
  or public.cronos_is_admin_writer()
)
with check (
  auth_id = auth.uid()
  or public.cronos_is_admin_writer()
);

drop policy if exists users_insert_admin on public.users;
create policy users_insert_admin
on public.users for insert to authenticated
with check (public.cronos_is_admin_writer());

drop policy if exists users_delete_admin on public.users;
create policy users_delete_admin
on public.users for delete to authenticated
using (public.cronos_is_admin_writer());

-- PERSONALE
alter table public.personale enable row level security;

drop policy if exists personale_select_own_or_staff on public.personale;
create policy personale_select_own_or_staff
on public.personale for select to authenticated
using (
  public.personale_belongs_to_current_auth(personale)
  or public.cronos_is_staff_reader()
);

drop policy if exists personale_update_own_or_writer on public.personale;
create policy personale_update_own_or_writer
on public.personale for update to authenticated
using (
  public.personale_belongs_to_current_auth(personale)
  or public.cronos_is_staff_writer()
)
with check (
  public.personale_belongs_to_current_auth(personale)
  or public.cronos_is_staff_writer()
);

drop policy if exists personale_insert_writer on public.personale;
create policy personale_insert_writer
on public.personale for insert to authenticated
with check (public.cronos_is_staff_writer());

drop policy if exists personale_delete_admin on public.personale;
create policy personale_delete_admin
on public.personale for delete to authenticated
using (public.cronos_is_admin_writer());

-- PERSONALE_TAGLIE
alter table public.personale_taglie enable row level security;

drop policy if exists personale_taglie_select on public.personale_taglie;
create policy personale_taglie_select
on public.personale_taglie for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_reader()
);

drop policy if exists personale_taglie_upsert on public.personale_taglie;
create policy personale_taglie_upsert
on public.personale_taglie for insert to authenticated
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists personale_taglie_update on public.personale_taglie;
create policy personale_taglie_update
on public.personale_taglie for update to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
)
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists personale_taglie_delete on public.personale_taglie;
create policy personale_taglie_delete
on public.personale_taglie for delete to authenticated
using (public.cronos_is_staff_writer());

-- BOOKINGS (pernotti)
alter table public.bookings enable row level security;

drop policy if exists bookings_select on public.bookings;
create policy bookings_select
on public.bookings for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_reader()
);

drop policy if exists bookings_insert on public.bookings;
create policy bookings_insert
on public.bookings for insert to authenticated
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_update on public.bookings;
create policy bookings_update
on public.bookings for update to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
)
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_delete on public.bookings;
create policy bookings_delete
on public.bookings for delete to authenticated
using (public.cronos_is_staff_writer());

-- BOOKINGS_AEREO / BOOKINGS_TRENO
alter table public.bookings_aereo enable row level security;
alter table public.bookings_treno enable row level security;

drop policy if exists bookings_aereo_select on public.bookings_aereo;
create policy bookings_aereo_select
on public.bookings_aereo for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or assigned_dt_user_uuid = public.current_user_uuid()
  or public.cronos_is_staff_reader()
);

drop policy if exists bookings_aereo_insert on public.bookings_aereo;
create policy bookings_aereo_insert
on public.bookings_aereo for insert to authenticated
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_aereo_update on public.bookings_aereo;
create policy bookings_aereo_update
on public.bookings_aereo for update to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or (
    public.cronos_is_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
  )
  or public.cronos_is_staff_writer()
)
with check (
  personale_id = public.cronos_my_personale_uuid()
  or (
    public.cronos_is_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
  )
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_aereo_delete on public.bookings_aereo;
create policy bookings_aereo_delete
on public.bookings_aereo for delete to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_treno_select on public.bookings_treno;
create policy bookings_treno_select
on public.bookings_treno for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or assigned_dt_user_uuid = public.current_user_uuid()
  or public.cronos_is_staff_reader()
);

drop policy if exists bookings_treno_insert on public.bookings_treno;
create policy bookings_treno_insert
on public.bookings_treno for insert to authenticated
with check (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_treno_update on public.bookings_treno;
create policy bookings_treno_update
on public.bookings_treno for update to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or (
    public.cronos_is_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
  )
  or public.cronos_is_staff_writer()
)
with check (
  personale_id = public.cronos_my_personale_uuid()
  or (
    public.cronos_is_dt_role()
    and assigned_dt_user_uuid = public.current_user_uuid()
  )
  or public.cronos_is_staff_writer()
);

drop policy if exists bookings_treno_delete on public.bookings_treno;
create policy bookings_treno_delete
on public.bookings_treno for delete to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_writer()
);

-- COMMESSE + lookup
alter table public.commesse enable row level security;
alter table public.structures enable row level security;
alter table public.stazioni enable row level security;
alter table public.aeroporti enable row level security;

drop policy if exists commesse_select_auth on public.commesse;
create policy commesse_select_auth
on public.commesse for select to authenticated
using (true);

drop policy if exists commesse_write_admin on public.commesse;
create policy commesse_write_admin
on public.commesse for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

drop policy if exists structures_select_auth on public.structures;
create policy structures_select_auth
on public.structures for select to authenticated
using (true);

drop policy if exists structures_write_admin on public.structures;
create policy structures_write_admin
on public.structures for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

drop policy if exists stazioni_select_auth on public.stazioni;
create policy stazioni_select_auth
on public.stazioni for select to authenticated
using (true);

drop policy if exists stazioni_write_admin on public.stazioni;
create policy stazioni_write_admin
on public.stazioni for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

drop policy if exists aeroporti_select_auth on public.aeroporti;
create policy aeroporti_select_auth
on public.aeroporti for select to authenticated
using (true);

drop policy if exists aeroporti_write_admin on public.aeroporti;
create policy aeroporti_write_admin
on public.aeroporti for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

-- FORMAZIONE
alter table public.formazioni enable row level security;
alter table public.formazione_rfi_corsi enable row level security;
alter table public.formazione_rfi_records enable row level security;

drop policy if exists formazioni_select on public.formazioni;
create policy formazioni_select
on public.formazioni for select to authenticated
using (
  utente_id = coalesce(public.current_user_uuid()::text, '')
  or utente_id = coalesce(public.cronos_my_personale_uuid()::text, '')
  or utente_id = coalesce(public.cronos_my_personale_id()::text, '')
  or public.cronos_is_staff_reader()
);

drop policy if exists formazioni_write on public.formazioni;
create policy formazioni_write
on public.formazioni for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists formazione_rfi_corsi_select on public.formazione_rfi_corsi;
create policy formazione_rfi_corsi_select
on public.formazione_rfi_corsi for select to authenticated
using (true);

drop policy if exists formazione_rfi_corsi_write on public.formazione_rfi_corsi;
create policy formazione_rfi_corsi_write
on public.formazione_rfi_corsi for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists formazione_rfi_records_select on public.formazione_rfi_records;
create policy formazione_rfi_records_select
on public.formazione_rfi_records for select to authenticated
using (
  personale_id = public.cronos_my_personale_id()
  or public.cronos_is_staff_reader()
);

drop policy if exists formazione_rfi_records_write on public.formazione_rfi_records;
create policy formazione_rfi_records_write
on public.formazione_rfi_records for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

-- DPI / VESTIARIO
alter table public.dpi_categories enable row level security;
alter table public.dpi_dotazioni enable row level security;
alter table public.vestiario_dotazioni enable row level security;
alter table public.vestiario_fabbisogno_annuo_config enable row level security;

drop policy if exists dpi_categories_select on public.dpi_categories;
create policy dpi_categories_select
on public.dpi_categories for select to authenticated
using (true);

drop policy if exists dpi_categories_write on public.dpi_categories;
create policy dpi_categories_write
on public.dpi_categories for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists dpi_dotazioni_select on public.dpi_dotazioni;
create policy dpi_dotazioni_select
on public.dpi_dotazioni for select to authenticated
using (
  personale_id = public.cronos_my_personale_uuid()
  or public.cronos_is_staff_reader()
);

drop policy if exists dpi_dotazioni_write on public.dpi_dotazioni;
create policy dpi_dotazioni_write
on public.dpi_dotazioni for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists vestiario_dotazioni_select on public.vestiario_dotazioni;
create policy vestiario_dotazioni_select
on public.vestiario_dotazioni for select to authenticated
using (public.cronos_is_staff_reader());

drop policy if exists vestiario_dotazioni_write on public.vestiario_dotazioni;
create policy vestiario_dotazioni_write
on public.vestiario_dotazioni for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists vestiario_fabbisogno_select on public.vestiario_fabbisogno_annuo_config;
create policy vestiario_fabbisogno_select
on public.vestiario_fabbisogno_annuo_config for select to authenticated
using (public.cronos_is_staff_reader());

drop policy if exists vestiario_fabbisogno_write on public.vestiario_fabbisogno_annuo_config;
create policy vestiario_fabbisogno_write
on public.vestiario_fabbisogno_annuo_config for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

-- Tabelle log / job / channel: niente accesso client autenticato (cron SECURITY DEFINER ok)
alter table public.logs enable row level security;
alter table public.job_codes enable row level security;
alter table public.windows_channels enable row level security;
alter table public.booking_overdue_hourly_log enable row level security;
alter table public.dt_pending_approval_hourly_log enable row level security;
alter table public.logistica_mezzi_km_reminder_log enable row level security;

drop policy if exists logs_admin_select on public.logs;
create policy logs_admin_select
on public.logs for select to authenticated
using (public.cronos_is_admin_writer());

drop policy if exists job_codes_admin_all on public.job_codes;
create policy job_codes_admin_all
on public.job_codes for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

drop policy if exists windows_channels_admin_all on public.windows_channels;
create policy windows_channels_admin_all
on public.windows_channels for all to authenticated
using (public.cronos_is_admin_writer())
with check (public.cronos_is_admin_writer());

-- reminder logs: nessun policy authenticated → deny client; definer/cron ok

-- ---------------------------------------------------------------------------
-- Indurisci policy troppo permissive (USING true) su viaggio_stradale_*
-- ---------------------------------------------------------------------------
drop policy if exists viaggio_stradale_settings_all on public.viaggio_stradale_settings;
create policy viaggio_stradale_settings_select
on public.viaggio_stradale_settings for select to authenticated
using (true);
create policy viaggio_stradale_settings_write
on public.viaggio_stradale_settings for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

drop policy if exists viaggio_stradale_tratte_all on public.viaggio_stradale_tratte;
create policy viaggio_stradale_tratte_select
on public.viaggio_stradale_tratte for select to authenticated
using (true);
create policy viaggio_stradale_tratte_write
on public.viaggio_stradale_tratte for all to authenticated
using (public.cronos_is_staff_writer())
with check (public.cronos_is_staff_writer());

notify pgrst, 'reload schema';
