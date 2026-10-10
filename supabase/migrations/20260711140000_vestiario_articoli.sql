-- Catalogo articoli vestiario (magazzino, assegnazione, fabbisogno taglie).

create table if not exists public.vestiario_articoli (
  articolo_key text primary key,
  label text not null,
  active boolean not null default true,
  size_type text not null default 'top'
    check (size_type in ('top', 'trouser', 'shoe', 'glove', 'unit', 'none')),
  in_magazzino boolean not null default true,
  in_assegnazione boolean not null default false,
  stagione_estivo boolean not null default true,
  stagione_invernale boolean not null default true,
  modello_unico boolean not null default false,
  is_dpi_iii boolean not null default false,
  magazzino_stagione_unica text
    check (magazzino_stagione_unica is null or magazzino_stagione_unica in ('estivo', 'invernale')),
  moltiplicatore_estivo integer not null default 0 check (moltiplicatore_estivo >= 0),
  moltiplicatore_invernale integer not null default 0 check (moltiplicatore_invernale >= 0),
  sort_order integer not null default 100,
  excel_rows text,
  size_label text,
  taglia_personale_field text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.app_page_registry (page_key, label, active)
values ('vestiario_categorie', 'Categorie Vestiario', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

grant select, insert, update, delete on public.vestiario_articoli to authenticated;

alter table public.vestiario_articoli enable row level security;

drop policy if exists vestiario_articoli_all on public.vestiario_articoli;
create policy vestiario_articoli_all
on public.vestiario_articoli
for all
to authenticated
using (public.is_vestiario_magazzino_user())
with check (public.is_vestiario_magazzino_user());

insert into public.vestiario_articoli (
  articolo_key, label, size_type, in_magazzino, in_assegnazione,
  stagione_estivo, stagione_invernale, modello_unico, is_dpi_iii,
  magazzino_stagione_unica, moltiplicatore_estivo, moltiplicatore_invernale,
  sort_order, excel_rows, size_label, taglia_personale_field
) values
  ('scarpe', 'Scarpe', 'shoe', true, true, true, true, true, false, null, 1, 1, 10, '15', 'Scarpe', 'taglia_scarpe'),
  ('occhiali', 'Occhiale Paraschegge', 'none', false, true, true, true, false, false, null, 0, 0, 16, '16', null, null),
  ('archetti', 'Archetti Antirumore', 'none', false, true, true, true, false, false, null, 0, 0, 17, '17', null, null),
  ('cuffie', 'Cuffie Antirumore', 'none', false, true, true, true, false, false, null, 0, 0, 18, '18', null, null),
  ('guanti_pelle', 'Guanti pelle', 'glove', true, true, false, true, true, false, 'invernale', 0, 1, 19, '19', 'Guanti', 'taglia_guanti'),
  ('guanti_tessuto', 'Guanti tessuto (nylon/poliuretano)', 'glove', true, true, false, true, true, false, 'invernale', 0, 1, 20, '20', 'Guanti', 'taglia_guanti'),
  ('gilet', 'Gilet', 'top', true, true, true, true, true, false, null, 1, 1, 21, '21', 'Gilet', 'taglia_gilet'),
  ('tshirt', 'T-shirt', 'top', true, true, true, true, true, false, null, 1, 1, 22, '22', 'T-shirt', 'taglia_tshirt'),
  ('pantalone', 'Pantalone', 'trouser', true, true, true, true, false, false, null, 1, 1, 24, '24', 'Pantalone', 'taglia_pantalone'),
  ('felpa', 'Felpa', 'top', true, true, false, true, false, false, null, 0, 1, 25, '25', 'Felpa', 'taglia_felpa'),
  ('giacca_leggera', 'Giacca leggera', 'top', true, true, true, false, false, false, null, 1, 0, 26, '26', 'Giacca', 'taglia_giacca'),
  ('giacca', 'Giacca', 'top', true, true, false, true, false, false, null, 0, 1, 27, '26', 'Giacca', 'taglia_giacca'),
  ('borsa_dpi', 'Borsa Porta DPI 48x50x35', 'none', false, true, true, true, false, false, null, 0, 0, 28, '27', null, null),
  ('lampada_frontale', 'Lampada Frontale', 'none', false, true, true, true, false, false, null, 0, 0, 29, '28', null, null),
  ('completo_antipioggia', 'Completo Antipioggia', 'none', false, true, true, true, false, false, null, 0, 0, 30, '29', null, null),
  ('berretto_lana', 'Berretto in Lana', 'none', false, true, false, true, false, false, null, 0, 0, 31, '30', null, null),
  ('elmetto', 'Elmetto', 'unit', true, false, true, false, false, true, 'estivo', 0, 0, 40, null, null, null),
  ('imbracatura', 'Imbracatura', 'unit', true, false, true, false, false, true, 'estivo', 0, 0, 41, null, null, null),
  ('cordino_singolo_dissipatore', 'Cordino singolo con dissipatore', 'unit', true, false, true, false, false, true, 'estivo', 0, 0, 42, null, null, null),
  ('cordino_posizionamento', 'Cordino di posizionamento', 'unit', true, false, true, false, false, true, 'estivo', 0, 0, 43, null, null, null),
  ('cordino_y_dissipatore', 'Cordino Shock Absorber Doppio', 'unit', true, false, true, false, false, true, 'estivo', 0, 0, 44, null, null, null)
on conflict (articolo_key) do update
set label = excluded.label,
    active = true,
    updated_at = now();
