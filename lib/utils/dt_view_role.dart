import 'package:flutter/material.dart';

import 'roles.dart';

/// Ruolo DT da usare in anteprima Vista DT (admin con secondario DT → comportamento DT).
String dtPreviewEffectiveRole({
  required String sessionPrimaryRole,
  String? sessionSecondaryRole,
}) {
  final p = normalizeRole(sessionPrimaryRole);
  final s = (sessionSecondaryRole ?? '').trim().isEmpty
      ? ''
      : normalizeRole(sessionSecondaryRole!);
  if (p == 'assistente_dt' || s == 'assistente_dt') return 'assistente_dt';
  if (p == 'dt' || s == 'dt') return 'dt';
  return 'dt';
}

/// Ruolo effettivo per permessi UI: in anteprima Vista DT forza il ruolo DT.
String effectiveRoleForContext({
  required String pageRole,
  String? sessionPrimaryRole,
  String? sessionSecondaryRole,
  bool dtViewPreview = false,
}) {
  if (dtViewPreview &&
      (sessionPrimaryRole ?? '').trim().isNotEmpty &&
      isAnyAdminRole(sessionPrimaryRole!)) {
    return dtPreviewEffectiveRole(
      sessionPrimaryRole: sessionPrimaryRole,
      sessionSecondaryRole: sessionSecondaryRole,
    );
  }
  final r = pageRole.trim();
  if (r.isNotEmpty) return normalizeRole(r);
  if ((sessionPrimaryRole ?? '').trim().isNotEmpty) {
    return normalizeRole(sessionPrimaryRole!);
  }
  return '';
}

/// Propaga il ruolo DT alle route aperte dalla Vista DT (anteprima).
class DtViewRoleScope extends InheritedWidget {
  const DtViewRoleScope({
    super.key,
    required this.effectiveRole,
    required this.sessionPrimaryRole,
    this.sessionSecondaryRole,
    required super.child,
  });

  final String effectiveRole;
  final String sessionPrimaryRole;
  final String? sessionSecondaryRole;

  static DtViewRoleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DtViewRoleScope>();

  /// Se siamo sotto Vista DT, usa il ruolo DT anche se il widget ha ancora «admin».
  static String resolveForPage(BuildContext context, String? widgetRole) {
    final scope = maybeOf(context);
    if (scope == null) {
      return (widgetRole ?? '').trim().isEmpty
          ? ''
          : normalizeRole(widgetRole!);
    }
    final w = (widgetRole ?? '').trim();
    if (w.isEmpty || isAnyAdminRole(w)) {
      return scope.effectiveRole;
    }
    return normalizeRole(w);
  }

  /// Ruolo per [loadHubOrders]: in anteprima Vista DT da admin usa il layout globale.
  static String layoutPersistenceRole(BuildContext context, String? widgetRole) {
    final scope = maybeOf(context);
    if (scope != null && isAnyAdminRole(scope.sessionPrimaryRole)) {
      return normalizeRole(scope.sessionPrimaryRole);
    }
    final w = (widgetRole ?? '').trim();
    return w.isEmpty ? '' : normalizeRole(w);
  }

  @override
  bool updateShouldNotify(DtViewRoleScope oldWidget) =>
      effectiveRole != oldWidget.effectiveRole ||
      sessionPrimaryRole != oldWidget.sessionPrimaryRole ||
      sessionSecondaryRole != oldWidget.sessionSecondaryRole;
}
