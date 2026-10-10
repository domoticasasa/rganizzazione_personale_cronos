import 'package:flutter/material.dart';

import '../pages/admin_logistica_assegnazione_mezzi_stradali_page.dart';
import '../pages/employee_assegnazione_mezzi_page.dart';

class AdminLogisticaAssegnazioneMezziStradaliAndroidPage extends StatelessWidget {
  final bool dipendenteMode;

  const AdminLogisticaAssegnazioneMezziStradaliAndroidPage({
    super.key,
    this.dipendenteMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (dipendenteMode) {
      return const EmployeeAssegnazioneMezziPage(forceMobileLayout: true);
    }
    return const AdminLogisticaAssegnazioneMezziStradaliPage(
      forceMobileLayout: true,
    );
  }
}
