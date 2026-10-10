import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/admin_gestopro_dt_hub_page.dart';
import '../pages/dt_home_page.dart';
import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../widgets/futuristic/gestopro_access_dialog.dart';
import 'roles.dart';
import 'dt_view_role.dart';

/// Admin (non DT primario): anteprima della home DT.
bool canPreviewDtView(String role) {
  final r = normalizeRole(role);
  if (r == 'dt' || r == 'assistente_dt') return false;
  return isAnyAdminRole(role);
}

/// Apre la home DT in anteprima; [sessionRole] è il ruolo reale (es. admin),
/// [effectiveRole] è DT per permessi e pagine figlie.
void openDtView(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
  required String sessionRole,
  String? sessionSecondaryRole,
}) {
  if (GestoproModePrefs.sessionActive) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AdminGestoproDtHubPage(
          userId: userId,
          username: username,
          fullName: fullName,
          sessionRole: sessionRole,
          sessionSecondaryRole: sessionSecondaryRole,
        ),
      ),
    );
    return;
  }

  final effectiveRole = dtPreviewEffectiveRole(
    sessionPrimaryRole: sessionRole,
    sessionSecondaryRole: sessionSecondaryRole,
  );
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DtHomePage(
        username: username,
        fullName: fullName,
        role: effectiveRole,
        userId: userId,
        layoutEditorRole: sessionRole,
        secondaryRole: sessionSecondaryRole,
      ),
    ),
  );
}

/// DT / Assistente DT: accesso GESTOPRO dalla home classica.
bool canOpenGestoproFromDtHome(String role) {
  final r = normalizeRole(role);
  return r == 'dt' || r == 'assistente_dt';
}

/// Apre la home DT in GESTOPRO (moduli filtrati per ruolo).
Future<void> openDtGestoproSession(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
  required String sessionRole,
  String? sessionSecondaryRole,
  bool requirePassword = false,
}) async {
  if (requirePassword) {
    final ok = await showGestoproAccessDialog(context);
    if (!ok || !context.mounted) return;
  }
  GestoproModePrefs.sessionActive = true;
  ClassicNavSessionCache.markGestoproChrome();
  final nav = Navigator.of(context);
  final page = AdminGestoproDtHubPage(
    userId: userId,
    username: username,
    fullName: fullName,
    sessionRole: sessionRole,
    sessionSecondaryRole: sessionSecondaryRole,
  );
  unawaited(GestoproModePrefs.activate());
  await nav.pushReplacement(
    MaterialPageRoute(builder: (_) => page),
  );
}

/// Torna alla home DT in GESTOPRO (sidebar Home / navigazione interna).
void openDtGestoproHome(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
  required String sessionRole,
  String? sessionSecondaryRole,
  Set<String>? customAllowedPages,
}) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => AdminGestoproDtHubPage(
        userId: userId,
        username: username,
        fullName: fullName,
        sessionRole: sessionRole,
        sessionSecondaryRole: sessionSecondaryRole,
        customAllowedPages: customAllowedPages,
      ),
    ),
    (_) => false,
  );
}

/// Esce da GESTOPRO e torna alla home DT classica.
Future<void> exitDtGestoproSession(
  BuildContext context, {
  required int userId,
  required String username,
  required String fullName,
  required String role,
  String? secondaryRole,
}) async {
  await GestoproModePrefs.deactivate();
  ClassicNavSessionCache.markClassicChrome(forceNotify: true);
  if (!context.mounted) return;
  await Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => DtHomePage(
        username: username,
        fullName: fullName,
        role: role,
        userId: userId,
        secondaryRole: secondaryRole,
      ),
    ),
    (_) => false,
  );
}
