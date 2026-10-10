-- Cron SQL: dopo insert in-app, invoca anche Web Push (tab/app web chiusa).
-- Richiede vault secret `service_role_key` (JWT service_role Supabase).

create or replace function public.invoke_admin_send_push(
  p_user_ids integer[],
  p_title text,
  p_message text,
  p_booking_id bigint,
  p_action text,
  p_booking_type text default null
)
returns bigint
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  v_key text;
  v_url text;
  v_request_id bigint;
  v_body jsonb;
begin
  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    return 0;
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net non disponibile: skip invoke_admin_send_push';
    return 0;
  end if;

  begin
    select ds.decrypted_secret
      into v_key
    from vault.decrypted_secrets ds
    where ds.name = 'service_role_key'
    limit 1;
  exception when others then
    v_key := null;
  end;

  if coalesce(trim(v_key), '') = '' then
    raise notice
      'Vault secret service_role_key assente: cron inserisce in-app ma non Web Push a tab chiusa.';
    return 0;
  end if;

  v_url := 'https://bjdimalvbdablzoctrsf.supabase.co/functions/v1/admin-send-notification';
  v_body := jsonb_build_object(
    'user_ids', to_jsonb(p_user_ids),
    'booking_id', p_booking_id,
    'title', p_title,
    'message', p_message,
    'action', p_action,
    'push_only', true
  );
  if coalesce(trim(p_booking_type), '') <> '' then
    v_body := v_body || jsonb_build_object('booking_type', p_booking_type);
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key,
      'apikey', v_key
    ),
    body := v_body,
    timeout_milliseconds := 15000
  )
  into v_request_id;

  return coalesce(v_request_id, 0);
end;
$$;

comment on function public.invoke_admin_send_push(integer[], text, text, bigint, text, text) is
  'Chiama admin-send-notification con push_only=true (FCM+Web Push, no insert DB). Vault: service_role_key.';

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
          'type', 'pernottamento'
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
        'action', 'dt_pending_hourly'
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
