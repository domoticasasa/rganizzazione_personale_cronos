-- Distingue richieste workflow (ferie/permessi dipendente) da segnalazioni inserite dall'admin.

alter table public.dipendente_assenze
  add column if not exists segnalazione_admin boolean not null default false;

create index if not exists dipendente_assenze_segnalazione_admin_idx
  on public.dipendente_assenze (segnalazione_admin);

create or replace function public.set_dipendente_assenze_workflow_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uuid uuid;
begin
  v_user_uuid := public.current_user_uuid();
  if tg_op = 'INSERT' then
    if new.requester_user_uuid is null then
      new.requester_user_uuid := v_user_uuid;
    end if;
    if coalesce(trim(new.workflow_status), '') = '' then
      if coalesce(new.segnalazione_admin, false) then
        new.workflow_status := 'APPROVATA_ADMIN';
      else
        new.workflow_status := 'INVIATA_AL_DT';
      end if;
    end if;
  end if;
  return new;
end;
$$;

insert into public.app_page_registry (page_key, label, active)
values
  ('richieste_ferie_permessi', 'Richieste ferie / permessi (workflow)', true),
  ('segnalazione_assenze', 'Segnalazione assenze (malattia, infortunio, …)', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;
