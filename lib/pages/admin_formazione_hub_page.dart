import 'package:flutter/material.dart';

import '../hub/home_dipendente_nav_items.dart';
import '../services/app_ui_layout_service.dart';
import 'admin_reorderable_hub_page.dart';

class AdminFormazioneHubPage extends StatelessWidget {
  const AdminFormazioneHubPage({
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
    return AdminReorderableHubPage(
      layoutKey: AppUiLayoutService.layoutUqsaHub,
      title: 'UQSA',
      userId: adminUserId,
      role: role,
      showUqsaTesserino: showIlMioTesserino,
      showUqsaTesserini: showTesserini,
      homeDipendente: adminUserId != null
          ? HomeDipendenteNavParams(
              userId: adminUserId!,
              username: '',
              fullName: '',
            )
          : null,
      maxCellWidth: 200,
      mobileAspectRatio: 2.45,
      savedSnackMessage: 'Ordine UQSA salvato per tutti gli utenti.',
    );
  }
}
