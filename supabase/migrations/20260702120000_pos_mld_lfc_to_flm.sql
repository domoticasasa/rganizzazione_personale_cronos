-- Rinomina lista MLD LFC → FLM (POS commesse multifunzionali).

-- Dipendenti: elimina righe LFC duplicate se esiste già la stessa coppia commessa/personale in FLM.
delete from public.pos_commessa_dipendenti lfc
using public.pos_commessa_dipendenti flm
where upper(trim(lfc.lista_mld)) = 'LFC'
  and upper(trim(flm.lista_mld)) = 'FLM'
  and lfc.commessa_id = flm.commessa_id
  and lfc.personale_id = flm.personale_id;

update public.pos_commessa_dipendenti
set lista_mld = 'FLM'
where upper(trim(lista_mld)) = 'LFC';

-- Meta: unifica eventuale FLM esistente e rimuovi LFC.
delete from public.pos_commessa_lista_meta lfc
using public.pos_commessa_lista_meta flm
where upper(trim(lfc.lista_mld)) = 'LFC'
  and upper(trim(flm.lista_mld)) = 'FLM'
  and lfc.commessa_id = flm.commessa_id;

update public.pos_commessa_lista_meta
set lista_mld = 'FLM'
where upper(trim(lista_mld)) = 'LFC';
