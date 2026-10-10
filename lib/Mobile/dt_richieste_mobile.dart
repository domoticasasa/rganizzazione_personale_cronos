import 'package:flutter/material.dart';

import '../pages/dt_richieste_page.dart';

class DTRichiesteMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;
  const DTRichiesteMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return DTRichiestePage(userId: userId, fullName: fullName);
  }
}
