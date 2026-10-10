import 'package:flutter/material.dart';

import '../pages/dipendente_prenotazione_page.dart';
import '../pages/notifications_page.dart';
import '../pages/richiesta_treno_page.dart';
import '../pages/richiesta_aereo_page.dart';
import '../pages/richiesta_ferie_permessi_page.dart';

class DipendentePrenotazioniMobilePage extends StatelessWidget {
  final int userId;
  final String username;
  final String fullName;
  const DipendentePrenotazioniMobilePage({
    super.key,
    required this.userId,
    required this.username,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return DipendentePrenotazioniPage(
      userId: userId,
      username: username,
      fullName: fullName,
    );
  }
}

class NotificationsMobilePage extends StatelessWidget {
  final int userId;
  const NotificationsMobilePage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return NotificationsPage(userId: userId);
  }
}

class RichiestaTrenoMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;
  const RichiestaTrenoMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return RichiestaTrenoPage(userId: userId, fullName: fullName);
  }
}

class RichiestaAereoMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;
  const RichiestaAereoMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return RichiestaAereoPage(userId: userId, fullName: fullName);
  }
}

class RichiestaFeriePermessiMobilePage extends StatelessWidget {
  final int userId;
  final String fullName;
  const RichiestaFeriePermessiMobilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return RichiestaFeriePermessiPage(userId: userId, fullName: fullName);
  }
}
