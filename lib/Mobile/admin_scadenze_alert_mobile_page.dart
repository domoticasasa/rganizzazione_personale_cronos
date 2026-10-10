import 'package:flutter/material.dart';

import '../pages/admin_scadenze_alert_page.dart';

/// Alert scadenze su telefono: elenco compatto senza logo verticale.
class AdminScadenzeAlertMobilePage extends StatelessWidget {
  const AdminScadenzeAlertMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminScadenzeAlertPage(hideTopLogo: true);
  }
}
