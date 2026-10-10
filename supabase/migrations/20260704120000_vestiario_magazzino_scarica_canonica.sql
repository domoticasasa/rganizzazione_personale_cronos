-- Scarico magazzino: stagione canonica (stock unificato estivo, guanti invernale).

create or replace function public.vestiario_magazzino_stagione_canonica(p_articolo text)
returns text
language sql
immutable
as $$
  select case
    when trim(coalesce(p_articolo, '')) = 'guanti' then 'invernale'
    else 'estivo'
  end;
$$;

create or replace function public.vestiario_magazzino_quantita(
  p_articolo text,
  p_taglia text
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  with canon as (
    select public.vestiario_magazzino_stagione_canonica(p_articolo) as s
  )
  select coalesce(
    (
      select m.quantita
      from public.vestiario_magazzino m, canon c
      where m.stagione = c.s
        and m.articolo = trim(p_articolo)
        and m.taglia = trim(p_taglia)
    ),
    (
      select m.quantita
      from public.vestiario_magazzino m, canon c
      where m.stagione = case when c.s = 'estivo' then 'invernale' else 'estivo' end
        and m.articolo = trim(p_articolo)
        and m.taglia = trim(p_taglia)
    ),
    0
  );
$$;

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
  v_stagione text;
  v_old integer;
  v_new integer;
  v_legacy_stagione text;
begin
  if not public.is_vestiario_magazzino_user() then
    raise exception 'Permesso negato su inventario vestiario';
  end if;

  if p_quantita is null or p_quantita <= 0 then
    return;
  end if;

  v_stagione := public.vestiario_magazzino_stagione_canonica(p_articolo);
  v_legacy_stagione := case when v_stagione = 'estivo' then 'invernale' else 'estivo' end;

  insert into public.vestiario_magazzino (stagione, articolo, taglia, quantita)
  values (v_stagione, trim(p_articolo), trim(p_taglia), 0)
  on conflict (stagione, articolo, taglia) do nothing;

  v_old := public.vestiario_magazzino_quantita(trim(p_articolo), trim(p_taglia));

  update public.vestiario_magazzino m
  set quantita = v_old
  where m.stagione = v_stagione
    and m.articolo = trim(p_articolo)
    and m.taglia = trim(p_taglia);

  delete from public.vestiario_magazzino m
  where m.stagione = v_legacy_stagione
    and m.articolo = trim(p_articolo)
    and m.taglia = trim(p_taglia)
    and trim(p_articolo) <> 'guanti';

  v_new := greatest(0, v_old - p_quantita);

  update public.vestiario_magazzino m
  set quantita = v_new
  where m.stagione = v_stagione
    and m.articolo = trim(p_articolo)
    and m.taglia = trim(p_taglia);

  quantita_residua := v_new;
  insufficiente := v_old < p_quantita;
  return next;
end;
$$;

grant execute on function public.vestiario_magazzino_stagione_canonica(text) to authenticated;
grant execute on function public.vestiario_magazzino_quantita(text, text) to authenticated;
