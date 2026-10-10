import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/employee_programmazione_service.dart';
import '../services/visite_mediche_service.dart';
import '../services/bacheca_service.dart';
import '../services/supabase_service.dart';
import '../services/dipendente_qt_mancanti_prompt.dart';
import '../services/tesserino_foto.dart';
import 'dt_programmazione_formazioni_page.dart';
import 'dt_programmazione_formazioni_rfi_page.dart';
import '../services/confirm_sound_service.dart';
import '../services/app_open_tracker.dart';
import '../widgets/app_logo.dart';
import '../widgets/premium_glass_hub.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/employee_taglie_editor_dialog.dart';
import '../utils/app_copyright.dart';
import '../utils/app_logout.dart';
import '../services/dipendente_foto_prompt.dart';
import '../utils/date_formatters.dart';
import '../utils/buono_pasto_scan_deep_link.dart';
import '../utils/dipendente_rifornimento_chooser.dart';
import '../utils/personale_profile_resolver.dart';
import '../utils/viaggio_mezzo_scan_deep_link.dart';
import 'richiesta_treno_page.dart';
import 'richiesta_aereo_page.dart';
import 'dpi_page.dart';
import 'notifications_page.dart';
import 'employee_formazione_scadenze_page.dart';
import 'employee_formazione_rfi_scadenze_page.dart';
import 'employee_uqsa_attestati_page.dart';
import 'admin_logistica_attrezzature_page.dart';
import 'admin_bacheca_page.dart';
import 'admin_logistica_mdo_ferroviari_page.dart';
import 'admin_logistica_mdo_mappa_page.dart';
import 'admin_dislocazione_mdo_per_commessa_page.dart';
import 'admin_logistica_mezzi_stradali_page.dart';
import 'security_incident_page.dart';
import 'admin_logistica_multicard_page.dart';
import 'admin_logistica_officine_convenzionate_page.dart';
import '../Mobile/admin_misc_mobile_pages.dart';
import 'logistica_rcc_carburante_page.dart';
import 'logistica_rcc_mdo_carburante_page.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../Mobile/employee_mobile_pages.dart';
import '../utils/mobile_navigation.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/responsive.dart';
import '../widgets/mobile_open_container.dart';
import '../widgets/cronos_hold_to_reorder.dart';
import '../widgets/cronos_adaptive_hub_grid.dart';
import '../widgets/futuristic/futuristic_hub_chip.dart';
import '../widgets/futuristic/neon_card.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/video_gallery_navigation.dart';
import '../hub/app_ui_custom_hub.dart';
import '../hub/app_ui_hub_registry.dart';
import '../hub/dipendente_home_button_keys.dart';
import '../hub/home_dipendente_nav_items.dart';
import '../hub/hub_tile_style.dart';
import '../hub/hub_tile_grid.dart';
import 'admin_custom_hub_page.dart';
import '../services/app_ui_layout_service.dart';
import '../utils/custom_hub_creator.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/roles.dart';
import '../widgets/cronos_hub_delete_tile_button.dart';
import '../widgets/cronos_hub_move_to_folder.dart';
import '../widgets/hub_tile_style_editor.dart';
import 'dipendente_documenti_firma_page.dart';
import 'dipendente_tesserino_page.dart';
import 'dipendente_rifornimenti_mancanti_page.dart';
import 'my_profile_page.dart';
import '../widgets/passkey_security_section.dart';
import 'dipendente_buono_pasto_scan_page.dart';
import 'dipendente_buoni_pasto_riepilogo_page.dart';
import 'dipendente_viaggio_mezzo_scan_page.dart';
import 'viaggi_mezzi_report_page.dart';
import 'admin_visite_mediche_page.dart';
import 'richiesta_ferie_permessi_page.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/app_theme_mode_toggle.dart';
import '../services/app_chat_overlay_controller.dart';

/// Dipendente – Vista Dipendente (hub funzioni / prenotazioni in sola lettura)
class DipendentePrenotazioniPage extends StatefulWidget {
  final int userId;
  final String username;
  final String fullName;

  const DipendentePrenotazioniPage({
    super.key,
    required this.userId,
    required this.username,
    required this.fullName,
  });

  @override
  State<DipendentePrenotazioniPage> createState() =>
      _DipendentePrenotazioniPageState();
}

class _DipendentePrenotazioniPageState
    extends State<DipendentePrenotazioniPage> {
  bool _busy = false;
  bool _hasMyProgrammazione = false;
  bool _hasMyProgrammazioneRfi = false;
  bool _hasVisitaMedica = false;
  bool _hasBachecaUnread = false;
  bool _progBlinkOn = true;
  Timer? _progBlinkTimer;
  /// Ruolo dell'utente loggato (non del dipendente in anteprima).
  String? _loggedInRole;
  List<String> _homeButtonKeys = DipendenteHomeButtonKeys.applyVisibility(
    List<String>.from(DipendenteHomeButtonKeys.defaults),
  );
  bool _loadingHomeLayout = true;
  bool _homeReorderMode = false;
  List<String> _homeReorderDraft = <String>[];
  Map<String, HubTileStyle> _tileStyles = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraft = <String, HubTileStyle>{};
  Map<String, HubTileStyle> _styleDraftBaseline = <String, HubTileStyle>{};
  List<AppUiCustomHub> _customHubs = <AppUiCustomHub>[];
  HubLayoutOrders? _hubOrders;
  final Set<String> _dirtyLayoutKeys = <String>{};

  Map<String, HubTileStyle> get _activeStyles =>
      _homeReorderMode ? _styleDraft : _tileStyles;

  /// UUID della riga `personale` collegata all’utente loggato
  String? _myPersonaleUuid;
  String? _fotoTesserinoPath;

  /// Telefono/tablet stretto: UI a sezioni e tile grandi.
  bool get _isMobile => useMobileUi(context);

  @override
  void initState() {
    super.initState();
    unawaited(AppOpenTracker.touchCurrentUser(force: true));
    // FAB chat libero: tieni premuto e trascina (niente posizione fissa).
    AppChatOverlayController.fabAnchorOverride.value = null;
    _progBlinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      if (!_hasMyProgrammazione &&
          !_hasMyProgrammazioneRfi &&
          !_hasVisitaMedica &&
          !_hasBachecaUnread) {
        return;
      }
      setState(() => _progBlinkOn = !_progBlinkOn);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        await AppCopyright.ensureAccepted(context, userId: widget.userId);
        if (!mounted) return;
        await DipendenteFotoPrompt.maybeAsk(
          context,
          onUploaded: (path) {
            if (!mounted) return;
            setState(() => _fotoTesserinoPath = path);
            unawaited(reloadPersonaleProfile());
          },
        );
        if (!mounted) return;
        await DipendenteQtMancantiPrompt.maybeAsk(context);
        if (!mounted) return;
        await ViaggioMezzoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
        if (!mounted) return;
        await BuonoPastoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
      }());
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _progBlinkTimer?.cancel();
    AppChatOverlayController.fabAnchorOverride.value = null;
    super.dispose();
  }

  Future<void> _loadProgrammazioneAlert() async {
    try {
      final hasDlgs =
          await EmployeeProgrammazioneService.hasScheduledForCurrentUser(
        employeeFullName: widget.fullName,
      );
      final hasRfi =
          await EmployeeProgrammazioneService.hasRfiScheduledForCurrentUser(
        employeeFullName: widget.fullName,
      );
      if (!mounted) return;
      setState(() {
        _hasMyProgrammazione = hasDlgs;
        _hasMyProgrammazioneRfi = hasRfi;
      });
    } catch (_) {}
  }

  bool get _canEditHomeLayout =>
      AppUiLayoutService.canEditGlobalLayout(normalizeRole(_loggedInRole ?? ''));

  HomeDipendenteNavParams get _homeDipendenteParams => HomeDipendenteNavParams(
        userId: widget.userId,
        username: widget.username,
        fullName: widget.fullName,
        personaleUuid: _myPersonaleUuid,
      );

  AppUiCustomHub? _folderByLauncherKey(String key) {
    if (!AppUiCustomHub.isLauncherKey(key)) return null;
    for (final hub in _customHubs) {
      if (hub.launcherKey == key) return hub;
    }
    return null;
  }

  String _labelForHomeKey(String key) {
    final folder = _folderByLauncherKey(key);
    if (folder != null) return folder.label;
    return DipendenteHomeButtonKeys.labelFor(key);
  }

  IconData _iconForHomeKey(String key) {
    if (_folderByLauncherKey(key) != null) return Icons.folder_outlined;
    return DipendenteHomeButtonKeys.iconFor(key);
  }

  Future<void> _openFolder(AppUiCustomHub hub) async {
    final page = useMobileUi(context)
        ? AdminCustomHubMobilePage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: widget.userId,
            role: _loggedInRole,
            initialHub: hub,
            homeDipendente: _homeDipendenteParams,
          )
        : AdminCustomHubPage(
            layoutKey: hub.layoutKey,
            title: hub.label,
            userId: widget.userId,
            role: _loggedInRole,
            initialHub: hub,
            homeDipendente: _homeDipendenteParams,
          );
    await FuturisticNavigation.pushPage<void>(
      context,
      page: page,
      title: hub.label,
    );
    if (mounted) await _loadHomeLayout();
  }

  Future<void> _createHomeFolder() async {
    await promptCreateCustomHubPage(
      context,
      userId: widget.userId,
      role: _loggedInRole,
      originLayoutKey: DipendenteHomeButtonKeys.layoutKey,
      asSubfolder: true,
      homeDipendente: _homeDipendenteParams,
    );
    if (mounted) await _loadHomeLayout();
  }

  Future<void> _moveKeyToFolder(String itemKey) async {
    if (_hubOrders == null) return;
    AppUiHubRegistry.bindCustomHubs(_customHubs);
    final target = await pickHubFolderTarget(
      context: context,
      folders: _customHubs,
      currentLayoutKey: DipendenteHomeButtonKeys.layoutKey,
      movingItemKey: itemKey,
    );
    if (target == null || !mounted) return;
    final targetLabel = AppUiHubRegistry.labelFor(target);
    final movedLabel = _labelForHomeKey(itemKey);
    setState(() {
      _hubOrders = AppUiLayoutService.moveItemToLayout(
        orders: _hubOrders!,
        itemKey: itemKey,
        targetLayoutKey: target,
      );
      _homeReorderDraft.remove(itemKey);
      _hubOrders!.setKeysFor(
        DipendenteHomeButtonKeys.layoutKey,
        List<String>.from(_homeReorderDraft),
      );
      _dirtyLayoutKeys.add(DipendenteHomeButtonKeys.layoutKey);
      _dirtyLayoutKeys.add(target);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '«$movedLabel» spostato in $targetLabel. Premi «Salva per tutti» per confermare.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteFolderTile(String launcherKey) async {
    final hub = _folderByLauncherKey(launcherKey);
    if (hub == null) return;
    final confirmed = await confirmDeleteHubTile(
      context,
      label: hub.label,
      itemKey: launcherKey,
      scope: HubTileDeleteScope.customPage,
    );
    if (!confirmed || !mounted) return;
    try {
      await AppUiLayoutService.deleteCustomHub(hub.layoutKey);
      if (!mounted) return;
      setState(() {
        _customHubs = _customHubs
            .where((h) => h.layoutKey != hub.layoutKey)
            .toList(growable: false);
        _homeReorderDraft.remove(launcherKey);
        _homeButtonKeys.remove(launcherKey);
        if (_hubOrders != null) {
          _hubOrders = AppUiLayoutService.removeItemEverywhere(
            _hubOrders!,
            launcherKey,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cartella «${hub.label}» eliminata.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore eliminazione cartella: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _homeReorderActions(String key) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CronosHubMoveToFolderButton(onPressed: () => _moveKeyToFolder(key)),
        if (AppUiCustomHub.isLauncherKey(key))
          CronosHubDeleteTileButton(onPressed: () => _deleteFolderTile(key)),
      ],
    );
  }

  Future<void> _bootstrap() async {
    await _resolveMyPersonaleUuid();
    await _loadLoggedInUserRole();
    await _loadHomeLayout();
    // Non resettare più il layout globale: sovrascriveva «Salva per tutti».
    await _loadProgrammazioneAlert();
    await _loadVisitaMedicaAlert();
    await _loadBachecaUnreadAlert();
  }

  Future<void> _loadLoggedInUserRole() async {
    try {
      final authId = SupabaseService.client.auth.currentUser?.id;
      if (authId == null) return;
      final row = await SupabaseService.client
          .from('users')
          .select('role')
          .eq('auth_id', authId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _loggedInRole = (row?['role'] ?? '').toString());
    } catch (_) {}
  }

  Future<void> _loadHomeLayout({bool forceRefresh = false}) async {
    try {
      final customHubs = await AppUiLayoutService.loadCustomHubs();
      AppUiHubRegistry.bindCustomHubs(customHubs);
      final allOrders = await AppUiLayoutService.loadAllGlobalOrders(
        forceRefresh: forceRefresh,
      );
      const homeKey = DipendenteHomeButtonKeys.layoutKey;
      var homeKeys = List<String>.from(allOrders[homeKey] ?? const <String>[]);
      final catalog = DipendenteHomeButtonKeys.defaults.toSet();
      final elsewhere = <String>{};
      for (final entry in allOrders.entries) {
        if (entry.key == homeKey) continue;
        elsewhere.addAll(entry.value);
      }
      if (homeKeys.isEmpty) {
        homeKeys = List<String>.from(DipendenteHomeButtonKeys.defaults);
      } else {
        homeKeys = homeKeys.where((k) {
          if (catalog.contains(k)) return true;
          if (AppUiCustomHub.isLauncherKey(k)) {
            return customHubs.any((h) => h.launcherKey == k);
          }
          return !elsewhere.contains(k);
        }).toList();
        for (final d in DipendenteHomeButtonKeys.defaults) {
          if (!homeKeys.contains(d)) homeKeys.add(d);
        }
      }
      homeKeys = DipendenteHomeButtonKeys.coalesceGroupedKeys(homeKeys);
      homeKeys = DipendenteHomeButtonKeys.applyVisibility(homeKeys);
      Map<String, HubTileStyle> styles = <String, HubTileStyle>{};
      try {
        styles = await AppUiLayoutService.loadTileStylesForLayout(homeKey);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _customHubs = customHubs;
        _hubOrders = HubLayoutOrders({
          ...allOrders,
          homeKey: homeKeys,
        });
        _dirtyLayoutKeys.clear();
        _homeButtonKeys = homeKeys;
        _tileStyles = styles;
        _loadingHomeLayout = false;
        _homeReorderMode = false;
        _homeReorderDraft = <String>[];
        _styleDraft = <String, HubTileStyle>{};
        _styleDraftBaseline = <String, HubTileStyle>{};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _homeButtonKeys =
            DipendenteHomeButtonKeys.applyVisibility(
          List<String>.from(DipendenteHomeButtonKeys.defaults),
        );
        _tileStyles = <String, HubTileStyle>{};
        _loadingHomeLayout = false;
      });
    }
  }

  // ignore: unused_element
  Future<void> _restoreHomeLayoutDefaults({bool showSnack = true}) async {
    if (!_canEditHomeLayout) return;
    final launchers = _homeButtonKeys
        .where(AppUiCustomHub.isLauncherKey)
        .toList(growable: false);
    try {
      await AppUiLayoutService.resetHubOrderToCatalog(
        layoutKey: DipendenteHomeButtonKeys.layoutKey,
        catalogKeys: DipendenteHomeButtonKeys.defaults,
        extraKeysToKeep: launchers,
        reclaimFromOtherLayouts: true,
      );
      if (!mounted) return;
      await _loadHomeLayout();
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pulsanti ripristinati come in origine.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Errore ripristino: ${AppUiLayoutService.formatPersistError(e)}',
          ),
        ),
      );
    }
  }

  void _enterHomeReorderMode() {
    setState(() {
      _homeReorderMode = true;
      _homeReorderDraft = List<String>.from(_homeButtonKeys);
      _styleDraft = Map<String, HubTileStyle>.from(_tileStyles);
      _styleDraftBaseline = Map<String, HubTileStyle>.from(_tileStyles);
    });
  }

  void _cancelHomeReorderMode() {
    setState(() {
      _homeReorderMode = false;
      _homeReorderDraft = <String>[];
      _styleDraft = <String, HubTileStyle>{};
      _styleDraftBaseline = <String, HubTileStyle>{};
    });
  }

  Future<void> _editButtonStyle(String key) async {
    final result = await showHubTileStyleEditor(
      context: context,
      itemKey: key,
      defaultLabel: _labelForHomeKey(key),
      defaultIcon: _iconForHomeKey(key),
      initial: _activeStyles[key],
      pillButtonOnly: !_isGestoproHomeUi(context),
      futuristicMode: _isGestoproHomeUi(context),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.hasOverrides) {
        if (_homeReorderMode) {
          _styleDraft[key] = result;
        } else {
          _tileStyles[key] = result;
        }
      } else if (_homeReorderMode) {
        _styleDraft.remove(key);
      } else {
        _tileStyles.remove(key);
      }
    });
    if (!_homeReorderMode) {
      await AppUiLayoutService.saveTileStyleForLayout(
        layoutKey: DipendenteHomeButtonKeys.layoutKey,
        itemKey: key,
        style: result,
      );
    }
  }

  Future<void> _saveHomeLayout() async {
    final orderToSave = List<String>.from(_homeReorderDraft);
    if (orderToSave.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ordine vuoto: annulla, riapri «Riordina pulsanti» e riprova.',
          ),
        ),
      );
      return;
    }
    final clearedStyleKeys = _styleDraftBaseline.keys
        .where((k) => !_styleDraft.containsKey(k))
        .toSet();
    final stylesToPersist = AppUiLayoutService.stylesToPersist(
      draft: _styleDraft,
      clearedKeys: clearedStyleKeys,
    );
    final mergedStyles = AppUiLayoutService.applyStyleDraft(
      saved: _tileStyles,
      draft: _styleDraft,
      removedKeys: clearedStyleKeys,
    );
    try {
      if (_hubOrders != null) {
        _hubOrders!.setKeysFor(
          DipendenteHomeButtonKeys.layoutKey,
          orderToSave,
        );
        await AppUiLayoutService.saveOrder(
          layoutKey: DipendenteHomeButtonKeys.layoutKey,
          itemKeys: orderToSave,
        );
        for (final layoutKey in _dirtyLayoutKeys) {
          if (layoutKey == DipendenteHomeButtonKeys.layoutKey) continue;
          await AppUiLayoutService.saveOrder(
            layoutKey: layoutKey,
            itemKeys: _hubOrders!.keysFor(layoutKey),
          );
        }
      } else {
        await AppUiLayoutService.saveOrder(
          layoutKey: DipendenteHomeButtonKeys.layoutKey,
          itemKeys: orderToSave,
        );
      }
      if (stylesToPersist.isNotEmpty) {
        await AppUiLayoutService.saveTileStyles(stylesToPersist);
      }
      if (!mounted) return;
      setState(() {
        _homeButtonKeys = orderToSave;
        _tileStyles = mergedStyles;
        _homeReorderMode = false;
        _homeReorderDraft = <String>[];
        _styleDraft = <String, HubTileStyle>{};
        _styleDraftBaseline = <String, HubTileStyle>{};
        _dirtyLayoutKeys.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ordine e aspetto pulsanti salvati per tutti gli utenti.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      await _loadHomeLayout(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Errore salvataggio: ${AppUiLayoutService.formatPersistError(e)}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  bool _isGestoproHomeUi(BuildContext context) =>
      isGestoproFuturisticUi(context);

  bool _isAlertKey(String key) {
    final formazioneAlert = switch (key) {
      'emp_formazione' =>
        (_hasMyProgrammazione || _hasMyProgrammazioneRfi) && _progBlinkOn,
      'emp_programmazione_formazioni' =>
        _hasMyProgrammazione && _progBlinkOn,
      'emp_programmazione_formazioni_rfi' =>
        _hasMyProgrammazioneRfi && _progBlinkOn,
      _ => false,
    };
    final visitaAlert =
        key == 'emp_visita_medica' && _hasVisitaMedica && _progBlinkOn;
    final bachecaAlert =
        key == 'emp_bacheca' && _hasBachecaUnread && _progBlinkOn;
    return formazioneAlert || visitaAlert || bachecaAlert;
  }

  Color _futuristicAccentForKey(String key, {bool alert = false}) {
    final style = _activeStyles[key];
    if (style?.iconColor != null) return style!.iconColor!;
    if (alert) return CronosFuturisticTheme.neonRed;
    if (_folderByLauncherKey(key) != null) {
      return CronosFuturisticTheme.neonGold;
    }
    switch (key) {
      case 'emp_richiedi_treno':
      case 'emp_richiedi_aereo':
      case 'emp_treni':
      case 'emp_aerei':
        return CronosFuturisticTheme.neonGreen;
      case 'emp_tesserino':
        return CronosFuturisticTheme.neonRed;
      case 'emp_i_miei_dati':
        return CronosFuturisticTheme.neonTeal;
      case 'emp_notifiche':
        return CronosFuturisticTheme.neonGold;
      case 'emp_formazione':
      case 'emp_formazione_scadenze':
      case 'emp_formazione_rfi_scadenze':
        return CronosFuturisticTheme.neonPurple;
      case 'emp_visita_medica':
        return CronosFuturisticTheme.neonTeal;
      default:
        return CronosFuturisticTheme.neonCyan;
    }
  }

  Widget? _buildFuturisticHomeTile(
    String key, {
    bool reorderPreview = false,
  }) {
    final handler = _onPressedForKey(key);
    if (handler == null) return null;

    final defaultIcon = _iconForHomeKey(key);
    final defaultLabel = _labelForHomeKey(key);
    final style = _activeStyles[key];
    final alert = _isAlertKey(key);
    final accent = _futuristicAccentForKey(key, alert: alert);

    Widget card = NeonCard(
      title: style?.effectiveLabel(defaultLabel) ?? defaultLabel,
      icon: style?.effectiveIcon(defaultIcon) ?? defaultIcon,
      color: accent,
      tileStyle: style,
      onTap: _busy || reorderPreview ? null : handler,
    );

    if (_homeReorderMode && _canEditHomeLayout) {
      card = Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          card,
          if (reorderPreview)
            const Positioned(
              top: 8,
              left: 8,
              child: Icon(Icons.drag_indicator, color: CronosFuturisticTheme.neonCyan),
            ),
          if (_canEditHomeLayout)
            Positioned(
              top: 4,
              right: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FuturisticHubChip(
                    child: CronosHubTileStyleButton(
                      onPressed: () => _editButtonStyle(key),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FuturisticHubChip(
                    child: CronosHubMoveToFolderButton(
                      onPressed: () => _moveKeyToFolder(key),
                    ),
                  ),
                  if (AppUiCustomHub.isLauncherKey(key)) ...[
                    const SizedBox(height: 4),
                    FuturisticHubChip(
                      child: CronosHubDeleteTileButton(
                        onPressed: () => _deleteFolderTile(key),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    } else if (_canEditHomeLayout && !_homeReorderMode) {
      card = CronosHoldToReorderDetector(
        enabled: true,
        onHoldComplete: _enterHomeReorderMode,
        child: card,
      );
    }

    return card;
  }

  Widget _buildFuturisticHomeGrid(List<String> keys, {bool reorder = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = hubResponsiveCrossAxisCount(
          width: constraints.maxWidth,
          maxCellWidth: 168,
          isMobileLayout: _isMobile,
        );
        return CronosAdaptiveHubGrid(
          crossAxisCount: cross,
          childAspectRatio: HubTileGridConfig.cellAspectRatio,
          itemCount: keys.length,
          scaleForIndex: (i) => _activeStyles[keys[i]]?.sizeScale ?? 1.0,
          reorderMode: reorder,
          onReorder: reorder
              ? (oldIndex, newIndex) {
                  setState(() {
                    final next = List<String>.from(_homeReorderDraft);
                    if (newIndex > oldIndex) newIndex--;
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);
                    _homeReorderDraft = next;
                  });
                }
              : null,
          itemBuilder: (context, index) {
            final key = keys[index];
            return _buildFuturisticHomeTile(
                  key,
                  reorderPreview: reorder,
                ) ??
                const SizedBox.shrink();
          },
        );
      },
    );
  }

  /// Pulsante pillola glass: forma fissa; colori, icona e carattere da [HubTileStyle].
  Widget _styledPillButton({
    required String layoutKey,
    required IconData defaultIcon,
    required String defaultLabel,
    required VoidCallback? onPressed,
    bool primary = false,
    Color? alertHighlight,
    BorderSide? alertSide,
    bool alertBold = false,
  }) {
    final style = _activeStyles[layoutKey];
    final theme = Theme.of(context);
    final scale = style?.sizeScale ?? 1.0;
    final icon = style?.effectiveIcon(defaultIcon) ?? defaultIcon;
    final label = style?.effectiveLabel(defaultLabel) ?? defaultLabel;
    final accent = style?.iconColor ??
        PremiumGlassHubTheme.defaultAccentForKey(layoutKey) ??
        theme.colorScheme.primary;
    final fill = PremiumGlassHubTheme.resolveFill(
      styleBg: style?.backgroundColor,
      layoutKey: layoutKey,
      alert: alertHighlight != null,
      appDark: PremiumGlassHubTheme.appIsDark(context),
    );
    final dark = PremiumGlassHubTheme.isDarkFill(fill);

    final defaultFg = dark ? Colors.white : const Color(0xFF2F6FED);
    final fg = style?.textColor ??
        (alertHighlight != null && style?.textColor == null
            ? alertHighlight
            : defaultFg);
    final ic = style?.iconColor ??
        (alertHighlight != null && style?.iconColor == null
            ? alertHighlight
            : (dark ? Colors.white : accent));

    final baseText = theme.textTheme.labelLarge ?? const TextStyle();
    final textStyle = style?.titleTextStyle(
          base: baseText,
          color: fg,
          fontWeight: alertBold ? FontWeight.w700 : FontWeight.w600,
        ) ??
        baseText.copyWith(
          color: fg,
          fontWeight: alertBold ? FontWeight.w700 : FontWeight.w600,
        );

    final padding = EdgeInsets.symmetric(
      horizontal: 14 * scale,
      vertical: 12 * scale,
    );

    return PremiumGlassPillShell(
      background: fill,
      accent: accent,
      onPressed: onPressed,
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ic, size: 20 * scale),
            SizedBox(width: 8 * scale),
            Text(label, style: textStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeLayoutToolbar() {
    if (!_canEditHomeLayout || _loadingHomeLayout) {
      return const SizedBox.shrink();
    }
    final gestopro = _isGestoproHomeUi(context);
    if (!_homeReorderMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _createHomeFolder,
                style: gestopro
                    ? null
                    : TextButton.styleFrom(
                        foregroundColor:
                            PremiumGlassHubTheme.accentLink(context),
                        visualDensity: VisualDensity.compact,
                      ),
                icon: Icon(
                  Icons.create_new_folder_outlined,
                  size: 20,
                  color: gestopro
                      ? CronosFuturisticTheme.neonCyan
                      : PremiumGlassHubTheme.accentLink(context),
                ),
                label: Text(
                  'Nuova cartella',
                  style: gestopro
                      ? const TextStyle(color: CronosFuturisticTheme.neonCyan)
                      : TextStyle(
                          color: PremiumGlassHubTheme.accentLink(context),
                          fontWeight: FontWeight.w600,
                        ),
                ),
              ),
              TextButton.icon(
                onPressed: _enterHomeReorderMode,
                style: gestopro
                    ? null
                    : TextButton.styleFrom(
                        foregroundColor:
                            PremiumGlassHubTheme.accentLink(context),
                        visualDensity: VisualDensity.compact,
                      ),
                icon: Icon(
                  Icons.reorder,
                  size: 20,
                  color: gestopro
                      ? CronosFuturisticTheme.neonCyan
                      : PremiumGlassHubTheme.accentLink(context),
                ),
                label: Text(
                  'Riordina',
                  style: gestopro
                      ? const TextStyle(color: CronosFuturisticTheme.neonCyan)
                      : TextStyle(
                          color: PremiumGlassHubTheme.accentLink(context),
                          fontWeight: FontWeight.w600,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          TextButton(
            onPressed: _cancelHomeReorderMode,
            child: Text(
              'Annulla',
              style: gestopro
                  ? const TextStyle(color: CronosFuturisticTheme.textMuted)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saveHomeLayout,
            style: gestopro
                ? FilledButton.styleFrom(
                    backgroundColor: CronosFuturisticTheme.neonCyan,
                    foregroundColor: const Color(0xFF041018),
                  )
                : null,
            child: Text(_canEditHomeLayout ? 'Salva per tutti' : 'Salva'),
          ),
        ],
      ),
    );
  }

  Widget? _buildDesktopActionButton(String key) {
    final primary = DipendenteHomeButtonKeys.isPrimaryStyle(key);
    final icon = _iconForHomeKey(key);
    final label = _labelForHomeKey(key);
    final handler = _onPressedForKey(key);
    if (handler == null) return null;
    final onPressed = _busy ? null : handler;

    final progAlert = (key == 'emp_programmazione_formazioni' ||
            key == 'emp_formazione') &&
        _hasMyProgrammazione &&
        _progBlinkOn;
    final rfiAlert = (key == 'emp_programmazione_formazioni_rfi' ||
            key == 'emp_formazione') &&
        _hasMyProgrammazioneRfi &&
        _progBlinkOn;
    final visitaAlert =
        key == 'emp_visita_medica' && _hasVisitaMedica && _progBlinkOn;
    final bachecaAlert =
        key == 'emp_bacheca' && _hasBachecaUnread && _progBlinkOn;
    final alert = progAlert || rfiAlert || visitaAlert || bachecaAlert;

    return _styledPillButton(
      layoutKey: key,
      defaultIcon: icon,
      defaultLabel: label,
      onPressed: onPressed,
      primary: primary,
      alertHighlight: alert ? Colors.red : null,
      alertSide: alert ? const BorderSide(color: Colors.red, width: 1.5) : null,
      alertBold: (key == 'emp_formazione' &&
              (_hasMyProgrammazione || _hasMyProgrammazioneRfi)) ||
          (key == 'emp_programmazione_formazioni' &&
              _hasMyProgrammazione) ||
          (key == 'emp_programmazione_formazioni_rfi' &&
              _hasMyProgrammazioneRfi) ||
          (key == 'emp_visita_medica' && _hasVisitaMedica) ||
          (key == 'emp_bacheca' && _hasBachecaUnread),
    );
  }

  VoidCallback? _onPressedForKey(String key) {
    final folder = _folderByLauncherKey(key);
    if (folder != null) {
      return () => _openFolder(folder);
    }
    switch (key) {
      case 'emp_richiedi_treno':
      case 'emp_treni':
        return _openTreniChooser;
      case 'emp_richiedi_aereo':
      case 'emp_aerei':
        return _openAereiChooser;
      case 'emp_richiedi_ferie_permessi':
        if (!ModuleVisibilityFlags.showEmpLeMieFeriePermessi) return null;
        return _tapRichiediFeriePermessi;
      case 'emp_notifiche':
        return _openNotifications;
      case 'emp_pernottamenti':
        return _openMyPernotti;
      case 'emp_tesserino':
        return _openIlMioTesserino;
      case 'emp_i_miei_dati':
        return _openIMieiDati;
      case 'emp_documenti_firma':
        return _openDocumentiFirma;
      case 'emp_bacheca':
        return _openBacheca;
      case 'emp_video_istruzioni':
        return _openVideoIstruzioni;
      case 'emp_formazione':
        return _openFormazioneChooser;
      case 'emp_formazione_scadenze':
        return _openFormazioni;
      case 'emp_formazione_rfi_scadenze':
        return _openFormazioniRfi;
      case 'emp_programmazione_formazioni':
        return _openProgrammazioneFormazioni;
      case 'emp_programmazione_formazioni_rfi':
        return _openProgrammazioneFormazioniRfi;
      case 'emp_visita_medica':
        return _openVisitaMedica;
      case 'emp_sicurezza':
        return _openSicurezzaChooser;
      case 'emp_dpi':
        return _tapDpi;
      case 'emp_misure_vestiario':
        return _openMySizesDialog;
      case 'emp_mezzi':
        return _openMezziChooser;
      case 'emp_mdo_ferroviari':
        return _openMdoFerroviari;
      case 'emp_mezzi_stradali':
        return _openMezziStradali;
      case 'emp_rifornimento':
        return _openRifornimentoChooser;
      case 'emp_registro_rcc':
        return _openRegistroRccCarburante;
      case 'emp_rifornimento_mdo':
        return _openRifornimentoMdo;
      case 'emp_multicard':
        return _openMulticard;
      case 'emp_attrezzature':
        return _openAttrezzature;
      case 'emp_mappa_gps':
      case 'mdo_mappa_gps':
        return _openMappaGps;
      case 'emp_incidente_sicurezza':
        return _openIncidenteSicurezza;
      case 'emp_buoni_pasto':
        return _openBuoniPastoChooser;
      case 'emp_buoni_pasto_scan':
        return _openBuoniPastoScan;
      case 'emp_buoni_pasto_riepilogo':
        return _openBuoniPastoRiepilogo;
      case 'emp_viaggi_mezzi':
        return _openViaggiMezziChooser;
      case 'emp_viaggi_mezzi_scan':
        return _openViaggiMezziScan;
      case 'emp_viaggi_mezzi_riepilogo':
        return _openViaggiMezziRiepilogo;
      case 'emp_viaggi_mezzi_assegnatario':
        return _openViaggiMezziAssegnatario;
      default:
        return null;
    }
  }

  Widget _buildHomeReorderRow(String key) {
    final theme = Theme.of(context);
    final button = _buildDesktopActionButton(key);
    if (button == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(Icons.drag_handle, color: theme.colorScheme.outline),
        ),
        if (_canEditHomeLayout)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _homeReorderActions(key),
          ),
        if (_canEditHomeLayout)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: CronosHubTileStyleButton(
              onPressed: () => _editButtonStyle(key),
            ),
          ),
        Flexible(child: AbsorbPointer(child: button)),
      ],
    );
  }

  Widget _buildOrderedDesktopActions() {
    if (_loadingHomeLayout) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final keys = _homeReorderMode ? _homeReorderDraft : _homeButtonKeys;
    final gestopro = _isGestoproHomeUi(context);
    if (gestopro) {
      if (_homeReorderMode) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: CronosFuturisticTheme.panelBg.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: CronosFuturisticTheme.neonGold.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'Trascina i moduli per l\'ordine; tavolozza per colori e testo; '
                'icona cartella per spostare un pulsante in una sotto-cartella. Poi «Salva».',
                style: TextStyle(
                  color: CronosFuturisticTheme.neonGold,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFuturisticHomeGrid(keys, reorder: true),
          ],
        );
      }
      return _buildFuturisticHomeGrid(keys);
    }
    if (_homeReorderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.amber.shade100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                'Trascina per l\'ordine; icona tavolozza per colori e testo; '
                'icona cartella per spostare un pulsante in una sotto-cartella. '
                'Poi «Salva per tutti».',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: keys.length,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final next = List<String>.from(_homeReorderDraft);
                if (newIndex > oldIndex) newIndex--;
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                _homeReorderDraft = next;
              });
            },
            itemBuilder: (context, index) {
              final key = keys[index];
              return ReorderableDragStartListener(
                key: ValueKey<String>(key),
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildHomeReorderRow(key),
                ),
              );
            },
          ),
        ],
      );
    }
    final children = <Widget>[];
    for (final key in keys) {
      final button = _buildDesktopActionButton(key);
      if (button == null) continue;
      Widget child = button;
      if (_canEditHomeLayout) {
        child = CronosHoldToReorderDetector(
          enabled: true,
          onHoldComplete: _enterHomeReorderMode,
          child: child,
        );
      }
      children.add(child);
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: children,
    );
  }

  Widget? _buildMobileActionForKey(String key) {
    switch (key) {
      case 'emp_richiedi_treno':
      case 'emp_treni':
        return _mobileTile(
          layoutKey: 'emp_treni',
          icon: Icons.train_outlined,
          title: 'Treni',
          subtitle: 'Nuova richiesta o elenco',
          primary: true,
          onTap: _busy ? null : _openTreniChooser,
        );
      case 'emp_richiedi_aereo':
      case 'emp_aerei':
        return _mobileTile(
          layoutKey: 'emp_aerei',
          icon: Icons.flight_takeoff_outlined,
          title: 'Aerei',
          subtitle: 'Nuova richiesta o elenco',
          primary: true,
          onTap: _busy ? null : _openAereiChooser,
        );
      case 'emp_richiedi_ferie_permessi':
        if (!ModuleVisibilityFlags.showEmpLeMieFeriePermessi) return null;
        return _mobileTile(
          layoutKey: key,
          icon: Icons.event_busy_outlined,
          title: 'Le mie ferie / permessi',
          subtitle: 'Richieste inserite dal DT — stato e PDF',
          primary: true,
          openDestination: RichiestaFeriePermessiMobilePage(
            userId: widget.userId,
            fullName: widget.fullName,
          ),
        );
      case 'emp_notifiche':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.notifications_outlined,
          title: 'Notifiche',
          subtitle: 'Tutte le notifiche',
          openDestination: NotificationsMobilePage(userId: widget.userId),
        );
      case 'emp_pernottamenti':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.bed_outlined,
          title: 'Pernottamenti',
          subtitle: 'Prenota o consulta soggiorni',
          onTap: _busy ? null : _openMyPernotti,
        );
      case 'emp_tesserino':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.badge_outlined,
          title: 'Il mio tesserino',
          subtitle: 'Visualizza tesserino e foto',
          primary: true,
          openDestination: DipendenteTesserinoMobilePage(userId: widget.userId),
          onOpenClosed: reloadPersonaleProfile,
        );
      case 'emp_i_miei_dati':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.phone_android_outlined,
          title: 'I miei dati',
          subtitle: 'Sostituisci telefono e data di nascita',
          primary: true,
          openDestination: const MyProfilePage(expandEditOnOpen: true),
        );
      case 'emp_documenti_firma':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.fingerprint,
          title: 'Firma digitale',
          subtitle: 'Firma OTP e download PDF',
          primary: true,
          openDestination: DipendenteDocumentiFirmaMobilePage(
            userId: widget.userId,
            fullName: widget.fullName,
          ),
        );
      case 'emp_bacheca':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.campaign_outlined,
          title: 'Bacheca',
          subtitle: 'Comunicazioni aziendali',
          openDestination: const AdminBachecaMobilePage(readOnly: true),
          onOpenClosed: _loadBachecaUnreadAlert,
          alertBlinkBacheca: true,
        );
      case 'emp_video_istruzioni':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.ondemand_video_outlined,
          title: 'Video istruttivi',
          subtitle: 'Tutorial e guide in app',
          onTap: _busy ? null : _openVideoIstruzioni,
        );
      case 'emp_formazione':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.school_outlined,
          title: 'Formazione',
          subtitle: 'Scadenze e programmazioni',
          onTap: _busy ? null : _openFormazioneChooser,
          alertBlink: true,
          alertBlinkRfi: true,
        );
      case 'emp_formazione_scadenze':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.school_outlined,
          title: 'Formazione e Scadenze',
          subtitle: 'Corsi fatti, ultima data e scadenze',
          openDestination: EmployeeFormazioneScadenzeMobilePage(
            userId: widget.userId,
            fullName: widget.fullName,
          ),
        );
      case 'emp_formazione_rfi_scadenze':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.account_tree_outlined,
          title: 'Formazione RFI',
          subtitle: 'Corsi RFI e relative scadenze',
          openDestination: EmployeeFormazioneRfiScadenzeMobilePage(
            userId: widget.userId,
            fullName: widget.fullName,
          ),
        );
      case 'emp_programmazione_formazioni':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.event_note_outlined,
          title: 'Programmazione Formazioni',
          subtitle: 'Corsi D.Lgs. 81/08 programmati a tuo nome',
          openDestination: DtProgrammazioneFormazioniMobilePage(
            employeeOnly: true,
            employeeFullName: widget.fullName,
          ),
          onOpenClosed: _loadProgrammazioneAlert,
          alertBlink: true,
        );
      case 'emp_programmazione_formazioni_rfi':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.event_available_outlined,
          title: 'Programmazioni corsi RFI',
          subtitle: 'Corsi RFI programmati a tuo nome (dal/al)',
          openDestination: DtProgrammazioneFormazioniRfiMobilePage(
            employeeOnly: true,
            employeeFullName: widget.fullName,
          ),
          onOpenClosed: _loadProgrammazioneAlert,
          alertBlinkRfi: true,
        );
      case 'emp_visita_medica':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.medical_services_outlined,
          title: 'Visita medica',
          subtitle: 'Visita normale o RFI',
          onTap: _busy ? null : _openVisitaMedica,
          alertBlinkVisita: true,
        );
      case 'emp_sicurezza':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.health_and_safety_outlined,
          title: 'Sicurezza',
          subtitle: 'Dotazioni DPI e misure vestiario',
          onTap: _busy ? null : _openSicurezzaChooser,
        );
      case 'emp_dpi':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.shield_outlined,
          title: 'Le mie dotazioni DPI',
          subtitle:
              'Dispositivi di protezione assegnati a te (elmetto, imbracatura, cordini…)',
          onTap: _busy ? null : _tapDpi,
          openDestination: _myPersonaleUuid != null &&
                  _myPersonaleUuid!.trim().isNotEmpty
              ? DpiMobilePage(
                  fullName: widget.fullName,
                  personaleUuid: _myPersonaleUuid!,
                )
              : null,
        );
      case 'emp_misure_vestiario':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.straighten,
          title: 'Misure vestiario',
          subtitle: 'Taglie T‑shirt, pantaloni, scarpe…',
          onTap: _busy ? null : _openMySizesDialog,
        );
      case 'emp_mezzi':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.commute_outlined,
          title: 'Mezzi',
          subtitle: 'MDO, mezzi stradali e officine',
          onTap: _busy ? null : _openMezziChooser,
        );
      case 'emp_mdo_ferroviari':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.train_outlined,
          title: 'MDO Ferroviari',
          subtitle: 'Check dotazioni DPI, posizione GPS e commessa',
          openDestination: const AdminLogisticaMdoDipendenteMobilePage(),
        );
      case 'emp_mezzi_stradali':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.local_shipping_outlined,
          title: 'Mezzi Stradali',
          subtitle: 'Il tuo mezzo, PDF assegnazione e gomme',
          onTap: _busy ? null : _openMezziStradali,
        );
      case 'emp_rifornimento':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.local_gas_station_outlined,
          title: 'Rifornimento',
          subtitle: 'Mezzi stradali, MDO e Multicard',
          onTap: _busy ? null : _openRifornimentoChooser,
        );
      case 'emp_registro_rcc':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.local_gas_station_outlined,
          title: 'Registro carburante RCC',
          subtitle: 'Mod. RCC — registro rifornimenti',
          openDestination: const LogisticaRccCarburanteMobilePage(
            dipendenteMode: true,
          ),
        );
      case 'emp_rifornimento_mdo':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.local_gas_station_outlined,
          title: 'Rifornimento MDO',
          subtitle: 'Giustificativo carburante',
          openDestination: const LogisticaRccMdoCarburanteMobilePage(
            dipendenteMode: true,
          ),
        );
      case 'emp_multicard':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.credit_card_outlined,
          title: 'Multicard',
          subtitle: 'Carte carburante associate',
          openDestination: const AdminLogisticaMulticardMobilePage(
            dipendenteMode: true,
          ),
        );
      case 'emp_attrezzature':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.handyman_outlined,
          title: 'Attrezzature',
          subtitle: 'Le attrezzature assegnate a te',
          openDestination: AdminLogisticaAttrezzatureMobilePage(
            dipendenteMode: true,
            fullName: widget.fullName,
          ),
        );
      case 'emp_buoni_pasto':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.restaurant_outlined,
          title: 'Buoni Pasto',
          subtitle: 'Scansione e storico registrazioni',
          onTap: _busy ? null : _openBuoniPastoChooser,
        );
      case 'emp_buoni_pasto_scan':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.qr_code_scanner_outlined,
          title: 'Scansiona buono pasto',
          subtitle: 'Registra pranzo o cena al ristorante',
          primary: true,
          openDestination: DipendenteBuonoPastoScanPage(userId: widget.userId),
        );
      case 'emp_buoni_pasto_riepilogo':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.restaurant_outlined,
          title: 'I miei buoni pasto',
          subtitle: 'Storico registrazioni del mese',
          openDestination: DipendenteBuoniPastoRiepilogoPage(
            userId: widget.userId,
          ),
        );
      case 'emp_viaggi_mezzi':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.route_outlined,
          title: 'Viaggi mezzi',
          subtitle: 'Scansione, i miei viaggi e mezzi assegnati',
          onTap: _busy ? null : _openViaggiMezziChooser,
        );
      case 'emp_viaggi_mezzi_scan':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.qr_code_scanner,
          title: 'Scansiona viaggio mezzo',
          subtitle: 'Apertura e chiusura viaggio con km e GPS',
          primary: true,
          openDestination: DipendenteViaggioMezzoScanPage(userId: widget.userId),
        );
      case 'emp_viaggi_mezzi_riepilogo':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.route_outlined,
          title: 'I miei viaggi mezzo',
          subtitle: 'Storico mensile dei mezzi guidati',
          openDestination: const ViaggiMezziReportPage(
            mode: ViaggiMezziReportMode.conducente,
          ),
        );
      case 'emp_viaggi_mezzi_assegnatario':
        return _mobileTile(
          layoutKey: key,
          icon: Icons.local_shipping_outlined,
          title: 'Viaggi sui miei mezzi',
          subtitle: 'Chi ha guidato i mezzi a te assegnati',
          openDestination: const ViaggiMezziReportPage(
            mode: ViaggiMezziReportMode.assegnatario,
          ),
        );
      default:
        final folder = _folderByLauncherKey(key);
        if (folder == null) return null;
        return _mobileTile(
          layoutKey: key,
          icon: Icons.folder_outlined,
          title: folder.label,
          subtitle: 'Apri cartella',
          onTap: _busy ? null : () => _openFolder(folder),
        );
    }
  }

  Widget _buildOrderedMobileActions() {
    if (_loadingHomeLayout) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final keys = _homeReorderMode ? _homeReorderDraft : _homeButtonKeys;
    final gestopro = _isGestoproHomeUi(context);
    if (gestopro) {
      if (_homeReorderMode) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: CronosFuturisticTheme.panelBg.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: CronosFuturisticTheme.neonGold.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'Trascina i moduli per l\'ordine; tavolozza per colori e testo; '
                'icona cartella per spostare un pulsante in una sotto-cartella. Poi «Salva».',
                style: TextStyle(
                  color: CronosFuturisticTheme.neonGold,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFuturisticHomeGrid(keys, reorder: true),
          ],
        );
      }
      return _buildFuturisticHomeGrid(keys);
    }
    if (_homeReorderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.amber.shade100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                'Trascina per l\'ordine; icona tavolozza per colori e testo; '
                'icona cartella per spostare un pulsante in una sotto-cartella. '
                'Poi «Salva per tutti».',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: keys.length,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final next = List<String>.from(_homeReorderDraft);
                if (newIndex > oldIndex) newIndex--;
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                _homeReorderDraft = next;
              });
            },
            itemBuilder: (context, index) {
              final key = keys[index];
              final tile = _buildMobileActionForKey(key);
              if (tile == null) {
                return SizedBox(key: ValueKey<String>(key));
              }
              return ReorderableDragStartListener(
                key: ValueKey<String>(key),
                index: index,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20, right: 4),
                      child: Icon(
                        Icons.drag_handle,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (_canEditHomeLayout)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, right: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CronosHubTileStyleButton(
                              onPressed: () => _editButtonStyle(key),
                            ),
                            _homeReorderActions(key),
                          ],
                        ),
                      ),
                    Expanded(
                      child: AbsorbPointer(child: tile),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    }
    final tiles = <Widget>[];
    for (final key in keys) {
      final tile = _buildMobileActionForKey(key);
      if (tile == null) continue;
      Widget child = tile;
      if (_canEditHomeLayout) {
        child = CronosHoldToReorderDetector(
          enabled: true,
          onHoldComplete: _enterHomeReorderMode,
          child: child,
        );
      }
      tiles.add(child);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tiles,
    );
  }

  Future<void> _loadVisitaMedicaAlert() async {
    try {
      final has = await VisiteMedicheService.hasUpcomingForCurrentUser(
        employeeFullName: widget.fullName,
      );
      if (!mounted) return;
      setState(() => _hasVisitaMedica = has);
    } catch (_) {}
  }

  Future<void> _loadBachecaUnreadAlert() async {
    try {
      final has = await BachecaService.hasUnread();
      if (!mounted) return;
      setState(() => _hasBachecaUnread = has);
    } catch (_) {}
  }

  Future<void> _openVisitaMedica() async {
    if (_busy) return;
    await showDipendenteVisiteMedicheChooser(
      context,
      employeeFullName: widget.fullName,
      standardPage: () => useMobileUi(context)
          ? VisiteMedicheMobilePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            )
          : VisiteMedichePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            ),
      rfiPage: () => useMobileUi(context)
          ? VisiteMedicheMobilePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
              rfiMode: true,
            )
          : VisiteMedichePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
              rfiMode: true,
            ),
    );
    await _loadVisitaMedicaAlert();
  }

  Future<void> _openProgrammazioneFormazioni() async {
    if (_busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? DtProgrammazioneFormazioniMobilePage(
                employeeOnly: true,
                employeeFullName: widget.fullName,
              )
            : DtProgrammazioneFormazioniPage(
                employeeOnly: true,
                employeeFullName: widget.fullName,
              ),
      ),
    );
    await _loadProgrammazioneAlert();
  }

  Future<void> _openProgrammazioneFormazioniRfi() async {
    if (_busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? DtProgrammazioneFormazioniRfiMobilePage(
                employeeOnly: true,
                employeeFullName: widget.fullName,
              )
            : DtProgrammazioneFormazioniRfiPage(
                employeeOnly: true,
                employeeFullName: widget.fullName,
              ),
      ),
    );
    await _loadProgrammazioneAlert();
  }

  void _applyPersonaleRow(Map<String, dynamic> row) {
    final uuid = (row['id_uuid'] ?? '').toString().trim();
    if (uuid.isEmpty) return;
    setState(() {
      _myPersonaleUuid = uuid;
      _fotoTesserinoPath = (row['foto_tesserino_path'] ?? '').toString().trim();
    });
  }

  String get _profileInitial {
    if (widget.fullName.isNotEmpty) return widget.fullName[0];
    if (widget.username.isNotEmpty) return widget.username[0];
    return '?';
  }

  Widget _buildProfileAvatar({double radius = 20}) {
    return InkWell(
      onTap: _busy ? null : _openIlMioTesserino,
      customBorder: const CircleBorder(),
      child: _EmployeeProfileAvatar(
        radius: radius,
        initial: _profileInitial,
        fotoPath: _fotoTesserinoPath,
      ),
    );
  }

  /// Ricarica anagrafica (es. dopo aggiornamento foto tesserino).
  Future<void> reloadPersonaleProfile() => _resolveMyPersonaleUuid();

  // =========================================================================================
  // 1) Ricava il mio personale.id_uuid (auth_id -> users.id/id_uuid -> personale.user_id)
  // =========================================================================================
  Future<void> _resolveMyPersonaleUuid() async {
    try {
      final row = await resolveMyPersonaleRow();
      if (row != null) _applyPersonaleRow(row);
    } catch (_) {
      // non blocchiamo
    }
  }

  // =========================================================================================
  // 2) Estrattori dinamici
  // =========================================================================================

  // ignore: unused_element
  String _getPersonaleId(Map<String, dynamic> r) {
    for (final k in const [
      'personale_id_uuid',
      'personale_id_text',
      'personale_id',
    ]) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getCommessaId(Map<String, dynamic> r) {
    for (final k in const ['commessa_id_uuid', 'commessa_id']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getStrutturaId(Map<String, dynamic> r) {
    for (final k in const [
      'struttura_id_uuid',
      'structure_id_uuid',
      'struttura_id',
      'structure_id',
    ]) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getDtKey(Map<String, dynamic> r) {
    for (final k in const ['dt_user_uuid', 'dt_uuid', 'dt_id']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getMapLink(Map<String, dynamic> r) {
    for (final k in const ['map_link_txt', 'maps_link_txt', 'map_link']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // =========================================================================================
  // 3) Dizionari (commesse / strutture / utenti)
  // =========================================================================================

  String _orEq(String col, Iterable<String> values) =>
      values.map((e) => '$col.eq.$e').join(',');

  Future<Map<String, String>> _loadCommesseLabels(Set<String> ids) async {
    final out = <String, String>{};
    final wanted = ids.where((e) => e.trim().isNotEmpty).toSet();
    if (wanted.isEmpty) return out;
    final orExpr = _orEq('id_uuid', wanted);
    final cr = await SupabaseService.client
        .from('commesse')
        .select('id_uuid, nome')
        .or(orExpr);
    for (final c in (cr as List)) {
      final idu = (c['id_uuid'] ?? '').toString();
      final nm = (c['nome'] ?? '').toString();
      if (idu.isNotEmpty) out[idu] = nm;
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _loadStrutture(
      Set<String> ids) async {
    final out = <String, Map<String, dynamic>>{};
    final wanted = ids.where((e) => e.trim().isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    try {
      final orExpr = _orEq('id_uuid', wanted);
      final sr = await SupabaseService.client
          .from('structures')
          .select('id_uuid, name, lat, lng')
          .or(orExpr);
      for (final s in (sr as List)) {
        final idu = (s['id_uuid'] ?? '').toString();
        out[idu] = {
          'name': (s['name'] ?? '').toString(),
          'lat': (s['lat'] is num) ? (s['lat'] as num).toDouble() : null,
          'lng': (s['lng'] is num) ? (s['lng'] as num).toDouble() : null,
        };
      }
      return out;
    } catch (_) {}

    try {
      final orExpr = _orEq('id_uuid', wanted);
      final sr = await SupabaseService.client
          .from('structures')
          .select('id_uuid, name, latitudine, longitudine')
          .or(orExpr);
      for (final s in (sr as List)) {
        final idu = (s['id_uuid'] ?? '').toString();
        out[idu] = {
          'name': (s['name'] ?? '').toString(),
          'lat': (s['latitudine'] is num)
              ? (s['latitudine'] as num).toDouble()
              : null,
          'lng': (s['longitudine'] is num)
              ? (s['longitudine'] as num).toDouble()
              : null,
        };
      }
      return out;
    } catch (_) {}

    final orExpr = _orEq('id_uuid', wanted);
    final sr = await SupabaseService.client
        .from('structures')
        .select('id_uuid, name')
        .or(orExpr);
    for (final s in (sr as List)) {
      final idu = (s['id_uuid'] ?? '').toString();
      out[idu] = {
        'name': (s['name'] ?? '').toString(),
        'lat': null,
        'lng': null
      };
    }
    return out;
  }

  Future<Map<String, String>> _loadRequesterNames(Set<String> keys) async {
    final out = <String, String>{};
    final wanted = keys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    Future<void> doMerge(String col) async {
      final orExpr = _orEq(col, wanted);
      try {
        final ur = await SupabaseService.client
            .from('users')
            .select('id, id_uuid, auth_id, full_name, username')
            .or(orExpr);
        for (final u in (ur as List)) {
          final id = (u['id'] ?? '').toString();
          final uuid = (u['id_uuid'] ?? '').toString();
          final aid = (u['auth_id'] ?? '').toString();
          final label = ((u['full_name'] ?? '') as String).isNotEmpty
              ? (u['full_name'] as String)
              : (u['username'] ?? '').toString();
          if (id.isNotEmpty) out[id] = label;
          if (uuid.isNotEmpty) out[uuid] = label;
          if (aid.isNotEmpty) out[aid] = label;
        }
      } catch (_) {}
    }

    await doMerge('id_uuid');
    await doMerge('auth_id');
    await doMerge('id');
    return out;
  }

  // =========================================================================================
  // 4) AEREI/TRANI/PERNOTTI – con filtro server‑side (se possibile) + fallback
  // =========================================================================================

  Future<void> _openTreniChooser() async {
    if (_busy) return;
    await showDipendenteTreniChooser(
      context,
      nuovaPage: () => useMobileUi(context)
          ? RichiestaTrenoMobilePage(
              userId: widget.userId,
              fullName: widget.fullName,
            )
          : RichiestaTrenoPage(
              userId: widget.userId,
              fullName: widget.fullName,
            ),
      elenco: _openMyTreni,
    );
  }

  Future<void> _openAereiChooser() async {
    if (_busy) return;
    await showDipendenteAereiChooser(
      context,
      nuovaPage: () => useMobileUi(context)
          ? RichiestaAereoMobilePage(
              userId: widget.userId,
              fullName: widget.fullName,
            )
          : RichiestaAereoPage(
              userId: widget.userId,
              fullName: widget.fullName,
            ),
      elenco: _openMyAerei,
    );
  }

  Future<void> _openMyAerei() async {
    if (_busy) return;
    setState(() => _busy = true);
    List<Map<String, dynamic>> rows = [];
    Map<String, String> commesse = {};
    Map<String, String> dtMap = {};
    try {
      final pid = await _ensurePid();
      if (pid == null) return;

      // Tentativo 1: personale_id
      try {
        final rs = await SupabaseService.client
            .from('bookings_aereo')
            .select()
            .eq('personale_id', pid)
            .order('data', ascending: false)
            .range(0, 499);
        rows = List<Map<String, dynamic>>.from(rs as List);
      } on PostgrestException catch (e) {
        if (e.code != '42703') rethrow;
      } catch (_) {}

      // Tentativo 2: personale_id_uuid
      if (rows.isEmpty) {
        try {
          final rs = await SupabaseService.client
              .from('bookings_aereo')
              .select()
              .eq('personale_id_uuid', pid)
              .order('data', ascending: false)
              .range(0, 499);
          rows = List<Map<String, dynamic>>.from(rs as List);
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        } catch (_) {}
      }

      // Tentativo 3: personale_id_text
      if (rows.isEmpty) {
        try {
          final rs = await SupabaseService.client
              .from('bookings_aereo')
              .select()
              .eq('personale_id_text', pid)
              .order('data', ascending: false)
              .range(0, 499);
          rows = List<Map<String, dynamic>>.from(rs as List);
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        } catch (_) {}
      }
      // Nessun fallback unfiltered: evita timeout RLS su tutta la tabella.

      final commIds = <String>{};
      final dtIds = <String>{};
      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        dtIds.add(_getDtKey(r));
      }
      commesse = await _loadCommesseLabels(commIds);
      dtMap = await _loadRequesterNames(dtIds);
    } catch (e) {
      _toast('Errore nel caricamento aerei: $e', error: true);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    await _showAdaptiveList(
      title: 'Le mie richieste aerei',
      child: _AereiList(
        rows: rows,
        commesse: commesse,
        dtMap: dtMap,
        buildHeader: _headerWithLogo,
      ),
      desktopDialog: _MieiAereiDialog(
        rows: rows,
        commesse: commesse,
        dtMap: dtMap,
        buildHeader: _headerWithLogo,
      ),
    );
  }

  Future<void> _openMyTreni() async {
    if (_busy) return;
    setState(() => _busy = true);
    List<Map<String, dynamic>> rows = [];
    Map<String, String> commesse = {};
    Map<String, String> dtMap = {};
    try {
      final pid = await _ensurePid();
      if (pid == null) return;

      // Tentativo 1: personale_id_uuid
      try {
        final rs = await SupabaseService.client
            .from('bookings_treno')
            .select()
            .eq('personale_id_uuid', pid)
            .order('data', ascending: false)
            .range(0, 499);
        rows = List<Map<String, dynamic>>.from(rs as List);
      } on PostgrestException catch (e) {
        if (e.code != '42703') rethrow;
      } catch (_) {}

      // Tentativo 2: personale_id
      if (rows.isEmpty) {
        try {
          final rs = await SupabaseService.client
              .from('bookings_treno')
              .select()
              .eq('personale_id', pid)
              .order('data', ascending: false)
              .range(0, 499);
          rows = List<Map<String, dynamic>>.from(rs as List);
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        } catch (_) {}
      }

      // Tentativo 3: personale_id_text
      if (rows.isEmpty) {
        try {
          final rs = await SupabaseService.client
              .from('bookings_treno')
              .select()
              .eq('personale_id_text', pid)
              .order('data', ascending: false)
              .range(0, 499);
          rows = List<Map<String, dynamic>>.from(rs as List);
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        } catch (_) {}
      }
      // Nessun fallback unfiltered: evita timeout RLS su tutta la tabella.

      final commIds = <String>{};
      final dtIds = <String>{};
      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        dtIds.add(_getDtKey(r));
      }
      commesse = await _loadCommesseLabels(commIds);
      dtMap = await _loadRequesterNames(dtIds);
    } catch (e) {
      _toast('Errore nel caricamento treni: $e', error: true);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    await _showAdaptiveList(
      title: 'Le mie richieste treno',
      child: _TreniList(
        rows: rows,
        commesse: commesse,
        dtMap: dtMap,
        buildHeader: _headerWithLogo,
      ),
      desktopDialog: _MieiTreniDialog(
        rows: rows,
        commesse: commesse,
        dtMap: dtMap,
        buildHeader: _headerWithLogo,
      ),
    );
  }

  Future<void> _openMezziChooser() async {
    if (_busy) return;
    await showDipendenteMezziChooser(
      context,
      mdoPage: () => useMobileUi(context)
          ? const AdminLogisticaMdoDipendenteMobilePage()
          : AdminLogisticaMdoFerroviariPage(
              dipendenteMode: true,
              forceMobileLayout: _isMobile,
            ),
      mdoPerCommessaPage: () => useMobileUi(context)
          ? const AdminDislocazioneMdoPerCommessaMobilePage(readOnly: true)
          : AdminDislocazioneMdoPerCommessaPage(
              readOnly: true,
              forceMobileLayout: _isMobile,
            ),
      trasferimentiPage: () => useMobileUi(context)
          ? const AdminDislocazioneMdoPerCommessaMobilePage(
              readOnly: true,
              initialMainTab: 1,
            )
          : AdminDislocazioneMdoPerCommessaPage(
              readOnly: true,
              forceMobileLayout: _isMobile,
              initialMainTab: 1,
            ),
      stradaliMioMezzoPage: () => useMobileUi(context)
          ? const AdminLogisticaMezziDipendenteMobilePage()
          : AdminLogisticaMezziStradaliPage(
              dipendenteMode: true,
              forceMobileLayout: _isMobile,
            ),
      officinePage: () => useMobileUi(context)
          ? const AdminLogisticaOfficineConvenzionateMobilePage(readOnly: true)
          : AdminLogisticaOfficineConvenzionatePage(
              readOnly: true,
              forceMobileLayout: _isMobile,
            ),
    );
  }

  Future<void> _openMdoFerroviari() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => useMobileUi(context)
            ? const AdminLogisticaMdoDipendenteMobilePage()
            : const AdminLogisticaMdoFerroviariPage(dipendenteMode: true),
      ),
    );
  }

  Future<void> _openMezziStradali() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => useMobileUi(context)
            ? const AdminLogisticaMezziDipendenteMobilePage()
            : const AdminLogisticaMezziStradaliPage(dipendenteMode: true),
      ),
    );
  }

  Future<void> _openIlMioTesserino() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? DipendenteTesserinoMobilePage(userId: widget.userId)
            : DipendenteTesserinoPage(userId: widget.userId),
      ),
    );
    await reloadPersonaleProfile();
  }

  Future<void> _openIMieiDati() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const MyProfilePage(expandEditOnOpen: true),
      ),
    );
  }

  Future<void> _openDocumentiFirma() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? DipendenteDocumentiFirmaMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : DipendenteDocumentiFirmaPage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
  }

  Future<void> _openBacheca() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? const AdminBachecaMobilePage(readOnly: true)
            : const AdminBachecaPage(readOnly: true),
      ),
    );
    await _loadBachecaUnreadAlert();
  }

  Future<void> _openVideoIstruzioni() async {
    await VideoGalleryNavigation.open(
      context,
      role: _loggedInRole,
    );
  }

  Future<void> _openRifornimentoChooser() async {
    if (_busy) return;
    await showDipendenteRifornimentoChooser(
      context,
      mancantiPage: () => DipendenteRifornimentiMancantiPage(
        forceMobileLayout: _isMobile,
      ),
      rccPage: () => useMobileUi(context)
          ? const LogisticaRccCarburanteMobilePage(dipendenteMode: true)
          : LogisticaRccCarburantePage(
              dipendenteMode: true,
              forceMobileLayout: _isMobile,
            ),
      mdoPage: () => useMobileUi(context)
          ? const LogisticaRccMdoCarburanteMobilePage(dipendenteMode: true)
          : LogisticaRccMdoCarburantePage(
              dipendenteMode: true,
              forceMobileLayout: _isMobile,
            ),
      multicardPage: () => useMobileUi(context)
          ? const AdminLogisticaMulticardMobilePage(dipendenteMode: true)
          : AdminLogisticaMulticardPage(
              forceMobileLayout: _isMobile,
              dipendenteMode: true,
            ),
    );
  }

  Future<void> _openRegistroRccCarburante() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? const LogisticaRccCarburanteMobilePage(dipendenteMode: true)
            : LogisticaRccCarburantePage(
                dipendenteMode: true,
                forceMobileLayout: _isMobile,
              ),
      ),
    );
  }

  Future<void> _openRifornimentoMdo() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? const LogisticaRccMdoCarburanteMobilePage(dipendenteMode: true)
            : LogisticaRccMdoCarburantePage(
                dipendenteMode: true,
                forceMobileLayout: _isMobile,
              ),
      ),
    );
  }

  Future<void> _openMulticard() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? const AdminLogisticaMulticardMobilePage(dipendenteMode: true)
            : AdminLogisticaMulticardPage(
                forceMobileLayout: _isMobile,
                dipendenteMode: true,
              ),
      ),
    );
  }

  Future<void> _openAttrezzature() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? AdminLogisticaAttrezzatureMobilePage(
                dipendenteMode: true,
                fullName: widget.fullName,
              )
            : AdminLogisticaAttrezzaturePage(
                dipendenteMode: true,
                fullName: widget.fullName,
              ),
      ),
    );
  }

  Future<void> _openMappaGps() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => useMobileUi(context)
            ? const AdminLogisticaMdoMappaMobilePage()
            : const AdminLogisticaMdoMappaPage(),
      ),
    );
  }

  Future<void> _openIncidenteSicurezza() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const SecurityIncidentPage(),
      ),
    );
  }

  Future<void> _openSicurezzaChooser() async {
    if (_busy) return;
    final pid = (_myPersonaleUuid ?? '').trim();
    await showDipendenteSicurezzaChooser(
      context,
      dpiPage: () {
        if (pid.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Profilo dipendente non disponibile')),
          );
        }
        return useMobileUi(context)
            ? DpiMobilePage(fullName: widget.fullName, personaleUuid: pid)
            : DpiPage(fullName: widget.fullName, personaleUuid: pid);
      },
      openMisureVestiario: _openMySizesDialog,
    );
  }

  Future<void> _openBuoniPastoChooser() async {
    if (_busy) return;
    await showDipendenteBuoniPastoChooser(
      context,
      scanPage: () => DipendenteBuonoPastoScanPage(userId: widget.userId),
      riepilogoPage: () =>
          DipendenteBuoniPastoRiepilogoPage(userId: widget.userId),
    );
  }

  Future<void> _openBuoniPastoScan() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DipendenteBuonoPastoScanPage(userId: widget.userId),
      ),
    );
  }

  Future<void> _openBuoniPastoRiepilogo() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DipendenteBuoniPastoRiepilogoPage(userId: widget.userId),
      ),
    );
  }

  Future<void> _openViaggiMezziChooser() async {
    if (_busy) return;
    await showDipendenteViaggiMezziChooser(
      context,
      scanPage: () => DipendenteViaggioMezzoScanPage(userId: widget.userId),
      riepilogoPage: () => const ViaggiMezziReportPage(
        mode: ViaggiMezziReportMode.conducente,
      ),
      assegnatarioPage: () => const ViaggiMezziReportPage(
        mode: ViaggiMezziReportMode.assegnatario,
      ),
    );
  }

  Future<void> _openViaggiMezziScan() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DipendenteViaggioMezzoScanPage(userId: widget.userId),
      ),
    );
  }

  Future<void> _openViaggiMezziRiepilogo() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ViaggiMezziReportPage(
          mode: ViaggiMezziReportMode.conducente,
        ),
      ),
    );
  }

  Future<void> _openViaggiMezziAssegnatario() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ViaggiMezziReportPage(
          mode: ViaggiMezziReportMode.assegnatario,
        ),
      ),
    );
  }

  Future<void> _openMyPernotti() async {
    setState(() => _busy = true);
    try {
      final pid = await _ensurePid();
      if (pid == null) return;

      final rs = await SupabaseService.client
          .from('bookings')
          .select()
          .eq('personale_id', pid)
          .order('start_date', ascending: false)
          .range(0, 999);

      final rows = (rs as List).cast<Map<String, dynamic>>();

      final commIds = <String>{};
      final structIds = <String>{};
      final dtIds = <String>{};
      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        structIds.add(_getStrutturaId(r));
        dtIds.add(_getDtKey(r));
      }

      final commesse = await _loadCommesseLabels(commIds);
      final structures = await _loadStrutture(structIds);
      final dtMap = await _loadRequesterNames(dtIds);

      if (!mounted) return;
      await _showAdaptiveList(
        title: 'I miei pernottamenti',
        child: _PernottiList(
          rows: rows,
          commesse: commesse,
          structures: structures,
          buildHeader: _headerWithLogo,
          getCommessaId: _getCommessaId,
          getStrutturaId: _getStrutturaId,
          getDtKey: _getDtKey,
          getMapLink: _getMapLink,
          dtMap: dtMap,
          onNavigate: _openMaps,
        ),
        desktopDialog: _MieiPernottiDialog(
          rows: rows,
          commesse: commesse,
          structures: structures,
          buildHeader: _headerWithLogo,
          getCommessaId: _getCommessaId,
          getStrutturaId: _getStrutturaId,
          getDtKey: _getDtKey,
          getMapLink: _getMapLink,
          dtMap: dtMap,
          onNavigate: _openMaps,
        ),
      );
    } catch (e) {
      _toast('Errore nel caricamento pernottamenti: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =========================================================================================
  // 5) FORMAZIONI – ricerca per utente_id (users.id_uuid) + fallback; nessun 42703
  // =========================================================================================

  Future<void> _openFormazioneChooser() async {
    if (_busy) return;
    await showDipendenteFormazioneChooser(
      context,
      employeeFullName: widget.fullName,
      alertProgrammazione: _hasMyProgrammazione,
      alertProgrammazioneRfi: _hasMyProgrammazioneRfi,
      scadenzePage: () => useMobileUi(context)
          ? EmployeeFormazioneScadenzeMobilePage(
              userId: widget.userId,
              fullName: widget.fullName,
            )
          : EmployeeFormazioneScadenzePage(
              userId: widget.userId,
              fullName: widget.fullName,
            ),
      rfiScadenzePage: () => useMobileUi(context)
          ? EmployeeFormazioneRfiScadenzeMobilePage(
              userId: widget.userId,
              fullName: widget.fullName,
            )
          : EmployeeFormazioneRfiScadenzePage(
              userId: widget.userId,
              fullName: widget.fullName,
            ),
      programmazionePage: () => useMobileUi(context)
          ? DtProgrammazioneFormazioniMobilePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            )
          : DtProgrammazioneFormazioniPage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            ),
      programmazioneRfiPage: () => useMobileUi(context)
          ? DtProgrammazioneFormazioniRfiMobilePage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            )
          : DtProgrammazioneFormazioniRfiPage(
              employeeOnly: true,
              employeeFullName: widget.fullName,
            ),
      attestatiPage: () => useMobileUi(context)
          ? EmployeeUqsaAttestatiMobilePage(
              userId: widget.userId,
              fullName: widget.fullName,
            )
          : EmployeeUqsaAttestatiPage(
              userId: widget.userId,
              fullName: widget.fullName,
            ),
    );
    await _loadProgrammazioneAlert();
  }

  Future<void> _openFormazioni() async {
    if (_busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => useMobileUi(context)
            ? EmployeeFormazioneScadenzeMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : EmployeeFormazioneScadenzePage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
  }

  Future<void> _openFormazioniRfi() async {
    if (_busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => useMobileUi(context)
            ? EmployeeFormazioneRfiScadenzeMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : EmployeeFormazioneRfiScadenzePage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
  }

  // =========================================================================================
  // 6) Helpers UI / nav
  // =========================================================================================

  Future<String?> _ensurePid() async {
    if (_myPersonaleUuid == null || _myPersonaleUuid!.isEmpty) {
      await _resolveMyPersonaleUuid();
    }
    final pid = _myPersonaleUuid;
    if (pid == null || pid.isEmpty) {
      _toast(
        'Impossibile determinare la tua anagrafica (personale). '
        'Verifica che "personale.user_id" sia collegato al tuo utente.',
        error: true,
      );
      return null;
    }
    return pid;
  }

  /// Apre Google Maps (priorità: link salvato → coordinate → nome)
  Future<void> _openMaps(
      {String? mapLink, double? lat, double? lng, String? name}) async {
    Uri? uri;
    if ((mapLink ?? '').trim().isNotEmpty) {
      final raw = mapLink!.trim();
      uri = Uri.tryParse(raw);
      if (uri == null) {
        _toast('Link mappa non valido', error: true);
        return;
      }
      if (!uri.hasScheme) uri = Uri.parse('https://$raw');
    } else if (lat != null && lng != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if ((name ?? '').trim().isNotEmpty) {
      final q = Uri.encodeComponent(name!);
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    } else {
      _toast('Posizione non disponibile', error: true);
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Impossibile aprire Maps', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    final duration = msg.length > 72
        ? const Duration(seconds: 8)
        : const Duration(seconds: 4);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        duration: duration,
      ),
    );
  }

  Future<void> _openMySizesDialog() async {
    final pid = (_myPersonaleUuid ?? '').trim();
    if (pid.isEmpty) {
      _toast('Impossibile risolvere il dipendente corrente', error: true);
      return;
    }
    await showEmployeeTaglieEditorDialog(
      context,
      personaleIdUuid: pid,
      dialogTitle: 'Le mie taglie',
      messenger: (msg, {error = false}) => _toast(msg, error: error),
    );
  }

  // --- Logo & header ---
  Widget _logo([double size = 22]) => Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.apartment, size: 20),
      );

  Widget _headerWithLogo(String title) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(20),
        const SizedBox(width: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Future<void> _logout() => performAppLogout(context);

  // ignore: unused_element
  Future<void> _tapRichiediTreno() async {
    if (_busy) return;
    final msg = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _isMobile
            ? RichiestaTrenoMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : RichiestaTrenoPage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
    if (!mounted) return;
    if ((msg ?? '').trim().isNotEmpty) _toast(msg!.trim());
  }

  // ignore: unused_element
  Future<void> _tapRichiediAereo() async {
    if (_busy) return;
    final msg = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _isMobile
            ? RichiestaAereoMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : RichiestaAereoPage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
    if (!mounted) return;
    if ((msg ?? '').trim().isNotEmpty) _toast(msg!.trim());
  }

  Future<void> _tapRichiediFeriePermessi() async {
    if (_busy) return;
    final msg = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => _isMobile
            ? RichiestaFeriePermessiMobilePage(
                userId: widget.userId,
                fullName: widget.fullName,
              )
            : RichiestaFeriePermessiPage(
                userId: widget.userId,
                fullName: widget.fullName,
              ),
      ),
    );
    if (!mounted) return;
    if ((msg ?? '').trim().isNotEmpty) _toast(msg!.trim());
  }

  Future<void> _tapDpi() async {
    if (_busy) return;
    if (_myPersonaleUuid == null || _myPersonaleUuid!.trim().isEmpty) {
      _toast('Impossibile risolvere il personale per i DPI.', error: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => useMobileUi(context)
            ? DpiMobilePage(
                fullName: widget.fullName,
                personaleUuid: _myPersonaleUuid!,
              )
            : DpiPage(
                fullName: widget.fullName,
                personaleUuid: _myPersonaleUuid!,
              ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    if (_busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _isMobile
            ? NotificationsMobilePage(userId: widget.userId)
            : NotificationsPage(userId: widget.userId),
      ),
    );
  }

  Widget _mobileTile({
    String? layoutKey,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? openDestination,
    VoidCallback? onOpenClosed,
    bool primary = false,
    bool alertBlink = false,
    bool alertBlinkRfi = false,
    bool alertBlinkVisita = false,
    bool alertBlinkBacheca = false,
  }) {
    final style = layoutKey != null ? _activeStyles[layoutKey] : null;
    // Mockup v5: titoli fissi; solo icona personalizzata dallo stile.
    final displayIcon = style?.effectiveIcon(icon) ?? icon;
    final displayTitle = title;
    final hasAlert = (alertBlinkVisita && _hasVisitaMedica) ||
        (alertBlinkRfi && _hasMyProgrammazioneRfi) ||
        (alertBlink && _hasMyProgrammazione) ||
        (alertBlinkBacheca && _hasBachecaUnread);
    final blinkRed = (alertBlink ||
            alertBlinkRfi ||
            alertBlinkVisita ||
            alertBlinkBacheca) &&
        hasAlert &&
        _progBlinkOn;
    final closedColor = PremiumGlassHubTheme.resolveFill(
      styleBg: null,
      layoutKey: layoutKey,
      alert: blinkRed,
      preferMockup: true,
      appDark: PremiumGlassHubTheme.appIsDark(context),
    );

    Widget tileBody({VoidCallback? tap}) {
      return PremiumGlassHubTile(
        layoutKey: layoutKey,
        title: displayTitle,
        subtitle: subtitle,
        icon: displayIcon,
        onTap: tap,
        // Mockup glass: colori da layoutKey (niente testo/icona bianchi salvati).
        iconColor: blinkRed ? Colors.red : null,
        textColor: blinkRed ? Colors.red : null,
        alert: blinkRed,
        margin: EdgeInsets.zero,
      );
    }

    // MobileOpenContainer gestisce anche desktop (push classico).
    // Non legare a useMobileUi: su Windows web i tile con solo openDestination
    // altrimenti restavano senza onTap.
    final child = openDestination != null
        ? MobileOpenContainer(
            onClosed: onOpenClosed,
            closedColor: closedColor,
            closedBorderRadius: BorderRadius.circular(22),
            closedBuilder: (_, open) => tileBody(tap: _busy ? null : open),
            destination: openDestination,
          )
        : tileBody(tap: _busy ? null : onTap);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: child,
    );
  }

  Widget _buildMobileHome() {
    final gestopro = _isGestoproHomeUi(context);
    if (gestopro) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHomeLayoutToolbar(),
          _buildOrderedMobileActions(),
          const SizedBox(height: 72),
        ],
      );
    }

    // Layout mockup: una sola card glass (profilo + azioni + moduli).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumGlassPanel(
          borderRadius: 26,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              PremiumGlassHubTheme.cyan.withValues(alpha: 0.45),
                          blurRadius: 18,
                        ),
                      ],
                      border: Border.all(
                        color:
                            PremiumGlassHubTheme.cyan.withValues(alpha: 0.75),
                        width: 2.4,
                      ),
                    ),
                    child: _buildProfileAvatar(radius: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              color: PremiumGlassHubTheme.titleColor(context),
                              fontSize: 18,
                              height: 1.2,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Ciao, ',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              TextSpan(
                                text: widget.fullName.isNotEmpty
                                    ? widget.fullName
                                    : widget.username,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Account dipendente',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: PremiumGlassHubTheme.subtitleColor(
                                  context,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2EAE6A),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2EAE6A)
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Online',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const PasskeyForceSetupBanner(),
              if (_canEditHomeLayout && !_loadingHomeLayout) ...[
                const SizedBox(height: 10),
                _buildHomeLayoutToolbar(),
              ],
              const SizedBox(height: 6),
              _buildOrderedMobileActions(),
            ],
          ),
        ),
        // Margine inferiore per FAB chat (spostabile).
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildMobileBody() {
    final gestopro = _isGestoproHomeUi(context);
    // Sfondo treno globale (CronosAppBackground): nessun velo opaco sopra.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!gestopro)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Center(
              child: GestoproOrbitBrandHeader(iconSize: 72),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: _buildMobileHome(),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHome() {
    final gestopro = _isGestoproHomeUi(context);
    if (gestopro) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.fullName,
            style: const TextStyle(
              color: CronosFuturisticTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _buildHomeLayoutToolbar(),
          _buildOrderedDesktopActions(),
          const SizedBox(height: 16),
        ],
      );
    }
    // Dual brand (GESTOPRO | CRONOS) arriva da PageWithTopLogo; qui solo home.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _buildMobileHome(),
      ),
    );
  }

  // =========================================================================================
  // 7) UI principale (overlay di caricamento)
  // =========================================================================================
  @override
  Widget build(BuildContext context) {
    final gestopro = _isGestoproHomeUi(context);
    final homeContent = _isMobile
        ? _buildMobileBody()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _buildDesktopHome(),
          );

    final busyOverlay = _busy
        ? Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.10),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          )
        : null;

    if (gestopro) {
      return Stack(
        children: [
          buildGestoproAwarePage(
            context: context,
            title: 'Area dipendente',
            toolbarActions: [
              if (_canEditHomeLayout && !_loadingHomeLayout) ...[
                if (!_homeReorderMode) ...[
                  IconButton(
                    tooltip: 'Nuova cartella',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _createHomeFolder,
                  ),
                  IconButton(
                    tooltip: 'Riordina pulsanti',
                    icon: const Icon(Icons.reorder),
                    onPressed: _enterHomeReorderMode,
                  ),
                ],
                if (_homeReorderMode) ...[
                  TextButton(
                    onPressed: _cancelHomeReorderMode,
                    child: const Text('Annulla'),
                  ),
                  TextButton(
                    onPressed: _saveHomeLayout,
                    child: Text(_canEditHomeLayout ? 'Salva per tutti' : 'Salva'),
                  ),
                ],
              ],
              IconButton(
                tooltip: 'Video istruttivi',
                icon: const Icon(Icons.ondemand_video_outlined),
                onPressed: _openVideoIstruzioni,
              ),
              IconButton(
                tooltip: 'I miei dati',
                icon: const Icon(Icons.phone_android_outlined),
                onPressed: _openIMieiDati,
              ),
              IconButton(
                tooltip: 'Notifiche',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _openNotifications,
              ),
            ],
            body: homeContent,
          ),
          ?busyOverlay,
        ],
      );
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: wrapClassicAppBarChrome(context, AppBar(
            titleSpacing: 0,
            title: _isMobile
                ? Text(
                    'CRONOS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                  )
                : Row(
                    children: [
                      _logo(),
                      const SizedBox(width: 8),
                      const Text('Vista Dipendente'),
                    ],
                  ),
            actions: [
              if (_isMobile &&
                  _canEditHomeLayout &&
                  _homeReorderMode &&
                  !_loadingHomeLayout) ...[
                TextButton(
                  onPressed: _cancelHomeReorderMode,
                  child: const Text('Annulla',
                      style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: _saveHomeLayout,
                  child: const Text('Salva',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
              if (!_isMobile &&
                  _canEditHomeLayout &&
                  !_loadingHomeLayout) ...[
                if (!_homeReorderMode) ...[
                  IconButton(
                    tooltip: 'Nuova cartella',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _createHomeFolder,
                  ),
                  IconButton(
                    tooltip: 'Riordina pulsanti (3 sec. su un pulsante)',
                    icon: const Icon(Icons.reorder),
                    onPressed: _enterHomeReorderMode,
                  ),
                ],
                if (_homeReorderMode) ...[
                  TextButton(
                    onPressed: _cancelHomeReorderMode,
                    child: const Text('Annulla'),
                  ),
                  TextButton(
                    onPressed: _saveHomeLayout,
                    child: const Text('Salva'),
                  ),
                ],
              ],
              IconButton(
                tooltip: 'Notifiche',
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: _hasBachecaUnread ||
                      _hasMyProgrammazione ||
                      _hasMyProgrammazioneRfi ||
                      _hasVisitaMedica,
                  backgroundColor: const Color(0xFFE53935),
                  smallSize: 10,
                  label: Text(
                    [
                      if (_hasBachecaUnread) 1 else 0,
                      if (_hasMyProgrammazione) 1 else 0,
                      if (_hasMyProgrammazioneRfi) 1 else 0,
                      if (_hasVisitaMedica) 1 else 0,
                    ].fold<int>(0, (a, b) => a + b).clamp(1, 9).toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
              const AppThemeModeToggleIconButton(),
              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          )),
          body: _isMobile
              ? _buildMobileBody()
              : PageWithTopLogo(
                  showLogo: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _buildDesktopHome(),
                  ),
                ),
        ),
        ?busyOverlay,
      ],
    );
  }
  // =========================================================================================
  // 8) Adaptive List: Bottom‑Sheet su Mobile; Pagina full‑screen su Desktop
  // =========================================================================================

  Future<void> _showAdaptiveList({
    required String title,
    required Widget child,
    required Widget desktopDialog, // mantenuta per compatibilità
    String? addLabel,
    Future<void> Function(BuildContext listContext)? onAdd,
  }) async {
    if (_isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (ctx) {
            final h = MediaQuery.of(ctx).size.height;
            return SizedBox(
              height: h * 0.92,
              child: Scaffold(
                body: Column(
                  children: [
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: _headerWithLogo(title),
                    ),
                    const Divider(height: 1),
                    Expanded(child: child),
                  ],
                ),
                floatingActionButton: onAdd == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: () => onAdd(ctx),
                        icon: const Icon(Icons.add),
                        label: Text(addLabel ?? 'Nuova'),
                      ),
              ),
            );
          },
        );
      });
    } else {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ListPage(
            title: title,
            headerBuilder: _headerWithLogo,
            body: child,
            addLabel: addLabel,
            onAdd: onAdd,
          ),
          fullscreenDialog: false,
        ),
      );
    }
  }
}

/* =============================================================================
 *  LIST PAGE (desktop) + LISTE
 * ===========================================================================*/

class _ListPage extends StatelessWidget {
  final String title;
  final Widget Function(String) headerBuilder;
  final Widget body;
  final String? addLabel;
  final Future<void> Function(BuildContext listContext)? onAdd;

  const _ListPage({
    required this.title,
    required this.headerBuilder,
    required this.body,
    this.addLabel,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
          context, AppBar(title: headerBuilder(title))),
      body: SafeArea(child: body),
      floatingActionButton: onAdd == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => onAdd!(context),
              icon: const Icon(Icons.add),
              label: Text(addLabel ?? 'Nuova'),
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  Color _color() {
    switch (status.toUpperCase()) {
      case 'CONFERMATA':
        return Colors.green;
      case 'IN_ATTESA':
        return Colors.orange;
      case 'IN ATTESA DT':
        return Colors.orange;
      case 'IN ATTESA ADMIN':
        return Colors.deepOrange;
      case 'INOLTRATA ADMIN':
        return Colors.deepOrange;
      case 'ANNULLATA':
        return Colors.redAccent;
      case 'RIFIUTATA':
        return Colors.red;
      case 'RIFIUTATA DT':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child:
          Text(status, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ChipInfo({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }
}

/* ------------------------------ Aerei ----------------------------------- */

class _AereiList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Widget Function(String title) buildHeader;

  const _AereiList({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.buildHeader,
  });

  @override
  State<_AereiList> createState() => _AereiListState();
}

class _AereiListState extends State<_AereiList> {
  late final List<Map<String, dynamic>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = List<Map<String, dynamic>>.from(widget.rows);
  }

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();
  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  String _displayStatus(Map<String, dynamic> r) {
    final s = _get(r, 'status').toUpperCase().trim();
    if (s == 'CONFERMATA' || s == 'RIFIUTATA' || s == 'ANNULLATA') return s;
    final ws = _get(r, 'workflow_status').toUpperCase().trim();
    switch (ws) {
      case 'INVIATA_AL_DT':
        return 'IN ATTESA DT';
      case 'INVIATA_ADMIN':
        return 'IN ATTESA ADMIN';
      case 'RIFIUTATA_DAL_DT':
        return 'RIFIUTATA DT';
      default:
        return s.isEmpty ? 'IN_ATTESA' : s;
    }
  }

  bool _canDelete(String displayStatus) {
    final s = displayStatus.toUpperCase().trim();
    return s == 'RIFIUTATA' || s == 'RIFIUTATA DT';
  }

  Future<void> _deleteBooking(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminare prenotazione?'),
        content:
            const Text('Questa prenotazione verrà cancellata definitivamente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.client.from('bookings_aereo').delete().eq('id', id);
      if (!mounted) return;
      setState(() => _rows
          .removeWhere((r) => int.tryParse((r['id'] ?? '').toString()) == id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prenotazione eliminata')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Errore eliminazione: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final date = _fmtDate(_get(r, 'data'));
        final time = _get(r, 'orario');
        final returnDate = _fmtDate(_get(r, 'data_ritorno'));
        final returnTime = _get(r, 'orario_ritorno');
        final from = _get(r, 'aeroporto_partenza');
        final to = _get(r, 'aeroporto_arrivo');
        final returnFromRaw = _get(r, 'aeroporto_partenza_ritorno');
        final returnToRaw = _get(r, 'aeroporto_arrivo_ritorno');
        final hasRitorno = returnDate.isNotEmpty;
        // Solo se c'è data ritorno: altrimenti non mostrare riga ritorno.
        final returnFrom = !hasRitorno
            ? ''
            : (returnFromRaw.isNotEmpty ? returnFromRaw : to);
        final returnTo = !hasRitorno
            ? ''
            : (returnToRaw.isNotEmpty ? returnToRaw : from);

        final commId =
            (r['commessa_id_uuid'] ?? r['commessa_id'] ?? '').toString();
        final comm = widget.commesse[commId] ?? commId;

        final stato = _displayStatus(r);
        final note = _get(r, 'master_note');
        final rejectReason = _get(r, 'dt_reject_reason').trim();

        final dtKey =
            (r['dt_user_uuid'] ?? r['dt_id'] ?? r['dt_uuid'] ?? '').toString();
        final rich = widget.dtMap[dtKey] ?? dtKey;

        final bag = _get(r, 'bagaglio');
        final park = (r['parcheggio'] == true) ? 'Sì' : 'No';
        final targa = _get(r, 'targa_veicolo');
        final id = int.tryParse((r['id'] ?? '').toString());

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.buildHeader('$from → $to'),
                        const SizedBox(height: 6),
                        _StatusBadge(stato),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: widget.buildHeader('$from → $to')),
                      const SizedBox(width: 8),
                      _StatusBadge(stato),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 6, children: [
                _ChipInfo(
                    icon: Icons.event,
                    text:
                        '$date ${time.isEmpty ? '' : 'Orario andata: $time'}'),
                if (hasRitorno &&
                    (returnFrom.isNotEmpty || returnTo.isNotEmpty))
                  _ChipInfo(
                    icon: Icons.event_repeat,
                    text:
                        'Ritorno: ${returnFrom.isEmpty ? '--' : returnFrom} → ${returnTo.isEmpty ? '--' : returnTo}',
                  ),
                if (hasRitorno)
                  _ChipInfo(
                    icon: Icons.event_repeat,
                    text:
                        'Ritorno: $returnDate${returnTime.isEmpty ? '' : ' Orario ritorno: $returnTime'}',
                  ),
                _ChipInfo(icon: Icons.work_outline, text: 'Commessa: $comm'),
                _ChipInfo(
                    icon: Icons.assignment_ind_outlined,
                    text: 'Richiedente: ${rich.isEmpty ? '—' : rich}'),
                _ChipInfo(
                    icon: Icons.luggage_outlined,
                    text:
                        'Bagaglio: ${bag == 'stiva' ? 'In stiva' : 'A mano'}'),
                _ChipInfo(
                    icon: Icons.local_parking_outlined,
                    text: 'Parcheggio: $park'),
                if (targa.isNotEmpty)
                  _ChipInfo(
                      icon: Icons.directions_car_outlined,
                      text: 'Targa: $targa'),
              ]),
              if (rejectReason.isNotEmpty &&
                  stato.toUpperCase() == 'RIFIUTATA DT') ...[
                const SizedBox(height: 8),
                Text('Motivo rifiuto DT: $rejectReason'),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
              ],
              if (id != null && _canDelete(stato)) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _deleteBooking(id),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancella'),
                  ),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _MieiAereiDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Widget Function(String title) buildHeader;

  const _MieiAereiDialog({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.buildHeader,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('Le mie richieste aerei'),
      content: SizedBox(
        width: 700,
        child: _AereiList(
            rows: rows,
            commesse: commesse,
            dtMap: dtMap,
            buildHeader: buildHeader),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'))
      ],
    );
  }
}

/* ------------------------------ TRENI ----------------------------------- */

class _TreniList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Widget Function(String title) buildHeader;

  const _TreniList({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.buildHeader,
  });

  @override
  State<_TreniList> createState() => _TreniListState();
}

class _TreniListState extends State<_TreniList> {
  late final List<Map<String, dynamic>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = List<Map<String, dynamic>>.from(widget.rows);
  }

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();
  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  String _displayStatus(Map<String, dynamic> r) {
    final s = _get(r, 'status').toUpperCase().trim();
    if (s == 'CONFERMATA' || s == 'RIFIUTATA' || s == 'ANNULLATA') return s;
    final ws = _get(r, 'workflow_status').toUpperCase().trim();
    switch (ws) {
      case 'INVIATA_AL_DT':
        return 'IN ATTESA DT';
      case 'INVIATA_ADMIN':
        return 'IN ATTESA ADMIN';
      case 'RIFIUTATA_DAL_DT':
        return 'RIFIUTATA DT';
      default:
        return s.isEmpty ? 'IN_ATTESA' : s;
    }
  }

  bool _canDelete(String displayStatus) {
    final s = displayStatus.toUpperCase().trim();
    return s == 'RIFIUTATA' || s == 'RIFIUTATA DT';
  }

  Future<void> _deleteBooking(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminare prenotazione?'),
        content:
            const Text('Questa prenotazione verrà cancellata definitivamente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.client.from('bookings_treno').delete().eq('id', id);
      if (!mounted) return;
      setState(() => _rows
          .removeWhere((r) => int.tryParse((r['id'] ?? '').toString()) == id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prenotazione eliminata')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Errore eliminazione: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final date = _fmtDate(_get(r, 'data'));
        final time = _get(r, 'orario');
        final returnDate = _fmtDate(_get(r, 'data_ritorno'));
        final returnTime = _get(r, 'orario_ritorno');
        final from = _get(r, 'stazione_partenza');
        final to = _get(r, 'stazione_arrivo');
        final returnFromRaw = _get(r, 'stazione_partenza_ritorno');
        final returnToRaw = _get(r, 'stazione_arrivo_ritorno');
        final hasRitorno = returnDate.isNotEmpty;
        // Solo se c'è data ritorno: altrimenti non mostrare riga ritorno.
        final returnFrom = !hasRitorno
            ? ''
            : (returnFromRaw.isNotEmpty ? returnFromRaw : to);
        final returnTo = !hasRitorno
            ? ''
            : (returnToRaw.isNotEmpty ? returnToRaw : from);

        final commId =
            (r['commessa_id_uuid'] ?? r['commessa_id'] ?? '').toString();
        final comm = widget.commesse[commId] ?? commId;

        final stato = _displayStatus(r);
        final note = _get(r, 'master_note');
        final rejectReason = _get(r, 'dt_reject_reason').trim();

        final dtKey =
            (r['dt_user_uuid'] ?? r['dt_id'] ?? r['dt_uuid'] ?? '').toString();
        final rich = widget.dtMap[dtKey] ?? dtKey;
        final id = int.tryParse((r['id'] ?? '').toString());

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.buildHeader('$from → $to'),
                        const SizedBox(height: 6),
                        _StatusBadge(stato),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: widget.buildHeader('$from → $to')),
                      const SizedBox(width: 8),
                      _StatusBadge(stato),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 6, children: [
                _ChipInfo(
                    icon: Icons.event,
                    text:
                        '$date ${time.isEmpty ? '' : 'Orario andata: $time'}'),
                if (hasRitorno &&
                    (returnFrom.isNotEmpty || returnTo.isNotEmpty))
                  _ChipInfo(
                    icon: Icons.event_repeat,
                    text:
                        'Ritorno: ${returnFrom.isEmpty ? '--' : returnFrom} → ${returnTo.isEmpty ? '--' : returnTo}',
                  ),
                if (hasRitorno)
                  _ChipInfo(
                    icon: Icons.event_repeat,
                    text:
                        'Ritorno: $returnDate${returnTime.isEmpty ? '' : ' Orario ritorno: $returnTime'}',
                  ),
                _ChipInfo(icon: Icons.work_outline, text: 'Commessa: $comm'),
                _ChipInfo(
                    icon: Icons.assignment_ind_outlined,
                    text: 'Richiedente: ${rich.isEmpty ? '—' : rich}'),
              ]),
              if (rejectReason.isNotEmpty &&
                  stato.toUpperCase() == 'RIFIUTATA DT') ...[
                const SizedBox(height: 8),
                Text('Motivo rifiuto DT: $rejectReason'),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
              ],
              if (id != null && _canDelete(stato)) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _deleteBooking(id),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancella'),
                  ),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _MieiTreniDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Widget Function(String title) buildHeader;

  const _MieiTreniDialog({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.buildHeader,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('Le mie richieste treno'),
      content: SizedBox(
        width: 700,
        child: _TreniList(
            rows: rows,
            commesse: commesse,
            dtMap: dtMap,
            buildHeader: buildHeader),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'))
      ],
    );
  }
}

/* --------------------------- PERNOTTAMENTI ------------------------------- */

class _PernottiList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;

  /// id_uuid → { name, lat?, lng? }
  final Map<String, Map<String, dynamic>> structures;
  final Widget Function(String title) buildHeader;

  final String Function(Map<String, dynamic>) getCommessaId;
  final String Function(Map<String, dynamic>) getStrutturaId;
  final String Function(Map<String, dynamic>) getDtKey;
  final String Function(Map<String, dynamic>) getMapLink;

  final Map<String, String> dtMap;
  final Future<void> Function(
      {String? mapLink, double? lat, double? lng, String? name}) onNavigate;

  const _PernottiList({
    required this.rows,
    required this.commesse,
    required this.structures,
    required this.buildHeader,
    required this.getCommessaId,
    required this.getStrutturaId,
    required this.getDtKey,
    required this.getMapLink,
    required this.dtMap,
    required this.onNavigate,
  });

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();
  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('Nessun pernottamento trovato.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = rows[i];

        final dal = _fmtDate(_get(r, 'start_date'));
        final al = _fmtDate(_get(r, 'end_date'));
        final cam = (r['camera_tipo'] ?? '').toString();

        final sid = getStrutturaId(r);
        final cid = getCommessaId(r);
        final structInfo = structures[sid] ?? const {'name': ''};
        final struttura = (structInfo['name'] ?? '').toString();
        final double? lat = structInfo['lat'] is num
            ? (structInfo['lat'] as num).toDouble()
            : null;
        final double? lng = structInfo['lng'] is num
            ? (structInfo['lng'] as num).toDouble()
            : null;

        final commessa = commesse[cid] ?? cid;
        final stato = (r['status'] ?? '').toString();
        final note = (r['master_note'] ?? '').toString();

        final dtKey = getDtKey(r);
        final rich = dtMap[dtKey] ?? dtKey;

        final mapLink = getMapLink(r);

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  buildHeader('$dal → $al'),
                  _ChipInfo(
                      icon: Icons.bed_outlined,
                      text: 'Camera: ${cam.isEmpty ? '—' : cam}'),
                  _ChipInfo(
                      icon: Icons.apartment_outlined,
                      text:
                          'Struttura: ${struttura.isEmpty ? '—' : struttura}'),
                  _StatusBadge(stato),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.directions),
                    label: const Text('Raggiungi'),
                    onPressed: () => onNavigate(
                        mapLink: mapLink, lat: lat, lng: lng, name: struttura),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 6, children: [
                _ChipInfo(
                    icon: Icons.work_outline, text: 'Commessa: $commessa'),
                _ChipInfo(
                    icon: Icons.assignment_ind_outlined,
                    text: 'Richiedente: ${rich.isEmpty ? '—' : rich}'),
              ]),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _MieiPernottiDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, Map<String, dynamic>> structures;
  final Widget Function(String title) buildHeader;
  final String Function(Map<String, dynamic>) getCommessaId;
  final String Function(Map<String, dynamic>) getStrutturaId;
  final String Function(Map<String, dynamic>) getDtKey;
  final String Function(Map<String, dynamic>) getMapLink;
  final Map<String, String> dtMap;
  final Future<void> Function(
      {String? mapLink, double? lat, double? lng, String? name}) onNavigate;

  const _MieiPernottiDialog({
    required this.rows,
    required this.commesse,
    required this.structures,
    required this.buildHeader,
    required this.getCommessaId,
    required this.getStrutturaId,
    required this.getDtKey,
    required this.getMapLink,
    required this.dtMap,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('I miei pernottamenti'),
      content: SizedBox(
        width: 760,
        child: _PernottiList(
          rows: rows,
          commesse: commesse,
          structures: structures,
          buildHeader: buildHeader,
          getCommessaId: getCommessaId,
          getStrutturaId: getStrutturaId,
          getDtKey: getDtKey,
          getMapLink: getMapLink,
          dtMap: dtMap,
          onNavigate: onNavigate,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'))
      ],
    );
  }
}

/// Avatar dipendente con caricamento da Storage (bytes) e fallback iniziale.
class _EmployeeProfileAvatar extends StatefulWidget {
  final double radius;
  final String initial;
  final String? fotoPath;

  const _EmployeeProfileAvatar({
    required this.radius,
    required this.initial,
    this.fotoPath,
  });

  @override
  State<_EmployeeProfileAvatar> createState() => _EmployeeProfileAvatarState();
}

class _EmployeeProfileAvatarState extends State<_EmployeeProfileAvatar> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EmployeeProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoPath != widget.fotoPath) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _bytes = null;
    });
    final path = (widget.fotoPath ?? '').trim();
    if (path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final bytes = await loadTesserinoFotoBytes(path);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
      _failed = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    if (_loading) {
      return CircleAvatar(
        radius: r,
        child: SizedBox(
          width: r,
          height: r,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null && !_failed) {
      return CircleAvatar(
        radius: r,
        backgroundImage: MemoryImage(_bytes!),
      );
    }
    return CircleAvatar(
      radius: r,
      child: Text(widget.initial.toUpperCase()),
    );
  }
}
