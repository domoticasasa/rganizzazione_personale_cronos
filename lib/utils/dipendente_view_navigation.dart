import 'package:flutter/material.dart';

import '../Mobile/employee_mobile_pages.dart';
import '../pages/dipendente_prenotazione_page.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';

/// Ruoli che possono aprire l’anteprima «vista dipendente» (non già dipendente puro).
bool canPreviewDipendenteView(String role) {
  return !const {'dipendente', 'dipendenti', 'user'}
      .contains(normalizeRole(role));
}

/// Hub dipendente (Vista Dipendente / funzioni da dipendente).
Future<void> openDipendenteView(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
}) {
  final page = useMobileUi(context)
      ? DipendentePrenotazioniMobilePage(
          userId: userId,
          username: username,
          fullName: fullName,
        )
      : DipendentePrenotazioniPage(
          userId: userId,
          username: username,
          fullName: fullName,
        );
  return FuturisticNavigation.pushPage<void>(
    context,
    page: page,
    title: 'Area dipendente',
  );
}
