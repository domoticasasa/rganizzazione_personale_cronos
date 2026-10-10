import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/admin_scadenze_alert_mobile_page.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/aereo_mobile.dart';
import '../Mobile/dt_assistenti_permissions_mobile.dart';
import '../Mobile/dt_richieste_mobile.dart';
import '../Mobile/prenotazione_pernottamenti_mobile.dart';
import '../Mobile/treno_mobile.dart';
import '../pages/admin_bacheca_page.dart';
import '../pages/admin_commesse_cig_cup_page.dart';
import '../pages/admin_dipendente_assenze_page.dart';
import '../pages/admin_formazione_dlgs_81_08_page.dart';
import '../pages/admin_formazione_hub_page.dart';
import '../pages/admin_formazione_rfi_page.dart';
import '../pages/admin_logistica_hub_page.dart';
import '../pages/admin_carburante_hub_page.dart';
import '../pages/admin_logistica_mdo_mappa_page.dart';
import '../pages/admin_scadenze_alert_page.dart';
import '../pages/admin_visite_mediche_page.dart';
import '../pages/aereo_page.dart';
import '../pages/dt_assistenti_permissions_page.dart';
import '../pages/dt_programmazione_formazioni_page.dart';
import '../pages/dt_programmazione_formazioni_rfi_page.dart';
import '../pages/dt_richieste_page.dart';
import '../pages/dt_rubrica_page.dart';
import '../pages/prenotazione_pernottamenti_page.dart';
import '../pages/treno_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

List<AdminHubNavItem> buildDtHomeHubNavItems(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
  required String role,
  String? secondaryRole,
}) {
  const home = AppUiLayoutService.layoutHomeDt;
  final normalized = normalizeRole(role);
  final isDt = normalized == 'dt';
  final isAssistenteDt = normalized == 'assistente_dt';

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'pernottamenti',
      defaultLayoutKey: home,
      icon: Icons.bed_outlined,
      label: 'Pernottamenti',
      onTap: (ctx) => useMobileUi(ctx)
          ? PernottamentiMobilePage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            )
          : PrenotazionePernottamentiPage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'treni',
      defaultLayoutKey: home,
      icon: Icons.train_outlined,
      label: 'Treni',
      onTap: (ctx) => useMobileUi(ctx)
          ? TrenoMobilePage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            )
          : TrenoPage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'aerei',
      defaultLayoutKey: home,
      icon: Icons.flight_takeoff_outlined,
      label: 'Aerei',
      onTap: (ctx) => useMobileUi(ctx)
          ? AereoMobilePage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            )
          : AereoPage(
              username: username,
              userId: userId,
              role: role,
              fullName: fullName,
            ),
    ),
    if (isDt)
      AdminHubNavItem(
        layoutKey: 'richieste_da_approvare',
        defaultLayoutKey: home,
        icon: Icons.approval_outlined,
        label: 'Richieste da approvare',
        onTap: (ctx) => useMobileUi(ctx)
            ? DTRichiesteMobilePage(userId: userId, fullName: fullName)
            : DTRichiestePage(userId: userId, fullName: fullName),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'programmazione_formazioni',
        defaultLayoutKey: home,
        icon: Icons.event_note_outlined,
        label: 'Programmazione Formazioni',
        onTap: (ctx) => useMobileUi(ctx)
            ? DtProgrammazioneFormazioniMobilePage(role: role)
            : DtProgrammazioneFormazioniPage(role: role),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'programmazione_formazioni_rfi',
        defaultLayoutKey: home,
        icon: Icons.event_available_outlined,
        label: 'Programmazioni corsi RFI',
        onTap: (ctx) => useMobileUi(ctx)
            ? const DtProgrammazioneFormazioniRfiMobilePage()
            : const DtProgrammazioneFormazioniRfiPage(),
      ),
    if (isDt || isAssistenteDt)
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
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'formazione_rfi',
        defaultLayoutKey: home,
        icon: Icons.account_tree_outlined,
        label: 'Formazione RFI',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminFormazioneRfiMobilePage(readOnly: true)
            : const AdminFormazioneRfiPage(readOnly: true),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'logistica',
        defaultLayoutKey: home,
        icon: Icons.local_shipping_outlined,
        label: 'Logistica',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminLogisticaHubMobilePage(userId: userId, role: role)
            : AdminLogisticaHubPage(userId: userId, role: role),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'carburante',
        defaultLayoutKey: home,
        icon: Icons.oil_barrel_outlined,
        label: 'Carburante',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminCarburanteHubMobilePage(userId: userId, role: role)
            : AdminCarburanteHubPage(userId: userId, role: role),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'mdo_mappa_gps',
        defaultLayoutKey: home,
        icon: Icons.map_outlined,
        label: 'Mappa GPS',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminLogisticaMdoMappaMobilePage()
            : const AdminLogisticaMdoMappaPage(),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'bacheca',
        defaultLayoutKey: home,
        icon: Icons.campaign_outlined,
        label: 'Bacheca',
        subtitle: 'Comunicazioni aziendali',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminBachecaMobilePage(readOnly: true)
            : const AdminBachecaPage(readOnly: true),
      ),
    if (isDt)
      AdminHubNavItem(
        layoutKey: 'formazione_dlgs_81_08',
        defaultLayoutKey: home,
        icon: Icons.school_outlined,
        label: 'Formazione D.Lgs. 81/08',
        onTap: (ctx) => useMobileUi(ctx)
            ? const AdminFormazioneDlgsMobilePage(readOnly: true)
            : const AdminFormazionePage(readOnly: true),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'uqsa',
        defaultLayoutKey: home,
        icon: Icons.school_outlined,
        label: 'UQSA',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminFormazioneHubMobilePage(
                adminUserId: userId,
                role: role,
                showIlMioTesserino: true,
                showTesserini: true,
              )
            : AdminFormazioneHubPage(
                adminUserId: userId,
                role: role,
                showIlMioTesserino: true,
                showTesserini: true,
              ),
      ),
    if (isDt)
      AdminHubNavItem(
        layoutKey: 'permessi_assistenti_dt',
        defaultLayoutKey: home,
        icon: Icons.security_outlined,
        label: 'Permessi Assistenti DT',
        onTap: (ctx) => useMobileUi(ctx)
            ? DtAssistentiPermissionsMobilePage(fullName: fullName)
            : DtAssistentiPermissionsPage(fullName: fullName),
      ),
    if (canViewVisiteMedicheList(role) ||
        hasDtWorkflowRole(role, secondaryRole))
      AdminHubNavItem(
        layoutKey: 'visite_mediche',
        defaultLayoutKey: home,
        icon: Icons.medical_services_outlined,
        label: 'Visite mediche',
        onTap: (ctx) => useMobileUi(ctx)
            ? const VisiteMedicheMobilePage(adminMode: false)
            : const VisiteMedichePage(adminMode: false),
      ),
    if (ModuleVisibilityFlags.showDtRichiesteFeriePermessi &&
        canViewDipendenteAssenzeList(role, secondaryRole))
      AdminHubNavItem(
        layoutKey: 'richieste_ferie_permessi',
        defaultLayoutKey: home,
        icon: Icons.beach_access_outlined,
        label: 'Richieste ferie / permessi',
        onTap: (ctx) => useMobileUi(ctx)
            ? DipendenteAssenzeMobilePage(
                pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
                userId: userId,
                role: role,
                fullName: fullName,
              )
            : DipendenteAssenzePage(
                pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
                userId: userId,
                role: role,
                fullName: fullName,
              ),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'rubrica',
        defaultLayoutKey: home,
        icon: Icons.contacts_outlined,
        label: 'Rubrica',
        subtitle: 'Nome, telefono, email e età',
        onTap: (ctx) => const DtRubricaPage(),
      ),
    if (isDt || isAssistenteDt)
      AdminHubNavItem(
        layoutKey: 'commesse_cig_cup',
        defaultLayoutKey: home,
        icon: Icons.badge_outlined,
        label: 'Commesse CIG / CUP',
        onTap: (ctx) => useMobileUi(ctx)
            ? AdminCommesseCigCupPage(
                userId: userId,
                role: role,
                readOnly: true,
              )
            : AdminCommesseCigCupPage(
                userId: userId,
                role: role,
                readOnly: true,
              ),
      ),
    if (canViewDipendenteAssenzeList(role, secondaryRole))
      AdminHubNavItem(
        layoutKey: 'segnalazione_assenze',
        defaultLayoutKey: home,
        icon: Icons.medical_information_outlined,
        label: 'Segnalazione assenze',
        onTap: (ctx) => useMobileUi(ctx)
            ? DipendenteAssenzeMobilePage(
                pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
                readOnly: true,
                userId: userId,
                role: role,
                fullName: fullName,
              )
            : DipendenteAssenzePage(
                pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
                readOnly: true,
                userId: userId,
                role: role,
                fullName: fullName,
              ),
      ),
  ];
}
