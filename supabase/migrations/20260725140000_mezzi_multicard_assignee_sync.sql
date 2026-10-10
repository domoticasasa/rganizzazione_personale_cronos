-- Propaga assegnatario (e periodi) da Mezzi Stradali alle multicard collegate per targa.

create or replace function public.trg_logistica_mezzi_sync_multicard_assignee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_targa text := nullif(trim(coalesce(new.targa, '')), '');
begin
  if v_targa is null then
    return new;
  end if;

  if to_regclass('public.logistica_multicard') is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if coalesce(new.assegnatario_attuale, '') is not distinct from coalesce(old.assegnatario_attuale, '')
       and coalesce(new.assegnatario_user_uuid::text, '') is not distinct from coalesce(old.assegnatario_user_uuid::text, '')
       and new.periodo_assegnatario_attuale is not distinct from old.periodo_assegnatario_attuale
       and new.data_fine_assegnatario_attuale is not distinct from old.data_fine_assegnatario_attuale then
      return new;
    end if;
  end if;

  update public.logistica_multicard c
  set
    assegnatario_attuale = new.assegnatario_attuale,
    assegnatario_user_uuid = new.assegnatario_user_uuid,
    periodo_assegnatario_attuale = new.periodo_assegnatario_attuale,
    data_fine_assegnatario_attuale = new.data_fine_assegnatario_attuale,
    updated_at = now()
  where lower(trim(coalesce(c.mezzo_targa, ''))) = lower(v_targa);

  return new;
end;
$$;

drop trigger if exists trg_logistica_mezzi_sync_multicard_assignee
  on public.logistica_mezzi_stradali;

create trigger trg_logistica_mezzi_sync_multicard_assignee
after insert or update of
  targa,
  assegnatario_attuale,
  assegnatario_user_uuid,
  periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale
on public.logistica_mezzi_stradali
for each row
execute function public.trg_logistica_mezzi_sync_multicard_assignee();

-- Allineamento una tantum dati già presenti.
update public.logistica_multicard c
set
  assegnatario_attuale = m.assegnatario_attuale,
  assegnatario_user_uuid = m.assegnatario_user_uuid,
  periodo_assegnatario_attuale = m.periodo_assegnatario_attuale,
  data_fine_assegnatario_attuale = m.data_fine_assegnatario_attuale,
  updated_at = now()
from public.logistica_mezzi_stradali m
where lower(trim(coalesce(c.mezzo_targa, ''))) = lower(trim(coalesce(m.targa, '')))
  and nullif(trim(coalesce(c.mezzo_targa, '')), '') is not null
  and (
    coalesce(c.assegnatario_attuale, '') is distinct from coalesce(m.assegnatario_attuale, '')
    or coalesce(c.assegnatario_user_uuid::text, '') is distinct from coalesce(m.assegnatario_user_uuid::text, '')
    or c.periodo_assegnatario_attuale is distinct from m.periodo_assegnatario_attuale
    or c.data_fine_assegnatario_attuale is distinct from m.data_fine_assegnatario_attuale
  );
