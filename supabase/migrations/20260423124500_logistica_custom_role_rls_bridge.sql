-- Bridge RLS: consente ai ruoli personalizzati con pagina "logistica"
-- di leggere/scrivere le tabelle logistica (e estintori sotto logistica).

create or replace function public.has_custom_page_access(p_page_key text)
returns boolean
language sql
stable
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
  );
$$;

-- ===========================
-- LOGISTICA BOX
-- ===========================
drop policy if exists logistica_box_select_role_allowed on public.logistica_box;
create policy logistica_box_select_role_allowed
on public.logistica_box
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_box_insert_role_allowed on public.logistica_box;
create policy logistica_box_insert_role_allowed
on public.logistica_box
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_box_update_role_allowed on public.logistica_box;
create policy logistica_box_update_role_allowed
on public.logistica_box
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_box_delete_role_allowed on public.logistica_box;
create policy logistica_box_delete_role_allowed
on public.logistica_box
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

-- ===========================
-- LOGISTICA MDO FERROVIARI
-- ===========================
drop policy if exists logistica_mdo_ferroviari_select_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_select_role_allowed
on public.logistica_mdo_ferroviari
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mdo_ferroviari_insert_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_insert_role_allowed
on public.logistica_mdo_ferroviari
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mdo_ferroviari_update_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_update_role_allowed
on public.logistica_mdo_ferroviari
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mdo_ferroviari_delete_role_allowed on public.logistica_mdo_ferroviari;
create policy logistica_mdo_ferroviari_delete_role_allowed
on public.logistica_mdo_ferroviari
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

-- ===========================
-- LOGISTICA CASETTE P.S.
-- ===========================
drop policy if exists logistica_casette_ps_select_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_select_role_allowed
on public.logistica_casette_ps
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_casette_ps_insert_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_insert_role_allowed
on public.logistica_casette_ps
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_casette_ps_update_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_update_role_allowed
on public.logistica_casette_ps
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_casette_ps_delete_role_allowed on public.logistica_casette_ps;
create policy logistica_casette_ps_delete_role_allowed
on public.logistica_casette_ps
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo'
      )
  )
  or public.has_custom_page_access('logistica')
);

-- ===========================
-- ESTINTORI (spostata sotto Logistica)
-- ===========================
drop policy if exists estintori_select_role_allowed on public.estintori;
create policy estintori_select_role_allowed
on public.estintori
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists estintori_insert_role_allowed on public.estintori;
create policy estintori_insert_role_allowed
on public.estintori
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists estintori_update_role_allowed on public.estintori;
create policy estintori_update_role_allowed
on public.estintori
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
);

drop policy if exists estintori_delete_role_allowed on public.estintori;
create policy estintori_delete_role_allowed
on public.estintori
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in ('admin', 'admin_generale', 'dt', 'assistente_dt')
  )
  or public.has_custom_page_access('logistica')
);

