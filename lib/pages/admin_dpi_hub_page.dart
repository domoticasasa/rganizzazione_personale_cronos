import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import 'admin_reorderable_hub_page.dart';

class AdminDpiHubPage extends StatelessWidget {
  const AdminDpiHubPage({
    super.key,
    this.userId,
    this.role,
  });

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutDpiHub,
      title: 'Admin - DPI e Vestiario',
      userId: userId,
      role: role,
      maxCellWidth: 200,
      mobileAspectRatio: 1.12,
      savedSnackMessage: 'Ordine DPI salvato per tutti gli utenti.',
    );
  }
}
