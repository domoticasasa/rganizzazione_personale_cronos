import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/admin_scadenze_alert_mobile_page.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/admin_aerei_mobile.dart';
import '../Mobile/admin_pernottamenti_mobile.dart';
import '../Mobile/admin_treni_mobile.dart';
import '../pages/admin_carburante_hub_page.dart';
import '../pages/admin_documenti_firma_page.dart';
import '../pages/admin_bacheca_page.dart';
import '../pages/admin_formazione_hub_page.dart';
import '../pages/admin_formazione_rfi_page.dart';
import '../pages/admin_logistica_hub_page.dart';
import '../pages/admin_logistica_mdo_mappa_page.dart';
import '../pages/admin_pernottamenti_page.dart';
import '../pages/admin_scadenze_alert_page.dart';
import '../pages/admin_treni_page.dart';
import '../pages/admin_aerei_page.dart';
import '../pages/admin_buoni_pasto_page.dart';
import '../pages/admin_commesse_cig_cup_page.dart';
import '../pages/admin_dipendente_assenze_page.dart';
import '../pages/admin_visite_mediche_page.dart';
import '../pages/admin_formazione_dlgs_81_08_page.dart';
import '../pages/admin_uqsa_attestati_page.dart';
import '../pages/dt_programmazione_formazioni_page.dart';
import '../pages/dt_programmazione_formazioni_rfi_page.dart';
import '../pages/dt_rubrica_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/dislocazione_personale_access.dart';
import '../utils/mobile_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

List<AdminHubNavItem> buildDashboardHubNavItems(
  BuildContext context, {
  required int adminId,
  String? role,
  Set<String>? customAllowedPages,
}) {
  const home = AppUiLayoutService.layoutDashboardAdmin;
  final normalizedRole = normalizeRole(role ?? '');
  final isGenerale = isAdminGeneraleLikeRole(normalizedRole);
  final isBuiltInRole = const {
    'admin_generale',
    'admin_vista',
    'admin_pernottamenti',
    'admin_trenoaereo',
    'admin_dpi',
    'admin_formazione',
    'uqsa',
    'caposquadra',
    'dt',
    'assistente_dt',
    'user',
    'dipendente',
    'admin',
  }.contains(normalizedRole);

  bool canForCustom(String pageKey) {
    if (isBuiltInRole) return true;
    return (customAllowedPages ?? const <String>{}).contains(pageKey);
  }

  return <AdminHubNavItem>[
    if (canForCustom('pernottamenti'))
      AdminHubNavItem(
        layoutKey: 'pernottamenti',
        defaultLayoutKey: home,
        icon: Icons.bed_outlined,
        label: 'Pernottamenti',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminPernottiMobilePage()
            : const AdminPernottiPage(),
      ),
    if (canForCustom('treni'))
      AdminHubNavItem(
        layoutKey: 'treni',
        defaultLayoutKey: home,
        icon: Icons.train_outlined,
        label: 'Treni',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminTreniMobilePage(adminId: adminId)
            : AdminTreniPage(adminId: adminId),
      ),
    if (canForCustom('aerei'))
      AdminHubNavItem(
        layoutKey: 'aerei',
        defaultLayoutKey: home,
        icon: Icons.flight_takeoff_outlined,
        label: 'Aerei',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminAereiMobilePage(adminId: adminId)
            : AdminAereiPage(adminId: adminId),
      ),
    if (isGenerale || canForCustom('visite_mediche'))
      AdminHubNavItem(
        layoutKey: 'visite_mediche',
        defaultLayoutKey: home,
        icon: Icons.medical_services_outlined,
        label: 'Visite mediche',
        onTap: (ctx) => useMobileUi(ctx)
            ? const VisiteMedicheMobilePage(adminMode: true)
            : const VisiteMedichePage(adminMode: true),
      ),
    if (ModuleVisibilityFlags.showDtRichiesteFeriePermessi &&
        (isGenerale || canForCustom('richieste_ferie_permessi')))
      AdminHubNavItem(
        layoutKey: 'richieste_ferie_permessi',
        defaultLayoutKey: home,
        icon: Icons.beach_access_outlined,
        label: 'Richieste ferie / permessi',
        subtitle: 'Inserimento DT → approvazione admin',
        onTap: (ctx) => useMobileUi(ctx)
            ? DipendenteAssenzeMobilePage(
                pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
                userId: adminId,
                role: role,
              )
            : DipendenteAssenzePage(
                pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
                userId: adminId,
                role: role,
              ),
      ),
    if (isGenerale || canForCustom('segnalazione_assenze'))
      AdminHubNavItem(
        layoutKey: 'segnalazione_assenze',
        defaultLayoutKey: home,
        icon: Icons.medical_information_outlined,
        label: 'Segnalazione assenze',
        subtitle: 'Malattia, infortunio, permessi, ferie',
        onTap: (ctx) => useMobileUi(ctx)
            ? DipendenteAssenzeMobilePage(
                pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
                readOnly: !canMutateSegnalazioneAssenze(role ?? ''),
                userId: adminId,
                role: role,
              )
            : DipendenteAssenzePage(
                pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
                readOnly: !canMutateSegnalazioneAssenze(role ?? ''),
                userId: adminId,
                role: role,
              ),
      ),
    if (isGenerale || canForCustom('rubrica'))
      AdminHubNavItem(
        layoutKey: 'rubrica',
        defaultLayoutKey: home,
        icon: Icons.contacts_outlined,
        label: 'Rubrica',
        subtitle: 'Nome, telefono, email e età',
        onTap: (ctx) => const DtRubricaPage(),
      ),
    if (isGenerale || canForCustom('commesse_cig_cup'))
      AdminHubNavItem(
        layoutKey: 'commesse_cig_cup',
        defaultLayoutKey: home,
        icon: Icons.badge_outlined,
        label: 'Commesse CIG / CUP',
        subtitle: 'CIG, CIG derivato e CUP per commessa',
        onTap: (ctx) => AdminCommesseCigCupPage(
          userId: adminId,
          role: role,
          readOnly: normalizedRole == 'dt' || normalizedRole == 'assistente_dt',
        ),
      ),
    if (isGenerale || canForCustom('buoni_pasto_admin'))
      AdminHubNavItem(
        layoutKey: 'buoni_pasto_admin',
        defaultLayoutKey: home,
        icon: Icons.qr_code_scanner_outlined,
        label: 'Buoni pasto',
        subtitle: 'QR ristoranti, credenziali e report',
        onTap: (ctx) => const AdminBuoniPastoPage(),
      ),
    if (isGenerale || canForCustom('dislocazione_personale'))
      AdminHubNavItem(
        layoutKey: 'dislocazione_personale',
        defaultLayoutKey: home,
        icon: Icons.groups_outlined,
        label: 'Dislocazione Personale',
        subtitle: 'Assegnazione personale a commesse/stati per periodo',
        onTap: (ctx) {
          openDislocazionePersonaleWithPassword(
            ctx,
            readOnly: normalizedRole == 'dt' ||
                normalizedRole == 'assistente_dt' ||
                isAdminVistaRole(normalizedRole),
          );
          return const AdminHubActionOnly();
        },
      ),
    if (canForCustom('programmazione_formazioni') &&
        canViewProgrammazioneFormazioniList(normalizedRole))
      AdminHubNavItem(
        layoutKey: 'programmazione_formazioni',
        defaultLayoutKey: home,
        icon: Icons.event_note_outlined,
        label: 'Programmazione Formazioni',
        onTap: (ctx) => useMobileUi(ctx)
            ? DtProgrammazioneFormazioniMobilePage(role: role)
            : DtProgrammazioneFormazioniPage(role: role),
      ),
    if (canForCustom('programmazione_formazioni_rfi') &&
        canViewProgrammazioneFormazioniRfiList(normalizedRole))
      AdminHubNavItem(
        layoutKey: 'programmazione_formazioni_rfi',
        defaultLayoutKey: home,
        icon: Icons.event_available_outlined,
        label: 'Programmazioni corsi RFI',
        onTap: (ctx) => useMobileUi(ctx)
            ? const DtProgrammazioneFormazioniRfiMobilePage()
            : const DtProgrammazioneFormazioniRfiPage(),
      ),
    if (isGenerale || canForCustom('formazione_rfi'))
      AdminHubNavItem(
        layoutKey: 'formazione_rfi',
        defaultLayoutKey: home,
        icon: Icons.account_tree_outlined,
        label: 'Formazione RFI',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminFormazioneRfiMobilePage()
            : const AdminFormazioneRfiPage(),
      ),
    if (canForCustom('scadenze_alert') ||
        canForCustom('uqsa') ||
        canForCustom('formazione_dlgs_81_08') ||
        canForCustom('formazione_rfi') ||
        canForCustom('attestati_dipendenti'))
      AdminHubNavItem(
        layoutKey: 'scadenze_alert',
        defaultLayoutKey: home,
        icon: Icons.warning_amber_rounded,
        label: 'Alert scadenze',
        iconColor: Colors.red,
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminScadenzeAlertMobilePage()
            : const AdminScadenzeAlertPage(),
      ),
    if (canForCustom('logistica') || canForCustom('mdo_ferroviari'))
      AdminHubNavItem(
        layoutKey: 'logistica',
        defaultLayoutKey: home,
        icon: Icons.local_shipping_outlined,
        label: 'Logistica',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminLogisticaHubMobilePage(userId: adminId, role: role)
            : AdminLogisticaHubPage(userId: adminId, role: role),
      ),
    if (canForCustom('logistica') || canForCustom('mdo_ferroviari'))
      AdminHubNavItem(
        layoutKey: 'carburante',
        defaultLayoutKey: home,
        icon: Icons.oil_barrel_outlined,
        label: 'Carburante',
        subtitle: 'Rifornimenti e verifica fatturazione QT',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminCarburanteHubMobilePage(userId: adminId, role: role)
            : AdminCarburanteHubPage(userId: adminId, role: role),
      ),
    if (canForCustom('logistica') || canForCustom('mdo_ferroviari'))
      AdminHubNavItem(
        layoutKey: 'mdo_mappa_gps',
        defaultLayoutKey: home,
        icon: Icons.map_outlined,
        label: 'Mappa GPS',
        subtitle: 'MDO tipo A e commesse con GPS',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminLogisticaMdoMappaMobilePage()
            : const AdminLogisticaMdoMappaPage(),
      ),
    if (isGenerale || canForCustom('documenti_firma'))
      AdminHubNavItem(
        layoutKey: 'documenti_firma',
        defaultLayoutKey: home,
        icon: Icons.fingerprint,
        label: 'Firma digitale',
        subtitle: 'Invio PDF e firme digitali',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminDocumentiFirmaMobilePage()
            : const AdminDocumentiFirmaPage(),
      ),
    if (isGenerale || canForCustom('bacheca'))
      AdminHubNavItem(
        layoutKey: 'bacheca',
        defaultLayoutKey: home,
        icon: Icons.campaign_outlined,
        label: 'Bacheca',
        subtitle: 'Comunicazioni a tutti i dipendenti',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminBachecaMobilePage()
            : const AdminBachecaPage(),
      ),
    if (isGenerale || canForCustom('formazione_dlgs_81_08'))
      AdminHubNavItem(
        layoutKey: 'formazione_dlgs',
        defaultLayoutKey: home,
        icon: Icons.school_outlined,
        label: 'Formazione D.Lgs. 81/08',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminFormazioneDlgsMobilePage(
                role: role,
                readOnly: !canManageFormazioneDlgs81Griglia(normalizedRole),
              )
            : AdminFormazionePage(
                role: role,
                readOnly: !canManageFormazioneDlgs81Griglia(normalizedRole),
              ),
      ),
    if (isGenerale || canForCustom('attestati_dipendenti'))
      AdminHubNavItem(
        layoutKey: 'attestati_dipendenti',
        defaultLayoutKey: home,
        icon: Icons.workspace_premium_outlined,
        label: 'Attestati',
        subtitle: 'RFI e D.Lgs. 81/08 · file, caricamento e scadenza',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminUqsaAttestatiMobilePage(
                role: role,
                readOnly: role == null || !canManageUqsaAttestati(role),
              )
            : AdminUqsaAttestatiPage(
                role: role,
                readOnly: role == null || !canManageUqsaAttestati(role),
              ),
      ),
    if (canForCustom('uqsa') ||
        canForCustom('formazione_dlgs_81_08') ||
        canForCustom('formazione_rfi'))
      AdminHubNavItem(
        layoutKey: 'uqsa',
        defaultLayoutKey: home,
        icon: Icons.school_outlined,
        label: 'UQSA',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminFormazioneHubMobilePage(
                adminUserId: adminId,
                role: role,
                showIlMioTesserino: isGenerale || canForCustom('tesserini'),
                showTesserini: isGenerale || canForCustom('tesserini'),
              )
            : AdminFormazioneHubPage(
                adminUserId: adminId,
                role: role,
                showIlMioTesserino: isGenerale || canForCustom('tesserini'),
                showTesserini: isGenerale || canForCustom('tesserini'),
              ),
      ),
  ];
}

/// Chiavi non spostabili tra hub (menu o pagina hub).
const Set<String> kHubNonRelocatableKeys = {
  'impostazioni_app',
  'dpi_hub',
};

/// Chiavi che aprono menu/dialog al tap (non una pagina).
const Set<String> kHubActionOnlyKeys = {
  'impostazioni_app',
  'pulizia_dati',
  'emp_treni',
  'emp_aerei',
  'emp_pernottamenti',
  'emp_misure_vestiario',
  'emp_rifornimento',
  'emp_formazione',
  'emp_mezzi',
  'mdo_ferroviari',
  'attrezzature',
  'mezzi_stradali',
};
