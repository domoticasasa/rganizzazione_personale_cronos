import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/aereo_mobile.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/prenotazione_pernottamenti_mobile.dart';
import '../Mobile/treno_mobile.dart';
import '../hub/home_main_button_keys.dart';
import '../utils/dipendente_rifornimento_chooser.dart';
import '../utils/mobile_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/roles.dart';
import 'admin_formazione_hub_page.dart';
import 'admin_logistica_hub_page.dart';
import 'admin_logistica_mdo_ferroviari_page.dart';
import 'admin_logistica_mezzi_stradali_page.dart';
import 'admin_pos_dipendenti_page.dart';
import 'admin_pos_mdo_ferroviari_page.dart';
import 'admin_pos_mezzi_stradali_page.dart';
import 'admin_pos_mdo_proprieta_page.dart';
import 'admin_dipendente_assenze_page.dart';
import 'admin_visite_mediche_page.dart';
import 'aereo_page.dart';
import 'dt_programmazione_formazioni_page.dart';
import 'dt_programmazione_formazioni_rfi_page.dart';
import 'home/home_hub_page_base.dart';
import 'prenotazione_pernottamenti_page.dart';
import 'treno_page.dart';

/// Home per dipendenti, logistica e ruoli custom (non admin home, non DT).
class GenericHomePage extends HomeHubPage {
  const GenericHomePage({
    super.key,
    required super.username,
    required super.fullName,
    required super.role,
    required super.userId,
    super.secondaryRole,
  }) : super(
          layoutConfig: const HomeHubLayoutConfig(
            layoutKey: HomeMainButtonKeys.layoutKey,
            defaultOrderKeys: HomeMainButtonKeys.defaults,
            useCompactHomeGrid: false,
            isAdminHomeGrid: false,
            isDtHomeGrid: false,
            compactMaxWidth: 1100,
          ),
        );

  @override
  HomeHubPageState createState() => _GenericHomePageState();
}

class _GenericHomePageState extends HomeHubPageState {
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
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: PrenotazionePernottamentiPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
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
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: TrenoPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
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
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: AereoPage(
            username: widget.username,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
    ];

    if (canShowPage(
      'programmazione_formazioni',
      isDipendenteLike ||
          (!isAdmin && canViewProgrammazioneFormazioniList(widget.role)),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'programmazione_formazioni',
          icon: Icons.event_note_outlined,
          label: 'Programmazione Formazioni',
          color: isDipendenteLike && hasMyProgrammazione
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          mobilePage: DtProgrammazioneFormazioniMobilePage(
            employeeOnly: isDipendenteLike,
            employeeFullName: widget.fullName,
            role: isDipendenteLike ? null : widget.role,
          ),
          desktopPage: DtProgrammazioneFormazioniPage(
            employeeOnly: isDipendenteLike,
            employeeFullName: widget.fullName,
            role: isDipendenteLike ? null : widget.role,
          ),
          onClosed: loadEmployeeProgrammazioneAlert,
        ),
      );
    }

    if (canShowPage(
      'programmazione_formazioni_rfi',
      isDipendenteLike ||
          (!isAdmin && canViewProgrammazioneFormazioniRfiList(widget.role)),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'programmazione_formazioni_rfi',
          icon: Icons.event_available_outlined,
          label: 'Programmazioni corsi RFI',
          color: isDipendenteLike && hasMyProgrammazioneRfi
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          mobilePage: DtProgrammazioneFormazioniRfiMobilePage(
            employeeOnly: isDipendenteLike,
            employeeFullName: widget.fullName,
          ),
          desktopPage: DtProgrammazioneFormazioniRfiPage(
            employeeOnly: isDipendenteLike,
            employeeFullName: widget.fullName,
          ),
          onClosed: loadEmployeeProgrammazioneAlert,
        ),
      );
    }

    if (canShowPage('visite_mediche', isDipendenteLike)) {
      tiles.add(
        HomeHubTile(
          layoutKey: 'visite_mediche',
          icon: Icons.medical_services_outlined,
          label: 'Visita medica',
          color: hasVisitaMedica
              ? (pendingBlinkOn ? Colors.red : theme.colorScheme.primary)
              : theme.colorScheme.primary,
          onTap: () async {
            await showDipendenteVisiteMedicheChooser(
              context,
              employeeFullName: widget.fullName,
              standardPage: () => useMobileUi(context)
                  ? VisiteMedicheMobilePage(
                      employeeOnly: true,
                      employeeFullName: widget.fullName,
                    )
                  : VisiteMedichePage(
                      employeeOnly: true,
                      employeeFullName: widget.fullName,
                    ),
              rfiPage: () => useMobileUi(context)
                  ? VisiteMedicheMobilePage(
                      employeeOnly: true,
                      employeeFullName: widget.fullName,
                      rfiMode: true,
                    )
                  : VisiteMedichePage(
                      employeeOnly: true,
                      employeeFullName: widget.fullName,
                      rfiMode: true,
                    ),
            );
            await loadVisitaMedicaAlert();
          },
        ),
      );
    }

    if (canShowPage('dipendente_assenze', isDipendenteLike)) {
      tiles.add(
        navTile(
          layoutKey: 'dipendente_assenze',
          icon: Icons.event_busy_outlined,
          label: 'Ferie / Permessi',
          color: theme.colorScheme.primary,
          mobilePage: DipendenteAssenzeMobilePage(
            adminMode: false,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: DipendenteAssenzePage(
            adminMode: false,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
      );
    }

    if (canShowPage(
      'visite_mediche',
      canViewVisiteMedicheList(widget.role) &&
          !isDipendenteLike &&
          !isAdmin,
    )) {
      tiles.add(
        navTile(
          layoutKey: 'visite_mediche',
          icon: Icons.medical_services_outlined,
          label: 'Visite mediche',
          color: theme.colorScheme.primary,
          mobilePage: VisiteMedicheMobilePage(
            adminMode: canManageVisiteMediche(widget.role),
          ),
          desktopPage: VisiteMedichePage(
            adminMode: canManageVisiteMediche(widget.role),
          ),
        ),
      );
    }

    if (ModuleVisibilityFlags.showDtRichiesteFeriePermessi &&
        canShowPage(
          'richieste_ferie_permessi',
          canViewDipendenteAssenzeList(widget.role) &&
              !isDipendenteLike &&
              !isAdmin,
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
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: DipendenteAssenzePage(
            pageMode: DipendenteAssenzePageMode.richiesteWorkflow,
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          onClosed: () => loadPendingApprovals(force: true),
        ),
      );
    }

    if (canShowPage(
      'segnalazione_assenze',
      canManageDipendenteAssenze(widget.role) && !isDipendenteLike && !isAdmin,
    )) {
      tiles.add(
        navTile(
          layoutKey: 'segnalazione_assenze',
          icon: Icons.medical_information_outlined,
          label: 'Segnalazione assenze',
          color: theme.colorScheme.primary,
          mobilePage: DipendenteAssenzeMobilePage(
            pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
            readOnly: !canMutateSegnalazioneAssenze(widget.role),
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
          desktopPage: DipendenteAssenzePage(
            pageMode: DipendenteAssenzePageMode.registroSegnalazioni,
            readOnly: !canMutateSegnalazioneAssenze(widget.role),
            userId: widget.userId,
            role: widget.role,
            fullName: widget.fullName,
          ),
        ),
      );
    }

    if (canShowPage('logistica', isLogistica)) {
      tiles.add(
        navTile(
          layoutKey: 'logistica',
          icon: Icons.local_shipping_outlined,
          label: 'Logistica',
          color: theme.colorScheme.primary,
          mobilePage: AdminLogisticaHubMobilePage(
            userId: widget.userId,
            role: widget.role,
          ),
          desktopPage: AdminLogisticaHubPage(
            userId: widget.userId,
            role: widget.role,
          ),
        ),
      );
    }

    if (canShowPage('mdo_ferroviari', isDipendenteLike)) {
      tiles.add(
        navTile(
          layoutKey: 'mdo_ferroviari',
          icon: Icons.train_outlined,
          label: 'MDO Ferroviari',
          color: theme.colorScheme.primary,
          mobilePage: const AdminLogisticaMdoDipendenteMobilePage(),
          desktopPage: const AdminLogisticaMdoFerroviariPage(
            dipendenteMode: true,
          ),
        ),
      );
    }

    if (canShowPage('mezzi_stradali', isDipendenteLike)) {
      tiles.add(
        navTile(
          layoutKey: 'mezzi_stradali',
          icon: Icons.local_shipping_outlined,
          label: 'Mezzi Stradali',
          color: theme.colorScheme.primary,
          mobilePage: const AdminLogisticaMezziDipendenteMobilePage(),
          desktopPage: const AdminLogisticaMezziStradaliPage(
            dipendenteMode: true,
          ),
        ),
      );
    }

    if (canShowPage(
      'pos_dipendenti_lista',
      canAccessPosDipendentiLista(widget.role),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'pos_dipendenti_lista',
          icon: Icons.engineering_outlined,
          label: 'Lista dipendenti POS',
          color: theme.colorScheme.primary,
          mobilePage: AdminPosDipendentiMobilePage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosDipendentiLista(widget.role),
          ),
          desktopPage: AdminPosDipendentiPage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosDipendentiLista(widget.role),
          ),
        ),
      );
    }

    if (canShowPage(
      'pos_mdo_ferroviari_lista',
      canAccessPosMdoFerroviariLista(widget.role),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'pos_mdo_ferroviari_lista',
          icon: Icons.train_outlined,
          label: 'Elenco MdO Ferroviari',
          color: theme.colorScheme.primary,
          mobilePage: AdminPosMdoFerroviariMobilePage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMdoFerroviariLista(widget.role),
          ),
          desktopPage: AdminPosMdoFerroviariPage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMdoFerroviariLista(widget.role),
          ),
        ),
      );
    }

    if (canShowPage(
      'pos_mezzi_stradali_lista',
      canAccessPosMezziStradaliLista(widget.role),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'pos_mezzi_stradali_lista',
          icon: Icons.local_shipping_outlined,
          label: 'Elenco Mezzi Stradali',
          color: theme.colorScheme.primary,
          mobilePage: AdminPosMezziStradaliMobilePage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMezziStradaliLista(widget.role),
          ),
          desktopPage: AdminPosMezziStradaliPage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMezziStradaliLista(widget.role),
          ),
        ),
      );
    }

    if (canShowPage(
      'pos_mdo_proprieta_lista',
      canAccessPosMdoProprietaLista(widget.role),
    )) {
      tiles.add(
        navTile(
          layoutKey: 'pos_mdo_proprieta_lista',
          icon: Icons.construction_outlined,
          label: 'Elenco MdO',
          color: theme.colorScheme.primary,
          mobilePage: AdminPosMdoProprietaMobilePage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMdoProprietaLista(widget.role),
          ),
          desktopPage: AdminPosMdoProprietaPage(
            userId: widget.userId,
            role: widget.role,
            readOnly: !canManagePosMdoProprietaLista(widget.role),
          ),
        ),
      );
    }

    if (canShowPage(
      'uqsa',
      normalizedRole == 'uqsa' || normalizedRole == 'admin_formazione',
    )) {
      tiles.add(
        navTile(
          layoutKey: 'uqsa',
          icon: Icons.school_outlined,
          label: 'UQSA',
          color: theme.colorScheme.primary,
          mobilePage: AdminFormazioneHubMobilePage(
            adminUserId: widget.userId,
            role: widget.role,
          ),
          desktopPage: AdminFormazioneHubPage(
            adminUserId: widget.userId,
            role: widget.role,
          ),
        ),
      );
    }

    return tiles;
  }
}
