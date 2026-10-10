// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void configureAppUrlStrategy() {
  // Path URL: `/login#access_token=…` resta un hash auth, non una rotta `#/login`.
  usePathUrlStrategy();
}

void restoreSupabaseAuthCallbackFromStorage() {
  try {
    final loc = html.window.location;
    final storedHash = html.window.sessionStorage['cronos_supabase_auth_hash'];
    final storedSearch =
        html.window.sessionStorage['cronos_supabase_auth_search'];
    final rawPath = loc.pathname;
    final path = (rawPath == null || rawPath.isEmpty) ? '/' : rawPath;
    var search = loc.search ?? '';
    var hash = loc.hash;

    if (storedSearch != null &&
        (storedSearch.contains('code=') ||
            storedSearch.contains('token_hash=')) &&
        !search.contains('code=') &&
        !search.contains('token_hash=')) {
      search = storedSearch.startsWith('?') ? storedSearch : '?$storedSearch';
    }
    if (storedHash != null &&
        storedHash.isNotEmpty &&
        !hash.contains('access_token') &&
        !hash.contains('type=recovery')) {
      hash = storedHash.startsWith('#') ? storedHash : '#$storedHash';
    } else if (hash == '#/login' || hash == '#/') {
      if (storedHash != null && storedHash.contains('access_token')) {
        hash = storedHash.startsWith('#') ? storedHash : '#$storedHash';
      }
    }

    html.window.history.replaceState(null, '', '$path$search$hash');
  } catch (_) {}
}

bool storedAuthCallbackLooksLikeRecovery() {
  try {
    final stored = html.window.sessionStorage['cronos_supabase_auth_hash'] ?? '';
    final search = html.window.sessionStorage['cronos_supabase_auth_search'] ?? '';
    final th = html.window.sessionStorage['cronos_recovery_token_hash'] ?? '';
    return stored.contains('type=recovery') ||
        stored.contains('access_token') ||
        search.contains('code=') ||
        search.contains('token_hash=') ||
        th.isNotEmpty;
  } catch (_) {
    return false;
  }
}

String? readStoredRecoveryTokenHash() {
  try {
    final th = html.window.sessionStorage['cronos_recovery_token_hash'] ?? '';
    if (th.trim().isNotEmpty) return th.trim();
    final search = html.window.sessionStorage['cronos_supabase_auth_search'] ?? '';
    if (search.isEmpty) return null;
    final q = search.startsWith('?') ? search.substring(1) : search;
    return Uri.splitQueryString(q)['token_hash']?.trim();
  } catch (_) {
    return null;
  }
}

void clearStoredAuthCallback() {
  try {
    html.window.sessionStorage.remove('cronos_supabase_auth_hash');
    html.window.sessionStorage.remove('cronos_supabase_auth_search');
    html.window.sessionStorage.remove('cronos_recovery_token_hash');
  } catch (_) {}
}

void stripAuthQueryFromUrl() {
  try {
    final loc = html.window.location;
    final uri = Uri.parse(loc.href);
    final qp = Map<String, String>.from(uri.queryParameters);
    if (!qp.containsKey('token_hash') &&
        !qp.containsKey('code') &&
        qp['type'] != 'recovery') {
      return;
    }
    qp.remove('token_hash');
    qp.remove('code');
    qp.remove('type');
    final cleaned = uri.replace(
      queryParameters: qp.isEmpty ? null : qp,
      fragment: '',
    );
    html.window.history.replaceState(null, '', cleaned.toString());
  } catch (_) {}
}

String? readStoredViaggioMezzoVm() {
  try {
    final vm = html.window.sessionStorage['cronos_viaggio_mezzo_vm'] ?? '';
    if (vm.trim().isNotEmpty) return vm.trim();
  } catch (_) {}
  return null;
}

void clearStoredViaggioMezzoVm() {
  try {
    html.window.sessionStorage.remove('cronos_viaggio_mezzo_vm');
  } catch (_) {}
}

String? readStoredBuonoPastoBp() {
  try {
    final bp = html.window.sessionStorage['cronos_buono_pasto_bp'] ?? '';
    if (bp.trim().isNotEmpty) return bp.trim();
  } catch (_) {}
  return null;
}

void clearStoredBuonoPastoBp() {
  try {
    html.window.sessionStorage.remove('cronos_buono_pasto_bp');
  } catch (_) {}
}
