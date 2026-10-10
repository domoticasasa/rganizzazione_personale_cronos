-- Ore / fascia oraria per permessi (giornata intera se null).

alter table public.dipendente_assenze
  add column if not exists ore_permesso numeric(5, 2),
  add column if not exists ora_inizio time,
  add column if not exists ora_fine time;

alter table public.dipendente_assenze
  drop constraint if exists dipendente_assenze_ore_permesso_range;

alter table public.dipendente_assenze
  add constraint dipendente_assenze_ore_permesso_range check (
    ore_permesso is null or (ore_permesso > 0 and ore_permesso <= 24)
  );

alter table public.dipendente_assenze
  drop constraint if exists dipendente_assenze_permesso_ore_tipo;

alter table public.dipendente_assenze
  add constraint dipendente_assenze_permesso_ore_tipo check (
    tipo_assenza = 'PERMESSO'
    or (
      ore_permesso is null
      and ora_inizio is null
      and ora_fine is null
    )
  );
