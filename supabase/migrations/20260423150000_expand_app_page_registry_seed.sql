insert into public.app_page_registry (page_key, label, active)
values
  ('richiedi_treno', 'Richiedi Treno', true),
  ('richiedi_aereo', 'Richiedi Aereo', true),
  ('notifiche', 'Notifiche', true),
  ('pernottamenti', 'Pernottamenti', true),
  ('treni', 'Treni', true),
  ('aerei', 'Aerei', true),
  ('uqsa', 'UQSA', true),
  ('logistica', 'Logistica', true),
  ('logistica_box', 'Logistica - BOX', true),
  ('logistica_mdo_ferroviari', 'Logistica - MDO Ferroviari', true),
  ('logistica_casette_ps', 'Logistica - Casette P.S', true),
  ('estintori', 'Estintori', true),
  ('formazione_hub', 'Formazione Hub', true),
  ('formazione_dlgs_81_08', 'Formazione D.Lgs. 81/08', true),
  ('formazione_rfi', 'Formazione RFI', true),
  ('dpi', 'DPI', true),
  ('dotazioni_dpi', 'Dotazioni DPI', true),
  ('misure_vestiario', 'Misure Vestiario', true),
  ('vestiario_report', 'Riepilogo Vestiario', true),
  ('vestiario_fabbisogno_taglie', 'Fabbisogno Taglie', true),
  ('admin_dashboard', 'Admin Dashboard', true),
  ('anteprima_vista_ruolo', 'Anteprima vista ruolo', true),
  ('richieste_da_approvare', 'Richieste da approvare', true),
  ('mdo_ferroviari', 'MDO Ferroviari', true),
  ('permessi_assistenti_dt', 'Permessi Assistenti DT', true)
on conflict (page_key) do update
set label = excluded.label,
    active = true;

