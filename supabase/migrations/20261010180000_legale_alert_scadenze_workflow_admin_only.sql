-- Audit legale A3 (10/10/2026): alert_scadenze_workflow era leggibile e
-- modificabile da qualsiasi utente autenticato ("using (true)").
-- Ora: lettura solo ruoli admin (incluso admin_vista), scrittura solo admin
-- con permessi di modifica (public.is_cronos_admin_role()).
-- NON applicato automaticamente: vedi CHECKLIST_modifiche_legali.md

create or replace function public.is_cronos_any_admin_role()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_cronos_admin_role() or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(replace(replace(coalesce(u.role, ''), ' ', '_'), '/', '_')) in (
        'admin_vista', 'admin_readonly', 'admin_sola_lettura', 'admin_sola_vista'
      )
  );
$$;

alter table public.alert_scadenze_workflow enable row level security;

drop policy if exists alert_scadenze_workflow_select on public.alert_scadenze_workflow;
create policy alert_scadenze_workflow_select
  on public.alert_scadenze_workflow
  for select
  to authenticated
  using (public.is_cronos_any_admin_role());

drop policy if exists alert_scadenze_workflow_write on public.alert_scadenze_workflow;
drop policy if exists alert_scadenze_workflow_insert on public.alert_scadenze_workflow;
drop policy if exists alert_scadenze_workflow_update on public.alert_scadenze_workflow;
drop policy if exists alert_scadenze_workflow_delete on public.alert_scadenze_workflow;

create policy alert_scadenze_workflow_insert
  on public.alert_scadenze_workflow
  for insert
  to authenticated
  with check (public.is_cronos_admin_role());

create policy alert_scadenze_workflow_update
  on public.alert_scadenze_workflow
  for update
  to authenticated
  using (public.is_cronos_admin_role())
  with check (public.is_cronos_admin_role());

create policy alert_scadenze_workflow_delete
  on public.alert_scadenze_workflow
  for delete
  to authenticated
  using (public.is_cronos_admin_role());

revoke all on public.alert_scadenze_workflow from anon;

notify pgrst, 'reload schema';
