-- I job orari erano assenti su prod (solo cleanup/backup in cron.job).
-- Le funzioni notify_* esistono già; qui le rischeduliamo.
-- Vault secret `service_role_key` va creato una tantum (non in migration).

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1 from cron.job where jobname = 'notify_overdue_pernotti_hourly'
    ) then
      perform cron.unschedule('notify_overdue_pernotti_hourly');
    end if;
    perform cron.schedule(
      'notify_overdue_pernotti_hourly',
      '0 * * * *',
      $job$select public.notify_overdue_pernotti_hourly();$job$
    );

    if exists (
      select 1 from cron.job where jobname = 'notify_dt_pending_approvals_hourly'
    ) then
      perform cron.unschedule('notify_dt_pending_approvals_hourly');
    end if;
    perform cron.schedule(
      'notify_dt_pending_approvals_hourly',
      '5 * * * *',
      $job$select public.notify_dt_pending_approvals_hourly();$job$
    );
  end if;
end
$$;
