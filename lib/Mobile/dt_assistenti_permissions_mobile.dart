import 'package:flutter/material.dart';

import '../pages/dt_assistenti_permissions_page.dart';

class DtAssistentiPermissionsMobilePage extends StatelessWidget {
  final String fullName;
  const DtAssistentiPermissionsMobilePage({
    super.key,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return DtAssistentiPermissionsPage(fullName: fullName);
  }
}
