import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/device.dart';
import '../utils/responsive.dart';
import 'gestopro_mode_prefs.dart';

/// Sezione attiva (stesse voci della sidebar Gestopro).
enum ClassicNavSection {
  home,
  dashboard,
  notifiche,
  alert,
  impostazioni,
  profilo,
  vistaDipendente,
  vistaDt,
  logout,
}

class ClassicNavSessionSnapshot {
  const ClassicNavSessionSnapshot({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    this.secondaryRole,
  });

  final int userId;
  final String username;
  final String fullName;
  final String role;
  final String? secondaryRole;
}

/// Rail sinistra: no telefono / viewport stretto (mobile web incluso).
bool shouldShowClassicRail(BuildContext context) {
  if (ClassicNavSessionCache.current == null) return false;
  if (Supabase.instance.client.auth.currentSession == null) return false;
  if (isMobileDevice()) {
    return MediaQuery.sizeOf(context).shortestSide >= CronosBreakpoints.phone;
  }
  return MediaQuery.sizeOf(context).width >= CronosBreakpoints.phone;
}

/// Sessione + flag UI classica + sezione attiva sidebar.
abstract final class ClassicNavSessionCache {
  ClassicNavSessionCache._();

  static final ValueNotifier<ClassicNavSessionSnapshot?> notifier =
      ValueNotifier<ClassicNavSessionSnapshot?>(null);

  /// true = pagina classica visibile (non shell Gestopro).
  static final ValueNotifier<bool> classicChromeActive =
      ValueNotifier<bool>(false);

  static final ValueNotifier<ClassicNavSection> activeSection =
      ValueNotifier<ClassicNavSection>(ClassicNavSection.home);

  static ClassicNavSessionSnapshot? get current => notifier.value;

  static bool get _hasAuthSession =>
      Supabase.instance.client.auth.currentSession != null;

  /// Evita notifyListeners / setState durante build/layout.
  static void _runOutsideBuild(VoidCallback fn) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      fn();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => fn());
  }

  static void update({
    required int userId,
    required String username,
    required String fullName,
    required String role,
    String? secondaryRole,
  }) {
    // Dopo logout non ripristinare la rail (build/didChangeDependencies residui).
    if (!_hasAuthSession) return;
    final next = ClassicNavSessionSnapshot(
      userId: userId,
      username: username,
      fullName: fullName,
      role: role,
      secondaryRole: secondaryRole,
    );
    _runOutsideBuild(() {
      if (!_hasAuthSession) return;
      final prev = notifier.value;
      if (prev != null &&
          prev.userId == next.userId &&
          prev.username == next.username &&
          prev.fullName == next.fullName &&
          prev.role == next.role &&
          prev.secondaryRole == next.secondaryRole) {
        markClassicChrome();
        return;
      }
      notifier.value = next;
      markClassicChrome();
    });
  }

  static void setActiveSection(ClassicNavSection section) {
    _runOutsideBuild(() {
      if (activeSection.value != section) {
        activeSection.value = section;
      }
    });
  }

  static void markClassicChrome({bool forceNotify = false}) {
    _runOutsideBuild(() {
      // Mai riattivare la rail classica mentre la sessione Gestopro è attiva.
      if (GestoproModePrefs.sessionActive) return;
      if (!_hasAuthSession || current == null) return;
      if (!classicChromeActive.value) {
        classicChromeActive.value = true;
        return;
      }
      // Dopo uscita Gestopro: se era già true non notifica → forza rebuild.
      if (forceNotify) {
        classicChromeActive.value = false;
        classicChromeActive.value = true;
      }
    });
  }

  static void markGestoproChrome() {
    _runOutsideBuild(() {
      if (classicChromeActive.value) {
        classicChromeActive.value = false;
      }
    });
  }

  static void clear() {
    _runOutsideBuild(() {
      notifier.value = null;
      classicChromeActive.value = false;
      activeSection.value = ClassicNavSection.home;
    });
  }
}
