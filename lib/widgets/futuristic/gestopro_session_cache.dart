import 'package:flutter/material.dart';

import 'futuristic_nav_section.dart';
import 'futuristic_nav_sub_item.dart';
import 'gestopro_session_scope.dart';

/// Dati sessione GESTOPRO — disponibili anche fuori dall'albero [GestoproSessionScope].
class GestoproSessionSnapshot {
  const GestoproSessionSnapshot({
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
  });

  final int adminId;
  final int userId;
  final String username;
  final String fullName;
  final String role;
  final Set<String>? customAllowedPages;
  final bool? gestoproDtHome;
  final String? secondaryRole;
  final FuturisticNavSection activeSection;
  final List<FuturisticNavSubItem> subItems;
  final String? activeSubKey;

  factory GestoproSessionSnapshot.fromScope(GestoproSessionScope scope) {
    return GestoproSessionSnapshot(
      adminId: scope.adminId,
      userId: scope.userId,
      username: scope.username,
      fullName: scope.fullName,
      role: scope.role,
      customAllowedPages: scope.customAllowedPages,
      gestoproDtHome: scope.gestoproDtHome,
      secondaryRole: scope.secondaryRole,
      activeSection: scope.activeSection,
      subItems: scope.subItems,
      activeSubKey: scope.activeSubKey,
    );
  }

  GestoproSessionScope wrap({
    FuturisticNavSection? activeSection,
    List<FuturisticNavSubItem>? subItems,
    String? activeSubKey,
    required Widget child,
  }) {
    return GestoproSessionScope(
      adminId: adminId,
      userId: userId,
      username: username,
      fullName: fullName,
      role: role,
      customAllowedPages: customAllowedPages,
      gestoproDtHome: gestoproDtHome,
      secondaryRole: secondaryRole,
      activeSection: activeSection ?? this.activeSection,
      subItems: subItems ?? this.subItems,
      activeSubKey: activeSubKey ?? this.activeSubKey,
      child: child,
    );
  }

  GestoproSessionSnapshot copyWith({
    FuturisticNavSection? activeSection,
    List<FuturisticNavSubItem>? subItems,
    String? activeSubKey,
  }) {
    return GestoproSessionSnapshot(
      adminId: adminId,
      userId: userId,
      username: username,
      fullName: fullName,
      role: role,
      customAllowedPages: customAllowedPages,
      gestoproDtHome: gestoproDtHome ?? false,
      secondaryRole: secondaryRole,
      activeSection: activeSection ?? this.activeSection,
      subItems: subItems ?? this.subItems,
      activeSubKey: activeSubKey ?? this.activeSubKey,
    );
  }
}

/// Cache sessione — la navigazione usa spesso il `context` dello State, sopra lo scope.
abstract final class GestoproSessionCache {
  GestoproSessionCache._();

  static GestoproSessionSnapshot? current;

  static void update(GestoproSessionScope scope) {
    current = GestoproSessionSnapshot(
      adminId: scope.adminId,
      userId: scope.userId,
      username: scope.username,
      fullName: scope.fullName,
      role: scope.role,
      customAllowedPages: scope.customAllowedPages,
      gestoproDtHome: scope.gestoproDtHome,
      secondaryRole: scope.secondaryRole,
      activeSection: scope.activeSection,
      subItems: scope.subItems,
      activeSubKey: scope.activeSubKey,
    );
  }

  static void clear() {
    current = null;
  }

  static GestoproSessionSnapshot? resolve(BuildContext context) {
    final inherited = GestoproSessionScope.maybeOf(context);
    if (inherited != null) {
      return GestoproSessionSnapshot.fromScope(inherited);
    }
    return current;
  }
}
