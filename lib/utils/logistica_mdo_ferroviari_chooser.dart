import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_dislocazione_mdo_per_commessa_page.dart';
import '../pages/admin_logistica_mdo_check_riepilogo_page.dart';
import '../pages/admin_logistica_mdo_documenti_page.dart';
import '../pages/admin_logistica_mdo_ferroviari_page.dart';
import '../utils/futuristic_navigation.dart';
import 'dipendente_rifornimento_chooser.dart';
import 'mobile_navigation.dart';

/// Popup Logistica → MDO Ferroviari: lista, documenti, per commessa, riepilogo check.
Future<void> showLogisticaMdoFerroviariChooser(
  BuildContext context, {
  required bool mdoPerCommessaReadOnly,
}) {
  return showDipendentePageChooser(
    context,
    title: 'MDO Ferroviari',
    headerIcon: Icons.train_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'lista',
        icon: Icons.list_alt_outlined,
        title: 'Lista MDO',
        subtitle: 'Anagrafica mezzi d’opera ferroviari',
        accent: const Color(0xFF1565C0),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMdoFerroviariMobilePage()
              : const AdminLogisticaMdoFerroviariPage(),
          title: 'Lista MDO',
          activeSubKey: 'mdo_ferroviari',
        ),
      ),
      DipendenteChooserOption(
        id: 'documenti',
        icon: Icons.folder_special_outlined,
        title: 'Documenti MDO',
        subtitle: 'CDC, libro di bordo, INAIL, allegati…',
        accent: const Color(0xFFE65100),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMdoDocumentiMobilePage()
              : const AdminLogisticaMdoDocumentiPage(),
          title: 'Documenti MDO',
          activeSubKey: 'mdo_ferroviari_documenti',
        ),
      ),
      DipendenteChooserOption(
        id: 'per_commessa',
        icon: Icons.alt_route_outlined,
        title: 'MDO per commessa',
        subtitle: 'Mezzi per cantiere e trasferimenti in corso',
        accent: const Color(0xFF00897B),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? AdminDislocazioneMdoPerCommessaMobilePage(
                  readOnly: mdoPerCommessaReadOnly,
                )
              : AdminDislocazioneMdoPerCommessaPage(
                  readOnly: mdoPerCommessaReadOnly,
                ),
          title: 'MDO per commessa',
          activeSubKey: 'mdo_per_commessa',
        ),
      ),
      DipendenteChooserOption(
        id: 'check',
        icon: Icons.fact_check_outlined,
        title: 'Riepilogo check MDO',
        subtitle: 'Data check e assegnatario DT',
        accent: const Color(0xFF5C6BC0),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMdoCheckRiepilogoMobilePage()
              : const AdminLogisticaMdoCheckRiepilogoPage(),
          title: 'Riepilogo check MDO',
          activeSubKey: 'mdo_check_riepilogo',
        ),
      ),
    ],
  );
}
