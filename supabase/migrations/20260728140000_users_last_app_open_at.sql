-- Ultima apertura app (diversa dal login auth).

alter table public.users
  add column if not exists last_app_open_at timestamptz;

comment on column public.users.last_app_open_at is
  'Ultima volta che l''utente ha aperto/entrato in app (non last_sign_in).';

create or replace function public.touch_my_last_app_open()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz := timezone('utc', now());
  v_prev timestamptz;
  v_updated int := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select u.last_app_open_at
    into v_prev
  from public.users u
  where u.auth_id = auth.uid()
     or u.id_uuid = auth.uid()
  order by case when u.auth_id = auth.uid() then 0 else 1 end
  limit 1;

  -- Evita update continui su token refresh (ogni 2 minuti max).
  if v_prev is not null and v_prev > (v_at - interval '2 minutes') then
    return v_prev;
  end if;

  update public.users u
  set last_app_open_at = v_at
  where u.auth_id = auth.uid();
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    update public.users u
    set last_app_open_at = v_at
    where u.id_uuid = auth.uid();
  end if;

  return v_at;
end;
$$;

grant execute on function public.touch_my_last_app_open() to authenticated;

comment on function public.touch_my_last_app_open() is
  'Registra last_app_open_at per l''utente autenticato (throttle 2 min).';
