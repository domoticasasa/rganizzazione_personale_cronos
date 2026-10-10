-- Presenza più reattiva: aggiorna last_app_open_at ogni 30s, log attività ogni 2 min.
create or replace function public.touch_my_last_app_open(p_platform text default '')
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_prev timestamptz;
  v_updated int := 0;
  v_platform text := lower(trim(coalesce(p_platform, '')));
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_platform not in ('web', 'android', 'windows', 'ios', 'macos', 'linux') then
    v_platform := '';
  end if;

  select u.last_app_open_at
    into v_prev
    from public.users u
   where u.auth_id = auth.uid()
      or u.id_uuid = auth.uid()
   order by case when u.auth_id = auth.uid() then 0 else 1 end
   limit 1;

  -- Throttle presenza: 30 secondi.
  if v_prev is not null and v_prev > (v_at - interval '30 seconds') then
    return v_prev;
  end if;

  update public.users u
     set last_app_open_at = v_at,
         last_app_open_platform = nullif(v_platform, '')
   where u.auth_id = auth.uid();
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    update public.users u
       set last_app_open_at = v_at,
           last_app_open_platform = nullif(v_platform, '')
     where u.id_uuid = auth.uid();
  end if;

  -- Log attività meno frequente (2 minuti), per non inondare app_activity_logs.
  if v_prev is null or v_prev <= (v_at - interval '2 minutes') then
    perform public._insert_app_activity_log(
      'app_open',
      coalesce(nullif(v_platform, ''), '')
    );
  end if;

  return v_at;
end;
$$;

grant execute on function public.touch_my_last_app_open(text) to authenticated;

comment on function public.touch_my_last_app_open(text) is
  'Aggiorna last_app_open_at (throttle 30s). Log attività ogni 2 minuti.';
