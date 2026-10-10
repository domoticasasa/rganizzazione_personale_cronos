-- Programmazione visite mediche (admin inserisce; DT riepilogo; dipendente solo le proprie).

create table if not exists public.visite_mediche_programmazione (
  id_uuid uuid primary key default gen_random_uuid(),
  personale_id_uuid uuid not null references public.personale (id_uuid) on delete cascade,
  dipendente_nome text,
  data_visita timestamptz not null,
  luogo_struttura text not null,
  link text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null
);

create index if not exists visite_mediche_programmazione_personale_idx
  on public.visite_mediche_programmazione (personale_id_uuid);

create index if not exists visite_mediche_programmazione_data_visita_idx
  on public.visite_mediche_programmazione (data_visita);

create or replace function public.set_visite_mediche_audit_fields()
returns trigger
language plpgsql
as $$
declare
  v_user_uuid uuid;
begin
  select u.id_uuid into v_user_uuid
  from public.users u
  where u.auth_id = auth.uid()
  limit 1;

  if tg_op = 'INSERT' then
    if new.created_by_user_uuid is null then
      new.created_by_user_uuid = v_user_uuid;
    end if;
    new.updated_by_user_uuid := coalesce(v_user_uuid, new.updated_by_user_uuid, new.created_by_user_uuid);
  else
    new.updated_by_user_uuid := coalesce(v_user_uuid, new.updated_by_user_uuid);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_visite_mediche_audit_fields on public.visite_mediche_programmazione;
create trigger trg_visite_mediche_audit_fields
before insert or update on public.visite_mediche_programmazione
for each row execute function public.set_visite_mediche_audit_fields();

create or replace function public.visite_mediche_is_own_personale(p_personale_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.personale p
    join public.users u on u.auth_id = auth.uid()
    where p.id_uuid = p_personale_uuid
      and (
        p.user_id::text = u.auth_id::text
        or p.user_id::text = u.id_uuid::text
        or p.user_id::text = u.id::text
      )
  );
$$;

alter table public.visite_mediche_programmazione enable row level security;

drop policy if exists visite_mediche_select on public.visite_mediche_programmazione;
create policy visite_mediche_select
on public.visite_mediche_programmazione
for select
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt',
        'assistente_dt',
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione',
        'logistica'
      )
  )
  or public.visite_mediche_is_own_personale(personale_id_uuid)
  or public.has_custom_page_access('visite_mediche')
);

drop policy if exists visite_mediche_insert on public.visite_mediche_programmazione;
create policy visite_mediche_insert
on public.visite_mediche_programmazione
for insert
to authenticated
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
);

drop policy if exists visite_mediche_update on public.visite_mediche_programmazione;
create policy visite_mediche_update
on public.visite_mediche_programmazione
for update
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
);

drop policy if exists visite_mediche_delete on public.visite_mediche_programmazione;
create policy visite_mediche_delete
on public.visite_mediche_programmazione
for delete
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_pernottamenti',
        'admin_trenoaereo',
        'admin_dpi',
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('visite_mediche')
);
