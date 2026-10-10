import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/admin_scadenze_alert_mobile_page.dart';
import '../Mobile/aereo_mobile.dart';
import '../Mobile/dt_assistenti_permissions_mobile.dart';
import '../Mobile/dt_richieste_mobile.dart';
import '../Mobile/prenotazione_pernottamenti_mobile.dart';
import '../Mobile/treno_mobile.dart';
import '../hub/home_dt_button_keys.dart';
import '../services/app_ui_layout_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/dt_view_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/roles.dart';
import 'admin_gestopro_dt_hub_page.dart';
import 'admin_formazione_dlgs_81_08_page.dart';
import 'admin_formazione_hub_page.dart';
import 'admin_formazione_rfi_page.dart';
import 'admin_commesse_cig_cup_page.dart';
import 'admin_logistica_hub_page.dart';
import 'admin_carburante_hub_page.dart';
import 'admin_logistica_mdo_mappa_page.dart';
import 'admin_scadenze_alert_page.dart';
import 'admin_visite_mediche_page.dart';
import 'aereo_page.dart';
import 'admin_bacheca_page.dart';
import 'admin_dipendente_assenze_page.dart';
import 'dt_assistenti_permissions_page.dart';
import 'dt_programmazione_formazioni_page.dart';
import 'dt_programmazione_formazioni_rfi_page.dart';
import 'dt_richieste_page.dart';
import 'dt_rubrica_page.dart';
import 'home/home_hub_page_base.dart';
import 'prenotazione_pernottamenti_page.dart';
import 'treno_page.dart';

/// Home dedicata a DT e Assistente DT.
class DtHomePage extends HomeHubPage {
  DtHomePage({
    super.key,
    required super.username,
    required super.fullName,
    required super.role,
    required super.userId,
    super.secondaryRole,
    super.layoutEditorRole,
  }) : super(
          layoutConfig: HomeHubLayoutConfig(
            layoutKey: HomeDtButtonKeys.layoutKey,
            defaultOrderKeys: HomeDtButtonKeys.defaults,
            useCompactHomeGrid: true,
            isAdminHomeGrid: false,
            isDtHomeGrid: true,
            compactMaxWidth: 1280,
            resolveOrderKeys: AppUiLayoutService.resolveDtHomeOrderKeys,
          ),
        );

  @override
  HomeHubPageState createState() => _DtHomePageState();
}

class _DtHomePageState extends HomeHubPageState {
  bool get _adminPreview =>
      widget.isLayoutPreviewMode &&
      AppUiLayoutService.canEditGlobalLayout(widget.layoutEditorRole!);

  bool get _showGestoproFooter =>
      _adminPreview || canOpenGestoproFromDtHome(widget.role);

  @override
  void initState() {
    super.initState();
    if (_showGestoproFooter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resumeGestoproIfActive();
      });
    }
  }

  Future<void> _resumeGestoproIfActive() async {
    if (!await GestoproModePrefs.isActive()) return;
    if (!mounted) return;
    ClassicNavSessionCache.markGestoproChrome();
    final sessionRole = _adminPreview ? widget.layoutEditorRole! : widget.role;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminGestoproDtHubPage(
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
          sessionRole: sessionRole,
          sessionSecondaryRole: widget.secondaryRole,
        ),
      ),
    );
  }

  Future<void> _openGestopro() async {
    final sessionRole = _adminPreview ? widget.layoutEditorRole! : widget.role;
    await openDtGestoproSession(
      context,
      userId: widget.userId,
      username: widget.username,
      fullName: widget.fullName,
      sessionRole: sessionRole,
      sessionSecondaryRole: widget.secondaryRole,
      requirePassword: false,
    );
  }

  @override
  bool get showUiViewModeSwitch =>
      _showGestoproFooter && !widget.isLayoutPreviewMode;

  @override
  VoidCallback? get onOpenGestoproFromBar => _openGestopro;

  @override
  Widget? buildAdminHomeFooter(BuildContext context) => null;

  @override
  bool get canEditHomeLayout => _adminPreview;

  @override
  bool get usesPersonalHomeLayout => false;

  @override
  List<HomeHubTile> buildRoleTiles(ThemeData theme) {
    final tiles = <HomeHubTile>[
      if (canShowPage('pernottamenti', true))
        navTile(
          layoutKey: 'pernottamenti',
          icon: Icons.bed_outlined,
          label: 'Pernottamenti',
          color: theme.colorScheme.primary,
          mobilePage: PernottamentiMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          desktopPage: PrenotazionePernottamentiPage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
        ),
      if (canShowPage('treni', true))
        navTile(
          layoutKey: 'treni',
          icon: Icons.train_outlined,
          label: 'Treni',
          color: theme.colorScheme.primary,
          mobilePage: TrenoMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          desktopPage: TrenoPage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
        ),
      if (canShowPage('aerei', true))
        navTile(
          layoutKey: 'aerei',
          icon: Icons.flight_takeoff_outlined,
          label: 'Aerei',
          color: theme.colorScheme.primary,
          mobilePage: AereoMobilePage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          desktopPage: AereoPage(
            username: widget.username,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
        ),
    ];

    if (canShowPage('richieste_da_approvare', isDT)) {
      tiles.add(
        navTile(
          layoutKey: 'richieste_da_approvare',
          icon: Icons.approval_outlined,
          label: 'Richieste da approvare',
          color: hasPendingApprovals
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          mobilePage: DTRichiesteMobilePage(
            userId: widget.userId,
            fullName: widget.fullName,
          ),
          desktopPage:
              DTRichiestePage(userId: widget.userId, fullName: widget.fullName),
          onClosed: () => loadPendingApprovals(force: true),
        ),
      );
    }

    if (canShowPage(
      'programmazione_formazioni',
      isDT || isAssistenteDt,
    )) {
      tiles.add(
        navTile(
          layoutKey: 'programmazione_formazioni',
          icon: Icons.event_note_outlined,
          label: 'Programmazione Formazioni',
          color: theme.colorScheme.primary,
          mobilePage: DtProgrammazioneFormazioniMobilePage(role: widget.role),
          desktopPage: DtProgrammazioneFormazioniPage(role: widget.role),
        ),
      );
    }

    if (canShowPage(
      'programmazione_formazioni_rfi',
      isDT || isAssistenteDt,
    )) {
      tiles.add(
        navTile(
          layoutKey: 'programmazione_formazioni_rfi',
          icon: Icons.event_available_outlined,
          label: 'Programmazioni corsi RFI',
          color: theme.colorScheme.primary,
          mobilePage: const DtProgrammazioneFormazioniRfiMobilePage(),
          desktopPage: const DtProgrammazioneFormazioniRfiPage(),
        ),
      );
    }

    if (canShowPage('scadenze_alert', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'scadenze_alert',
          icon: Icons.warning_amber_rounded,
          label: 'Alert scadenze',
          color: Colors.red,
          mobilePage: const AdminScadenzeAlertMobilePage(),
          desktopPage: const AdminScadenzeAlertPage(),
        ),
      );
    }

    if (canShowPage('formazione_rfi', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'formazione_rfi',
          icon: Icons.account_tree_outlined,
          label: 'Formazione RFI',
          color: theme.colorScheme.primary,
          mobilePage: const AdminFormazioneRfiMobilePage(readOnly: true),
          desktopPage: const AdminFormazioneRfiPage(readOnly: true),
        ),
      );
    }

    if (canShowPage('logistica', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'logistica',
          icon: Icons.local_shipping_outlined,
          label: 'Logistica',
          color: theme.colorScheme.primary,
          mobilePage: AdminLogisticaHubMobilePage(
            userId: widget.userId,
            role: effectiveRole,
          ),
          desktopPage: AdminLogisticaHubPage(
            userId: widget.userId,
            role: effectiveRole,
          ),
        ),
      );
    }

    if (canShowPage('carburante', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'carburante',
          icon: Icons.oil_barrel_outlined,
          label: 'Carburante',
          color: theme.colorScheme.primary,
          mobilePage: AdminCarburanteHubMobilePage(
            userId: widget.userId,
            role: effectiveRole,
          ),
          desktopPage: AdminCarburanteHubPage(
            userId: widget.userId,
            role: effectiveRole,
          ),
        ),
      );
    }

    if (canShowPage('mdo_mappa_gps', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'mdo_mappa_gps',
          icon: Icons.map_outlined,
          label: 'Mappa GPS',
          color: theme.colorScheme.primary,
          mobilePage: const AdminLogisticaMdoMappaMobilePage(),
          desktopPage: const AdminLogisticaMdoMappaPage(),
        ),
      );
    }

    if (canShowPage('bacheca', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'bacheca',
          icon: Icons.campaign_outlined,
          label: 'Bacheca',
          color: hasBachecaUnread
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          mobilePage: const AdminBachecaMobilePage(readOnly: true),
          desktopPage: const AdminBachecaPage(readOnly: true),
          onClosed: () => loadBachecaUnreadAlert(),
        ),
      );
    }

    if (canShowPage('formazione_dlgs_81_08', isDT)) {
      tiles.add(
        navTile(
          layoutKey: 'formazione_dlgs_81_08',
          icon: Icons.school_outlined,
          label: 'Formazione D.Lgs. 81/08',
          color: theme.colorScheme.primary,
          mobilePage: const AdminFormazioneDlgsMobilePage(readOnly: true),
          desktopPage: const AdminFormazionePage(readOnly: true),
        ),
      );
    }

    if (canShowPage('uqsa', isDT || isAssistenteDt)) {
      final showTess = canShowPage('tesserini', isDT || isAssistenteDt);
      tiles.add(
        navTile(
          layoutKey: 'uqsa',
          icon: Icons.school_outlined,
          label: 'UQSA',
          color: theme.colorScheme.primary,
          mobilePage: AdminFormazioneHubMobilePage(
            adminUserId: widget.userId,
            role: effectiveRole,
            showIlMioTesserino: showTess,
            showTesserini: showTess,
          ),
          desktopPage: AdminFormazioneHubPage(
            adminUserId: widget.userId,
            role: effectiveRole,
            showIlMioTesserino: showTess,
            showTesserini: showTess,
          ),
        ),
      );
    }

    if (canShowPage('permessi_assistenti_dt', isDT)) {
      tiles.add(
        navTile(
          layoutKey: 'permessi_assistenti_dt',
          icon: Icons.security_outlined,
          label: 'Permessi Assistenti DT',
          color: theme.colorScheme.primary,
          mobilePage: DtAssistentiPermissionsMobilePage(
            fullName: widget.fullName,
          ),
          desktopPage: DtAssistentiPermissionsPage(
            fullName: widget.fullName,
          ),
        ),
      );
    }

    if (canShowPage(
      'visite_mediche',
      canViewVisiteMedicheList(effectiveRole) ||
          hasDtWorkflowRole(widget.role, widget.secondaryRole),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'visite_mediche',
          icon: Icons.medical_services_outlined,
          label: 'Visite mediche',
          color: theme.colorScheme.primary,
          mobilePage: const VisiteMedicheMobilePage(adminMode: false),
          desktopPage: const VisiteMedichePage(adminMode: false),
        ),
      );
    }

    if (ModuleVisibilityFlags.showDtRichiesteFeriePermessi &&
        canShowPage(
          'richieste_ferie_permessi',
          canViewDipendenteAssenzeList(widget.role),
        )) {
      tiles.add(
        navTile(
          layoutKey: 'richieste_ferie_permessi',
          icon: Icons.beach_access_outlined,
          label: 'Richieste ferie / permessi',
          color: hasPendingAssenzeRichieste
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          mobilePage: DipendenteAssenzeMobilePage(
            pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          desktopPage: DipendenteAssenzePage(
            pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          onClosed: () => loadPendingApprovals(force: true),
        ),
      );
    }

    if (canShowPage('rubrica', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'rubrica',
          icon: Icons.contacts_outlined,
          label: 'Rubrica',
          color: theme.colorScheme.primary,
          mobilePage: const DtRubricaPage(),
          desktopPage: const DtRubricaPage(),
        ),
      );
    }

    if (canShowPage('commesse_cig_cup', isDT || isAssistenteDt)) {
      tiles.add(
        navTile(
          layoutKey: 'commesse_cig_cup',
          icon: Icons.badge_outlined,
          label: 'Commesse CIG / CUP',
          color: theme.colorScheme.primary,
          mobilePage: AdminCommesseCigCupPage(
            userId: widget.userId,
            role: effectiveRole,
            readOnly: true,
          ),
          desktopPage: AdminCommesseCigCupPage(
            userId: widget.userId,
            role: effectiveRole,
            readOnly: true,
          ),
        ),
      );
    }

    if (canShowPage(
      'segnalazione_assenze',
      canViewDipendenteAssenzeList(widget.role),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'segnalazione_assenze',
          icon: Icons.medical_information_outlined,
          label: 'Segnalazione assenze',
          color: theme.colorScheme.primary,
          mobilePage: DipendenteAssenzeMobilePage(
            pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
            readOnly: true,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
          desktopPage: DipendenteAssenzePage(
            pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
            readOnly: true,
            userId: widget.userId,
            role: effectiveRole,
            fullName: widget.fullName,
          ),
        ),
      );
    }

    return tiles;
  }
}
