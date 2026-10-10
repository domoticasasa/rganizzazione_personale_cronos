-- Completa il lockdown di alert_scadenze_workflow:
-- restavano policy legacy OR-permissive (DT/logistica) che annullavano
-- 20261010180000 (RLS = OR tra policy).

drop policy if exists alert_scadenze_workflow_select_role_allowed
  on public.alert_scadenze_workflow;
drop policy if exists alert_scadenze_workflow_upsert_role_allowed
  on public.alert_scadenze_workflow;
drop policy if exists alert_scadenze_workflow_write
  on public.alert_scadenze_workflow;

notify pgrst, 'reload schema';
