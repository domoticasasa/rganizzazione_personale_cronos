update public.logistica_casette_ps
set tipo_cassetta = 'ALLEGATO 1 (piu di 3 lavoratori)'
where upper(trim(coalesce(tipo_cassetta, ''))) in (
  'ALL1',
  'ALLEGATO 1',
  'ALLEGATO 1 (PIU DI 3 LAVORATORI)'
);

update public.logistica_casette_ps
set tipo_cassetta = 'ALLEGATO 2 (fino a 3 lavoratori)'
where upper(trim(coalesce(tipo_cassetta, ''))) in (
  'ALL2',
  'ALLEGATO 2',
  'ALLEGATO 2 (FINO A 3 LAVORATORI)'
);
