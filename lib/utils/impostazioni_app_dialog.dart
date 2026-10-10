import 'package:flutter/material.dart';

import '../hub/impostazioni_hub_nav_items.dart';
import '../pages/admin_impostazioni_hub_page.dart';
import '../utils/pulizia_dati_dialog.dart';

/// Apre Impostazioni App come pagina normale (non popup).
Future<void> showImpostazioniAppDialog(
  BuildContext context, {
  required int adminId,
  String? role,
  ImpostazioniPuliziaCallback? onPuliziaDati,
}) async {
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AdminImpostazioniHubPage(
        adminId: adminId,
        role: role,
        onPuliziaDati: onPuliziaDati ?? showPuliziaDatiDialog,
      ),
    ),
  );
}
