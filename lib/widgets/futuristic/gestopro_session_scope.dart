import 'package:flutter/material.dart';

import 'futuristic_nav_section.dart';
import 'futuristic_nav_sub_item.dart';
import 'gestopro_session_cache.dart';

/// Sessione utente GESTOPRO — propagata per mantenere sidebar e navigazione.
class GestoproSessionScope extends StatelessWidget {
  const GestoproSessionScope({
    super.key,
    required this.adminId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    this.customAllowedPages,
    this.gestoproDtHome,
    this.secondaryRole,
    this.activeSection = FuturisticNavSection.dashboard,
    this.subItems = const <FuturisticNavSubItem>[],
    this.activeSubKey,
    required this.child,
  });

  final int adminId;
  final int userId;
  final String username;
  final String fullName;
  final String role;
  final Set<String>? customAllowedPages;
  /// Home GESTOPRO della Vista DT (non admin hub).
  final bool? gestoproDtHome;
  final String? secondaryRole;
  final FuturisticNavSection activeSection;
  final List<FuturisticNavSubItem> subItems;
  final String? activeSubKey;
  final Widget child;

  static GestoproSessionScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_GestoproSessionInherited>()
        ?.scope;
  }

  GestoproSessionScope copyWith({
    int? adminId,
    int? userId,
    String? username,
    String? fullName,
    String? role,
    Set<String>? customAllowedPages,
    bool? gestoproDtHome,
    String? secondaryRole,
    FuturisticNavSection? activeSection,
    List<FuturisticNavSubItem>? subItems,
    String? activeSubKey,
    Widget? child,
  }) {
    return GestoproSessionScope(
      adminId: adminId ?? this.adminId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      customAllowedPages: customAllowedPages ?? this.customAllowedPages,
      gestoproDtHome: gestoproDtHome ?? this.gestoproDtHome,
      secondaryRole: secondaryRole ?? this.secondaryRole,
      activeSection: activeSection ?? this.activeSection,
      subItems: subItems ?? this.subItems,
      activeSubKey: activeSubKey ?? this.activeSubKey,
      child: child ?? this.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    GestoproSessionCache.update(this);
    return _GestoproSessionInherited(
      scope: this,
      child: child,
    );
  }
}

class _GestoproSessionInherited extends InheritedWidget {
  const _GestoproSessionInherited({
    required this.scope,
    required super.child,
  });

  final GestoproSessionScope scope;

  @override
  bool updateShouldNotify(covariant _GestoproSessionInherited oldWidget) {
    return scope.adminId != oldWidget.scope.adminId ||
        scope.userId != oldWidget.scope.userId ||
        scope.username != oldWidget.scope.username ||
        scope.fullName != oldWidget.scope.fullName ||
        scope.role != oldWidget.scope.role ||
        scope.customAllowedPages != oldWidget.scope.customAllowedPages ||
        scope.gestoproDtHome != oldWidget.scope.gestoproDtHome ||
        scope.secondaryRole != oldWidget.scope.secondaryRole ||
        scope.activeSection != oldWidget.scope.activeSection ||
        scope.subItems != oldWidget.scope.subItems ||
        scope.activeSubKey != oldWidget.scope.activeSubKey;
  }
}
