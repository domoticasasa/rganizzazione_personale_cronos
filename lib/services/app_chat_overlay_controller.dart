import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_chat_rules.dart';
import 'supabase_service.dart';
import 'web_app_badge.dart';
import 'windows_taskbar_icon.dart';

/// Stato overlay chat aziendale (FAB + pannello + posizione nuvoletta).
class AppChatOverlayController {
  AppChatOverlayController._();

  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Non letti solo gruppi (tab «Gruppo» lampeggia se > 0).
  static final ValueNotifier<int> unreadGroupCount = ValueNotifier<int>(0);

  /// Non letti solo DM (tab «Privato» lampeggia se > 0).
  static final ValueNotifier<int> unreadDmCount = ValueNotifier<int>(0);

  static bool _badgeListenerAttached = false;

  /// Badge: PWA web (icona installata) + overlay taskbar Windows (app desktop).
  static void ensureWebBadgeSync() {
    if (_badgeListenerAttached) return;
    _badgeListenerAttached = true;
    unreadCount.addListener(_syncWebBadge);
    _syncWebBadge();
  }

  static void _syncWebBadge() {
    final n = unreadCount.value;
    unawaited(WebAppBadge.setCount(n));
    unawaited(_syncWindowsChatOverlay(n));
  }

  /// App desktop Windows: pallino sull'icona CRONOS (solo a processo avviato).
  static Future<void> _syncWindowsChatOverlay(int n) async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform != TargetPlatform.windows) return;
      if (n > 0) {
        await WindowsTaskbarIcon.setOverlayFromAssetPath(
          'assets/icon_tray_notify.ico',
          description: n == 1 ? '1 messaggio chat' : '$n messaggi chat',
        );
      } else {
        await WindowsTaskbarIcon.clearOverlay();
      }
    } catch (_) {}
  }

  /// True durante lo splash di avvio: nasconde FAB/chat.
  static final ValueNotifier<bool> splashBlocking = ValueNotifier<bool>(false);

  static void clearSplashBlock() {
    final wasBlocking = splashBlocking.value;
    if (wasBlocking) {
      splashBlocking.value = false;
    }
    // Solo se uscivamo dallo splash: evita FAB invisibile (isOpen senza pannello).
    if (wasBlocking && isOpen.value) {
      isOpen.value = false;
    }
  }

  /// Posizione FAB: frazione dello schermo (0–1) da sinistra/alto.
  static final ValueNotifier<Offset> fabAnchor = ValueNotifier<Offset>(
    const Offset(0.88, 0.86),
  );

  /// Se impostato, ha priorità su [fabAnchor] (es. home dipendente = centro basso).
  /// Non viene salvato in prefs.
  static final ValueNotifier<Offset?> fabAnchorOverride =
      ValueNotifier<Offset?>(null);

  /// Angolo alto-sinistra del pannello chat (pixel). Null = default in basso a destra.
  static final ValueNotifier<Offset?> panelTopLeft = ValueNotifier<Offset?>(null);

  /// Dimensione pannello desktop (pixel). Null = default proporzionale allo schermo.
  static final ValueNotifier<Size?> panelSize = ValueNotifier<Size?>(null);

  static const _prefsX = 'cronos_chat_fab_x';
  static const _prefsY = 'cronos_chat_fab_y';
  static const _prefsPanelX = 'cronos_chat_panel_x';
  static const _prefsPanelY = 'cronos_chat_panel_y';
  static const _prefsPanelW = 'cronos_chat_panel_w';
  static const _prefsPanelH = 'cronos_chat_panel_h';

  static const double panelMinWidth = 320;
  static const double panelMinHeight = 380;

  static bool _prefsLoaded = false;
  static bool _panelPrefsLoaded = false;

  static Future<void> ensureFabPositionLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefsX);
      final y = prefs.getDouble(_prefsY);
      if (x != null && y != null) {
        fabAnchor.value = Offset(x.clamp(0.08, 0.92), y.clamp(0.08, 0.92));
      }
    } catch (_) {}
  }

  static Future<void> ensurePanelPositionLoaded() async {
    if (_panelPrefsLoaded) return;
    _panelPrefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefsPanelX);
      final y = prefs.getDouble(_prefsPanelY);
      if (x != null && y != null) {
        panelTopLeft.value = Offset(x, y);
      }
      final w = prefs.getDouble(_prefsPanelW);
      final h = prefs.getDouble(_prefsPanelH);
      if (w != null && h != null && w >= panelMinWidth && h >= panelMinHeight) {
        panelSize.value = Size(w, h);
      }
    } catch (_) {}
  }

  static Offset clampPanelTopLeft({
    required Offset topLeft,
    required Size screen,
    required Size panel,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final maxLeft = math.max(8.0, screen.width - panel.width - 8);
    final maxTop = math.max(
      padding.top + 8,
      screen.height - padding.bottom - panel.height - 8,
    );
    return Offset(
      topLeft.dx.clamp(8.0, maxLeft),
      topLeft.dy.clamp(padding.top + 8, maxTop),
    );
  }

  static Size clampPanelSize({
    required Size size,
    required Size screen,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final maxW = math.max(panelMinWidth, screen.width - 16);
    final maxH = math.max(
      panelMinHeight,
      screen.height - padding.top - padding.bottom - 16,
    );
    return Size(
      size.width.clamp(panelMinWidth, maxW),
      size.height.clamp(panelMinHeight, maxH),
    );
  }

  static Future<void> setPanelTopLeft(Offset topLeft) async {
    panelTopLeft.value = topLeft;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsPanelX, topLeft.dx);
      await prefs.setDouble(_prefsPanelY, topLeft.dy);
    } catch (_) {}
  }

  static Future<void> setPanelSize(Size size) async {
    panelSize.value = size;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsPanelW, size.width);
      await prefs.setDouble(_prefsPanelH, size.height);
    } catch (_) {}
  }

  static Future<void> setFabAnchor(Offset fraction) async {
    final next = Offset(
      fraction.dx.clamp(0.08, 0.92),
      fraction.dy.clamp(0.08, 0.92),
    );
    fabAnchor.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsX, next.dx);
      await prefs.setDouble(_prefsY, next.dy);
    } catch (_) {}
  }

  static void open() {
    isOpen.value = true;
    // Il pannello segna letto sul gruppo/DM attivo.
    // Badge FAB azzerato; i conteggi gruppo/DM restano per il lampeggio tab.
    unreadCount.value = 0;
    unawaited(WebAppBadge.clear());
  }

  /// Apre la chat solo dopo accettazione del regolamento (prima volta).
  static Future<void> tryOpen(BuildContext? context) async {
    if (isOpen.value) return;
    final ok = await AppChatRules.ensureAccepted(context);
    if (!ok) return;
    open();
  }

  static void close() {
    isOpen.value = false;
    // Flush immediato del cursore in sospeso, poi ricalcola badge.
    unawaited(_flushMarkReadThenRefreshBadge());
  }

  static void toggle() {
    if (isOpen.value) {
      close();
    } else {
      // Preferire tryOpen(context) dal FAB: qui non c'è BuildContext.
      open();
    }
  }

  static void setUnreadCount(int n) {
    // Con chat aperta ignora i ricalcoli server sul FAB (evita badge fantasma).
    if (isOpen.value && n > 0) {
      unreadCount.value = 0;
      unawaited(WebAppBadge.clear());
      return;
    }
    unreadCount.value = n < 0 ? 0 : n;
  }

  /// Aggiorna conteggi gruppo/DM; il badge FAB totale solo a chat chiusa.
  static void setUnreadBreakdown({required int group, required int dm}) {
    final g = group < 0 ? 0 : group;
    final d = dm < 0 ? 0 : dm;
    unreadGroupCount.value = g;
    unreadDmCount.value = d;
    if (isOpen.value) {
      unreadCount.value = 0;
      unawaited(WebAppBadge.clear());
    } else {
      unreadCount.value = g + d;
    }
  }

  static void clearUnreadBreakdown() {
    unreadGroupCount.value = 0;
    unreadDmCount.value = 0;
  }

  static Timer? _markReadDebounce;
  static String? _pendingGroupId;
  static bool _pendingDmMark = false;

  /// Azzera il badge FAB; il cursore DB dipende da gruppo/DM attivo.
  static void markSeen({String? groupId}) {
    unreadCount.value = 0;
    if (groupId != null && groupId.trim().isNotEmpty) {
      markGroupSeen(groupId.trim());
      return;
    }
  }

  static void markGroupSeen(String groupId) {
    unreadCount.value = 0;
    _pendingDmMark = false;
    _pendingGroupId = groupId;
    _markReadDebounce?.cancel();
    // Debounce corto: evita perdita del mark se si chiude subito.
    _markReadDebounce = Timer(const Duration(milliseconds: 250), () {
      final gid = _pendingGroupId;
      _pendingGroupId = null;
      if (gid == null || gid.isEmpty) return;
      unawaited(_persistMarkGroupRead(gid).then((_) => _refreshBreakdownQuiet()));
    });
  }

  /// Cursore lettura DM (tabella app_chat_read_state legacy).
  static void markDmSeen() {
    unreadCount.value = 0;
    _pendingGroupId = null;
    _pendingDmMark = true;
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 250), () {
      _pendingDmMark = false;
      unawaited(_persistMarkRead().then((_) => _refreshBreakdownQuiet()));
    });
  }

  static Future<void> _refreshBreakdownQuiet() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final raw =
          await SupabaseService.client.rpc('app_chat_unread_breakdown');
      final map = _parseBreakdown(raw);
      setUnreadBreakdown(group: map.$1, dm: map.$2);
    } catch (_) {
      try {
        final raw = await SupabaseService.client.rpc('app_chat_unread_count');
        final n = raw is int
            ? raw
            : int.tryParse(raw?.toString() ?? '') ?? 0;
        if (!isOpen.value) unreadCount.value = n < 0 ? 0 : n;
      } catch (_) {}
    }
  }

  static (int, int) _parseBreakdown(dynamic raw) {
    if (raw is Map) {
      final g = raw['group'];
      final d = raw['dm'];
      return (
        g is int ? g : int.tryParse(g?.toString() ?? '') ?? 0,
        d is int ? d : int.tryParse(d?.toString() ?? '') ?? 0,
      );
    }
    if (raw is String) {
      try {
        // jsonb a volte arriva come stringa
        final cleaned = raw.trim();
        if (cleaned.startsWith('{')) {
          final groupMatch = RegExp(r'"group"\s*:\s*(\d+)').firstMatch(cleaned);
          final dmMatch = RegExp(r'"dm"\s*:\s*(\d+)').firstMatch(cleaned);
          return (
            int.tryParse(groupMatch?.group(1) ?? '') ?? 0,
            int.tryParse(dmMatch?.group(1) ?? '') ?? 0,
          );
        }
      } catch (_) {}
    }
    return (0, 0);
  }

  static Future<void> _flushMarkReadThenRefreshBadge() async {
    _markReadDebounce?.cancel();
    _markReadDebounce = null;
    final gid = _pendingGroupId;
    final dm = _pendingDmMark;
    _pendingGroupId = null;
    _pendingDmMark = false;
    if (gid != null && gid.isNotEmpty) {
      await _persistMarkGroupRead(gid);
    } else if (dm) {
      await _persistMarkRead();
    }
    await _refreshBreakdownQuiet();
  }

  static Future<void> _persistMarkRead() async {
    try {
      await SupabaseService.client.rpc('app_chat_mark_read');
    } catch (_) {}
  }

  static Future<void> _persistMarkGroupRead(String groupId) async {
    try {
      await SupabaseService.client.rpc(
        'app_chat_mark_group_read',
        params: {'p_group_id': groupId},
      );
    } catch (_) {}
  }
}