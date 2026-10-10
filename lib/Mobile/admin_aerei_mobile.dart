import 'package:flutter/material.dart';

import '../pages/admin_aerei_page.dart';

class AdminAereiMobilePage extends StatelessWidget {
  final int adminId;
  const AdminAereiMobilePage({super.key, required this.adminId});

  @override
  Widget build(BuildContext context) {
    return AdminAereiPage(adminId: adminId);
  }
}
