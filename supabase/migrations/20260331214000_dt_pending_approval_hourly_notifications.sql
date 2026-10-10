create table if not exists public.dt_pending_approval_hourly_log (
  booking_type text not null check (booking_type in ('treno', 'aereo')),
  booking_id bigint not null,
  dt_user_uuid uuid not null,
  last_notified_at timestamptz not null default now(),
  primary key (booking_type, booking_id, dt_user_uuid)
);

create or replace function public.notify_dt_pending_approvals_hourly()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  dt_user_id integer;
  inserted_count integer := 0;
  tipo_label text;
  data_label text;
begin
  for r in
    with pending as (
      select
        'treno'::text as booking_type,
        bt.id as booking_id,
        bt.assigned_dt_user_uuid as dt_user_uuid,
        bt.start_date as start_date
      from public.bookings_treno bt
      where upper(coalesce(bt.workflow_status, '')) = 'INVIATA_AL_DT'
        and bt.assigned_dt_user_uuid is not null
      union all
      select
        'aereo'::text as booking_type,
        ba.id as booking_id,
        ba.assigned_dt_user_uuid as dt_user_uuid,
        ba.start_date as start_date
      from public.bookings_aereo ba
      where upper(coalesce(ba.workflow_status, '')) = 'INVIATA_AL_DT'
        and ba.assigned_dt_user_uuid is not null
    )
    select
      p.booking_type,
      p.booking_id,
      p.dt_user_uuid,
      p.start_date,
      l.last_notified_at
    from pending p
    left join public.dt_pending_approval_hourly_log l
      on l.booking_type = p.booking_type
     and l.booking_id = p.booking_id
     and l.dt_user_uuid = p.dt_user_uuid
    where l.last_notified_at is null
       or l.last_notified_at <= (now() - interval '1 hour')
  loop
    select u.id
      into dt_user_id
    from public.users u
    where u.id_uuid = r.dt_user_uuid
    limit 1;

    if dt_user_id is null then
      continue;
    end if;

    tipo_label := case when r.booking_type = 'treno' then 'treno' else 'aereo' end;
    data_label := case
      when r.start_date is null then 'N/D'
      else to_char(r.start_date, 'DD/MM/YYYY')
    end;

    insert into public.notifications (user_id, title, message, meta, is_read)
    values (
      dt_user_id,
      'Richiesta da approvare in attesa',
      'Hai una richiesta ' || tipo_label || ' ancora da approvare.' || E'\nData inizio: ' || data_label,
      jsonb_build_object(
        'booking_id', r.booking_id,
        'booking_type', r.booking_type,
        'action', 'dt_pending_hourly'
      ),
      false
    );
    inserted_count := inserted_count + 1;

    insert into public.dt_pending_approval_hourly_log (
      booking_type, booking_id, dt_user_uuid, last_notified_at
    )
    values (r.booking_type, r.booking_id, r.dt_user_uuid, now())
    on conflict (booking_type, booking_id, dt_user_uuid)
    do update set last_notified_at = excluded.last_notified_at;
  end loop;

  return inserted_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
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
