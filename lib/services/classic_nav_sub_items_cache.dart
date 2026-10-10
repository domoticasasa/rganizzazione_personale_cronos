import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/futuristic/futuristic_nav_sub_item.dart';

/// Sotto-voci sidebar classica: Home e Dashboard separate (come Gestopro).
abstract final class ClassicNavSubItemsCache {
  ClassicNavSubItemsCache._();

  static List<FuturisticNavSubItem> homeItems = const [];
  static List<FuturisticNavSubItem> dashboardItems = const [];
  static String? activeKey;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final ValueNotifier<Set<String>> manuallyExpanded =
      ValueNotifier<Set<String>>(<String>{});

  static bool _revisionNotifyScheduled = false;

  static void updateHome(List<FuturisticNavSubItem> items) {
    homeItems = List<FuturisticNavSubItem>.from(items);
    _scheduleRevisionNotify();
  }

  static void updateDashboard(
    List<FuturisticNavSubItem> items, {
    String? activeSubKey,
  }) {
    dashboardItems = List<FuturisticNavSubItem>.from(items);
    if (activeSubKey != null) {
      activeKey = activeSubKey;
      _ensureExpandedAlongPath(items, activeSubKey);
    }
    _scheduleRevisionNotify();
  }

  static void setActiveKey(String? key) {
    if (activeKey == key) return;
    activeKey = key;
    if (key != null) {
      _ensureExpandedAlongPath(dashboardItems, key);
      _ensureExpandedAlongPath(homeItems, key);
    }
    _scheduleRevisionNotify();
  }

  static void toggleExpanded(String key) {
    final next = Set<String>.from(manuallyExpanded.value);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _setExpanded(next);
  }

  static bool isManuallyExpanded(String key) =>
      manuallyExpanded.value.contains(key);

  static void _ensureExpandedAlongPath(
    List<FuturisticNavSubItem> items,
    String activeSubKey,
  ) {
    final path = <String>[];
    if (!_findPath(items, activeSubKey, path)) return;
    final next = Set<String>.from(manuallyExpanded.value)..addAll(path);
    // Non includere la foglia attiva se non ha figli.
    next.remove(activeSubKey);
    _setExpanded(next, afterFrame: true);
  }

  static bool _findPath(
    List<FuturisticNavSubItem> items,
    String key,
    List<String> path,
  ) {
    for (final item in items) {
      path.add(item.key);
      if (item.key == key) return true;
      if (item.children.isNotEmpty && _findPath(item.children, key, path)) {
        return true;
      }
      path.removeLast();
    }
    return false;
  }

  static bool _expandedNotifyScheduled = false;
  static Set<String>? _pendingExpanded;

  static void _setExpanded(Set<String> next, {bool afterFrame = false}) {
    if (setEquals(manuallyExpanded.value, next)) return;
    if (!afterFrame) {
      manuallyExpanded.value = next;
      return;
    }
    _pendingExpanded = next;
    if (_expandedNotifyScheduled) return;
    _expandedNotifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _expandedNotifyScheduled = false;
      final pending = _pendingExpanded;
      _pendingExpanded = null;
      if (pending == null) return;
      if (setEquals(manuallyExpanded.value, pending)) return;
      manuallyExpanded.value = pending;
    });
  }

  static void _scheduleRevisionNotify() {
    if (_revisionNotifyScheduled) return;
    _revisionNotifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revisionNotifyScheduled = false;
      revision.value++;
    });
  }

  static void clear() {
    homeItems = const [];
    dashboardItems = const [];
    activeKey = null;
    _setExpanded(<String>{}, afterFrame: true);
    _scheduleRevisionNotify();
  }
}
