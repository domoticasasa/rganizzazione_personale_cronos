create table if not exists public.commesse_cig_cup (
  id_uuid uuid primary key default gen_random_uuid(),
  commessa_code text not null,
  commessa_id_uuid uuid references public.commesse (id_uuid) on delete set null,
  cig text,
  cig_derivato text,
  cup text,
  cliente text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_uuid uuid references public.users (id_uuid) on delete set null,
  updated_by_user_uuid uuid references public.users (id_uuid) on delete set null
);

create unique index if not exists commesse_cig_cup_code_uq
  on public.commesse_cig_cup (commessa_code);

create index if not exists commesse_cig_cup_commessa_idx
  on public.commesse_cig_cup (commessa_id_uuid);

create or replace function public.set_commesse_cig_cup_audit_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_uuid uuid;
begin
  begin
    select u.id_uuid into v_user_uuid
    from public.users u
    where u.auth_id = auth.uid()
    limit 1;
  exception when others then
    v_user_uuid := null;
  end;

  if tg_op = 'INSERT' then
    if new.created_at is null then new.created_at := now(); end if;
    if new.created_by_user_uuid is null then new.created_by_user_uuid := v_user_uuid; end if;
  end if;

  new.updated_at := now();
  new.updated_by_user_uuid := v_user_uuid;
  new.commessa_code := upper(trim(coalesce(new.commessa_code, '')));
  return new;
end;
$$;

drop trigger if exists trg_commesse_cig_cup_audit_fields on public.commesse_cig_cup;
create trigger trg_commesse_cig_cup_audit_fields
before insert or update on public.commesse_cig_cup
for each row execute function public.set_commesse_cig_cup_audit_fields();

alter table public.commesse_cig_cup enable row level security;

drop policy if exists commesse_cig_cup_select on public.commesse_cig_cup;
create policy commesse_cig_cup_select
on public.commesse_cig_cup
for select
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione',
    'dt',
    'assistente_dt'
  )
  or public.has_custom_page_access('commesse_cig_cup')
);

drop policy if exists commesse_cig_cup_insert on public.commesse_cig_cup;
create policy commesse_cig_cup_insert
on public.commesse_cig_cup
for insert
to authenticated
with check (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('commesse_cig_cup')
);

drop policy if exists commesse_cig_cup_update on public.commesse_cig_cup;
create policy commesse_cig_cup_update
on public.commesse_cig_cup
for update
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('commesse_cig_cup')
)
with check (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('commesse_cig_cup')
);

drop policy if exists commesse_cig_cup_delete on public.commesse_cig_cup;
create policy commesse_cig_cup_delete
on public.commesse_cig_cup
for delete
to authenticated
using (
  public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('commesse_cig_cup')
);

with src(commessa_code, cig, cig_derivato, cup, cliente) as (
  values
    ('MLD-03-21','77329128D9','-','H31B99000010001','NEOCOS'),
    ('MLD-04-21','8801867A6B','-','F87I17000020002','ATLANTE-ROMANO'),
    ('MLD-02-22','89986744B3','-','J71H92000000007','RFI/ATLANT/D''AGOSTI'),
    ('MLD-02-23','948682794B','-','J74J17000010001','RFI'),
    ('MLD-01-24','9835617FE6','-','J46E190000210001','RFI'),
    ('MLD-02-24','9569426C24','-','J47I09000030009','D''AGOSTINO'),
    ('MLD-03-24','9557041FB6','-','J64H17000140001','G.C.F.'),
    ('MLD-04-24','95084583C4','-','J81D19000000009','D''AGOSTINO'),
    ('MLD-01-25','8377957CD1','-','J41E91000000009','G.C.F.e.'),
    ('MLD-02-25','7514473340','-','F81H91000000008','G.C.F.e.'),
    ('MLD-03-25','956348111F','-','J44G1900001000','G.C.F.'),
    ('TE-01-19','169195014F','-','B89B07000030003','HITACHI'),
    ('TE-10-22','83594948AC','-','J74J17000020001','IM.A.F'),
    ('TE-09-23','9230980DAA','-','E11E14000610003','G.C.F.'),
    ('TE-03-24','90291019D9','derivato A041CD323D','J24E21001480001','G.C.F.'),
    ('TE-04-24','7928990988','-','J19B12000040001','G.C.F.'),
    ('TE-08-24','-','derivato A0081EFA4F','J97D22000210001','G.C.F.'),
    ('TE-09-24','-','derivato A0307A55D7','J84HI7000290001','G.C.F.'),
    ('TE-11-24','9658089B2A','-','',''),
    ('TE-12-24','9919327796','-','J74G18000150009','RFI SPA'),
    ('TE-14-24','90291019D9','derivato 963902463C','J24E21001480001','ATLANTE'),
    ('TE-15-24','988000560C','-','J44H20001400009','ATLANTE'),
    ('TE-16-24','-','derivato 8858387C32','J84H17000440001','G.C.F.'),
    ('TE-17-24','9783296741','-','','EAV'),
    ('TE-21-24','904284361C','-','C36G21019230001','G.C.F.'),
    ('TE-22-24','9747196897','-','6G21010450001','G.C.F.'),
    ('TE-23-24','A02D732A8E','derivato  B2DD1820A4','J11H03000180001','G.C.F.'),
    ('TE-24-24','A02D6C2E20','derivato B36DA177D1','J66J17000390001','G.C.F.'),
    ('TE-25-24','A02D6C2E20','derivato B2E6D1C8B0','J67H22000040001','G.C.F.'),
    ('TE-26-24','A02D6C2E20','derivato  B36D9EF6CF','J66J17000390001','G.C.F.'),
    ('TE-27-24','9229545D77','-','J51H03000170001','G.C.F.'),
    ('TE-28-24','-','B248693828','J97D23000150001','G.C.F.'),
    ('TE-01-25','94596741F0','-','F81H92000000008','G.C.F.e.'),
    ('TE-02-25','9564541CE9','-','F81H92000000008','G.C.F.e.'),
    ('TE-03-25','9657394B41','derivato B2B0AD6998','J47D23000160001','G.C.F.'),
    ('TE-04-25','9836091711','-','D21B21004890006','G.C.F.'),
    ('TE-05-25','9711352D2E','-','F47H21008020001','G.C.F.'),
    ('TE-07-25','9567879F83','derivato  B30C701BA6','-','G.C.F.'),
    ('TE-08-25','9657934B41','derivato B5E3B78297','J47D23000280001','G.C.F.'),
    ('TE-09-25','9657580721','derivato  B73A6E31DD','J84J24000020001','G.C.F.'),
    ('TE-10-25','9657580721','derivato B726CCCFE4','J97D23000320001','G.C.F.'),
    ('TE-11-25','B7C5A621F9','-','D17H21005530001','GTT'),
    ('TE-12-25','B70EAFEF9C','','J11J24002630005','PAROLDI'),
    ('TE-01-26','9657580721','','','G.C.F.'),
    ('TE-02-26','9657580721','Deriv. BA3819382A','J97D23000320001','G.C.F.'),
    ('TE-03-26','9657580721','Deriv. BA43D3A335','J97D25000140001','G.C.F.'),
    ('TE-04-26','','','','G.C.F.'),
    ('LFM-01-22','867789597D','-','J34H16000350001','COLAS'),
    ('LFM-02-24','-','derivato 9986283D6B','J97D22000250001','G.C.F.'),
    ('LFM-01-25','8796689966','derivato  982818285 A','J97D22000210001','G.C.F.'),
    ('LFM-02-25','9657580721','derivato B2DF35C00D','J97D23000150001','G.C.F'),
    ('LFM-01-26','','derivato A03BF62600','J97D2200032000','G.C.F.'),
    ('IS-01-22','88520151DE','-','J56E20000080009','ATLANTE'),
    ('IS-02-24','837893758C','-','J54B13001110001','G.C.F.'),
    ('IS-04-24','-','derivato B236FE6FB1','J84J24000020001','G.C.F.'),
    ('IS-01-25','8503907E0B','derivato B177000CEF','J56J16000460001','G.C.F.'),
    ('IS-02-25','8503907E0B','derivato  B5FC23A940','J84H20000850001','G.C.F.'),
    ('IS-01-26','9539193716','','J34G18000150001','G.C.F.'),
    ('TLC-05-20','7169564F5D','-','J44H14000090005','ATLANTE'),
    ('TLC-01-22','8369311DE9','derivato  954198464B','J97H22000100001','ATLANTE'),
    ('TLC-01-25','989006322D','-','D21B21004890006','G.C.F.'),
    ('TLC-02-25','-','-','-','G.C.F.'),
    ('TLC-03-25','A0370DA7A7','derivato  B5BE1DBB08','J54B13001100001','G.C.F.'),
    ('SSE-01-25','A02D732A8E','derivato B36D992A0F','J64E22000010001','G.C.F.'),
    ('TG-01-24','9791478741','-','J54D21000030001','SELCOM')
)
insert into public.commesse_cig_cup (
  commessa_code,
  commessa_id_uuid,
  cig,
  cig_derivato,
  cup,
  cliente,
  active
)
select
  src.commessa_code,
  c.id_uuid,
  nullif(src.cig, ''),
  nullif(src.cig_derivato, ''),
  nullif(src.cup, ''),
  nullif(src.cliente, ''),
  true
from src
left join public.commesse c
  on upper(trim(c.nome)) = src.commessa_code
on conflict (commessa_code)
do update set
  commessa_id_uuid = excluded.commessa_id_uuid,
  cig = excluded.cig,
  cig_derivato = excluded.cig_derivato,
  cup = excluded.cup,
  cliente = excluded.cliente,
  active = true,
  updated_at = now();

insert into public.app_page_registry (page_key, label, active)
values ('commesse_cig_cup', 'Commesse CIG/CUP', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;
