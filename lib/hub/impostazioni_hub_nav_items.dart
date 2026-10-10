import 'dart:async';

import 'package:flutter/material.dart';

import '../Mobile/admin_gestione_dipendenti_mobile.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../pages/admin_accessi_app_page.dart';
import '../pages/admin_data_import_hub_page.dart';
import '../pages/admin_gestione_dipendenti_page.dart';
import '../pages/admin_master_data_page.dart';
import '../pages/admin_notifiche_page.dart';
import '../pages/admin_notification_rules_page.dart';
import '../pages/admin_data_backup_page.dart';
import '../pages/admin_passkey_reset_page.dart';
import '../pages/admin_personalizzazione_app_page.dart';
import '../pages/admin_privacy_dipendente_page.dart';
import '../legal/privacy_termini_page.dart';
import '../pages/admin_supabase_usage_page.dart';
import '../pages/admin_verifica_costo_stradale_page.dart';
import '../pages/security_incident_page.dart';
import '../pages/video_gallery_page.dart';
import '../services/app_ui_layout_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/app_theme_mode_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/app_copyright.dart';
import '../utils/log_app_access.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/pulizia_dati_dialog.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

typedef ImpostazioniPuliziaCallback = void Function(BuildContext context);

List<AdminHubNavItem> buildImpostazioniHubNavItems({
  required int adminId,
  ImpostazioniPuliziaCallback? onPuliziaDati,
}) {
  const home = AppUiLayoutService.layoutImpostazioniHub;

  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'import_dati_excel',
      defaultLayoutKey: home,
      icon: Icons.upload_file_outlined,
      label: 'Import dati / Modelli Excel',
      subtitle: 'Scarica modelli e importa per tutte le pagine',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminDataImportHubMobilePage(userId: adminId)
          : AdminDataImportHubPage(userId: adminId),
    ),
    AdminHubNavItem(
      layoutKey: 'gestione_dipendenti',
      defaultLayoutKey: home,
      icon: Icons.groups_outlined,
      label: 'Gestione Dipendenti',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminGestioneDipendentiMobilePage()
          : const AdminGestioneDipendentiPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'verifica_costo_stradale',
      defaultLayoutKey: home,
      icon: Icons.directions_car_outlined,
      label: 'Verifica costo stradale',
      subtitle: 'Confronto mezzo stradale vs treno/aereo',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminVerificaCostoStradaleMobilePage()
          : const AdminVerificaCostoStradalePage(),
    ),
    AdminHubNavItem(
      layoutKey: 'gestione_dati',
      defaultLayoutKey: home,
      icon: Icons.settings_suggest_outlined,
      label: 'Gestione Dati',
      subtitle: 'Commesse / Stazioni / Aeroporti / Strutture',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminMasterDataMobilePage()
          : const AdminMasterDataPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'test_notifiche',
      defaultLayoutKey: home,
      icon: Icons.notifications_active_outlined,
      label: 'Test Notifiche',
      onTap: (ctx) => useMobileUi(ctx)
          ? AdminNotificheMobilePage(adminId: adminId)
          : AdminNotifichePage(adminId: adminId),
    ),
    AdminHubNavItem(
      layoutKey: 'regole_notifiche',
      defaultLayoutKey: home,
      icon: Icons.rule_folder_outlined,
      label: 'Regole Notifiche',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminNotificationRulesMobilePage()
          : const AdminNotificationRulesPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'pulizia_dati',
      defaultLayoutKey: home,
      icon: Icons.cleaning_services_outlined,
      label: 'Pulizia Dati',
      onTap: (ctx) {
        final role = ClassicNavSessionCache.current?.role ?? '';
        if (isAdminVistaRole(role)) {
          showAdminVistaReadOnlyDialog(ctx);
          return const AdminHubActionOnly();
        }
        (onPuliziaDati ?? showPuliziaDatiDialog)(ctx);
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'accessi_app',
      defaultLayoutKey: home,
      icon: Icons.login_outlined,
      label: 'Accessi app',
      subtitle: 'Ultima entrata in app di tutti gli utenti con login',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminAccessiAppMobilePage()
          : const AdminAccessiAppPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'reset_passkey',
      defaultLayoutKey: home,
      icon: Icons.key_off_outlined,
      label: 'Reset Passkey',
      subtitle: 'Solo admin generale · sblocca con password',
      onTap: (ctx) {
        final role = ClassicNavSessionCache.current?.role ?? '';
        if (!isAdminGeneraleLikeRole(role)) {
          ModifyFeedback.hint(
            ctx,
            'Solo admin generale può resettare le Passkey.',
          );
          return const AdminHubActionOnly();
        }
        return const AdminPasskeyResetPage();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'log_app',
      defaultLayoutKey: home,
      icon: Icons.history_outlined,
      label: 'Log app',
      subtitle: 'Accessi, inserimenti, cancellazioni ed export (14 giorni)',
      onTap: logAppHubDestination,
    ),
    AdminHubNavItem(
      layoutKey: 'video_istruzioni',
      defaultLayoutKey: home,
      icon: Icons.ondemand_video_outlined,
      label: 'Video istruttivi',
      subtitle: 'Carica video dal cellulare (player in app)',
      onTap: (ctx) => VideoGalleryPage(
        role: ClassicNavSessionCache.current?.role,
      ),
    ),
    AdminHubNavItem(
      layoutKey: 'tema_app',
      defaultLayoutKey: home,
      icon: Icons.dark_mode_outlined,
      label: 'Tema scuro',
      subtitle: 'Passa tra tema chiaro e scuro',
      onTap: (ctx) {
        final dark = !AppThemeModeService.instance.isDark;
        unawaited(AppThemeModeService.instance.setDark(dark));
        ModifyFeedback.hint(
          ctx,
          dark ? 'Tema scuro attivo' : 'Tema chiaro attivo',
        );
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'personalizzazione_app',
      defaultLayoutKey: home,
      icon: Icons.palette_outlined,
      label: 'Personalizzazione app',
      subtitle: 'Logo, nomi, colori e sfondi',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminPersonalizzazioneAppMobilePage()
          : const AdminPersonalizzazioneAppPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'utilizzo_supabase',
      defaultLayoutKey: home,
      icon: Icons.cloud_queue_outlined,
      label: 'Spazio Supabase',
      subtitle: 'Database, storage e quota ancora disponibile',
      onTap: (ctx) => useMobileUi(ctx)
          ? const AdminSupabaseUsageMobilePage()
          : const AdminSupabaseUsagePage(),
    ),
    AdminHubNavItem(
      layoutKey: 'backup_dati',
      defaultLayoutKey: home,
      icon: Icons.backup_outlined,
      label: 'Backup dati',
      subtitle: 'Solo admin generale · elenco, avvio e ripristino',
      onTap: (ctx) {
        final role = ClassicNavSessionCache.current?.role ?? '';
        if (!isAdminGeneraleLikeRole(role)) {
          ModifyFeedback.hint(
            ctx,
            'Solo admin generale può gestire i backup dati.',
          );
          return const AdminHubActionOnly();
        }
        return const AdminDataBackupPage();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'incidenti_sicurezza',
      defaultLayoutKey: home,
      icon: Icons.report_gmailerrorred_outlined,
      label: 'Incidenti sicurezza',
      subtitle: 'Segnala e gestisci phishing, furto dispositivo, account…',
      onTap: (ctx) => const SecurityIncidentPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'privacy_termini',
      defaultLayoutKey: home,
      icon: Icons.privacy_tip_outlined,
      label: 'Privacy e termini',
      subtitle: 'Informativa privacy dipendenti e termini d\'uso',
      onTap: (ctx) {
        final role = ClassicNavSessionCache.current?.role ?? '';
        PrivacyTerminiPage.open(ctx, canEdit: canMutateAsAdmin(role));
        return const AdminHubActionOnly();
      },
    ),
    AdminHubNavItem(
      layoutKey: 'privacy_dipendente',
      defaultLayoutKey: home,
      icon: Icons.folder_shared_outlined,
      label: 'Privacy dipendente',
      subtitle: 'Esporta o cancella i dati di un dipendente',
      onTap: (ctx) => const AdminPrivacyDipendentePage(),
    ),
    AdminHubNavItem(
      layoutKey: 'copyright_note_legali',
      defaultLayoutKey: home,
      icon: Icons.copyright_outlined,
      label: 'Copyright',
      subtitle: 'Note legali e diritti riservati',
      onTap: (ctx) {
        AppCopyright.showNotice(ctx);
        return const AdminHubActionOnly();
      },
    ),
  ];
}
