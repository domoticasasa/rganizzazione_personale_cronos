-- Sincronizza buoni_pasto_ristoranti con structures (flag RISTORANTE).

create or replace function public.sync_buoni_pasto_ristoranti_da_structures()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.buoni_pasto_ristoranti (structure_id_uuid, attivo)
  select s.id_uuid, false
  from public.structures s
  where s.is_ristorante = true
    and not exists (
      select 1
      from public.buoni_pasto_ristoranti r
      where r.structure_id_uuid = s.id_uuid
    );

  update public.buoni_pasto_ristoranti r
  set attivo = false
  from public.structures s
  where r.structure_id_uuid = s.id_uuid
    and coalesce(s.is_ristorante, false) = false;
end;
$$;

grant execute on function public.sync_buoni_pasto_ristoranti_da_structures() to authenticated;

create or replace function public.trg_structure_buoni_pasto_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.is_ristorante = true then
    insert into public.buoni_pasto_ristoranti (structure_id_uuid, attivo)
    values (new.id_uuid, false)
    on conflict (structure_id_uuid) do nothing;
  else
    update public.buoni_pasto_ristoranti
    set attivo = false
    where structure_id_uuid = new.id_uuid;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_structures_buoni_pasto_sync on public.structures;
create trigger trg_structures_buoni_pasto_sync
after insert or update of is_ristorante on public.structures
for each row execute function public.trg_structure_buoni_pasto_sync();

select public.sync_buoni_pasto_ristoranti_da_structures();

notify pgrst, 'reload schema';
