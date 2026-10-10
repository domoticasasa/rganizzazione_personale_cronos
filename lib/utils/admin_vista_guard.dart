import 'package:flutter/material.dart';

import '../services/classic_nav_session_cache.dart';
import '../widgets/futuristic/gestopro_session_cache.dart';
import 'app_navigator.dart';
import 'roles.dart';

/// Ruolo sessione corrente (classica o Gestopro).
String? currentSessionRole() {
  final classic = ClassicNavSessionCache.current?.role;
  if (classic != null && classic.trim().isNotEmpty) return classic;
  return GestoproSessionCache.current?.role;
}

bool get isCurrentUserAdminVista =>
    isAdminVistaRole(currentSessionRole() ?? '');

/// Popup quando un [admin_vista] tenta di salvare.
Future<void> showAdminVistaReadOnlyDialog([BuildContext? context]) {
  final ctx = context ?? appNavigatorContext;
  if (ctx == null) return Future<void>.value();
  return showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Salvataggio non consentito'),
      content: const Text(
        'Non puoi salvare le modifiche.\n\n'
        'Il tuo account ha solo la vista: contatta un amministratore.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// `true` se il salvataggio può procedere; `false` se bloccato (popup già mostrato).
///
/// Usare all'inizio di **ogni** azione di salvataggio / insert / update / delete.
Future<bool> ensureCanPersist([BuildContext? context, String? role]) async {
  final resolved =
      (role ?? currentSessionRole() ?? '').trim();
  if (!isAdminVistaRole(resolved)) return true;
  final ctx = context ?? appNavigatorContext;
  if (ctx != null && ctx.mounted) {
    await showAdminVistaReadOnlyDialog(ctx);
  }
  return false;
}

/// Come [ensureCanPersist], ma solleva se bloccato (utile nei servizi senza UI).
Future<void> ensureCanPersistOrThrow([BuildContext? context, String? role]) async {
  if (!await ensureCanPersist(context, role)) {
    throw const AdminVistaReadOnlyException();
  }
}

class AdminVistaReadOnlyException implements Exception {
  const AdminVistaReadOnlyException();

  @override
  String toString() =>
      'AdminVistaReadOnlyException: salvataggio non consentito (sola vista)';
}

/// Avvolge un'azione di salvataggio: blocca [admin_vista] con popup.
VoidCallback? wrapPersistAction(
  BuildContext context,
  VoidCallback? onSave, [
  String? role,
]) {
  if (onSave == null) return null;
  return () async {
    if (!await ensureCanPersist(context, role)) return;
    onSave();
  };
}
