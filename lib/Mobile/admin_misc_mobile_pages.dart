import 'package:flutter/material.dart';

import '../pages/admin_data_import_hub_page.dart';
import '../pages/admin_master_data_page.dart';
import '../pages/admin_dislocazione_personale_page.dart';
import '../pages/admin_notifiche_page.dart';
import '../pages/admin_notification_rules_page.dart';
import '../pages/admin_accessi_app_page.dart';
import '../pages/admin_app_logs_page.dart';
import '../pages/admin_personalizzazione_app_page.dart';
import '../pages/admin_supabase_usage_page.dart';
import '../pages/admin_dpi_report_page.dart';
import '../pages/admin_dpi_categories_page.dart';
import '../pages/admin_dpi_terza_categoria_page.dart';
import '../pages/admin_vestiario_page.dart';
import '../pages/admin_vestiario_report_page.dart';
import '../pages/admin_vestiario_fabbisogno_taglie_page.dart';
import '../pages/admin_pos_dipendenti_page.dart';
import '../pages/admin_pos_mdo_ferroviari_page.dart';
import '../pages/admin_pos_mezzi_stradali_page.dart';
import '../pages/admin_pos_mdo_proprieta_page.dart';
import '../pages/admin_dislocazione_mdo_per_commessa_page.dart';
import '../pages/admin_vestiario_categorie_page.dart';
import '../pages/admin_vestiario_inventario_page.dart';
import '../pages/admin_formazione_dlgs_81_08_page.dart';
import '../pages/admin_formazione_dlgs_strutture_page.dart';
import '../pages/admin_formazione_rfi_page.dart';
import '../pages/admin_formazione_rfi_strutture_page.dart';
import '../pages/admin_estintori_page.dart';
import '../pages/admin_logistica_casette_ps_page.dart';
import '../pages/admin_logistica_sim_page.dart';
import '../pages/admin_uqsa_attestati_page.dart';
import '../pages/admin_uqsa_sedi_sicurezza_page.dart';
import '../pages/admin_logistica_box_page.dart';
import '../pages/admin_logistica_attrezzature_page.dart';
import '../hub/app_ui_custom_hub.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../pages/admin_custom_hub_page.dart';
import '../pages/admin_dpi_hub_page.dart';
import '../pages/admin_logistica_hub_page.dart';
import '../pages/admin_carburante_hub_page.dart';
import 'admin_logistica_mdo_ferroviari_android_page.dart';
import '../pages/admin_logistica_mdo_documenti_page.dart';
import '../pages/admin_logistica_multicard_mdo_assegnazioni_page.dart';
import 'admin_logistica_mdo_proprieta_android_page.dart';
import 'admin_logistica_mdo_mappa_android_page.dart';
import 'admin_logistica_mdo_check_riepilogo_android_page.dart';
import 'admin_logistica_mezzi_stradali_android_page.dart';
import 'admin_logistica_assegnazione_mezzi_stradali_android_page.dart';
import 'admin_logistica_assegnazione_attrezzature_android_page.dart';
import 'admin_logistica_noleggio_android_page.dart';
import '../pages/admin_logistica_officine_convenzionate_page.dart';
import '../pages/admin_bacheca_page.dart';

class AdminDataImportHubMobilePage extends StatelessWidget {
  const AdminDataImportHubMobilePage({super.key, this.userId, this.role});

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminDataImportHubPage(userId: userId, role: role);
  }
}

class AdminMasterDataMobilePage extends StatelessWidget {
  const AdminMasterDataMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminMasterDataPage();
  }
}

class AdminDislocazionePersonaleMobilePage extends StatelessWidget {
  final bool readOnly;
  const AdminDislocazionePersonaleMobilePage({super.key, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return AdminDislocazionePersonalePage(readOnly: readOnly);
  }
}

class AdminNotificheMobilePage extends StatelessWidget {
  final int adminId;
  const AdminNotificheMobilePage({super.key, required this.adminId});

  @override
  Widget build(BuildContext context) {
    return AdminNotifichePage(adminId: adminId);
  }
}

class AdminAccessiAppMobilePage extends StatelessWidget {
  const AdminAccessiAppMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAccessiAppPage();
  }
}

class AdminAppLogsMobilePage extends StatelessWidget {
  const AdminAppLogsMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminAppLogsPage();
  }
}

class AdminPersonalizzazioneAppMobilePage extends StatelessWidget {
  const AdminPersonalizzazioneAppMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPersonalizzazioneAppPage();
  }
}

class AdminSupabaseUsageMobilePage extends StatelessWidget {
  const AdminSupabaseUsageMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSupabaseUsagePage();
  }
}

class AdminNotificationRulesMobilePage extends StatelessWidget {
  const AdminNotificationRulesMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminNotificationRulesPage();
  }
}

class AdminCustomHubMobilePage extends StatelessWidget {
  const AdminCustomHubMobilePage({
    super.key,
    required this.layoutKey,
    required this.title,
    this.userId,
    this.role,
    this.initialHub,
    this.homeDipendente,
  });

  final String layoutKey;
  final String title;
  final int? userId;
  final String? role;
  final AppUiCustomHub? initialHub;
  final HomeDipendenteNavParams? homeDipendente;

  @override
  Widget build(BuildContext context) {
    return AdminCustomHubPage(
      layoutKey: layoutKey,
      title: title,
      userId: userId,
      role: role,
      initialHub: initialHub,
      homeDipendente: homeDipendente,
    );
  }
}

class AdminDpiHubMobilePage extends StatelessWidget {
  const AdminDpiHubMobilePage({super.key, this.userId, this.role});

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminDpiHubPage(userId: userId, role: role);
  }
}

class AdminDpiReportMobilePage extends StatelessWidget {
  const AdminDpiReportMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDpiReportPage();
  }
}

class AdminDpiCategoriesMobilePage extends StatelessWidget {
  const AdminDpiCategoriesMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDpiCategoriesPage();
  }
}

class AdminDpiTerzaCategoriaMobilePage extends StatelessWidget {
  const AdminDpiTerzaCategoriaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDpiTerzaCategoriaPage();
  }
}

class AdminVestiarioMobilePage extends StatelessWidget {
  const AdminVestiarioMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVestiarioPage();
  }
}

class AdminVestiarioReportMobilePage extends StatelessWidget {
  const AdminVestiarioReportMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVestiarioReportPage();
  }
}

class AdminPosDipendentiMobilePage extends StatelessWidget {
  const AdminPosDipendentiMobilePage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminPosDipendentiPage(
      userId: userId,
      role: role,
      readOnly: readOnly,
    );
  }
}

class AdminPosMdoFerroviariMobilePage extends StatelessWidget {
  const AdminPosMdoFerroviariMobilePage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminPosMdoFerroviariPage(
      userId: userId,
      role: role,
      readOnly: readOnly,
    );
  }
}

class AdminPosMezziStradaliMobilePage extends StatelessWidget {
  const AdminPosMezziStradaliMobilePage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminPosMezziStradaliPage(
      userId: userId,
      role: role,
      readOnly: readOnly,
    );
  }
}

class AdminPosMdoProprietaMobilePage extends StatelessWidget {
  const AdminPosMdoProprietaMobilePage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminPosMdoProprietaPage(
      userId: userId,
      role: role,
      readOnly: readOnly,
    );
  }
}

class AdminVestiarioFabbisognoMobilePage extends StatelessWidget {
  const AdminVestiarioFabbisognoMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVestiarioFabbisognoTagliePage();
  }
}

class AdminVestiarioInventarioMobilePage extends StatelessWidget {
  const AdminVestiarioInventarioMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVestiarioInventarioPage();
  }
}

class AdminVestiarioCategorieMobilePage extends StatelessWidget {
  const AdminVestiarioCategorieMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVestiarioCategoriePage();
  }
}

class AdminFormazioneDlgsMobilePage extends StatelessWidget {
  final bool readOnly;
  final String? role;

  const AdminFormazioneDlgsMobilePage({
    super.key,
    this.readOnly = false,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    return AdminFormazionePage(readOnly: readOnly, role: role);
  }
}

class AdminFormazioneRfiMobilePage extends StatelessWidget {
  final bool readOnly;

  const AdminFormazioneRfiMobilePage({super.key, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return AdminFormazioneRfiPage(readOnly: readOnly);
  }
}

class AdminFormazioneRfiStruttureMobilePage extends StatelessWidget {
  const AdminFormazioneRfiStruttureMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminFormazioneRfiStrutturePage();
  }
}

class AdminFormazioneDlgsStruttureMobilePage extends StatelessWidget {
  const AdminFormazioneDlgsStruttureMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminFormazioneDlgsStrutturePage();
  }
}

class AdminEstintoriMobilePage extends StatelessWidget {
  const AdminEstintoriMobilePage({super.key, this.highlightUuid});

  final String? highlightUuid;

  @override
  Widget build(BuildContext context) {
    return AdminEstintoriPage(highlightUuid: highlightUuid);
  }
}

class AdminLogisticaCasettePsMobilePage extends StatelessWidget {
  const AdminLogisticaCasettePsMobilePage({super.key, this.highlightUuid});

  final String? highlightUuid;

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaCasettePsPage(highlightUuid: highlightUuid);
  }
}

class AdminUqsaSediSicurezzaMobilePage extends StatelessWidget {
  const AdminUqsaSediSicurezzaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminUqsaSediSicurezzaPage(forceMobileLayout: true);
  }
}

class AdminUqsaAttestatiMobilePage extends StatelessWidget {
  const AdminUqsaAttestatiMobilePage({
    super.key,
    this.role,
    this.readOnly = false,
  });

  final String? role;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminUqsaAttestatiPage(role: role, readOnly: readOnly);
  }
}

class AdminLogisticaBoxMobilePage extends StatelessWidget {
  const AdminLogisticaBoxMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaBoxPage();
  }
}

class AdminLogisticaAttrezzatureMobilePage extends StatelessWidget {
  final bool readOnly;
  final bool dipendenteMode;
  final String? fullName;

  const AdminLogisticaAttrezzatureMobilePage({
    super.key,
    this.readOnly = false,
    this.dipendenteMode = false,
    this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaAttrezzaturePage(
      readOnly: readOnly,
      dipendenteMode: dipendenteMode,
      fullName: fullName,
    );
  }
}

class AdminLogisticaMdoFerroviariMobilePage extends StatelessWidget {
  const AdminLogisticaMdoFerroviariMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoFerroviariAndroidPage();
  }
}

class AdminDislocazioneMdoPerCommessaMobilePage extends StatelessWidget {
  const AdminDislocazioneMdoPerCommessaMobilePage({
    super.key,
    this.readOnly = false,
    this.initialMainTab = 0,
  });

  final bool readOnly;
  final int initialMainTab;

  @override
  Widget build(BuildContext context) {
    return AdminDislocazioneMdoPerCommessaPage(
      readOnly: readOnly,
      forceMobileLayout: true,
      initialMainTab: initialMainTab,
    );
  }
}

class AdminLogisticaMdoDocumentiMobilePage extends StatelessWidget {
  const AdminLogisticaMdoDocumentiMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoDocumentiPage(forceMobileLayout: true);
  }
}

class AdminLogisticaMulticardMdoAssegnazioniMobilePage extends StatelessWidget {
  const AdminLogisticaMulticardMdoAssegnazioniMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMulticardMdoAssegnazioniPage(
      forceMobileLayout: true,
    );
  }
}

class AdminLogisticaMdoProprietaMobilePage extends StatelessWidget {
  const AdminLogisticaMdoProprietaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoProprietaAndroidPage();
  }
}

class AdminLogisticaMdoMappaMobilePage extends StatelessWidget {
  const AdminLogisticaMdoMappaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoMappaAndroidPage();
  }
}

class AdminLogisticaMdoCheckRiepilogoMobilePage extends StatelessWidget {
  const AdminLogisticaMdoCheckRiepilogoMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoCheckRiepilogoAndroidPage();
  }
}

class AdminLogisticaMezziStradaliMobilePage extends StatelessWidget {
  const AdminLogisticaMezziStradaliMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMezziStradaliAndroidPage();
  }
}

class AdminLogisticaAssegnazioneMezziStradaliMobilePage extends StatelessWidget {
  const AdminLogisticaAssegnazioneMezziStradaliMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaAssegnazioneMezziStradaliAndroidPage();
  }
}

class AdminLogisticaAssegnazioneAttrezzatureMobilePage extends StatelessWidget {
  const AdminLogisticaAssegnazioneAttrezzatureMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaAssegnazioneAttrezzatureAndroidPage();
  }
}

class AdminLogisticaNoleggioMobilePage extends StatelessWidget {
  const AdminLogisticaNoleggioMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaNoleggioAndroidPage();
  }
}

class AdminLogisticaSimMobilePage extends StatelessWidget {
  const AdminLogisticaSimMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaSimPage(forceMobileLayout: true);
  }
}

class AdminLogisticaOfficineConvenzionateMobilePage extends StatelessWidget {
  const AdminLogisticaOfficineConvenzionateMobilePage({
    super.key,
    this.readOnly = false,
  });

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaOfficineConvenzionatePage(
      forceMobileLayout: true,
      readOnly: readOnly,
    );
  }
}

class AdminBachecaMobilePage extends StatelessWidget {
  const AdminBachecaMobilePage({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return AdminBachecaPage(
      forceMobileLayout: true,
      readOnly: readOnly,
    );
  }
}

class AdminLogisticaHubMobilePage extends StatelessWidget {
  final int? userId;
  final String? role;
  const AdminLogisticaHubMobilePage({super.key, this.userId, this.role});

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaHubPage(userId: userId, role: role);
  }
}

class AdminCarburanteHubMobilePage extends StatelessWidget {
  final int? userId;
  final String? role;
  const AdminCarburanteHubMobilePage({super.key, this.userId, this.role});

  @override
  Widget build(BuildContext context) {
    return AdminCarburanteHubPage(userId: userId, role: role);
  }
}
