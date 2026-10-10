import 'package:flutter/material.dart';

import '../pages/admin_formazione_hub_page.dart';
import '../pages/admin_pos_liste_hub_page.dart';
import '../pages/admin_documenti_firma_page.dart';
import '../pages/admin_logistica_multicard_page.dart';
import '../pages/admin_logistica_telepass_page.dart';
import '../pages/admin_tesserini_page.dart';
import '../pages/dipendente_documenti_firma_page.dart';
import '../pages/dipendente_tesserino_page.dart';
import '../pages/dpi_page.dart';
import '../pages/dt_programmazione_formazioni_page.dart';
import '../pages/admin_dipendente_assenze_page.dart';
import '../pages/admin_visite_mediche_page.dart';
import '../pages/dt_programmazione_formazioni_rfi_page.dart';
import '../pages/employee_formazione_rfi_scadenze_page.dart';
import '../pages/employee_formazione_scadenze_page.dart';
import '../pages/employee_uqsa_attestati_page.dart';
import '../pages/logistica_qt_carburante_verifica_page.dart';
import '../pages/carburante_giustificativi_riepilogo_page.dart';
import '../pages/logistica_rcc_carburante_page.dart';
import '../pages/logistica_rcc_mdo_carburante_page.dart';
import '../pages/admin_verifica_costo_stradale_page.dart';
import 'admin_logistica_mezzi_stradali_android_page.dart';
import 'admin_logistica_mdo_ferroviari_android_page.dart';

// —— Tesserini ——

class DipendenteTesserinoMobilePage extends StatelessWidget {
  final int userId;

  const DipendenteTesserinoMobilePage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return DipendenteTesserinoPage(userId: userId);
  }
}

class AdminTesseriniMobilePage extends StatelessWidget {
  const AdminTesseriniMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminTesseriniPage();
  }
}

// —— Formazione / UQSA ——

class AdminFormazioneHubMobilePage extends StatelessWidget {
  const AdminFormazioneHubMobilePage({
    super.key,
    this.adminUserId,
    this.showIlMioTesserino = false,
    this.showTesserini = false,
    this.role,
  });

  final int? adminUserId;
  final bool showIlMioTesserino;
  final bool showTesserini;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminFormazioneHubPage(
      adminUserId: adminUserId,
      showIlMioTesserino: showIlMioTesserino,
      showTesserini: showTesserini,
      role: role,
    );
  }
}

class AdminPosListeHubMobilePage extends StatelessWidget {
  const AdminPosListeHubMobilePage({
    super.key,
    this.userId,
    this.role,
  });

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminPosListeHubPage(
      userId: userId,
      role: role,
    );
  }
}

class DtProgrammazioneFormazioniMobilePage extends StatelessWidget {
  final bool employeeOnly;
  final String? employeeFullName;
  final String? role;

  const DtProgrammazioneFormazioniMobilePage({
    super.key,
    this.employeeOnly = false,
    this.employeeFullName,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    return DtProgrammazioneFormazioniPage(
      employeeOnly: employeeOnly,
      employeeFullName: employeeFullName,
      role: role,
    );
  }
}

class DtProgrammazioneFormazioniRfiMobilePage extends StatelessWidget {
  final bool employeeOnly;
  final String? employeeFullName;

  const DtProgrammazioneFormazioniRfiMobilePage({
    super.key,
    this.employeeOnly = false,
    this.employeeFullName,
  });

  @override
  Widget build(BuildContext context) {
    return DtProgrammazioneFormazioniRfiPage(
      employeeOnly: employeeOnly,
      employeeFullName: employeeFullName,
    );
  }
}

// —— Dipendente ——

class EmployeeFormazioneScadenzeMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;

  const EmployeeFormazioneScadenzeMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return EmployeeFormazioneScadenzePage(
      userId: userId,
      fullName: fullName,
      forceMobileLayout: true,
    );
  }
}

class EmployeeFormazioneRfiScadenzeMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;

  const EmployeeFormazioneRfiScadenzeMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return EmployeeFormazioneRfiScadenzePage(
      userId: userId,
      fullName: fullName,
      forceMobileLayout: true,
    );
  }
}

class EmployeeUqsaAttestatiMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;

  const EmployeeUqsaAttestatiMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return EmployeeUqsaAttestatiPage(
      userId: userId,
      fullName: fullName,
      forceMobileLayout: true,
    );
  }
}

class DpiMobilePage extends StatelessWidget {
  final String fullName;
  final String personaleUuid;

  const DpiMobilePage({
    super.key,
    required this.fullName,
    required this.personaleUuid,
  });

  @override
  Widget build(BuildContext context) {
    return DpiPage(fullName: fullName, personaleUuid: personaleUuid);
  }
}

// —— Logistica (layout mobile forzato) ——

class LogisticaRccCarburanteMobilePage extends StatelessWidget {
  final bool dipendenteMode;

  const LogisticaRccCarburanteMobilePage({
    super.key,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return LogisticaRccCarburantePage(
      dipendenteMode: dipendenteMode,
      forceMobileLayout: true,
    );
  }
}

class LogisticaRccMdoCarburanteMobilePage extends StatelessWidget {
  final bool dipendenteMode;

  const LogisticaRccMdoCarburanteMobilePage({
    super.key,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return LogisticaRccMdoCarburantePage(
      dipendenteMode: dipendenteMode,
      forceMobileLayout: true,
    );
  }
}

class LogisticaQtCarburanteVerificaMobilePage extends StatelessWidget {
  const LogisticaQtCarburanteVerificaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LogisticaQtCarburanteVerificaPage(forceMobileLayout: true);
  }
}

class CarburanteGiustificativiRiepilogoMobilePage extends StatelessWidget {
  const CarburanteGiustificativiRiepilogoMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CarburanteGiustificativiRiepilogoPage();
  }
}

class AdminVerificaCostoStradaleMobilePage extends StatelessWidget {
  const AdminVerificaCostoStradaleMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminVerificaCostoStradalePage(forceMobileLayout: true);
  }
}

class DipendenteAssenzeMobilePage extends StatelessWidget {
  final DipendenteAssenzePageMode pageMode;
  final bool adminMode;
  final bool readOnly;
  final int? userId;
  final String? role;
  final String? fullName;

  const DipendenteAssenzeMobilePage({
    super.key,
    this.pageMode = DipendenteAssenzePageMode.dipendente,
    this.adminMode = false,
    this.readOnly = false,
    this.userId,
    this.role,
    this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return DipendenteAssenzePage(
      pageMode: pageMode,
      adminMode: adminMode,
      readOnly: readOnly,
      userId: userId,
      role: role,
      fullName: fullName,
    );
  }
}

class VisiteMedicheMobilePage extends StatelessWidget {
  final bool adminMode;
  final bool employeeOnly;
  final String? employeeFullName;
  final bool rfiMode;

  const VisiteMedicheMobilePage({
    super.key,
    this.adminMode = false,
    this.employeeOnly = false,
    this.employeeFullName,
    this.rfiMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return VisiteMedichePage(
      adminMode: adminMode,
      employeeOnly: employeeOnly,
      employeeFullName: employeeFullName,
      rfiMode: rfiMode,
    );
  }
}

class AdminLogisticaMulticardMobilePage extends StatelessWidget {
  final bool dipendenteMode;
  const AdminLogisticaMulticardMobilePage({super.key, this.dipendenteMode = false});

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaMulticardPage(
      forceMobileLayout: true,
      dipendenteMode: dipendenteMode,
    );
  }
}

class AdminLogisticaTelepassMobilePage extends StatelessWidget {
  final bool dipendenteMode;
  const AdminLogisticaTelepassMobilePage({super.key, this.dipendenteMode = false});

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaTelepassPage(
      forceMobileLayout: true,
      dipendenteMode: dipendenteMode,
    );
  }
}

class AdminLogisticaMdoDipendenteMobilePage extends StatelessWidget {
  const AdminLogisticaMdoDipendenteMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMdoFerroviariAndroidPage(dipendenteMode: true);
  }
}

class AdminLogisticaMezziDipendenteMobilePage extends StatelessWidget {
  const AdminLogisticaMezziDipendenteMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLogisticaMezziStradaliAndroidPage(dipendenteMode: true);
  }
}

class AdminDocumentiFirmaMobilePage extends StatelessWidget {
  const AdminDocumentiFirmaMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDocumentiFirmaPage(forceMobileLayout: true);
  }
}

class DipendenteDocumentiFirmaMobilePage extends StatelessWidget {
  const DipendenteDocumentiFirmaMobilePage({
    super.key,
    required this.userId,
    this.fullName = '',
  });

  final int userId;
  final String fullName;

  @override
  Widget build(BuildContext context) {
    return DipendenteDocumentiFirmaPage(
      userId: userId,
      fullName: fullName,
      forceMobileLayout: true,
    );
  }
}
