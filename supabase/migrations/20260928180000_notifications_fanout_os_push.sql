-- Fan-out Web Push/FCM a ogni insert in-app che NON ha già l'OS push
-- (admin-send-notification imposta meta.skip_os_push). Serve a tab/PWA chiusa.

create or replace function public.notifications_fanout_os_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking bigint := 1;
  v_action text;
  v_type text;
  v_skip text;
begin
  v_skip := lower(coalesce(new.meta->>'skip_os_push', ''));
  if v_skip in ('true', '1', 't', 'yes') then
    return new;
  end if;

  v_type := lower(coalesce(nullif(trim(new.meta->>'type'), ''), ''));
  if v_type in ('doc_firma_otp', 'otp') then
    return new;
  end if;

  begin
    v_booking := nullif(trim(new.meta->>'booking_id'), '')::bigint;
  exception when others then
    v_booking := 1;
  end;
  if v_booking is null or v_booking <= 0 then
    v_booking := 1;
  end if;

  v_action := coalesce(nullif(trim(new.meta->>'action'), ''), 'in_app');

  perform public.invoke_admin_send_push(
    array[new.user_id::integer],
    coalesce(nullif(trim(new.title), ''), 'Cronos'),
    coalesce(new.message, ''),
    v_booking,
    v_action,
    nullif(trim(new.meta->>'type'), '')
  );
  return new;
exception
  when others then
    raise warning 'notifications_fanout_os_push: %', sqlerrm;
    return new;
end;
$$;

comment on function public.notifications_fanout_os_push() is
  'Dopo insert su notifications, invoca Web Push/FCM (push_only) se meta.skip_os_push non è true.';

drop trigger if exists trg_notifications_fanout_os_push on public.notifications;
create trigger trg_notifications_fanout_os_push
after insert on public.notifications
for each row
execute function public.notifications_fanout_os_push();

-- Cron orari: già chiamano invoke_admin_send_push dopo l'insert.
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
  v_title text;
  v_message text;
  v_admin_ids integer[];
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

    v_title := 'Pernottamento scaduto in attesa';
    v_message := 'Prenotazione ancora IN_ATTESA con inizio pernottamento scaduto'
      || case when persone_label <> '' then E'\nPer: ' || persone_label else '' end
      || E'\nData inizio: ' || to_char(r.start_date, 'DD/MM/YYYY');

    v_admin_ids := array[]::integer[];
    for admin_row in
      select u.id
      from public.users u
      where lower(coalesce(u.role, '')) = 'admin_pernottamenti'
    loop
      insert into public.notifications (user_id, title, message, meta, is_read)
      values (
        admin_row.id,
        v_title,
        v_message,
        jsonb_build_object(
          'booking_id', r.id,
          'action', 'overdue_hourly',
          'type', 'pernottamento',
          'skip_os_push', true
        ),
        false
      );
      v_admin_ids := array_append(v_admin_ids, admin_row.id);
      inserted_count := inserted_count + 1;
    end loop;

    if cardinality(v_admin_ids) > 0 then
      perform public.invoke_admin_send_push(
        v_admin_ids,
        v_title,
        v_message,
        r.id,
        'overdue_hourly',
        'pernottamento'
      );
    end if;

    insert into public.booking_overdue_hourly_log (booking_id, last_notified_at)
    values (r.id, now())
    on conflict (booking_id)
    do update set last_notified_at = excluded.last_notified_at;
  end loop;

  return inserted_count;
end;
$$;

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
  v_title text;
  v_message text;
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

    v_title := 'Richiesta da approvare in attesa';
    v_message := 'Hai una richiesta ' || tipo_label || ' ancora da approvare.'
      || E'\nData inizio: ' || data_label;

    insert into public.notifications (user_id, title, message, meta, is_read)
    values (
      dt_user_id,
      v_title,
      v_message,
      jsonb_build_object(
        'booking_id', r.booking_id,
        'booking_type', r.booking_type,
        'action', 'dt_pending_hourly',
        'skip_os_push', true
      ),
      false
    );
    inserted_count := inserted_count + 1;

    perform public.invoke_admin_send_push(
      array[dt_user_id],
      v_title,
      v_message,
      r.booking_id,
      'dt_pending_hourly',
      r.booking_type
    );

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

create or replace function public.doc_firma_notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select b.title into v_title
  from public.doc_firma_batches b
  where b.id = new.batch_id;

  insert into public.notifications (user_id, title, message, meta, is_read)
  values (
    new.recipient_user_id,
    'Documento da firmare',
    format(
      'Hai ricevuto «%s». Hai 3 giorni per firmarlo (OTP via email).',
      coalesce(nullif(trim(v_title), ''), 'documento')
    ),
    jsonb_build_object(
      'type', 'doc_firma',
      'batch_id', new.batch_id,
      'assignment_id', new.id,
      'action', 'assigned',
      'skip_os_push', true
    ),
    false
  );

  return new;
exception
  when others then
    raise warning 'doc_firma_notify_assignment: %', sqlerrm;
    return new;
end;
$$;
