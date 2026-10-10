-- RLS e permessi per inventario magazzino vestiario (hub DPI / UQSA).

insert into public.app_page_registry (page_key, label, active)
values ('vestiario_inventario', 'Inventario Vestiario', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

grant select, insert, update, delete on public.vestiario_magazzino to authenticated;

alter table public.vestiario_magazzino enable row level security;

create or replace function public.is_vestiario_magazzino_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.auth_id = auth.uid()
      and lower(coalesce(u.role, '')) in (
        'admin',
        'admin_generale',
        'admin_dpi',
        'uqsa',
        'caposquadra'
      )
  )
  or public.has_custom_page_access('vestiario_inventario')
  or public.has_custom_page_access('vestiario_report')
  or public.has_custom_page_access('vestiario_fabbisogno_taglie')
  or public.has_custom_page_access('dpi')
  or public.has_custom_page_access('uqsa')
  or public.has_custom_page_access('dotazioni_dpi');
$$;

grant execute on function public.is_vestiario_magazzino_user() to authenticated;

drop policy if exists vestiario_magazzino_select on public.vestiario_magazzino;
create policy vestiario_magazzino_select
on public.vestiario_magazzino
for select
to authenticated
using (public.is_vestiario_magazzino_user());

drop policy if exists vestiario_magazzino_insert on public.vestiario_magazzino;
create policy vestiario_magazzino_insert
on public.vestiario_magazzino
for insert
to authenticated
with check (public.is_vestiario_magazzino_user());

drop policy if exists vestiario_magazzino_update on public.vestiario_magazzino;
create policy vestiario_magazzino_update
on public.vestiario_magazzino
for update
to authenticated
using (public.is_vestiario_magazzino_user())
with check (public.is_vestiario_magazzino_user());

drop policy if exists vestiario_magazzino_delete on public.vestiario_magazzino;
create policy vestiario_magazzino_delete
on public.vestiario_magazzino
for delete
to authenticated
using (public.is_vestiario_magazzino_user());

-- RPC eseguite come definer con stesso controllo accessi (assegnazioni + arrivi).
create or replace function public.vestiario_magazzino_scarica(
  p_stagione text,
  p_articolo text,
  p_taglia text,
  p_quantita integer
)
returns table(quantita_residua integer, insufficiente boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old integer;
  v_new integer;
begin
  if not public.is_vestiario_magazzino_user() then
    raise exception 'Permesso negato su inventario vestiario';
  end if;

  if p_quantita is null or p_quantita <= 0 then
    return;
  end if;

  if p_stagione not in ('estivo', 'invernale') then
    raise exception 'Stagione non valida: %', p_stagione;
  end if;

  insert into public.vestiario_magazzino (stagione, articolo, taglia, quantita)
  values (p_stagione, p_articolo, p_taglia, 0)
  on conflict (stagione, articolo, taglia) do nothing;

  select m.quantita into v_old
  from public.vestiario_magazzino m
  where m.stagione = p_stagione
    and m.articolo = p_articolo
    and m.taglia = p_taglia
  for update;

  v_old := coalesce(v_old, 0);
  v_new := greatest(0, v_old - p_quantita);

  update public.vestiario_magazzino m
  set quantita = v_new
  where m.stagione = p_stagione
    and m.articolo = p_articolo
    and m.taglia = p_taglia;

  quantita_residua := v_new;
  insufficiente := v_old < p_quantita;
  return next;
end;
$$;

create or replace function public.vestiario_magazzino_registra_arrivo(
  p_stagione text,
  p_articolo text,
  p_taglia text,
  p_quantita integer
)
returns table(
  quantita_magazzino integer,
  quantita_ordinata integer,
  quantita_arrivata_totale integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mag integer;
  v_ord integer;
  v_arr integer;
begin
  if not public.is_vestiario_magazzino_user() then
    raise exception 'Permesso negato su inventario vestiario';
  end if;

  if p_quantita is null or p_quantita <= 0 then
    return;
  end if;

  if p_stagione not in ('estivo', 'invernale') then
    raise exception 'Stagione non valida: %', p_stagione;
  end if;

  insert into public.vestiario_magazzino (
    stagione, articolo, taglia, quantita, quantita_ordinata, quantita_arrivata_totale
  )
  values (p_stagione, p_articolo, p_taglia, 0, 0, 0)
  on conflict (stagione, articolo, taglia) do nothing;

  select m.quantita, m.quantita_ordinata, m.quantita_arrivata_totale
  into v_mag, v_ord, v_arr
  from public.vestiario_magazzino m
  where m.stagione = p_stagione
    and m.articolo = p_articolo
    and m.taglia = p_taglia
  for update;

  v_mag := coalesce(v_mag, 0) + p_quantita;
  v_arr := coalesce(v_arr, 0) + p_quantita;
  v_ord := greatest(0, coalesce(v_ord, 0) - p_quantita);

  update public.vestiario_magazzino m
  set
    quantita = v_mag,
    quantita_ordinata = v_ord,
    quantita_arrivata_totale = v_arr
  where m.stagione = p_stagione
    and m.articolo = p_articolo
    and m.taglia = p_taglia;

  quantita_magazzino := v_mag;
  quantita_ordinata := v_ord;
  quantita_arrivata_totale := v_arr;
  return next;
end;
$$;

grant execute on function public.vestiario_magazzino_scarica(text, text, text, integer) to authenticated;
grant execute on function public.vestiario_magazzino_registra_arrivo(text, text, text, integer) to authenticated;
