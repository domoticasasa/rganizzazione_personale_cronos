import 'package:flutter/material.dart';

import '../hub/custom_hub_structure_type.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../pages/admin_custom_hub_page.dart';
import '../services/app_ui_layout_service.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import '../utils/custom_hub_create_dialog.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/mobile_navigation.dart';

/// Dialogo + creazione pagina/cartella hub custom vuota e apertura.
Future<void> promptCreateCustomHubPage(
  BuildContext context, {
  int? userId,
  String? role,
  String? originLayoutKey,
  bool asSubfolder = false,
  HomeDipendenteNavParams? homeDipendente,
}) async {
  final request = await showCustomHubCreateDialog(
    context,
    asFolder: asSubfolder,
  );
  if (request == null || !context.mounted) return;

  try {
    final hub = await AppUiLayoutService.createCustomHub(
      label: request.label,
      structureType: CustomHubStructureType.home,
      slots: const <CustomHubSlot>[],
      alsoShowOnLayoutKey: originLayoutKey,
      onlyOnOriginLayout: asSubfolder,
    );
    if (!context.mounted) return;
    final origin = (originLayoutKey ?? '').trim();
    final onThisHub = origin.isNotEmpty &&
        origin != AppUiLayoutService.layoutDashboardAdmin;
    final snack = asSubfolder
        ? (onThisHub
            ? 'Cartella «${hub.label}» creata qui. In «Riordina» sposta i pulsanti dentro.'
            : 'Cartella «${hub.label}» creata.')
        : (onThisHub
            ? 'Pagina «${hub.label}» creata: compare qui e sulla Dashboard.'
            : 'Pagina «${hub.label}» creata sulla Dashboard.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snack),
        duration: const Duration(seconds: 4),
      ),
    );
    if (!context.mounted) return;

    final hubPage = useMobileUi(context)
        ? AdminCustomHubMobilePage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: userId,
            role: role,
            initialHub: hub,
            homeDipendente: homeDipendente,
          )
        : AdminCustomHubPage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: userId,
            role: role,
            initialHub: hub,
            homeDipendente: homeDipendente,
          );

    await FuturisticNavigation.pushPage<void>(
      context,
      page: hubPage,
      title: hub.label,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          asSubfolder
              ? 'Errore creazione cartella: $e'
              : 'Errore creazione pagina: $e',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }
}
