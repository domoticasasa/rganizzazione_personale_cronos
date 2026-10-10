import 'package:flutter/material.dart';

import '../hub/app_ui_custom_hub.dart';
import '../hub/custom_hub_page_config.dart';
import '../services/app_ui_layout_service.dart';
import '../services/supabase_service.dart';
import '../utils/roles.dart';
import 'custom_hub_page_config_editor.dart';
import 'prenotazione_pernottamenti_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Pagina prenotazioni costruita da configurazione (senza codice).
class CustomHubPrenotazioniPage extends StatefulWidget {
  const CustomHubPrenotazioniPage({
    super.key,
    required this.hub,
    this.userId,
    this.role,
  });

  final AppUiCustomHub hub;
  final int? userId;
  final String? role;

  @override
  State<CustomHubPrenotazioniPage> createState() =>
      _CustomHubPrenotazioniPageState();
}

class _CustomHubPrenotazioniPageState extends State<CustomHubPrenotazioniPage> {
  String? _username;
  String? _fullName;
  bool _loadingUser = true;
  CustomHubPageConfig? _pageConfig;

  @override
  void initState() {
    super.initState();
    _pageConfig = widget.hub.pageConfig ??
        CustomHubPageConfig.defaultPrenotazioni();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = widget.userId;
    if (uid == null) {
      setState(() {
        _username = 'admin';
        _fullName = widget.hub.label;
        _loadingUser = false;
      });
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('users')
          .select('username, full_name, role')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _username = (row?['username'] ?? 'admin').toString();
        _fullName = (row?['full_name'] ?? widget.hub.label).toString();
        _loadingUser = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _username = 'admin';
        _fullName = widget.hub.label;
        _loadingUser = false;
      });
    }
  }

  Future<void> _openConfigEditor() async {
    final cfg = _pageConfig ?? CustomHubPageConfig.defaultPrenotazioni();
    final updated = await showCustomHubPageConfigEditor(
      context,
      layoutKey: widget.hub.layoutKey,
      pageLabel: widget.hub.label,
      initial: cfg,
    );
    if (updated == null || !mounted) return;
    setState(() => _pageConfig = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout pagina aggiornato.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(context, AppBar(title: Text(widget.hub.label))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final canEdit = AppUiLayoutService.canEditGlobalLayout(
      normalizeRole(widget.role ?? ''),
    );

    return PrenotazionePernottamentiPage(
      key: ValueKey('${widget.hub.layoutKey}_${_pageConfig.hashCode}'),
      username: _username ?? 'admin',
      userId: widget.userId ?? 0,
      role: widget.role ?? 'admin_generale',
      fullName: _fullName ?? widget.hub.label,
      customHubLayoutKey: widget.hub.layoutKey,
      pageTitle: widget.hub.label,
      pageConfig: _pageConfig,
      onEditPageConfig: canEdit ? _openConfigEditor : null,
    );
  }
}
