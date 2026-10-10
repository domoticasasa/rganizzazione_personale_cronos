class AppPagePermission {
  final String key;
  final String label;
  final bool showInCustomRoles;

  const AppPagePermission({
    required this.key,
    required this.label,
    this.showInCustomRoles = true,
  });
}

const kAppPagePermissions = <AppPagePermission>[
  AppPagePermission(key: 'richiedi_treno', label: 'Richiedi Treno'),
  AppPagePermission(key: 'richiedi_aereo', label: 'Richiedi Aereo'),
  AppPagePermission(key: 'notifiche', label: 'Notifiche'),
  AppPagePermission(key: 'pernottamenti', label: 'Pernottamenti'),
  AppPagePermission(key: 'treni', label: 'Treni'),
  AppPagePermission(key: 'aerei', label: 'Aerei'),
  AppPagePermission(key: 'uqsa', label: 'UQSA'),
  AppPagePermission(
    key: 'pos_dipendenti_lista',
    label: 'Lista dipendenti POS',
  ),
  AppPagePermission(
    key: 'pos_mdo_ferroviari_lista',
    label: 'Elenco MdO Ferroviari POS',
  ),
  AppPagePermission(
    key: 'pos_mezzi_stradali_lista',
    label: 'Elenco Mezzi Stradali POS',
  ),
  AppPagePermission(
    key: 'pos_mdo_proprieta_lista',
    label: 'Elenco MdO POS',
  ),
  AppPagePermission(
    key: 'liste_pos_hub',
    label: 'Liste POS',
  ),
  AppPagePermission(key: 'logistica', label: 'Logistica'),
  AppPagePermission(key: 'logistica_box', label: 'Logistica - BOX'),
  AppPagePermission(
      key: 'logistica_mdo_ferroviari', label: 'Logistica - MDO Ferroviari'),
  AppPagePermission(
      key: 'logistica_mdo_proprieta', label: 'Logistica - MDO Proprietà'),
  AppPagePermission(
      key: 'mdo_check_riepilogo', label: 'Logistica - Riepilogo check MDO'),
  AppPagePermission(
      key: 'mdo_mappa_gps', label: 'Logistica - Mappa MDO GPS'),
  AppPagePermission(
      key: 'logistica_casette_ps', label: 'Logistica - Cassette P.S.'),
  AppPagePermission(
      key: 'logistica_attrezzature', label: 'Logistica - Attrezzature'),
  AppPagePermission(
    key: 'logistica_assegnazione_attrezzature',
    label: 'Logistica - Assegnazione Attrezzature',
  ),
  AppPagePermission(
      key: 'logistica_mezzi_stradali', label: 'Logistica - Mezzi Stradali'),
  AppPagePermission(
    key: 'logistica_assegnazione_mezzi_stradali',
    label: 'Logistica - Assegnazione mezzi stradali',
  ),
  AppPagePermission(
      key: 'viaggi_mezzi_stradali', label: 'Logistica - Viaggi mezzi stradali'),
  AppPagePermission(
      key: 'viaggi_mezzi_scan', label: 'Scansiona viaggio mezzo'),
  AppPagePermission(
      key: 'viaggi_mezzi_riepilogo', label: 'I miei viaggi mezzo'),
  AppPagePermission(
      key: 'viaggi_mezzi_assegnatario', label: 'Viaggi sui miei mezzi'),
  AppPagePermission(
      key: 'logistica_multicard', label: 'Logistica - Multicard'),
  AppPagePermission(
    key: 'multicard_mdo_assegnazioni',
    label: 'Logistica — Assegnazioni Multicard MDO',
  ),
  AppPagePermission(
      key: 'logistica_telepass', label: 'Logistica - Telepass'),
  AppPagePermission(
      key: 'logistica_rifornimento_mdo', label: 'Logistica - Rifornimento MDO'),
  AppPagePermission(key: 'logistica_noleggio', label: 'Logistica - Noleggio'),
  AppPagePermission(
      key: 'logistica_officine_convenzionate',
      label: 'Logistica - Officine convenzionate'),
  AppPagePermission(key: 'tesserino', label: 'Tesserino'),
  AppPagePermission(key: 'estintori', label: 'Estintori'),
  AppPagePermission(
    key: 'uqsa_sedi_sicurezza',
    label: 'UQSA — Sedi sicurezza (BOX/MDO/mezzi/altro · estintori/cassette)',
  ),
  AppPagePermission(key: 'formazione_hub', label: 'Formazione Hub'),
  AppPagePermission(
    key: 'formazione_dlgs_81_08',
    label: 'Formazione D.Lgs. 81/08',
  ),
  AppPagePermission(key: 'formazione_rfi', label: 'Formazione RFI'),
  AppPagePermission(
    key: 'attestati_dipendenti',
    label: 'Formazione — Attestati (RFI e D.Lgs. 81/08)',
  ),
  AppPagePermission(
    key: 'programmazione_formazioni',
    label: 'Programmazione Formazioni',
  ),
  AppPagePermission(
    key: 'programmazione_formazioni_rfi',
    label: 'Programmazioni corsi RFI',
  ),
  AppPagePermission(key: 'visite_mediche', label: 'Visite mediche'),
  AppPagePermission(key: 'visite_mediche_rfi', label: 'Visite mediche RFI'),
  AppPagePermission(
    key: 'dipendente_assenze',
    label: 'Permessi / Ferie / Assenze (dipendente)',
  ),
  AppPagePermission(
    key: 'richieste_ferie_permessi',
    label: 'Richieste ferie / permessi (workflow)',
  ),
  AppPagePermission(
    key: 'segnalazione_assenze',
    label: 'Segnalazione assenze (malattia, infortunio, …)',
  ),
  AppPagePermission(
    key: 'commesse_cig_cup',
    label: 'Commesse CIG/CUP',
  ),
  AppPagePermission(
    key: 'dislocazione_personale',
    label: 'Dislocazione Personale',
  ),
  AppPagePermission(
    key: 'verifica_costo_stradale',
    label: 'Verifica costo stradale',
  ),
  AppPagePermission(key: 'scadenze_alert', label: 'Alert scadenze'),
  AppPagePermission(key: 'tesserini', label: 'Tesserini'),
  AppPagePermission(key: 'dpi', label: 'DPI'),
  AppPagePermission(key: 'dotazioni_dpi', label: 'Dotazioni DPI'),
  AppPagePermission(key: 'misure_vestiario', label: 'Misure Vestiario'),
  AppPagePermission(key: 'vestiario_report', label: 'Riepilogo Vestiario'),
  AppPagePermission(
      key: 'vestiario_fabbisogno_taglie', label: 'Fabbisogno Taglie'),
  AppPagePermission(
      key: 'vestiario_categorie', label: 'Categorie Vestiario'),
  AppPagePermission(
      key: 'vestiario_inventario', label: 'Inventario Vestiario'),
  AppPagePermission(key: 'admin_dashboard', label: 'Admin Dashboard'),
  AppPagePermission(
    key: 'anteprima_vista_ruolo',
    label: 'Anteprima vista ruolo',
  ),
  AppPagePermission(
    key: 'richieste_da_approvare',
    label: 'Richieste da approvare',
  ),
  AppPagePermission(
    key: 'mdo_ferroviari',
    label: 'MDO Ferroviari',
  ),
  AppPagePermission(
    key: 'mdo_ferroviari_documenti',
    label: 'Logistica — Documenti MDO ferroviari',
  ),
  AppPagePermission(
    key: 'mezzi_stradali',
    label: 'Mezzi Stradali',
  ),
  AppPagePermission(
    key: 'permessi_assistenti_dt',
    label: 'Permessi Assistenti DT',
  ),
  AppPagePermission(key: 'rubrica', label: 'Rubrica'),
  AppPagePermission(key: 'buoni_pasto_admin', label: 'Buoni pasto (admin)'),
  AppPagePermission(key: 'bacheca', label: 'Bacheca comunicazioni'),
  AppPagePermission(
    key: 'buoni_pasto_ristoratore',
    label: 'Buoni pasto (ristoratore)',
    showInCustomRoles: false,
  ),
  AppPagePermission(
    key: 'buoni_pasto_scan',
    label: 'Scansiona buono pasto',
    showInCustomRoles: false,
  ),
  AppPagePermission(
    key: 'buoni_pasto_riepilogo',
    label: 'Riepilogo buoni pasto',
    showInCustomRoles: false,
  ),
];
