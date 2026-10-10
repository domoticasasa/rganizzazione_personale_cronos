import 'package:flutter/material.dart';

import '../Mobile/admin_logistica_assegnazione_attrezzature_android_page.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_logistica_assegnazione_attrezzature_page.dart';
import '../pages/admin_logistica_attrezzature_page.dart';
import '../utils/futuristic_navigation.dart';
import 'dipendente_rifornimento_chooser.dart';
import 'mobile_navigation.dart';

/// Popup Logistica → Attrezzature: anagrafica + PDF assegnazione.
Future<void> showLogisticaAttrezzatureChooser(
  BuildContext context, {
  required bool attrezzatureReadOnly,
}) {
  return showDipendentePageChooser(
    context,
    title: 'Attrezzature',
    headerIcon: Icons.handyman_outlined,
    headerAccent: const Color(0xFF2E7D32),
    options: [
      DipendenteChooserOption(
        id: 'lista',
        icon: Icons.handyman_outlined,
        title: 'Lista attrezzature',
        subtitle: 'Anagrafica e assegnatari',
        accent: const Color(0xFF2E7D32),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? AdminLogisticaAttrezzatureMobilePage(
                  readOnly: attrezzatureReadOnly,
                )
              : AdminLogisticaAttrezzaturePage(
                  readOnly: attrezzatureReadOnly,
                ),
          title: 'Attrezzature',
          activeSubKey: 'attrezzature',
        ),
      ),
      DipendenteChooserOption(
        id: 'assegnazione',
        icon: Icons.picture_as_pdf_outlined,
        title: 'Assegnazione Attrezzature',
        subtitle: 'Carica e consulta i PDF di assegnazione',
        accent: const Color(0xFFC62828),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaAssegnazioneAttrezzatureAndroidPage()
              : const AdminLogisticaAssegnazioneAttrezzaturePage(),
          title: 'Assegnazione Attrezzature',
          activeSubKey: 'assegnazione_attrezzature',
        ),
      ),
    ],
  );
}
