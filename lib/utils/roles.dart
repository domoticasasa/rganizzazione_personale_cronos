String normalizeRole(String role) {
  final t = role.trim().toLowerCase().replaceAll(" ", "_").replaceAll("/", "_");
  if (t == "admin") return "admin_generale";
  if (t == "admin_generale") return "admin_generale";
  if (t == "admin_vista" ||
      t == "admin_readonly" ||
      t == "admin_sola_lettura" ||
      t == "admin_sola_vista") {
    return "admin_vista";
  }
  if (t == "admin_pernottamenti") return "admin_pernottamenti";
  if (t == "admin_treno_aereo" || t == "admin_trenoaereo") {
    return "admin_trenoaereo";
  }
  if (t == "assistente_dt") return "assistente_dt";
  return t;
}

bool isRistoratoreRole(String role) => normalizeRole(role) == 'ristoratore';

/// Admin con UI completa ma senza permessi di salvataggio.
bool isAdminVistaRole(String role) => normalizeRole(role) == 'admin_vista';

bool isAnyAdminRole(String role) {
  final r = normalizeRole(role);
  return r == "admin_generale" ||
      r == "admin_vista" ||
      r == "admin_pernottamenti" ||
      r == "admin_trenoaereo" ||
      r == "admin_formazione" ||
      r == "admin_dpi";
}

/// Scritture admin (insert/update/delete). Esclude [admin_vista].
bool canMutateAsAdmin(String role) =>
    isAnyAdminRole(role) && !isAdminVistaRole(role);

/// Riordino Home: solo admin che può salvare. DT/Assistente DT vedono
/// il layout globale (lo modifica l'admin dalla Vista DT).
bool canEditHomePageLayout(String role) {
  if (isAdminVistaRole(role)) return false;
  return canMutateAsAdmin(role);
}

bool isAdminGeneraleRole(String role) => normalizeRole(role) == "admin_generale";

/// Stessi moduli/tile di Admin generale: anche Admin pernottamenti (scrittura)
/// e Admin vista (sola lettura).
bool isAdminGeneraleLikeRole(String role) =>
    isAdminGeneraleRole(role) ||
    isAdminPernottamentiRole(role) ||
    isAdminVistaRole(role);

bool isAdminPernottamentiRole(String role) =>
    normalizeRole(role) == "admin_pernottamenti";
bool isAdminTrenoAereoRole(String role) =>
    normalizeRole(role) == "admin_trenoaereo";

/// Modifica MDO per commessa / trasferimenti: admin (non vista) e logistica.
bool canEditMdoPerCommessa(String role) {
  if (isAdminVistaRole(role)) return false;
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return canMutateAsAdmin(role) || r == 'logistica';
}

/// Modifica manuale storico assegnatari (passaggi 1–4): solo admin che può salvare.
bool canEditLogisticaStoricoAssegnatari(String role) => canMutateAsAdmin(role);

/// Assegnazione mezzi stradali (edit + PDF): solo admin che può salvare.
/// DT / logistica / admin_vista: sola lettura.
bool canEditAssegnazioneMezziStradali(String role) => canMutateAsAdmin(role);

/// Assegnazione Attrezzature (PDF): solo admin che può salvare.
bool canEditAssegnazioneAttrezzature(String role) => canMutateAsAdmin(role);

/// Assegnazione / gestione SIM telefoniche: admin (non vista) e logistica.
bool canEditLogisticaSim(String role) {
  if (isAdminVistaRole(role)) return false;
  final r = normalizeRole(role);
  return canMutateAsAdmin(role) || r == 'logistica';
}

/// Nuovo rifornimento RCC/MDO: dipendente, DT, assistente DT e logistica/admin.
bool canInsertLogisticaRifornimenti({
  required bool dipendenteMode,
  required String role,
}) {
  if (dipendenteMode) return true;
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return true;
  return canMutateAsAdmin(role) || r == 'logistica';
}

/// Verifica fatturazione QT (hub Carburante): admin e logistica, non DT.
bool canAccessQtCarburanteVerifica(String role) {
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return isAnyAdminRole(role) || r == 'logistica';
}

/// Hub «DPI e Vestiario» e relativi moduli: nascosti a DT / Assistente DT.
bool canAccessDpiVestiarioModule(String role) {
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return true;
}

bool isDpiVestiarioLayoutKey(String key) {
  if (key == 'dpi_hub' || key == 'dpi_uqsa') return true;
  if (key.startsWith('vestiario_')) return true;
  if (key.startsWith('dpi_')) return true;
  return false;
}

/// Modifica rifornimenti esistenti. Il [dt] non modifica; il [dipendente] sì (con lock MDO se completo).
bool canEditLogisticaRifornimenti({
  required bool dipendenteMode,
  required String role,
}) {
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  if (isAdminVistaRole(role)) return false;
  if (dipendenteMode) return true;
  return canMutateAsAdmin(role) || r == 'logistica';
}

/// Eliminazione: solo admin/logistica (né dipendente né DT).
bool canDeleteLogisticaRifornimenti({
  required bool dipendenteMode,
  required String role,
}) {
  if (dipendenteMode) return false;
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return canMutateAsAdmin(role) || r == 'logistica';
}

/// Alias di [canEditLogisticaRifornimenti].
bool canManageLogisticaRifornimenti({
  required bool dipendenteMode,
  required String role,
}) =>
    canEditLogisticaRifornimenti(dipendenteMode: dipendenteMode, role: role);

/// Elenco completo corsi con data programmazione (non solo i propri).
bool canViewProgrammazioneFormazioniList(String role) {
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return true;
  if (isAnyAdminRole(role)) return true;
  return r == 'admin_formazione' || r == 'uqsa';
}

/// Lista dipendenti POS per commessa (hub UQSA): admin, DT, formazione/UQSA.
bool canAccessPosDipendentiLista(String role) =>
    canViewProgrammazioneFormazioniList(role);

/// Inserimento / import / modifica lista POS: DT, assistente DT, UQSA, admin
/// (non admin vista).
bool canManagePosDipendentiLista(String role) {
  if (isAdminVistaRole(role)) return false;
  return canAccessPosDipendentiLista(role);
}

/// Elenco MdO ferroviari POS per commessa (hub UQSA): stessi ruoli della lista dipendenti.
bool canAccessPosMdoFerroviariLista(String role) =>
    canAccessPosDipendentiLista(role);

/// Inserimento / import / modifica elenco MdO POS.
bool canManagePosMdoFerroviariLista(String role) =>
    canManagePosDipendentiLista(role);

/// Elenco mezzi stradali POS per commessa (hub UQSA): stessi ruoli della lista dipendenti.
bool canAccessPosMezziStradaliLista(String role) =>
    canAccessPosDipendentiLista(role);

/// Inserimento / import / modifica elenco mezzi stradali POS.
bool canManagePosMezziStradaliLista(String role) =>
    canManagePosDipendentiLista(role);

/// Elenco MdO (proprietà/noleggio) POS per commessa: stessi ruoli della lista dipendenti.
bool canAccessPosMdoProprietaLista(String role) =>
    canAccessPosDipendentiLista(role);

/// Inserimento / import / modifica elenco MdO POS.
bool canManagePosMdoProprietaLista(String role) =>
    canManagePosDipendentiLista(role);

/// Hub Liste POS (aperto dal tile POS in UQSA): almeno una lista accessibile.
bool canAccessListePosHub(String role) =>
    canAccessPosDipendentiLista(role) ||
    canAccessPosMdoFerroviariLista(role) ||
    canAccessPosMezziStradaliLista(role) ||
    canAccessPosMdoProprietaLista(role);

/// Elenco programmazioni corsi RFI (stessi ruoli della programmazione D.Lgs.).
bool canViewProgrammazioneFormazioniRfiList(String role) =>
    canViewProgrammazioneFormazioniList(role);

/// Inserimento / modifica programmazione visite mediche.
bool canManageVisiteMediche(String role) {
  final r = normalizeRole(role);
  if (isAdminVistaRole(role)) return false;
  return canMutateAsAdmin(role) ||
      r == 'admin_dpi' ||
      r == 'admin_formazione';
}

/// Riepilogo visite (DT / assistente) o gestione (admin).
bool canViewVisiteMedicheList(String role) {
  final r = normalizeRole(role);
  return canManageVisiteMediche(role) ||
      isAdminVistaRole(role) ||
      r == 'dt' ||
      r == 'assistente_dt';
}

/// Inserimento / modifica permessi, ferie, malattia, infortunio.
bool canManageDipendenteAssenze(String role) => canManageVisiteMediche(role);

/// Registro «Segnalazione assenze»: scrittura solo admin (non DT / admin vista).
bool canMutateSegnalazioneAssenze(String role) =>
    canManageDipendenteAssenze(role);

/// Elenco assenze: admin (modifica) o DT / assistente DT (sola lettura).
bool canViewDipendenteAssenzeList(String role, [String? secondaryRole]) {
  if (hasDtWorkflowRole(role, secondaryRole)) return true;
  final r = normalizeRole(role);
  return canManageDipendenteAssenze(role) ||
      isAdminVistaRole(role) ||
      r == 'dipendente' ||
      r == 'user' ||
      r == 'caposquadra';
}

/// Scrittura Formazione D.Lgs. 81/08 (griglia corsi, strutture, programmazione).
/// Solo Admin Pernottamenti; tutti gli altri ruoli (incluso Admin Generale) solo lettura.
bool canManageFormazioneDlgs81Griglia(String role) =>
    isAdminPernottamentiRole(role);

/// Archivio attestati UQSA (upload/modifica/elimina file RFI e D.Lgs. 81/08).
/// DT e admin vista: sola consultazione.
bool canManageUqsaAttestati(String role) {
  if (isAdminVistaRole(role)) return false;
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return r == 'uqsa' ||
      r == 'admin_formazione' ||
      r == 'admin_pernottamenti' ||
      isAdminGeneraleRole(role);
}

/// Comparire nelle liste «Seleziona DT» (ruolo primario o secondario).
bool isDtSelectableRole(String? primaryRole, [String? secondaryRole]) {
  final p = normalizeRole(primaryRole ?? '');
  final s = (secondaryRole ?? '').trim().isEmpty
      ? ''
      : normalizeRole(secondaryRole!);
  if (p == 'dt' || p == 'assistente_dt') return true;
  if (s == 'dt' || s == 'assistente_dt') return true;
  return false;
}

/// Workflow ferie/permessi come DT (ruolo primario o secondario).
bool hasDtWorkflowRole(String? primaryRole, [String? secondaryRole]) =>
    isDtSelectableRole(primaryRole, secondaryRole);
