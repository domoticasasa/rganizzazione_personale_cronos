-- Buoni pasto: QR ristorante, operatori, registrazioni dipendenti.

create table if not exists public.buoni_pasto_ristoranti (
  id_uuid uuid primary key default gen_random_uuid(),
  structure_id_uuid uuid not null unique references public.structures (id_uuid) on delete cascade,
  qr_token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  attivo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists buoni_pasto_ristoranti_token_idx
  on public.buoni_pasto_ristoranti (qr_token);

create table if not exists public.buoni_pasto_operatori (
  id_uuid uuid primary key default gen_random_uuid(),
  structure_id_uuid uuid not null references public.structures (id_uuid) on delete cascade,
  user_id_uuid uuid not null unique references public.users (id_uuid) on delete cascade,
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists buoni_pasto_operatori_structure_idx
  on public.buoni_pasto_operatori (structure_id_uuid);

create table if not exists public.buoni_pasto_registrazioni (
  id_uuid uuid primary key default gen_random_uuid(),
  structure_id_uuid uuid not null references public.structures (id_uuid) on delete restrict,
  personale_id_uuid uuid not null references public.personale (id_uuid) on delete cascade,
  dipendente_nome text not null,
  registrato_at timestamptz not null default now(),
  data_pasto date not null,
  tipo_pasto text not null,
  qr_token_used text,
  constraint buoni_pasto_registrazioni_tipo_check check (
    tipo_pasto in ('pranzo', 'cena')
  ),
  constraint buoni_pasto_registrazioni_unique_giorno unique (
    personale_id_uuid,
    data_pasto,
    tipo_pasto
  )
);

create index if not exists buoni_pasto_registrazioni_structure_data_idx
  on public.buoni_pasto_registrazioni (structure_id_uuid, data_pasto desc);

create index if not exists buoni_pasto_registrazioni_personale_data_idx
  on public.buoni_pasto_registrazioni (personale_id_uuid, data_pasto desc);

create or replace function public.set_buoni_pasto_ristoranti_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_buoni_pasto_ristoranti_updated on public.buoni_pasto_ristoranti;
create trigger trg_buoni_pasto_ristoranti_updated
before update on public.buoni_pasto_ristoranti
for each row execute function public.set_buoni_pasto_ristoranti_updated_at();

create or replace function public.is_buoni_pasto_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role_norm() in (
    'admin',
    'admin_generale',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione'
  )
  or public.has_custom_page_access('buoni_pasto_admin');
$$;

create or replace function public.current_ristoratore_structure_uuid()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select o.structure_id_uuid
  from public.buoni_pasto_operatori o
  join public.users u on u.id_uuid = o.user_id_uuid
  where u.auth_id = auth.uid()
    and o.attivo = true
  limit 1;
$$;

create or replace function public.current_personale_uuid()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id_uuid
  from public.personale p
  where p.user_id::text = auth.uid()::text
    and coalesce(p.active, true) = true
  limit 1;
$$;

create or replace function public.registra_buono_pasto(p_qr_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personale_id uuid;
  v_nome text;
  v_structure_id uuid;
  v_structure_name text;
  v_token text;
  v_now_rome timestamptz;
  v_data date;
  v_tipo text;
  v_hour int;
  v_existing uuid;
begin
  v_token := trim(coalesce(p_qr_token, ''));
  if v_token = '' then
    raise exception 'Token QR non valido.';
  end if;

  if upper(v_token) like 'CRONOS-BP:%' then
    v_token := trim(substring(v_token from position(':' in v_token) + 1));
  end if;

  select p.id_uuid, coalesce(nullif(trim(p.full_name), ''), '—')
  into v_personale_id, v_nome
  from public.personale p
  where p.user_id::text = auth.uid()::text
    and coalesce(p.active, true) = true
  limit 1;

  if v_personale_id is null then
    raise exception 'Profilo dipendente non trovato per questo account.';
  end if;

  select r.structure_id_uuid, s.name
  into v_structure_id, v_structure_name
  from public.buoni_pasto_ristoranti r
  join public.structures s on s.id_uuid = r.structure_id_uuid
  where r.qr_token = v_token
    and r.attivo = true
    and coalesce(s.active, true) = true
    and s.is_ristorante = true
  limit 1;

  if v_structure_id is null then
    raise exception 'QR code non valido o ristorante non attivo.';
  end if;

  v_now_rome := timezone('Europe/Rome', now());
  v_data := (v_now_rome)::date;
  v_hour := extract(hour from v_now_rome)::int;

  if v_hour < 17 then
    v_tipo := 'pranzo';
  else
    v_tipo := 'cena';
  end if;

  select id_uuid into v_existing
  from public.buoni_pasto_registrazioni
  where personale_id_uuid = v_personale_id
    and data_pasto = v_data
    and tipo_pasto = v_tipo;

  if v_existing is not null then
    raise exception 'Hai già registrato il % per oggi (%).',
      v_tipo,
      to_char(v_data, 'DD/MM/YYYY');
  end if;

  insert into public.buoni_pasto_registrazioni (
    structure_id_uuid,
    personale_id_uuid,
    dipendente_nome,
    registrato_at,
    data_pasto,
    tipo_pasto,
    qr_token_used
  ) values (
    v_structure_id,
    v_personale_id,
    v_nome,
    v_now_rome,
    v_data,
    v_tipo,
    v_token
  );

  return jsonb_build_object(
    'ok', true,
    'structure_id_uuid', v_structure_id,
    'structure_name', v_structure_name,
    'dipendente_nome', v_nome,
    'data_pasto', v_data,
    'tipo_pasto', v_tipo,
    'registrato_at', v_now_rome
  );
end;
$$;

grant execute on function public.registra_buono_pasto(text) to authenticated;
grant execute on function public.is_buoni_pasto_admin() to authenticated;
grant execute on function public.current_ristoratore_structure_uuid() to authenticated;
grant execute on function public.current_personale_uuid() to authenticated;

alter table public.buoni_pasto_ristoranti enable row level security;
alter table public.buoni_pasto_operatori enable row level security;
alter table public.buoni_pasto_registrazioni enable row level security;

-- Ristoranti QR
drop policy if exists buoni_pasto_ristoranti_select on public.buoni_pasto_ristoranti;
create policy buoni_pasto_ristoranti_select
on public.buoni_pasto_ristoranti
for select
to authenticated
using (
  public.is_buoni_pasto_admin()
  or structure_id_uuid = public.current_ristoratore_structure_uuid()
);

drop policy if exists buoni_pasto_ristoranti_write on public.buoni_pasto_ristoranti;
create policy buoni_pasto_ristoranti_write
on public.buoni_pasto_ristoranti
for all
to authenticated
using (public.is_buoni_pasto_admin())
with check (public.is_buoni_pasto_admin());

-- Operatori ristorante
drop policy if exists buoni_pasto_operatori_select on public.buoni_pasto_operatori;
create policy buoni_pasto_operatori_select
on public.buoni_pasto_operatori
for select
to authenticated
using (
  public.is_buoni_pasto_admin()
  or user_id_uuid = public.current_user_uuid()
);

drop policy if exists buoni_pasto_operatori_write on public.buoni_pasto_operatori;
create policy buoni_pasto_operatori_write
on public.buoni_pasto_operatori
for all
to authenticated
using (public.is_buoni_pasto_admin())
with check (public.is_buoni_pasto_admin());

-- Registrazioni
drop policy if exists buoni_pasto_registrazioni_select on public.buoni_pasto_registrazioni;
create policy buoni_pasto_registrazioni_select
on public.buoni_pasto_registrazioni
for select
to authenticated
using (
  public.is_buoni_pasto_admin()
  or structure_id_uuid = public.current_ristoratore_structure_uuid()
  or personale_id_uuid = public.current_personale_uuid()
);

drop policy if exists buoni_pasto_registrazioni_admin_delete on public.buoni_pasto_registrazioni;
create policy buoni_pasto_registrazioni_admin_delete
on public.buoni_pasto_registrazioni
for delete
to authenticated
using (public.is_buoni_pasto_admin());

insert into public.app_page_registry (page_key, label, active)
values
  ('buoni_pasto_admin', 'Buoni pasto (admin)', true),
  ('buoni_pasto_ristoratore', 'Buoni pasto (ristoratore)', true),
  ('buoni_pasto_scan', 'Scansiona buono pasto', true),
  ('buoni_pasto_riepilogo', 'Riepilogo buoni pasto', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

notify pgrst, 'reload schema';
