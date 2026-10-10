create table if not exists public.booking_overdue_hourly_log (
  booking_id bigint primary key,
  last_notified_at timestamptz not null default now()
);

create or replace function public.notify_overdue_pernotti_hourly()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  admin_row record;
  inserted_count integer := 0;
  persone_label text;
begin
  for r in
    select
      b.id,
      b.personale_id,
      b.start_date,
      l.last_notified_at
    from public.bookings b
    left join public.booking_overdue_hourly_log l on l.booking_id = b.id
    where upper(coalesce(b.status, '')) = 'IN_ATTESA'
      and b.start_date is not null
      and b.start_date < current_date
      and (
        l.last_notified_at is null
        or l.last_notified_at <= (now() - interval '1 hour')
      )
  loop
    select coalesce(p.full_name, '') into persone_label
    from public.personale p
    where p.id_uuid = r.personale_id
    limit 1;

    for admin_row in
      select u.id
      from public.users u
      where lower(coalesce(u.role, '')) = 'admin_pernottamenti'
    loop
      insert into public.notifications (user_id, title, message, meta, is_read)
      values (
        admin_row.id,
        'Pernottamento scaduto in attesa',
        'Prenotazione ancora IN_ATTESA con inizio pernottamento scaduto'
          || case when persone_label <> '' then E'\nPer: ' || persone_label else '' end
          || E'\nData inizio: ' || to_char(r.start_date, 'DD/MM/YYYY'),
        jsonb_build_object(
          'booking_id', r.id,
          'action', 'overdue_hourly',
          'type', 'pernottamento'
        ),
        false
      );
      inserted_count := inserted_count + 1;
    end loop;

    insert into public.booking_overdue_hourly_log (booking_id, last_notified_at)
    values (r.id, now())
    on conflict (booking_id)
    do update set last_notified_at = excluded.last_notified_at;
  end loop;

  return inserted_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (
      select 1
      from cron.job
      where jobname = 'notify_overdue_pernotti_hourly'
    ) then
      perform cron.unschedule('notify_overdue_pernotti_hourly');
    end if;

    perform cron.schedule(
      'notify_overdue_pernotti_hourly',
      '0 * * * *',
      $job$select public.notify_overdue_pernotti_hourly();$job$
    );
  end if;
end
$$;
