import 'package:flutter/material.dart';

import '../hub/app_ui_custom_hub.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/custom_hub_create_dialog.dart';
import '../utils/roles.dart';
import 'admin_carburante_hub_page.dart';
import 'admin_reorderable_hub_page.dart';
import 'custom_hub_prenotazioni_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminCustomHubPage extends StatefulWidget {
  const AdminCustomHubPage({
    super.key,
    required this.layoutKey,
    required this.title,
    this.userId,
    this.role,
    this.initialHub,
    this.homeDipendente,
  });

  final String layoutKey;
  final String title;
  final int? userId;
  final String? role;

  /// Hub appena creato (tipo struttura corretto prima del reload DB).
  final AppUiCustomHub? initialHub;
  final HomeDipendenteNavParams? homeDipendente;

  @override
  State<AdminCustomHubPage> createState() => _AdminCustomHubPageState();
}

class _AdminCustomHubPageState extends State<AdminCustomHubPage> {
  AppUiCustomHub? _hub;
  int _catalogGeneration = 0;
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _hub = widget.initialHub;
    _loadHub();
  }

  Future<void> _loadHub() async {
    final hub = await AppUiLayoutService.loadCustomHub(widget.layoutKey);
    if (!mounted) return;
    setState(() => _hub = hub);
  }

  Future<void> _convertToPrenotazioni() async {
    setState(() => _converting = true);
    try {
      final hub = await AppUiLayoutService.convertCustomHubToPrenotazioni(
        widget.layoutKey,
      );
      if (!mounted) return;
      setState(() {
        _hub = hub;
        _catalogGeneration++;
        _converting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagina convertita in layout Prenotazioni.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore conversione: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _renameSections() async {
    final hub = _hub;
    if (hub == null || hub.slots.isEmpty) return;
    final updated = await showRenameCustomHubSlotsDialog(
      context,
      slots: hub.slots,
      pageLabel: hub.label,
    );
    if (updated == null || !mounted) return;
    await AppUiLayoutService.updateCustomHubSlotLabels(
      layoutKey: hub.layoutKey,
      slots: updated,
    );
    if (!mounted) return;
    setState(() => _catalogGeneration++);
    await _loadHub();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nomi sezioni aggiornati.')),
    );
  }

  bool get _isCarburanteHubPage {
    final label = (_hub?.label ?? widget.title).trim().toLowerCase();
    return label == 'carburante';
  }

  @override
  Widget build(BuildContext context) {
    if (_isCarburanteHubPage && !_converting) {
      return AdminCarburanteHubPage(
        userId: widget.userId,
        role: widget.role,
      );
    }

    final hub = _hub;

    if (hub == null || _converting) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(title: Text('Admin - ${widget.title}'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final pageTitle = hub.label.trim().isNotEmpty ? hub.label : widget.title;

    if (hub.isPrenotazioniLayout) {
      return CustomHubPrenotazioniPage(
        key: ValueKey('${hub.layoutKey}_prenotazioni'),
        hub: hub,
        userId: widget.userId,
        role: widget.role,
      );
    }

    if (hub.looksLikeBrokenPrenotazioniCreate) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(title: Text('Admin - ${widget.title}'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Layout Prenotazioni non attivo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Questa pagina è stata salvata come griglia di pulsanti '
                    '(probabile migration Supabase mancante). Convertila per '
                    'ottenere form, calendario e tabella come Pernottamenti.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _convertToPrenotazioni,
                    icon: const Icon(Icons.transform),
                    label: const Text('Usa layout Prenotazioni'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AdminReorderableHubPage(
      key: ValueKey('${widget.layoutKey}_$_catalogGeneration'),
      layoutKey: widget.layoutKey,
      title: AppUiLayoutService.canEditGlobalLayout(
            normalizeRole(widget.role ?? ''),
          )
          ? 'Admin - $pageTitle'
          : pageTitle,
      userId: widget.userId,
      role: widget.role,
      homeDipendente: widget.homeDipendente,
      showCreatePageButton: true,
      onRenameSections: hub.slots.isNotEmpty ? _renameSections : null,
      maxCellWidth: 200,
      mobileAspectRatio: 2.45,
      savedSnackMessage: 'Ordine pagina salvato per tutti gli utenti.',
    );
  }
}
