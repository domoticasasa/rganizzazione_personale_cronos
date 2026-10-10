import 'package:flutter/material.dart';

import '../Mobile/admin_logistica_assegnatari_storico_android_page.dart';
import '../Mobile/admin_logistica_assegnazione_mezzi_stradali_android_page.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../pages/admin_logistica_assegnatari_storico_page.dart';
import '../pages/admin_logistica_assegnazione_mezzi_stradali_page.dart';
import '../pages/admin_logistica_mezzi_stradali_page.dart';
import '../pages/admin_logistica_multicard_mdo_assegnazioni_page.dart';
import '../pages/admin_logistica_multicard_page.dart';
import '../pages/admin_logistica_officine_convenzionate_page.dart';
import '../pages/admin_logistica_telepass_page.dart';
import '../pages/viaggi_mezzi_report_page.dart';
import '../utils/futuristic_navigation.dart';
import 'dipendente_rifornimento_chooser.dart';
import 'mobile_navigation.dart';

/// Popup Logistica → Mezzi Stradali e moduli collegati.
Future<void> showLogisticaMezziStradaliChooser(BuildContext context) {
  return showDipendentePageChooser(
    context,
    title: 'Mezzi Stradali',
    headerIcon: Icons.local_shipping_outlined,
    headerAccent: const Color(0xFF1565C0),
    options: [
      DipendenteChooserOption(
        id: 'lista',
        icon: Icons.local_shipping_outlined,
        title: 'Mezzi Stradali',
        subtitle: 'Anagrafica mezzi e scadenze',
        accent: const Color(0xFF1565C0),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMezziStradaliMobilePage()
              : const AdminLogisticaMezziStradaliPage(),
          title: 'Mezzi Stradali',
          activeSubKey: 'mezzi_stradali',
        ),
      ),
      DipendenteChooserOption(
        id: 'assegnazione',
        icon: Icons.assignment_ind_outlined,
        title: 'Assegnazione mezzi stradali',
        subtitle: 'Assegnatari attuali e PDF',
        accent: const Color(0xFF6A1B9A),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaAssegnazioneMezziStradaliAndroidPage()
              : const AdminLogisticaAssegnazioneMezziStradaliPage(),
          title: 'Assegnazione mezzi stradali',
          activeSubKey: 'assegnazione_mezzi_stradali',
        ),
      ),
      DipendenteChooserOption(
        id: 'multicard',
        icon: Icons.credit_card_outlined,
        title: 'Gestione Multicard',
        subtitle: 'Carte carburante associate ai mezzi',
        accent: const Color(0xFF00897B),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMulticardMobilePage()
              : const AdminLogisticaMulticardPage(),
          title: 'Gestione Multicard',
          activeSubKey: 'multicard',
        ),
      ),
      DipendenteChooserOption(
        id: 'multicard_mdo_assegnazioni',
        icon: Icons.picture_as_pdf_outlined,
        title: 'Assegnazioni Multicard MDO',
        subtitle: 'PDF assegnazione per carte con Assegnazione MDO',
        accent: const Color(0xFF00695C),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaMulticardMdoAssegnazioniMobilePage()
              : const AdminLogisticaMulticardMdoAssegnazioniPage(),
          title: 'Assegnazioni Multicard MDO',
          activeSubKey: 'multicard_mdo_assegnazioni',
        ),
      ),
      DipendenteChooserOption(
        id: 'telepass',
        icon: Icons.toll_outlined,
        title: 'Gestione Telepass',
        subtitle: 'Dispositivi Telepass associati',
        accent: const Color(0xFFE65100),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaTelepassMobilePage()
              : const AdminLogisticaTelepassPage(),
          title: 'Gestione Telepass',
          activeSubKey: 'telepass',
        ),
      ),
      DipendenteChooserOption(
        id: 'storico',
        icon: Icons.history_edu_outlined,
        title: 'Storico assegnatari',
        subtitle: 'Mezzi, Multicard, Telepass (4 passaggi)',
        accent: const Color(0xFF5C6BC0),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaAssegnatariStoricoAndroidPage()
              : const AdminLogisticaAssegnatariStoricoPage(),
          title: 'Storico assegnatari',
          activeSubKey: 'storico_assegnatari',
        ),
      ),
      DipendenteChooserOption(
        id: 'officine',
        icon: Icons.garage_outlined,
        title: 'Officine convenzionate',
        subtitle: 'Tagliandi, pneumatici, carrozzeria',
        accent: const Color(0xFF455A64),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: useMobileUi(context)
              ? const AdminLogisticaOfficineConvenzionateMobilePage()
              : const AdminLogisticaOfficineConvenzionatePage(),
          title: 'Officine convenzionate',
          activeSubKey: 'officine_convenzionate',
        ),
      ),
      DipendenteChooserOption(
        id: 'viaggi',
        icon: Icons.route_outlined,
        title: 'Viaggi mezzi stradali',
        subtitle: 'Report aperture/chiusure con km e GPS',
        accent: const Color(0xFF2F6FED),
        onSelect: () => FuturisticNavigation.pushPage(
          context,
          page: const ViaggiMezziReportPage(mode: ViaggiMezziReportMode.admin),
          title: 'Viaggi mezzi stradali',
          activeSubKey: 'viaggi_mezzi_stradali',
        ),
      ),
    ],
  );
}
