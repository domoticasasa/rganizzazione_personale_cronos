-- Login orfani (auth assente): scollega auth_id così non compaiono più in Accessi app.
-- Non cancelliamo le righe users se sono referenziate da storico (treni, ecc.).

update public.users u
set
  auth_id = null,
  active = false,
  hidden_from_directory = true
where u.auth_id is not null
  and not exists (
    select 1 from auth.users a where a.id = u.auth_id
  );

-- Dove possibile, rimuovi anche i token push degli stessi account (per id ancora presenti).
delete from public.device_tokens dt
where dt.user_id in (
  select u.id
  from public.users u
  where coalesce(u.active, true) = false
    and u.auth_id is null
    and coalesce(u.hidden_from_directory, false) = true
    and u.id in (10, 168) -- Cibuc admin orfano + Cagnazzo Luigi (noti)
);
