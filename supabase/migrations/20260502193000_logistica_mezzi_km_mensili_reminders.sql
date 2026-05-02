create table if not exists public.logistica_mezzi_km_mensili (
  id_uuid uuid primary key default gen_random_uuid(),
  mezzo_id_uuid uuid not null references public.logistica_mezzi_stradali(id_uuid) on delete cascade,
  user_uuid uuid not null references public.users(id_uuid) on delete cascade,
  mese_riferimento date not null,
  km_inseriti integer not null check (km_inseriti >= 0),
  data_inserimento timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  unique (mezzo_id_uuid, user_uuid, mese_riferimento)
);

create index if not exists logistica_mezzi_km_mensili_mezzo_idx
  on public.logistica_mezzi_km_mensili(mezzo_id_uuid);
create index if not exists logistica_mezzi_km_mensili_user_month_idx
  on public.logistica_mezzi_km_mensili(user_uuid, mese_riferimento);

create table if not exists public.logistica_mezzi_km_reminder_log (
  user_uuid uuid not null references public.users(id_uuid) on delete cascade,
  mese_riferimento date not null,
  reminder_date date not null,
  reminder_slot text not null,
  created_at timestamptz not null default now(),
  primary key (user_uuid, mese_riferimento, reminder_date, reminder_slot)
);

create or replace function public.set_logistica_mezzi_km_mensili_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid
    into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid = coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_km_mensili_audit_fields on public.logistica_mezzi_km_mensili;
create trigger trg_logistica_mezzi_km_mensili_audit_fields
before insert or update on public.logistica_mezzi_km_mensili
for each row execute function public.set_logistica_mezzi_km_mensili_audit_fields();

alter table public.logistica_mezzi_km_mensili enable row level security;

drop policy if exists logistica_mezzi_km_mensili_select_role_allowed on public.logistica_mezzi_km_mensili;
create policy logistica_mezzi_km_mensili_select_role_allowed
on public.logistica_mezzi_km_mensili
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        lower(coalesce(u.role, '')) in (
          'dt',
          'assistente_dt',
          'admin',
          'admin_generale',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'logistica'
        )
        or u.id_uuid = user_uuid
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_km_mensili_insert_role_allowed on public.logistica_mezzi_km_mensili;
create policy logistica_mezzi_km_mensili_insert_role_allowed
on public.logistica_mezzi_km_mensili
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        lower(coalesce(u.role, '')) in (
          'dt',
          'assistente_dt',
          'admin',
          'admin_generale',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'logistica'
        )
        or u.id_uuid = user_uuid
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

drop policy if exists logistica_mezzi_km_mensili_update_role_allowed on public.logistica_mezzi_km_mensili;
create policy logistica_mezzi_km_mensili_update_role_allowed
on public.logistica_mezzi_km_mensili
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        lower(coalesce(u.role, '')) in (
          'dt',
          'assistente_dt',
          'admin',
          'admin_generale',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'logistica'
        )
        or u.id_uuid = user_uuid
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        lower(coalesce(u.role, '')) in (
          'dt',
          'assistente_dt',
          'admin',
          'admin_generale',
          'admin_pernottamenti',
          'admin_trenoaereo',
          'logistica'
        )
        or u.id_uuid = user_uuid
      )
  )
  or public.has_custom_page_access('logistica_mezzi_stradali')
  or public.has_custom_page_access('mezzi_stradali')
  or public.has_custom_page_access('logistica')
);

create or replace function public.notify_mezzi_km_missing_for_slot(slot_key text default 'manual')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_month_start date := date_trunc('month', current_date)::date;
  v_slot text := coalesce(nullif(trim(slot_key), ''), 'manual');
  r record;
  inserted_count integer := 0;
  pending_list text;
begin
  if extract(day from current_date) <= 1 then
    return 0;
  end if;

  for r in
    with pending as (
      select
        lms.assegnatario_user_uuid as user_uuid,
        lms.id_uuid as mezzo_uuid,
        coalesce(nullif(trim(lms.targa), ''), 'Senza targa') as targa
      from public.logistica_mezzi_stradali lms
      where lms.active = true
        and lms.assegnatario_user_uuid is not null
        and not exists (
          select 1
          from public.logistica_mezzi_km_mensili km
          where km.mezzo_id_uuid = lms.id_uuid
            and km.user_uuid = lms.assegnatario_user_uuid
            and km.mese_riferimento = v_month_start
        )
    )
    select
      p.user_uuid,
      u.id as user_id,
      count(*) as pending_count
    from pending p
    join public.users u on u.id_uuid = p.user_uuid
    group by p.user_uuid, u.id
  loop
    if exists (
      select 1
      from public.logistica_mezzi_km_reminder_log lg
      where lg.user_uuid = r.user_uuid
        and lg.mese_riferimento = v_month_start
        and lg.reminder_date = current_date
        and lg.reminder_slot = v_slot
    ) then
      continue;
    end if;

    select string_agg(x.targa, ', ' order by x.targa)
      into pending_list
    from (
      select
        coalesce(nullif(trim(lms.targa), ''), 'Senza targa') as targa
      from public.logistica_mezzi_stradali lms
      where lms.active = true
        and lms.assegnatario_user_uuid = r.user_uuid
        and not exists (
          select 1
          from public.logistica_mezzi_km_mensili km
          where km.mezzo_id_uuid = lms.id_uuid
            and km.user_uuid = r.user_uuid
            and km.mese_riferimento = v_month_start
        )
      order by 1
      limit 5
    ) x;

    insert into public.notifications (user_id, title, message, meta, is_read)
    values (
      r.user_id,
      'Inserimento km mezzi richiesto',
      'Devi inserire i km mensili per i mezzi a te assegnati (' || r.pending_count || ').'
        || case when coalesce(pending_list, '') <> '' then E'\nMezzi: ' || pending_list else '' end,
      jsonb_build_object(
        'action', 'mezzi_km_monthly_reminder',
        'slot', v_slot,
        'mese_riferimento', v_month_start
      ),
      false
    );
    inserted_count := inserted_count + 1;

    insert into public.logistica_mezzi_km_reminder_log (
      user_uuid, mese_riferimento, reminder_date, reminder_slot, created_at
    )
    values (
      r.user_uuid, v_month_start, current_date, v_slot, v_now
    )
    on conflict (user_uuid, mese_riferimento, reminder_date, reminder_slot) do nothing;
  end loop;

  return inserted_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'notify_mezzi_km_missing_0800') then
      perform cron.unschedule('notify_mezzi_km_missing_0800');
    end if;
    if exists (select 1 from cron.job where jobname = 'notify_mezzi_km_missing_1150') then
      perform cron.unschedule('notify_mezzi_km_missing_1150');
    end if;
    if exists (select 1 from cron.job where jobname = 'notify_mezzi_km_missing_1400') then
      perform cron.unschedule('notify_mezzi_km_missing_1400');
    end if;
    if exists (select 1 from cron.job where jobname = 'notify_mezzi_km_missing_1630') then
      perform cron.unschedule('notify_mezzi_km_missing_1630');
    end if;

    perform cron.schedule(
      'notify_mezzi_km_missing_0800',
      '0 8 * * *',
      $job$select public.notify_mezzi_km_missing_for_slot('08:00');$job$
    );
    perform cron.schedule(
      'notify_mezzi_km_missing_1150',
      '50 11 * * *',
      $job$select public.notify_mezzi_km_missing_for_slot('11:50');$job$
    );
    perform cron.schedule(
      'notify_mezzi_km_missing_1400',
      '0 14 * * *',
      $job$select public.notify_mezzi_km_missing_for_slot('14:00');$job$
    );
    perform cron.schedule(
      'notify_mezzi_km_missing_1630',
      '30 16 * * *',
      $job$select public.notify_mezzi_km_missing_for_slot('16:30');$job$
    );
  end if;
end
$$;
