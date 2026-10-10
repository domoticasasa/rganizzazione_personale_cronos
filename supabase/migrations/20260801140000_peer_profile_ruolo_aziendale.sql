-- Espone ruolo_aziendale nel profilo collega (chat).
create or replace function public.get_app_chat_peer_profile(
  p_user_id integer default null,
  p_auth_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_users public.users%rowtype;
  v_personale public.personale%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_user_id is null and p_auth_id is null then
    raise exception 'user_id or auth_id required';
  end if;

  if p_user_id is not null then
    select u.*
      into v_users
    from public.users u
    where u.id = p_user_id
    limit 1;
  end if;

  if v_users.id is null and p_auth_id is not null then
    select u.*
      into v_users
    from public.users u
    where u.auth_id = p_auth_id
       or u.id_uuid = p_auth_id
    order by case when u.auth_id = p_auth_id then 0 else 1 end
    limit 1;
  end if;

  if v_users.id is null then
    return jsonb_build_object('users', null, 'personale', null);
  end if;

  select p.*
    into v_personale
  from public.personale p
  where (
      nullif(trim(p.user_id::text), '') in (
        nullif(trim(coalesce(v_users.auth_id::text, '')), ''),
        v_users.id::text,
        nullif(trim(coalesce(v_users.id_uuid::text, '')), '')
      )
    )
    or (
      nullif(trim(coalesce(v_users.email, '')), '') is not null
      and lower(trim(coalesce(p.email, ''))) = lower(trim(v_users.email))
    )
  order by coalesce(p.active, true) desc, p.id desc
  limit 1;

  return jsonb_build_object(
    'users', jsonb_build_object(
      'id', v_users.id,
      'auth_id', v_users.auth_id,
      'id_uuid', v_users.id_uuid,
      'full_name', v_users.full_name,
      'username', v_users.username,
      'email', v_users.email,
      'role', v_users.role
    ),
    'personale', case
      when v_personale.id is null then null
      else jsonb_build_object(
        'id', v_personale.id,
        'id_uuid', v_personale.id_uuid,
        'user_id', v_personale.user_id,
        'full_name', v_personale.full_name,
        'email', v_personale.email,
        'telefono', v_personale.telefono,
        'matricola', v_personale.matricola,
        'numero_tesserino', v_personale.numero_tesserino,
        'data_assunzione', v_personale.data_assunzione,
        'data_nascita', v_personale.data_nascita,
        'foto_tesserino_path', v_personale.foto_tesserino_path,
        'ruolo_aziendale', v_personale.ruolo_aziendale
      )
    end
  );
end;
$$;
