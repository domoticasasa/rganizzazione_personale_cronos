-- Pagina hub: Assegnazione mezzi stradali (catalogo permessi + RLS lettura/scrittura).

insert into public.app_page_registry (page_key, label, active)
values (
  'logistica_assegnazione_mezzi_stradali',
  'Logistica - Assegnazione mezzi stradali',
  true
)
on conflict (page_key) do update
set label = excluded.label,
    active = excluded.active;

drop policy if exists logistica_mezzi_stradali_select_role_allowed
  on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_select_role_allowed
on public.logistica_mezzi_stradali
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
        'admin_trenoaereo',
        'logistica',
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica_assegnazione_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_stradali_insert_role_allowed
  on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_insert_role_allowed
on public.logistica_mezzi_stradali
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
        'admin_trenoaereo',
        'logistica'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica_assegnazione_mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_stradali_update_role_allowed
  on public.logistica_mezzi_stradali;
create policy logistica_mezzi_stradali_update_role_allowed
on public.logistica_mezzi_stradali
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
        'admin_trenoaereo',
        'logistica',
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica_assegnazione_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
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
        'admin_trenoaereo',
        'logistica',
        'dipendente',
        'dipendenti',
        'user'
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('logistica_assegnazione_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);
