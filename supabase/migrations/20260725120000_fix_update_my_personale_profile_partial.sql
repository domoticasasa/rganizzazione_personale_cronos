-- Aggiornamento parziale profilo: non sovrascrivere users.username/email se l'email non cambia.

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
  v_new_email text;
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
    v_new_email := lower(trim(p_email));
    if v_new_email <> lower(trim(coalesce(v_users.email, ''))) then
      update public.users u
      set
        email = v_new_email,
        username = v_new_email
      where u.id = v_users.id;
    end if;
  end if;

  return public.get_my_personale_profile();
end;
$$;

comment on function public.update_my_personale_profile(text, text, date) is
  'Aggiorna solo i campi personale passati (null = invariato). users.email/username solo se email cambia.';
