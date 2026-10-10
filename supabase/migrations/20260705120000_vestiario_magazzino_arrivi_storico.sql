-- Storico arrivi magazzino vestiario (quantità e data).

create table if not exists public.vestiario_magazzino_arrivi (
  id uuid primary key default gen_random_uuid(),
  stagione text not null check (stagione in ('estivo', 'invernale')),
  articolo text not null,
  taglia text not null,
  quantita integer not null check (quantita > 0),
  arrivato_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null
);

create index if not exists vestiario_magazzino_arrivi_articolo_idx
  on public.vestiario_magazzino_arrivi (articolo, taglia, arrivato_at desc);

create index if not exists vestiario_magazzino_arrivi_arrivato_at_idx
  on public.vestiario_magazzino_arrivi (arrivato_at desc);

grant select on public.vestiario_magazzino_arrivi to authenticated;

alter table public.vestiario_magazzino_arrivi enable row level security;

drop policy if exists vestiario_magazzino_arrivi_select on public.vestiario_magazzino_arrivi;
create policy vestiario_magazzino_arrivi_select
on public.vestiario_magazzino_arrivi
for select
to authenticated
using (public.is_vestiario_magazzino_user());

-- Registra arrivo: aggiorna giacenza, scala ordinato, scrive storico.
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
  v_stagione text;
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

  v_stagione := public.vestiario_magazzino_stagione_canonica(p_articolo);

  insert into public.vestiario_magazzino (
    stagione, articolo, taglia, quantita, quantita_ordinata, quantita_arrivata_totale
  )
  values (v_stagione, trim(p_articolo), trim(p_taglia), 0, 0, 0)
  on conflict (stagione, articolo, taglia) do nothing;

  select m.quantita, m.quantita_ordinata, m.quantita_arrivata_totale
  into v_mag, v_ord, v_arr
  from public.vestiario_magazzino m
  where m.stagione = v_stagione
    and m.articolo = trim(p_articolo)
    and m.taglia = trim(p_taglia)
  for update;

  v_mag := coalesce(v_mag, 0) + p_quantita;
  v_arr := coalesce(v_arr, 0) + p_quantita;
  v_ord := greatest(0, coalesce(v_ord, 0) - p_quantita);

  update public.vestiario_magazzino m
  set
    quantita = v_mag,
    quantita_ordinata = v_ord,
    quantita_arrivata_totale = v_arr
  where m.stagione = v_stagione
    and m.articolo = trim(p_articolo)
    and m.taglia = trim(p_taglia);

  insert into public.vestiario_magazzino_arrivi (
    stagione, articolo, taglia, quantita, arrivato_at, created_by
  )
  values (
    v_stagione,
    trim(p_articolo),
    trim(p_taglia),
    p_quantita,
    now(),
    auth.uid()
  );

  quantita_magazzino := v_mag;
  quantita_ordinata := v_ord;
  quantita_arrivata_totale := v_arr;
  return next;
end;
$$;

grant execute on function public.vestiario_magazzino_registra_arrivo(text, text, text, integer) to authenticated;
