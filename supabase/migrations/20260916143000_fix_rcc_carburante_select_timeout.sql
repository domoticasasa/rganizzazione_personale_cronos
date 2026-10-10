-- Fix timeout / insert gasolio (RCC + MDO): InitPlan RLS, secondary_role, indici.

create index if not exists logistica_rcc_carburante_data_idx
  on public.logistica_rcc_carburante (data_rifornimento desc nulls last);

create index if not exists logistica_rcc_carburante_user_data_idx
  on public.logistica_rcc_carburante (user_uuid, data_rifornimento desc nulls last);

create index if not exists logistica_rcc_carburante_dt_data_idx
  on public.logistica_rcc_carburante (dt_user_uuid, data_rifornimento desc nulls last);

create index if not exists logistica_rcc_carburante_mezzo_data_idx
  on public.logistica_rcc_carburante (mezzo_stradale_id_uuid, data_rifornimento desc nulls last);

create index if not exists logistica_rcc_mdo_carburante_data_idx
  on public.logistica_rcc_mdo_carburante (data_rifornimento desc nulls last);

create index if not exists logistica_rcc_mdo_carburante_user_data_idx
  on public.logistica_rcc_mdo_carburante (user_uuid, data_rifornimento desc nulls last);

create index if not exists logistica_rcc_mdo_carburante_dt_data_idx
  on public.logistica_rcc_mdo_carburante (dt_user_uuid, data_rifornimento desc nulls last);

-- ---------------------------------------------------------------------------
-- logistica_rcc_carburante
-- ---------------------------------------------------------------------------
drop policy if exists logistica_rcc_carburante_select_role_allowed
  on public.logistica_rcc_carburante;
create policy logistica_rcc_carburante_select_role_allowed
on public.logistica_rcc_carburante for select to authenticated
using (
  user_uuid = (select public.current_user_uuid())
  or (
    dt_user_uuid = (select public.current_user_uuid())
    and (select public.cronos_is_dt_role())
  )
  or (select public.cronos_has_role(
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_carburante_insert_role_allowed
  on public.logistica_rcc_carburante;
create policy logistica_rcc_carburante_insert_role_allowed
on public.logistica_rcc_carburante for insert to authenticated
with check (
  user_uuid = (select public.current_user_uuid())
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
  or coalesce((select public.has_custom_page_access('logistica_rcc_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_carburante_update_role_allowed
  on public.logistica_rcc_carburante;
create policy logistica_rcc_carburante_update_role_allowed
on public.logistica_rcc_carburante for update to authenticated
using (
  user_uuid = (select public.current_user_uuid())
  or (
    dt_user_uuid = (select public.current_user_uuid())
    and (select public.cronos_is_dt_role())
  )
  or (select public.cronos_has_role(
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
)
with check (
  user_uuid = (select public.current_user_uuid())
  or (
    dt_user_uuid = (select public.current_user_uuid())
    and (select public.cronos_is_dt_role())
  )
  or (select public.cronos_has_role(
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_carburante_delete_role_allowed
  on public.logistica_rcc_carburante;
create policy logistica_rcc_carburante_delete_role_allowed
on public.logistica_rcc_carburante for delete to authenticated
using (
  user_uuid = (select public.current_user_uuid())
  or (
    dt_user_uuid = (select public.current_user_uuid())
    and (select public.cronos_is_dt_role())
  )
  or (select public.cronos_has_role(
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

-- ---------------------------------------------------------------------------
-- logistica_rcc_mdo_carburante
-- ---------------------------------------------------------------------------
drop policy if exists logistica_rcc_mdo_carburante_select_role_allowed
  on public.logistica_rcc_mdo_carburante;
create policy logistica_rcc_mdo_carburante_select_role_allowed
on public.logistica_rcc_mdo_carburante for select to authenticated
using (
  user_uuid = (select public.current_user_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_mdo_carburante_insert_role_allowed
  on public.logistica_rcc_mdo_carburante;
create policy logistica_rcc_mdo_carburante_insert_role_allowed
on public.logistica_rcc_mdo_carburante for insert to authenticated
with check (
  user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica',
    'dipendente',
    'dipendenti',
    'user'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_mdo_carburante_update_role_allowed
  on public.logistica_rcc_mdo_carburante;
create policy logistica_rcc_mdo_carburante_update_role_allowed
on public.logistica_rcc_mdo_carburante for update to authenticated
using (
  user_uuid = (select public.current_user_uuid())
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
  or coalesce((select public.has_custom_page_access('logistica_rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
)
with check (
  user_uuid = (select public.current_user_uuid())
  or dt_user_uuid = (select public.current_user_uuid())
  or (select public.cronos_has_role(
    'dt',
    'assistente_dt',
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_treno_aereo',
    'logistica',
    'dipendente',
    'dipendenti',
    'user'
  ))
  or coalesce((select public.has_custom_page_access('logistica_rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

drop policy if exists logistica_rcc_mdo_carburante_delete_role_allowed
  on public.logistica_rcc_mdo_carburante;
create policy logistica_rcc_mdo_carburante_delete_role_allowed
on public.logistica_rcc_mdo_carburante for delete to authenticated
using (
  user_uuid = (select public.current_user_uuid())
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
  or coalesce((select public.has_custom_page_access('logistica_rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('rcc_mdo_carburante')), false)
  or coalesce((select public.has_custom_page_access('logistica')), false)
);

notify pgrst, 'reload schema';
