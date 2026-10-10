-- Attrezzature: data di assegnazione attuale + storico assegnatari precedenti.

-- 1) Data di assegnazione dell'assegnatario attuale (testo gg/mm/aaaa o ISO).
alter table public.logistica_attrezzature
  add column if not exists data_assegnazione text;

-- 2) Storico assegnatari precedenti di un'attrezzatura.
create table if not exists public.logistica_attrezzature_assegnatari_storico (
  id_uuid uuid primary key default gen_random_uuid(),
  attrezzatura_id uuid not null references public.logistica_attrezzature(id_uuid) on delete cascade,
  assegnatario text,
  data_assegnazione text,
  data_fine text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null
);

create index if not exists logistica_attrezzature_storico_attrezzatura_idx
  on public.logistica_attrezzature_assegnatari_storico(attrezzatura_id);

create or replace function public.set_logistica_attrezzature_storico_audit_fields()
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

drop trigger if exists trg_logistica_attrezzature_storico_audit_fields
  on public.logistica_attrezzature_assegnatari_storico;
create trigger trg_logistica_attrezzature_storico_audit_fields
before insert or update on public.logistica_attrezzature_assegnatari_storico
for each row execute function public.set_logistica_attrezzature_storico_audit_fields();

alter table public.logistica_attrezzature_assegnatari_storico enable row level security;

-- SELECT: ruoli gestione (DT/assistente in sola lettura) + admin/logistica.
drop policy if exists logistica_attrezzature_storico_select_role_allowed
  on public.logistica_attrezzature_assegnatari_storico;
create policy logistica_attrezzature_storico_select_role_allowed
on public.logistica_attrezzature_assegnatari_storico
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

-- SELECT: dipendente vede lo storico delle attrezzature assegnate a se stesso.
drop policy if exists logistica_attrezzature_storico_select_dipendente
  on public.logistica_attrezzature_assegnatari_storico;
create policy logistica_attrezzature_storico_select_dipendente
on public.logistica_attrezzature_assegnatari_storico
for select
to authenticated
using (
  exists (
    select 1
    from public.logistica_attrezzature a
    join public.users u on u.auth_id = auth.uid()
    left join public.personale p on (p.user_id::text = u.id::text)
    where a.id_uuid = logistica_attrezzature_assegnatari_storico.attrezzatura_id
      and lower(coalesce(u.role, '')) in ('dipendente', 'user')
      and coalesce(a.assegnatario, '') <> ''
      and (
        public.norm_person_tokens(a.assegnatario) = public.norm_person_tokens(u.full_name)
        or public.norm_person_tokens(a.assegnatario) = public.norm_person_tokens(p.full_name)
      )
  )
);

-- WRITE: solo admin/logistica.
drop policy if exists logistica_attrezzature_storico_insert_role_allowed
  on public.logistica_attrezzature_assegnatari_storico;
create policy logistica_attrezzature_storico_insert_role_allowed
on public.logistica_attrezzature_assegnatari_storico
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_storico_update_role_allowed
  on public.logistica_attrezzature_assegnatari_storico;
create policy logistica_attrezzature_storico_update_role_allowed
on public.logistica_attrezzature_assegnatari_storico
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);

drop policy if exists logistica_attrezzature_storico_delete_role_allowed
  on public.logistica_attrezzature_assegnatari_storico;
create policy logistica_attrezzature_storico_delete_role_allowed
on public.logistica_attrezzature_assegnatari_storico
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'logistica'
      )
  )
);
