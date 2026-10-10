import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'futuristic_nav_sub_item.dart';

/// Cache sotto-voci sidebar — propagate tra push GESTOPRO.
abstract final class GestoproNavSubItemsCache {
  GestoproNavSubItemsCache._();

  static List<FuturisticNavSubItem> items = const <FuturisticNavSubItem>[];
  static String? activeKey;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _revisionNotifyScheduled = false;

  static void update(
    List<FuturisticNavSubItem> next, {
    String? activeSubKey,
  }) {
    items = List<FuturisticNavSubItem>.from(next);
    activeKey = activeSubKey;
    _scheduleRevisionNotify();
  }

  static void _scheduleRevisionNotify() {
    if (_revisionNotifyScheduled) return;
    _revisionNotifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revisionNotifyScheduled = false;
      revision.value++;
    });
  }
}
