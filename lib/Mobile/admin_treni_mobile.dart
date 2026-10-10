import 'package:flutter/material.dart';

import '../pages/admin_treni_page.dart';

class AdminTreniMobilePage extends StatelessWidget {
  final int adminId;
  const AdminTreniMobilePage({super.key, required this.adminId});

  @override
  Widget build(BuildContext context) {
    return AdminTreniPage(adminId: adminId);
  }
}
