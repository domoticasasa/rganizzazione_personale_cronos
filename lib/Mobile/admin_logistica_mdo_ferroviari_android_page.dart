import 'package:flutter/material.dart';

import '../pages/admin_logistica_mdo_ferroviari_page.dart';

/// Versione dedicata Android/mobile per MDO Ferroviari.
/// Forza sempre il layout mobile, anche su display larghi.
class AdminLogisticaMdoFerroviariAndroidPage extends StatelessWidget {
  final bool dipendenteMode;
  const AdminLogisticaMdoFerroviariAndroidPage({
    super.key,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaMdoFerroviariPage(
      dipendenteMode: dipendenteMode,
      forceMobileLayout: true,
    );
  }
}
