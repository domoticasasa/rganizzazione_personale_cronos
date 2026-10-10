-- SIM aziendali (linee telefoniche) — Logistica.
-- Seed da «Abbinamenti a SIM 21-09-26 definitive.xlsx».

create table if not exists public.logistica_sim (
  id_uuid uuid primary key default gen_random_uuid(),
  numero_linea text not null,
  assegnatario text,
  assegnatario_user_uuid uuid references public.users(id_uuid) on delete set null,
  data_assegnazione date,
  note text,
  field_timestamps jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users(id_uuid) on delete set null,
  constraint logistica_sim_numero_linea_nonempty
    check (length(trim(numero_linea)) > 0)
);

create unique index if not exists logistica_sim_numero_linea_uidx
  on public.logistica_sim (lower(trim(numero_linea)))
  where active;

create index if not exists logistica_sim_assegnatario_idx
  on public.logistica_sim (lower(trim(coalesce(assegnatario, ''))));

comment on table public.logistica_sim is
  'SIM / linee telefoniche aziendali e assegnatario corrente.';

create or replace function public.set_logistica_sim_audit_fields()
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

drop trigger if exists trg_logistica_sim_audit_fields on public.logistica_sim;
create trigger trg_logistica_sim_audit_fields
before insert or update on public.logistica_sim
for each row execute function public.set_logistica_sim_audit_fields();

drop trigger if exists trg_logistica_sim_field_timestamps on public.logistica_sim;
create trigger trg_logistica_sim_field_timestamps
before insert or update on public.logistica_sim
for each row execute function public.set_field_timestamps();

alter table public.logistica_sim enable row level security;

-- Lettura: admin / logistica / DT
drop policy if exists logistica_sim_select_role_allowed on public.logistica_sim;
create policy logistica_sim_select_role_allowed
on public.logistica_sim for select to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'dt', 'assistente_dt', 'admin', 'admin_generale', 'admin_vista',
        'admin_pernottamenti', 'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('sim_telefoni')
  or public.has_custom_page_access('logistica')
);

-- Scrittura: solo admin (non vista) e logistica
drop policy if exists logistica_sim_insert_role_allowed on public.logistica_sim;
create policy logistica_sim_insert_role_allowed
on public.logistica_sim for insert to authenticated
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin', 'admin_generale', 'admin_pernottamenti',
        'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('sim_telefoni')
);

drop policy if exists logistica_sim_update_role_allowed on public.logistica_sim;
create policy logistica_sim_update_role_allowed
on public.logistica_sim for update to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin', 'admin_generale', 'admin_pernottamenti',
        'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('sim_telefoni')
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin', 'admin_generale', 'admin_pernottamenti',
        'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('sim_telefoni')
);

drop policy if exists logistica_sim_delete_role_allowed on public.logistica_sim;
create policy logistica_sim_delete_role_allowed
on public.logistica_sim for delete to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin', 'admin_generale', 'admin_pernottamenti',
        'admin_trenoaereo', 'logistica'
      )
  )
  or public.has_custom_page_access('sim_telefoni')
);

-- Seed iniziale (idempotente su numero_linea)
insert into public.logistica_sim (numero_linea, assegnatario, data_assegnazione)
select v.numero_linea, v.assegnatario, current_date
from (
  values
  ('3397998105', 'Afflitto G.'),
  ('3397952987', 'Afflitto G.'),
  ('3333231685', 'Alberghi R.'),
  ('3397997466', 'Antonaci G'),
  ('3397997637', 'Benzo A.'),
  ('3331895328', 'Bernini G.'),
  ('3349937052', 'Bernini G.'),
  ('3349937055', 'Bloise C.'),
  ('3349937049', 'Bruni G.'),
  ('3317472357', 'Bruni G.'),
  ('3355326782', 'Bruni G.'),
  ('3666365841', 'Caldarola L.'),
  ('3331895327', 'Castronovo P.'),
  ('3349937031', 'Castronovo P.'),
  ('3356174627', 'Casucci G.'),
  ('3397952979', 'Chiaravalloti M.'),
  ('3331895329', 'Cibuc A.'),
  ('3349937042', 'Cibuc A.'),
  ('3355238484', 'Cibuc A.'),
  ('3355220134', 'Cibuc A.'),
  ('3317472352', 'De Bonis T.'),
  ('3357953308', 'De Bonis T.'),
  ('3388296015', 'De Filippis D.'),
  ('3333275598', 'DISPONIBILE IN SEDE'),
  ('3317472354', 'Fracchia C.'),
  ('3331849774', 'Grippo P.'),
  ('3349937038', 'Grippo P.'),
  ('3351441361', 'Guarnaschella G.'),
  ('3349937033', 'Guarnaschella G.'),
  ('3383383382', 'Hysa A.'),
  ('3349937068', 'Mammucari I.'),
  ('3386740224', 'Manconi R.'),
  ('3349937036', 'MERLI ANDREA'),
  ('3386200627', 'MERLI ANDREA'),
  ('3356249919', 'Monti A.'),
  ('3317472362', 'Moro A.'),
  ('3386181689', 'Murgia S.'),
  ('3397952980', 'Nicastro M.'),
  ('3388296206', 'Patrucco A.'),
  ('3316167223', 'Pecorella D.'),
  ('3333222743', 'Pizzorno D.'),
  ('3356742107', 'Puccio V.'),
  ('3338086476', 'Ribaudo O.'),
  ('3387192156', 'Ribaudo O.'),
  ('3346038898', 'Rizzolo S.'),
  ('3349937043', 'Rizzolo S. (IN SEGUITO DISPONIBILE IN SEDE)'),
  ('3317472350', 'Scopece A.'),
  ('3356810678', 'Scopece F.'),
  ('3333209934', 'Shabestary M.'),
  ('3349937034', 'Tagliero A.'),
  ('3316126637', 'Tancredi V.'),
  ('3349937119', 'TAVANI (ROMA)'),
  ('3346034769', 'Vencia G.'),
  ('3349937123', 'Vencia G.'),
  ('3385018125', 'Vivian L.'),
  ('3666323020', 'Vivian L.'),
  ('3317472361', 'Xhima A.')
) as v(numero_linea, assegnatario)
where not exists (
  select 1
  from public.logistica_sim s
  where lower(trim(s.numero_linea)) = lower(trim(v.numero_linea))
);

grant select, insert, update, delete on public.logistica_sim to authenticated;
