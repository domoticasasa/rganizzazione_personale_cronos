import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../services/app_branding_service.dart';
import '../services/classic_nav_session_cache.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Impostazioni → Personalizzazione app (white-label organizzazione).
class AdminPersonalizzazioneAppPage extends StatefulWidget {
  const AdminPersonalizzazioneAppPage({super.key});

  @override
  State<AdminPersonalizzazioneAppPage> createState() =>
      _AdminPersonalizzazioneAppPageState();
}

class _AdminPersonalizzazioneAppPageState
    extends State<AdminPersonalizzazioneAppPage> {
  final _brandCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _welcomeCtrl = TextEditingController();
  final _accentCtrl = TextEditingController();
  final _barCtrl = TextEditingController();
  final _topBarCtrl = TextEditingController();
  final _sidebarCtrl = TextEditingController();
  final _copyShortCtrl = TextEditingController();
  final _copyFullCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _busyAsset;

  bool get _canEdit {
    final role = ClassicNavSessionCache.current?.role ?? '';
    return canMutateAsAdmin(role);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _productCtrl.dispose();
    _titleCtrl.dispose();
    _welcomeCtrl.dispose();
    _accentCtrl.dispose();
    _barCtrl.dispose();
    _topBarCtrl.dispose();
    _sidebarCtrl.dispose();
    _copyShortCtrl.dispose();
    _copyFullCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(AppBrandingSnapshot d) {
    _brandCtrl.text = d.brandName;
    _productCtrl.text = d.productName;
    _titleCtrl.text = d.appTitle;
    _welcomeCtrl.text = d.welcomeSubtitle;
    _accentCtrl.text = d.accentColorHex;
    _barCtrl.text = d.logoBarColorHex;
    _topBarCtrl.text = d.topBarColorHex;
    _sidebarCtrl.text = d.sidebarColorHex;
    _copyShortCtrl.text = d.copyrightShort ?? '';
    _copyFullCtrl.text = d.copyrightFull ?? '';
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppBrandingService.instance.load();
      if (!mounted) return;
      _fillFrom(AppBrandingService.instance.data);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _guardEdit() {
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
      return false;
    }
    if (!_canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permesso negato: solo admin.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _saveTexts() async {
    if (!_guardEdit()) return;
    setState(() => _saving = true);
    try {
      await AppBrandingService.instance.saveTextsAndColors(
        brandName: _brandCtrl.text,
        productName: _productCtrl.text,
        appTitle: _titleCtrl.text,
        welcomeSubtitle: _welcomeCtrl.text,
        accentColorHex: _accentCtrl.text,
        logoBarColorHex: _barCtrl.text,
        topBarColorHex: _topBarCtrl.text,
        sidebarColorHex: _sidebarCtrl.text,
        copyrightShort: _copyShortCtrl.text,
        copyrightFull: _copyFullCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personalizzazione salvata.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUpload(AppBrandingAssetKind kind) async {
    if (!_guardEdit()) return;
    const group = XTypeGroup(
      label: 'Immagini',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    setState(() => _busyAsset = kind.name);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('File vuoto');
      if (bytes.length > 8 * 1024 * 1024) {
        throw Exception('File troppo grande (max 8 MB)');
      }
      final name = file.name;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot + 1) : 'png';
      await AppBrandingService.instance.uploadAsset(
        kind: kind,
        bytes: Uint8List.fromList(bytes),
        ext: ext,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Immagine caricata.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fallito: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAsset = null);
    }
  }

  Future<void> _clearAsset(AppBrandingAssetKind kind) async {
    if (!_guardEdit()) return;
    setState(() => _busyAsset = kind.name);
    try {
      await AppBrandingService.instance.clearAsset(kind);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Immagine rimossa (default ripristinato).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAsset = null);
    }
  }

  Future<void> _resetAll() async {
    if (!_guardEdit()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristina default'),
        content: const Text(
          'Tornare a CRONOS / GESTOPRO e rimuovere logo e sfondi personalizzati?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ripristina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await AppBrandingService.instance.resetToDefaults();
      if (!mounted) return;
      _fillFrom(AppBrandingService.instance.data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default ripristinati.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickColor(TextEditingController ctrl) async {
    final initial = parseBrandHex(ctrl.text);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _BrandColorPickerDialog(initial: initial),
    );
    if (picked == null) return;
    setState(() => ctrl.text = _colorToHex(picked));
  }

  static String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Widget _buildLivePreview(ThemeData theme) {
    final topBar = parseBrandHex(_topBarCtrl.text);
    final sidebar = parseBrandHex(_sidebarCtrl.text);
    final accent = parseBrandHex(_accentCtrl.text);
    final logoBar = parseBrandHex(_barCtrl.text);
    final brand = _brandCtrl.text.trim().isEmpty ? 'CRONOS' : _brandCtrl.text.trim();
    final product =
        _productCtrl.text.trim().isEmpty ? 'GESTOPRO' : _productCtrl.text.trim();
    final welcome = _welcomeCtrl.text.trim();
    final onTop = topBar.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    final onSide =
        sidebar.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Anteprima interfaccia',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Aggiornamento live',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Simulazione chrome classico + pulsante chat. '
              'I colori sotto si riflettono subito (salva per applicarli in app).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 292,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Top bar
                  Container(
                    height: 44,
                    color: topBar,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(Icons.menu, size: 18, color: onTop),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$brand  ·  $product',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onTop,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Icon(Icons.notifications_outlined,
                            size: 18, color: onTop.withValues(alpha: 0.9)),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: accent,
                          child: Icon(Icons.person,
                              size: 14,
                              color: accent.computeLuminance() > 0.55
                                  ? Colors.black87
                                  : Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        // Sidebar
                        Container(
                          width: 56,
                          color: sidebar,
                          child: Column(
                            children: [
                              const SizedBox(height: 10),
                              _previewNavIcon(Icons.dashboard_outlined, onSide,
                                  selected: true, accent: accent),
                              _previewNavIcon(Icons.inventory_2_outlined, onSide,
                                  accent: accent),
                              _previewNavIcon(Icons.local_shipping_outlined, onSide,
                                  accent: accent),
                              _previewNavIcon(Icons.settings_outlined, onSide,
                                  accent: accent),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Icon(Icons.logout,
                                    size: 16,
                                    color: onSide.withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                        ),
                        // Content
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                color: const Color(0xFFF4F6F9),
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: logoBar,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const AppLogo(size: 28),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              product,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: logoBar.computeLuminance() >
                                                        0.55
                                                    ? Colors.black87
                                                    : Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      welcome.isEmpty
                                          ? 'Benvenuto in $product'
                                          : welcome,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.black54,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.black12),
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            child: Column(
                                              children: [
                                                Text(
                                                  'Logo',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black45,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                const Expanded(
                                                  child: FittedBox(
                                                    fit: BoxFit.contain,
                                                    child: PageTopLogo(size: 40),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Container(
                                            height: 64,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.black12),
                                            ),
                                            padding: const EdgeInsets.fromLTRB(
                                                8, 6, 8, 6),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                const Text(
                                                  'Pulsante accent',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black45,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: accent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: Text(
                                                      'Salva',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: accent
                                                                    .computeLuminance() >
                                                                0.55
                                                            ? Colors.black87
                                                            : Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'A destra: anteprima del colore accent sui pulsanti (es. Salva).',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: Colors.black45,
                                        height: 1.25,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _copyShortCtrl.text.trim().isEmpty
                                          ? '© $product'
                                          : _copyShortCtrl.text.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: _PreviewChatFab(
                                  productName: product,
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _legendChip('Top bar', topBar),
                _legendChip('Sidebar', sidebar),
                _legendChip('Accent', accent),
                _legendChip('Logo bar', logoBar),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewNavIcon(
    IconData icon,
    Color onSide, {
    required Color accent,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: accent.withValues(alpha: 0.7), width: 1.2)
              : null,
        ),
        child: Icon(icon, size: 18, color: selected ? accent : onSide),
      ),
    );
  }

  Widget _legendChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            _colorToHex(color),
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const Text('Personalizzazione app'),
          actions: [
            IconButton(
              tooltip: 'Ricarica',
              onPressed: _loading || _saving ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListenableBuilder(
                  listenable: AppBrandingService.instance,
                  builder: (context, _) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _buildLivePreview(theme),
                        const SizedBox(height: 12),
                        _section(
                          theme,
                          title: 'Logo',
                          hint:
                              'Consigliato: PNG trasparente ~512×512. Qualsiasi misura funziona: l’app adatta l’immagine.',
                          child: Column(
                            children: [
                              _assetRow(
                                kind: AppBrandingAssetKind.logo,
                                label: 'Logo principale',
                              ),
                              const SizedBox(height: 8),
                              _assetRow(
                                kind: AppBrandingAssetKind.logoLight,
                                label: 'Logo su sfondo scuro (opzionale)',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          theme,
                          title: 'Nomi e titoli',
                          child: Column(
                            children: [
                              TextField(
                                controller: _brandCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nome brand (es. CRONOS)',
                                  border: OutlineInputBorder(),
                                ),
                                textCapitalization: TextCapitalization.characters,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _productCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nome prodotto (es. GESTOPRO)',
                                  border: OutlineInputBorder(),
                                ),
                                textCapitalization: TextCapitalization.characters,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _titleCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Titolo app (scheda browser / window)',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _welcomeCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Sottotitolo / welcome (opzionale)',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          theme,
                          title: 'Colori',
                          hint:
                              'Barra in alto e barra a sinistra si aggiornano in tutta l’app (classica e GESTOPRO).',
                          child: Column(
                            children: [
                              _colorField(
                                label: 'Colore accent (pulsanti / tema)',
                                controller: _accentCtrl,
                              ),
                              const SizedBox(height: 10),
                              _colorField(
                                label: 'Barra superiore (AppBar / top bar)',
                                controller: _topBarCtrl,
                              ),
                              const SizedBox(height: 10),
                              _colorField(
                                label: 'Barra laterale sinistra (sidebar / rail)',
                                controller: _sidebarCtrl,
                              ),
                              const SizedBox(height: 10),
                              _colorField(
                                label: 'Barra logo wordmark',
                                controller: _barCtrl,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          theme,
                          title: 'Copyright / note legali',
                          hint:
                              'Lascia vuoto per generare automaticamente dal nome prodotto.',
                          child: Column(
                            children: [
                              TextField(
                                controller: _copyShortCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Testo corto (footer)',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _copyFullCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Testo completo (popup regole)',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                maxLines: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          theme,
                          title: 'Sfondi',
                          hint:
                              'Immagine di sfondo landscape/portrait (UI classica e GESTOPRO). '
                              'Consigliato ~1920×1080; qualsiasi misura: cover adattivo.',
                          child: Column(
                            children: [
                              _assetRow(
                                kind: AppBrandingAssetKind.bgLandscape,
                                label: 'Sfondo landscape',
                              ),
                              const SizedBox(height: 8),
                              _assetRow(
                                kind: AppBrandingAssetKind.bgPortrait,
                                label: 'Sfondo portrait',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'Nota: nome e icona del launcher sul dispositivo '
                              '(Android / iOS / Windows) restano di build e non '
                              'si aggiornano da qui.',
                              style: TextStyle(height: 1.35),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving || !_canEdit ? null : _saveTexts,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Salva testi e colori'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _saving || !_canEdit ? null : _resetAll,
                              icon: const Icon(Icons.restore),
                              label: const Text('Ripristina default'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _section(
    ThemeData theme, {
    required String title,
    String? hint,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _colorField({
    required String label,
    required TextEditingController controller,
  }) {
    final color = parseBrandHex(controller.text);
    final onColor =
        color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _canEdit ? () => _pickColor(controller) : null,
                borderRadius: BorderRadius.circular(10),
                child: Ink(
                  width: 112,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black26),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.palette_outlined, size: 18, color: onColor),
                      const SizedBox(width: 6),
                      Text(
                        'Scegli',
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'HEX',
                  border: OutlineInputBorder(),
                  hintText: '#1565C0',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _assetRow({
    required AppBrandingAssetKind kind,
    required String label,
  }) {
    final branding = AppBrandingService.instance;
    final path = branding.pathFor(kind);
    final provider = branding.imageProviderFor(path);
    final busy = _busyAsset == kind.name;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : provider != null
                  ? Image(
                      image: provider,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    )
                  : Icon(
                      kind == AppBrandingAssetKind.logo ||
                              kind == AppBrandingAssetKind.logoLight
                          ? Icons.image_outlined
                          : Icons.wallpaper_outlined,
                      color: Colors.black45,
                    ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                path == null ? 'Default asset' : 'Personalizzato',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: busy || !_canEdit ? null : () => _pickAndUpload(kind),
          child: const Text('Carica'),
        ),
        TextButton(
          onPressed:
              busy || !_canEdit || path == null ? null : () => _clearAsset(kind),
          child: const Text('Rimuovi'),
        ),
      ],
    );
  }
}

class _PreviewChatFab extends StatelessWidget {
  const _PreviewChatFab({
    required this.productName,
    required this.accent,
  });

  final String productName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = productName.trim().isEmpty ? 'GESTOPRO' : productName.trim();
    final width = _chatFabWidthFor(label);
    return Container(
      width: width,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, 0.18)!,
            accent,
            Color.lerp(accent, Colors.black, 0.22)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                color: accent.computeLuminance() > 0.55
                    ? Colors.black87
                    : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 0.4,
                height: 1.05,
              ),
            ),
          ),
          Text(
            'Chat',
            style: TextStyle(
              color: (accent.computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white)
                  .withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 8,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

double _chatFabWidthFor(String productName) {
  final painter = TextPainter(
    text: TextSpan(
      text: productName.toUpperCase(),
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 10,
        letterSpacing: 0.6,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return (painter.width + 28).clamp(100.0, 168.0);
}

class _BrandColorPickerDialog extends StatefulWidget {
  const _BrandColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_BrandColorPickerDialog> createState() =>
      _BrandColorPickerDialogState();
}

class _BrandColorPickerDialogState extends State<_BrandColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;
  late final TextEditingController _rCtrl;
  late final TextEditingController _gCtrl;
  late final TextEditingController _bCtrl;

  static const _presets = <Color>[
    Color(0xFF1565C0),
    Color(0xFF0D47A1),
    Color(0xFF0277BD),
    Color(0xFF00838F),
    Color(0xFF2E7D32),
    Color(0xFF558B2F),
    Color(0xFFF9A825),
    Color(0xFFEF6C00),
    Color(0xFFC62828),
    Color(0xFFAD1457),
    Color(0xFF6A1B9A),
    Color(0xFF4527A0),
    Color(0xFF37474F),
    Color(0xFF263238),
    Color(0xFFEEF3FA),
    Color(0xFF00AEEF),
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController();
    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _syncFieldsFromHsv();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _syncFieldsFromHsv() {
    final c = _color;
    final hex =
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    _hexCtrl.text = hex;
    _rCtrl.text = '$r';
    _gCtrl.text = '$g';
    _bCtrl.text = '$b';
  }

  void _setColor(Color c) {
    setState(() {
      _hsv = HSVColor.fromColor(c);
      _syncFieldsFromHsv();
    });
  }

  void _applyHex(String raw) {
    final n = parseBrandHex(raw, fallback: _color);
    _setColor(n);
  }

  void _applyRgb() {
    final r = int.tryParse(_rCtrl.text.trim())?.clamp(0, 255) ?? 0;
    final g = int.tryParse(_gCtrl.text.trim())?.clamp(0, 255) ?? 0;
    final b = int.tryParse(_bCtrl.text.trim())?.clamp(0, 255) ?? 0;
    _setColor(Color.fromARGB(255, r, g, b));
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final onColor =
        color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return AlertDialog(
      title: const Text('Scegli colore'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 72,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black26),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Anteprima testo',
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: onColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: onColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Pulsante',
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Palette rapida',
                style: CronosFonts.exo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _presets)
                    InkWell(
                      onTap: () => _setColor(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: p,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.toARGB32() == p.toARGB32()
                                ? Colors.black87
                                : Colors.black26,
                            width: color.toARGB32() == p.toARGB32() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _hexCtrl,
                decoration: const InputDecoration(
                  labelText: 'HEX',
                  border: OutlineInputBorder(),
                  hintText: '#1565C0',
                  isDense: true,
                  suffixIcon: Icon(Icons.check, size: 18),
                ),
                onSubmitted: _applyHex,
                onEditingComplete: () => _applyHex(_hexCtrl.text),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _rgbField('R', _rCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _rgbField('G', _gCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _rgbField('B', _bCtrl)),
                ],
              ),
              const SizedBox(height: 8),
              _slider('Tonalità', _hsv.hue, 360, (v) {
                setState(() {
                  _hsv = _hsv.withHue(v);
                  _syncFieldsFromHsv();
                });
              }),
              _slider('Saturazione', _hsv.saturation, 1, (v) {
                setState(() {
                  _hsv = _hsv.withSaturation(v);
                  _syncFieldsFromHsv();
                });
              }),
              _slider('Luminosità', _hsv.value, 1, (v) {
                setState(() {
                  _hsv = _hsv.withValue(v);
                  _syncFieldsFromHsv();
                });
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _rgbField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => _applyRgb(),
    );
  }

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CronosFonts.exo2(fontSize: 12)),
        Slider(
          value: value.clamp(0, max),
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
