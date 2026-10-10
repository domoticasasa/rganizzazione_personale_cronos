-- Programmazione D.Lgs. 81/08: solo admin_generale e admin_pernottamenti possono aggiornare i corsi.

drop policy if exists formazione_corsi_dt_programmazione_update on public.formazione_corsi;
