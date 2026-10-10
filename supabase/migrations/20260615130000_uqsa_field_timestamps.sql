-- Audit per singolo campo (UQSA: formazione, POS).

do $$
declare
  t text;
  tables text[] := array[
    'formazione_corsi',
    'formazione_rfi_records',
    'formazione_rfi_corsi',
    'pos_commessa_dipendenti',
    'pos_commessa_lista_meta'
  ];
begin
  foreach t in array tables
  loop
    if to_regclass(format('public.%I', t)) is null then
      continue;
    end if;
    execute format(
      'alter table public.%I add column if not exists field_timestamps jsonb not null default ''{}''::jsonb;',
      t
    );
    execute format(
      'drop trigger if exists trg_%I_field_timestamps on public.%I;',
      t, t
    );
    execute format(
      'create trigger trg_%I_field_timestamps before insert or update on public.%I for each row execute function public.set_field_timestamps();',
      t, t
    );
  end loop;
end $$;
