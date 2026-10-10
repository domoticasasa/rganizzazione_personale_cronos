import 'dart:async';

import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/employee_mobile_pages.dart';
import '../pages/admin_logistica_attrezzature_page.dart';
import '../pages/admin_dislocazione_mdo_per_commessa_page.dart';
import '../pages/admin_logistica_mdo_ferroviari_page.dart';
import '../pages/admin_logistica_mdo_mappa_page.dart';
import '../pages/admin_logistica_mezzi_stradali_page.dart';
import '../pages/admin_logistica_multicard_page.dart';
import '../pages/admin_logistica_officine_convenzionate_page.dart';
import '../pages/dipendente_documenti_firma_page.dart';
import '../pages/admin_bacheca_page.dart';
import '../pages/dipendente_tesserino_page.dart';
import '../pages/video_gallery_page.dart';
import '../services/classic_nav_session_cache.dart';
import '../pages/dpi_page.dart';
import '../pages/my_profile_page.dart';
import '../pages/dt_programmazione_formazioni_page.dart';
import '../pages/dt_programmazione_formazioni_rfi_page.dart';
import '../pages/employee_formazione_rfi_scadenze_page.dart';
import '../pages/employee_formazione_scadenze_page.dart';
import '../pages/employee_uqsa_attestati_page.dart';
import '../pages/logistica_rcc_carburante_page.dart';
import '../pages/logistica_rcc_mdo_carburante_page.dart';
import '../pages/notifications_page.dart';
import '../pages/admin_visite_mediche_page.dart';
import '../pages/richiesta_ferie_permessi_page.dart';
import '../pages/dipendente_rifornimenti_mancanti_page.dart';
import '../pages/security_incident_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/dipendente_rifornimento_chooser.dart';
import '../utils/mobile_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../widgets/employee_taglie_editor_dialog.dart';
import 'admin_hub_nav_item.dart';

class HomeDipendenteNavParams {
  const HomeDipendenteNavParams({
    required this.userId,
    required this.username,
    required this.fullName,
    this.personaleUuid,
  });

  final int userId;
  final String username;
  final String fullName;
  final String? personaleUuid;
}

List<AdminHubNavItem> buildHomeDipendenteNavItems(HomeDipendenteNavParams p) {
  const home = AppUiLayoutService.layoutHomeDipendente;
  final pid = (p.personaleUuid ?? '').trim();

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'emp_treni',
      defaultLayoutKey: home,
      icon: Icons.train_outlined,
      label: 'Treni',
      subtitle: 'Nuova richiesta o elenco',
      onTap: (_) => const AdminHubActionOnly(),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_aerei',
      defaultLayoutKey: home,
      icon: Icons.flight_takeoff_outlined,
      label: 'Aerei',
      subtitle: 'Nuova richiesta o elenco',
      onTap: (_) => const AdminHubActionOnly(),
    ),
    if (ModuleVisibilityFlags.showEmpLeMieFeriePermessi)
      AdminHubNavItem(
        layoutKey: 'emp_richiedi_ferie_permessi',
        defaultLayoutKey: home,
        icon: Icons.event_busy_outlined,
        label: 'Le mie ferie / permessi',
        onTap: (ctx) => useMobileUi(ctx)
            ? RichiestaFeriePermessiMobilePage(
                userId: p.userId,
                fullName: p.fullName,
              )
            : RichiestaFeriePermessiPage(
                userId: p.userId,
                fullName: p.fullName,
              ),
      ),
    AdminHubNavItem(
      layoutKey: 'emp_notifiche',
      defaultLayoutKey: home,
      icon: Icons.notifications_outlined,
      label: 'Notifiche',
      subtitle: 'Tutte le notifiche',
      onTap: (ctx) => useMobileUi(ctx)
          ? NotificationsMobilePage(userId: p.userId)
          : NotificationsPage(userId: p.userId),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_pernottamenti',
      defaultLayoutKey: home,
      icon: Icons.bed_outlined,
      label: 'Pernottamenti',
      subtitle: 'Prenota o consulta soggiorni',
      onTap: (_) => const AdminHubActionOnly(),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_tesserino',
      defaultLayoutKey: home,
      icon: Icons.badge_outlined,
      label: 'Il mio tesserino',
      subtitle: 'Visualizza tesserino e foto',
      onTap: (ctx) => useMobileUi(ctx)
          ? DipendenteTesserinoMobilePage(userId: p.userId)
          : DipendenteTesserinoPage(userId: p.userId),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_i_miei_dati',
      defaultLayoutKey: home,
      icon: Icons.phone_android_outlined,
      label: 'I miei dati',
      subtitle: 'Sostituisci telefono e data di nascita',
      onTap: (_) => const MyProfilePage(expandEditOnOpen: true),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_documenti_firma',
      defaultLayoutKey: home,
      icon: Icons.fingerprint,
      label: 'Firma digitale',
      subtitle: 'Firma OTP e download PDF',
      onTap: (ctx) => useMobileUi(ctx)
          ? DipendenteDocumentiFirmaMobilePage(
              userId: p.userId,
              fullName: p.fullName,
            )
          : DipendenteDocumentiFirmaPage(
              userId: p.userId,
              fullName: p.fullName,
            ),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_bacheca',
      defaultLayoutKey: home,
      icon: Icons.campaign_outlined,
      label: 'Bacheca',
      subtitle: 'Comunicazioni aziendali',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminBachecaMobilePage(readOnly: true)
          : const AdminBachecaPage(readOnly: true),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_video_istruzioni',
      defaultLayoutKey: home,
      icon: Icons.ondemand_video_outlined,
      label: 'Video istruttivi',
      subtitle: 'Tutorial e guide in app',
      onTap: (ctx) => VideoGalleryPage(
        role: ClassicNavSessionCache.current?.role,
      ),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_formazione',
      defaultLayoutKey: home,
      icon: Icons.school_outlined,
      label: 'Formazione',
      subtitle: 'Scadenze, programmazioni e attestati',
      onTap: (ctx) {
        unawaited(
          showDipendenteFormazioneChooser(
            ctx,
            employeeFullName: p.fullName,
            scadenzePage: () => useMobileUi(ctx)
                ? EmployeeFormazioneScadenzeMobilePage(
                    userId: p.userId,
                    fullName: p.fullName,
                  )
                : EmployeeFormazioneScadenzePage(
                    userId: p.userId,
                    fullName: p.fullName,
                  ),
            rfiScadenzePage: () => useMobileUi(ctx)
                ? EmployeeFormazioneRfiScadenzeMobilePage(
                    userId: p.userId,
                    fullName: p.fullName,
                  )
                : EmployeeFormazioneRfiScadenzePage(
                    userId: p.userId,
                    fullName: p.fullName,
                  ),
            programmazionePage: () => useMobileUi(ctx)
                ? DtProgrammazioneFormazioniMobilePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  )
                : DtProgrammazioneFormazioniPage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  ),
            programmazioneRfiPage: () => useMobileUi(ctx)
                ? DtProgrammazioneFormazioniRfiMobilePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  )
                : DtProgrammazioneFormazioniRfiPage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  ),
            attestatiPage: () => useMobileUi(ctx)
                ? EmployeeUqsaAttestatiMobilePage(
                    userId: p.userId,
                    fullName: p.fullName,
                  )
                : EmployeeUqsaAttestatiPage(
                    userId: p.userId,
                    fullName: p.fullName,
                  ),
          ),
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_visita_medica',
      defaultLayoutKey: home,
      icon: Icons.medical_services_outlined,
      label: 'Visita medica',
      subtitle: 'Visita normale o RFI',
      onTap: (ctx) {
        unawaited(
          showDipendenteVisiteMedicheChooser(
            ctx,
            employeeFullName: p.fullName,
            standardPage: () => useMobileUi(ctx)
                ? VisiteMedicheMobilePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  )
                : VisiteMedichePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                  ),
            rfiPage: () => useMobileUi(ctx)
                ? VisiteMedicheMobilePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                    rfiMode: true,
                  )
                : VisiteMedichePage(
                    employeeOnly: true,
                    employeeFullName: p.fullName,
                    rfiMode: true,
                  ),
          ),
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_sicurezza',
      defaultLayoutKey: home,
      icon: Icons.health_and_safety_outlined,
      label: 'Sicurezza',
      subtitle: 'Dotazioni DPI e misure vestiario',
      onTap: (ctx) {
        unawaited(
          showDipendenteSicurezzaChooser(
            ctx,
            dpiPage: () {
              if (pid.isEmpty) {
                return const Scaffold(
                  body: Center(
                    child: Text('Profilo dipendente non disponibile'),
                  ),
                );
              }
              return useMobileUi(ctx)
                  ? DpiMobilePage(
                      fullName: p.fullName,
                      personaleUuid: pid,
                    )
                  : DpiPage(
                      fullName: p.fullName,
                      personaleUuid: pid,
                    );
            },
            openMisureVestiario: () async {
              if (pid.isEmpty) return;
              await showEmployeeTaglieEditorDialog(
                ctx,
                personaleIdUuid: pid,
                dialogTitle: 'Le mie taglie',
                messenger: (msg, {error = false}) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: error ? Colors.red : null,
                    ),
                  );
                },
              );
            },
          ),
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_dpi',
      defaultLayoutKey: home,
      icon: Icons.shield_outlined,
      label: 'Dotazioni DPI',
      onTap: (ctx) {
        if (pid.isEmpty) return const AdminHubActionOnly();
        return useMobileUi(ctx)
            ? DpiMobilePage(
                fullName: p.fullName,
                personaleUuid: pid,
              )
            : DpiPage(
                fullName: p.fullName,
                personaleUuid: pid,
              );
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_misure_vestiario',
      defaultLayoutKey: home,
      icon: Icons.straighten,
      label: 'Misure vestiario',
      onTap: (_) => const AdminHubActionOnly(),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_mezzi',
      defaultLayoutKey: home,
      icon: Icons.commute_outlined,
      label: 'Mezzi',
      subtitle: 'MDO, per commessa, trasferimenti, stradali e officine',
      onTap: (ctx) {
        unawaited(
          showDipendenteMezziChooser(
            ctx,
            mdoPage: () => useMobileUi(ctx)
                ? const AdminLogisticaMdoDipendenteMobilePage()
                : const AdminLogisticaMdoFerroviariPage(dipendenteMode: true),
            mdoPerCommessaPage: () => useMobileUi(ctx)
                ? const AdminDislocazioneMdoPerCommessaMobilePage(
                    readOnly: true,
                  )
                : const AdminDislocazioneMdoPerCommessaPage(readOnly: true),
            trasferimentiPage: () => useMobileUi(ctx)
                ? const AdminDislocazioneMdoPerCommessaMobilePage(
                    readOnly: true,
                    initialMainTab: 1,
                  )
                : const AdminDislocazioneMdoPerCommessaPage(
                    readOnly: true,
                    initialMainTab: 1,
                  ),
            stradaliMioMezzoPage: () => useMobileUi(ctx)
                ? const AdminLogisticaMezziDipendenteMobilePage()
                : const AdminLogisticaMezziStradaliPage(dipendenteMode: true),
            officinePage: () => useMobileUi(ctx)
                ? const AdminLogisticaOfficineConvenzionateMobilePage(
                    readOnly: true,
                  )
                : const AdminLogisticaOfficineConvenzionatePage(readOnly: true),
          ),
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_rifornimento',
      defaultLayoutKey: home,
      icon: Icons.local_gas_station_outlined,
      label: 'Rifornimento',
      subtitle: 'Da giustificare, Stradali, MDO e Multicard',
      onTap: (ctx) {
        unawaited(
          showDipendenteRifornimentoChooser(
            ctx,
            mancantiPage: () => const DipendenteRifornimentiMancantiPage(),
            rccPage: () => useMobileUi(ctx)
                ? const LogisticaRccCarburanteMobilePage(dipendenteMode: true)
                : LogisticaRccCarburantePage(dipendenteMode: true),
            mdoPage: () => useMobileUi(ctx)
                ? const LogisticaRccMdoCarburanteMobilePage(
                    dipendenteMode: true,
                  )
                : LogisticaRccMdoCarburantePage(dipendenteMode: true),
            multicardPage: () => useMobileUi(ctx)
                ? const AdminLogisticaMulticardMobilePage(dipendenteMode: true)
                : AdminLogisticaMulticardPage(dipendenteMode: true),
          ),
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'emp_mappa_gps',
      defaultLayoutKey: home,
      icon: Icons.map_outlined,
      label: 'Mappa GPS',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminLogisticaMdoMappaMobilePage()
          : const AdminLogisticaMdoMappaPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_incidente_sicurezza',
      defaultLayoutKey: home,
      icon: Icons.report_gmailerrorred_outlined,
      label: 'Incidenti sicurezza',
      subtitle: 'Segnala phishing, furto tablet, account…',
      onTap: (ctx) => const SecurityIncidentPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'emp_attrezzature',
      defaultLayoutKey: home,
      icon: Icons.handyman_outlined,
      label: 'Attrezzature',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminLogisticaAttrezzatureMobilePage(
              dipendenteMode: true,
              fullName: p.fullName,
            )
          : AdminLogisticaAttrezzaturePage(
              dipendenteMode: true,
              fullName: p.fullName,
            ),
    ),
  ];
}
