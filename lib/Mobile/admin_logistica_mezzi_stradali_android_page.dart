import 'package:flutter/material.dart';

import '../pages/admin_logistica_mezzi_stradali_page.dart';

/// Versione dedicata Android/mobile per Mezzi Stradali.
/// Forza sempre il layout mobile, anche su display larghi.
class AdminLogisticaMezziStradaliAndroidPage extends StatelessWidget {
  final bool dipendenteMode;
  const AdminLogisticaMezziStradaliAndroidPage({
    super.key,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return AdminLogisticaMezziStradaliPage(
      dipendenteMode: dipendenteMode,
      forceMobileLayout: true,
    );
  }
}
