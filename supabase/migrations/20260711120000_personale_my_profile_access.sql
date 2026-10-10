-- Profilo personale: lettura/scrittura del proprio record personale (allineato a Gestione dipendenti).

create or replace function public.personale_belongs_to_current_auth(p public.personale)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and (
        nullif(trim(p.user_id::text), '') = u.auth_id::text
        or nullif(trim(p.user_id::text), '') = u.id::text
        or nullif(trim(p.user_id::text), '') = u.id_uuid::text
      )
  )
  or (
    nullif(trim(coalesce(auth.jwt() ->> 'email', '')), '') is not null
    and lower(trim(coalesce(p.email, ''))) =
        lower(trim(auth.jwt() ->> 'email'))
  )
  or exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and nullif(trim(coalesce(u.email, '')), '') is not null
      and lower(trim(coalesce(p.email, ''))) = lower(trim(u.email))
  )
$$;

create or replace function public.get_my_personale_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_users public.users%rowtype;
  v_personale public.personale%rowtype;
  v_auth_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
begin
  select u.*
    into v_users
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if not found and v_auth_email <> '' then
    select u.*
      into v_users
    from public.users u
    where lower(trim(coalesce(u.email, ''))) = v_auth_email
    order by u.id
    limit 1;
  end if;

  select p.*
    into v_personale
  from public.personale p
  where public.personale_belongs_to_current_auth(p)
  order by coalesce(p.active, true) desc, p.id desc
  limit 1;

  if not found and v_users.id is not null then
    select p.*
      into v_personale
    from public.personale p
    where nullif(trim(p.user_id::text), '') in (
      v_users.auth_id::text,
      v_users.id::text,
      v_users.id_uuid::text
    )
    order by coalesce(p.active, true) desc, p.id desc
    limit 1;
  end if;

  if not found and nullif(trim(coalesce(v_users.email, '')), '') is not null then
    select p.*
      into v_personale
    from public.personale p
    where lower(trim(coalesce(p.email, ''))) = lower(trim(v_users.email))
    order by coalesce(p.active, true) desc, p.id desc
    limit 1;
  end if;

  if not found and v_auth_email <> '' then
    select p.*
      into v_personale
    from public.personale p
    where lower(trim(coalesce(p.email, ''))) = v_auth_email
    order by coalesce(p.active, true) desc, p.id desc
    limit 1;
  end if;

  return jsonb_build_object(
    'users', case when v_users.id is null then null else to_jsonb(v_users) end,
    'personale', case when v_personale.id is null then null else to_jsonb(v_personale) end
  );
end;
$$;

create or replace function public.update_my_personale_profile(
  p_email text default null,
  p_telefono text default null,
  p_data_nascita date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bundle jsonb;
  v_personale_id bigint;
  v_users public.users%rowtype;
begin
  v_bundle := public.get_my_personale_profile();
  v_personale_id := nullif(v_bundle #>> '{personale,id}', '')::bigint;

  if v_personale_id is null then
    raise exception 'Nessun record personale collegato al tuo account';
  end if;

  update public.personale p
  set
    email = case
      when p_email is null then p.email
      when trim(p_email) = '' then null
      else lower(trim(p_email))
    end,
    telefono = case
      when p_telefono is null then p.telefono
      when trim(p_telefono) = '' then null
      else trim(p_telefono)
    end,
    data_nascita = case
      when p_data_nascita is null then p.data_nascita
      else p_data_nascita
    end
  where p.id = v_personale_id;

  select u.*
    into v_users
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if found and p_email is not null and trim(p_email) <> '' then
    update public.users u
    set
      email = lower(trim(p_email)),
      username = lower(trim(p_email))
    where u.id = v_users.id;
  end if;

  return public.get_my_personale_profile();
end;
$$;

revoke all on function public.personale_belongs_to_current_auth(public.personale) from public;
grant execute on function public.get_my_personale_profile() to authenticated;
grant execute on function public.update_my_personale_profile(text, text, date) to authenticated;

comment on function public.get_my_personale_profile() is
  'Profilo personale: users + personale collegati all''utente autenticato (Gestione dipendenti).';

comment on function public.update_my_personale_profile(text, text, date) is
  'Aggiorna telefono, email e data di nascita sul proprio record personale.';
