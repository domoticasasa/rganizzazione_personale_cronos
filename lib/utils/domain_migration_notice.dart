import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain_canonical_redirect_stub.dart'
    if (dart.library.html) 'domain_canonical_redirect_web.dart' as redirect;

/// Migrazione dominio: pernotti/gestopro.pages.dev → gestopro360.it
abstract final class DomainMigrationNotice {
  DomainMigrationNotice._();

  static const _prefsKey = 'gestopro_domain_notice_v4_dismissed';
  static const canonicalHost = 'www.gestopro360.it';
  static const apexHost = 'gestopro360.it';
  static const wwwHost = 'www.gestopro360.it';

  /// Host legacy da cui forzare il redirect al dominio canonico.
  static const legacyHosts = <String>{
    'pernotti.pages.dev',
    'gestopro.pages.dev',
  };

  static bool get _onCanonicalHost {
    if (!kIsWeb) return false;
    try {
      final h = Uri.base.host.toLowerCase();
      return h == canonicalHost || h == apexHost || h == wwwHost;
    } catch (_) {
      return false;
    }
  }

  static bool get _onLegacyHost {
    if (!kIsWeb) return false;
    try {
      final h = Uri.base.host.toLowerCase();
      if (legacyHosts.contains(h)) return true;
      return h.endsWith('.pernotti.pages.dev') ||
          h.endsWith('.gestopro.pages.dev');
    } catch (_) {
      return false;
    }
  }

  /// Se l’utente apre ancora pages.dev, salta subito a www.gestopro360.it.
  static void redirectLegacyHostIfNeeded() {
    if (!_onLegacyHost) return;
    redirect.redirectToCanonical(
      host: wwwHost,
      path: Uri.base.path,
      query: Uri.base.hasQuery ? Uri.base.query : null,
      fragment: Uri.base.hasFragment ? Uri.base.fragment : null,
    );
  }

  /// Dialog una sola volta: sparisce con OK e non ripropone.
  static Future<void> maybeShow(BuildContext context) async {
    if (!_onCanonicalHost) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) == true) return;
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Nuovo indirizzo'),
            content: const Text(
              'L’app è su www.gestopro360.it.\n\n'
              'Se vedi una barra bianca con l’URL in alto, stai usando '
              'l’icona/app vecchia (pernotti o gestopro.pages.dev).\n\n'
              'Cosa fare:\n'
              '1. Disinstalla / rimuovi l’app o il collegamento vecchio\n'
              '2. Apri www.gestopro360.it in Chrome o Edge\n'
              '3. Installa di nuovo l’app da questo sito '
              '(menu ⋮ → Installa app / Aggiungi a schermata Home)\n\n'
              'Poi riabilita le notifiche se non le ricevi più.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      await prefs.setBool(_prefsKey, true);
    } catch (_) {}
  }
}
