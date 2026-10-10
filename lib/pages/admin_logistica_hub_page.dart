import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import 'admin_reorderable_hub_page.dart';

class AdminLogisticaHubPage extends StatelessWidget {
  final int? userId;
  final String? role;

  const AdminLogisticaHubPage({super.key, this.userId, this.role});

  @override
  Widget build(BuildContext context) {
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutLogisticaHub,
      title: 'Admin - Logistica',
      userId: userId,
      role: role,
      savedSnackMessage: 'Ordine Logistica salvato per tutti gli utenti.',
    );
  }
}
