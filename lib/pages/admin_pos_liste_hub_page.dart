import 'package:flutter/material.dart';

import '../services/app_ui_layout_service.dart';
import '../pages/admin_reorderable_hub_page.dart';

class AdminPosListeHubPage extends StatelessWidget {
  const AdminPosListeHubPage({
    super.key,
    this.userId,
    this.role,
  });

  final int? userId;
  final String? role;

  @override
  Widget build(BuildContext context) {
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutListePosHub,
      title: 'Liste POS',
      userId: userId,
      role: role,
      maxCellWidth: 200,
      mobileAspectRatio: 2.45,
      savedSnackMessage: 'Ordine Liste POS salvato.',
    );
  }
}
