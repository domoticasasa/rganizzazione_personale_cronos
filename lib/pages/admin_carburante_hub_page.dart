import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import 'admin_reorderable_hub_page.dart';

class AdminCarburanteHubPage extends StatelessWidget {
  const AdminCarburanteHubPage({
    super.key,
    this.userId,
    this.role,
  });

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutCarburanteHub,
      title: 'Admin - Carburante',
      userId: userId,
      role: role,
      maxCellWidth: 220,
      mobileAspectRatio: 2.2,
      savedSnackMessage: 'Ordine hub Carburante salvato per tutti gli utenti.',
    );
  }
}
