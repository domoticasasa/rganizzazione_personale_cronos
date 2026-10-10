import 'package:flutter/material.dart';

import '../Mobile/cronos_mobile_pages.dart';
import '../pages/carburante_giustificativi_riepilogo_page.dart';
import '../pages/logistica_qt_carburante_verifica_page.dart';
import '../pages/logistica_rcc_carburante_page.dart';
import '../pages/logistica_rcc_mdo_carburante_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import 'admin_hub_nav_item.dart';

List<AdminHubNavItem> buildCarburanteHubNavItems({String? role}) {
  final r = normalizeRole(role ?? '');
  // Assistente DT: form completo (compilatore + DT autorizzati), non sola modalità dipendente.
  final dipendenteMode = r == 'dipendente';
  const home = AppUiLayoutService.layoutCarburanteHub;
  return <AdminHubNavItem>[
    AdminHubNavItem(
      layoutKey: 'giustificativi_riepilogo',
      defaultLayoutKey: home,
      icon: Icons.summarize_outlined,
      label: 'Riepilogo giustificativi',
      subtitle: 'Statistiche mensili RCC e MDO',
      onTap: (ctx) => useMobileUi(ctx)
          ? const CarburanteGiustificativiRiepilogoMobilePage()
          : const CarburanteGiustificativiRiepilogoPage(),
    ),
    AdminHubNavItem(
      layoutKey: 'rifornimento_mdo',
      defaultLayoutKey: home,
      icon: Icons.local_gas_station_outlined,
      label: 'Rifornimento MDO',
      subtitle: 'Giustificativo carburante',
      onTap: (ctx) => useMobileUi(ctx)
          ? LogisticaRccMdoCarburanteMobilePage(dipendenteMode: dipendenteMode)
          : LogisticaRccMdoCarburantePage(dipendenteMode: dipendenteMode),
    ),
    AdminHubNavItem(
      layoutKey: 'rcc_carburante',
      defaultLayoutKey: home,
      icon: Icons.local_gas_station_outlined,
      label: 'RCC Carburante Stradali',
      subtitle: 'Rifornimento Carburante Mezzi Stradali',
      onTap: (ctx) => useMobileUi(ctx)
          ? LogisticaRccCarburanteMobilePage(dipendenteMode: dipendenteMode)
          : LogisticaRccCarburantePage(dipendenteMode: dipendenteMode),
    ),
    AdminHubNavItem(
      layoutKey: 'qt_fatturazione_verifica',
      defaultLayoutKey: home,
      icon: Icons.fact_check_outlined,
      label: 'Verifica fatturazione QT',
      subtitle: 'Import Excel e controllo giustificativi RCC',
      onTap: (ctx) => useMobileUi(ctx)
          ? const LogisticaQtCarburanteVerificaMobilePage()
          : const LogisticaQtCarburanteVerificaPage(),
    ),
  ];
}
