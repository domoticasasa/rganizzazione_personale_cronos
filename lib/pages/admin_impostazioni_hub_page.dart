import 'package:flutter/material.dart';

import '../hub/admin_hub_catalog.dart';
import '../services/app_ui_layout_service.dart';
import 'admin_reorderable_hub_page.dart';

/// Pagina Impostazioni App (griglia compatta, non dialog).
class AdminImpostazioniHubPage extends StatelessWidget {
  final int adminId;
  final String? role;
  final ImpostazioniPuliziaCallback? onPuliziaDati;

  const AdminImpostazioniHubPage({
    super.key,
    required this.adminId,
    this.role,
    this.onPuliziaDati,
  });

  @override
  Widget build(BuildContext context) {
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutImpostazioniHub,
      title: 'Impostazioni App',
      userId: adminId,
      role: role,
      onPuliziaDati: onPuliziaDati,
      // Tile più piccole: più colonne, meno “bottoni enormi”.
      maxCellWidth: 132,
      mobileAspectRatio: 2.35,
      showCreatePageButton: false,
      savedSnackMessage: 'Ordine Impostazioni salvato per tutti gli utenti.',
    );
  }
}
