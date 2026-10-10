-- Permessi, ferie, malattia, infortunio (admin gestisce; DT / assistente DT sola lettura).

create table if not exists public.dipendente_assenze (
  id_uuid uuid primary key default gen_random_uuid(),
  personale_id_uuid uuid not null references public.personale (id_uuid) on delete cascade,
  dipendente_nome text,
  tipo_assenza text not null,
  data_dal date not null,
  data_al date not null,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  constraint dipendente_assenze_tipo_check check (
    tipo_assenza in ('FERIE', 'PERMESSO', 'MALATTIA', 'INFORTUNIO', 'ALTRO')
  ),
  constraint dipendente_assenze_date_range_check check (data_al >= data_dal)
);

create index if not exists dipendente_assenze_personale_idx
  on public.dipendente_assenze (personale_id_uuid);

create index if not exists dipendente_assenze_data_dal_idx
  on public.dipendente_assenze (data_dal desc);

create index if not exists dipendente_assenze_tipo_idx
  on public.dipendente_assenze (tipo_assenza);

create or replace function public.set_dipendente_assenze_audit_fields()
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

drop trigger if exists trg_dipendente_assenze_audit_fields on public.dipendente_assenze;
create trigger trg_dipendente_assenze_audit_fields
before insert or update on public.dipendente_assenze
for each row execute function public.set_dipendente_assenze_audit_fields();

alter table public.dipendente_assenze enable row level security;

drop policy if exists dipendente_assenze_select on public.dipendente_assenze;
create policy dipendente_assenze_select
on public.dipendente_assenze
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
        'admin_formazione'
      )
  )
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_insert on public.dipendente_assenze;
create policy dipendente_assenze_insert
on public.dipendente_assenze
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
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_update on public.dipendente_assenze;
create policy dipendente_assenze_update
on public.dipendente_assenze
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
  or public.has_custom_page_access('dipendente_assenze')
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
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_delete on public.dipendente_assenze;
create policy dipendente_assenze_delete
on public.dipendente_assenze
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
  or public.has_custom_page_access('dipendente_assenze')
);

drop policy if exists dipendente_assenze_custom_role_read on public.dipendente_assenze;
create policy dipendente_assenze_custom_role_read
on public.dipendente_assenze
for select
to authenticated
using (public.has_custom_page_access('dipendente_assenze'));

drop policy if exists dipendente_assenze_custom_role_write on public.dipendente_assenze;
create policy dipendente_assenze_custom_role_write
on public.dipendente_assenze
for all
to authenticated
using (public.has_custom_page_access('dipendente_assenze'))
with check (public.has_custom_page_access('dipendente_assenze'));

insert into public.app_page_registry (page_key, label, active)
values ('dipendente_assenze', 'Permessi / Ferie / Assenze', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;
