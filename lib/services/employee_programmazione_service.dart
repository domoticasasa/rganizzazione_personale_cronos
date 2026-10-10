import 'package:supabase_flutter/supabase_flutter.dart';

import 'formazione_programmazione_service.dart';
import 'formazione_rfi_programmazione_service.dart';
import 'supabase_service.dart';

/// Anagrafica dipendente e corsi D.Lgs. con data programmazione (`prima_data`).
class EmployeeProgrammazioneService {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String _normPersonName(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Set<String> _personNameMatchKeys(String raw) {
    final n = _normPersonName(raw);
    if (n.isEmpty) return const {};
    final parts = n.split(' ').where((p) => p.isNotEmpty).toList();
    final keys = <String>{n};
    if (parts.length >= 2) {
      keys.add('${parts.first} ${parts.last}');
      keys.add('${parts.last} ${parts.first}');
      keys.add(parts.reversed.join(' '));
    }
    return keys;
  }

  static Future<String?> resolveOwnPersonaleUuid({String? employeeFullName}) async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser != null) {
      try {
        final p1 = await SupabaseService.client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', authUser.id)
            .maybeSingle();
        final pid1 = _s(p1?['id_uuid']);
        if (pid1.isNotEmpty) return pid1;

        final u = await SupabaseService.client
            .from('users')
            .select('id, id_uuid, full_name')
            .eq('auth_id', authUser.id)
            .maybeSingle();
        final uid = _s(u?['id']);
        final uuid = _s(u?['id_uuid']);
        if (uid.isNotEmpty) {
          final p2 = await SupabaseService.client
              .from('personale')
              .select('id_uuid')
              .eq('user_id', uid)
              .maybeSingle();
          final pid2 = _s(p2?['id_uuid']);
          if (pid2.isNotEmpty) return pid2;
        }
        if (uuid.isNotEmpty) {
          final p3 = await SupabaseService.client
              .from('personale')
              .select('id_uuid')
              .eq('user_id', uuid)
              .maybeSingle();
          final pid3 = _s(p3?['id_uuid']);
          if (pid3.isNotEmpty) return pid3;
        }
      } catch (_) {}
    }

    final namesToTry = <String>{
      if ((employeeFullName ?? '').trim().isNotEmpty) employeeFullName!.trim(),
    };
    try {
      if (authUser != null) {
        final u = await SupabaseService.client
            .from('users')
            .select('full_name')
            .eq('auth_id', authUser.id)
            .maybeSingle();
        final fn = _s(u?['full_name']);
        if (fn.isNotEmpty) namesToTry.add(fn);
      }
    } catch (_) {}

    final wanted = <String>{};
    for (final name in namesToTry) {
      wanted.addAll(_personNameMatchKeys(name));
    }
    if (wanted.isEmpty) return null;

    try {
      final personaleRes = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name');
      for (final e in (personaleRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = _s(m['id_uuid']);
        final fn = _s(m['full_name']);
        if (id.isEmpty || fn.isEmpty) continue;
        if (wanted.contains(_normPersonName(fn))) return id;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> hasScheduledForCurrentUser({String? employeeFullName}) async {
    final pid = await resolveOwnPersonaleUuid(employeeFullName: employeeFullName);
    if (pid == null || pid.isEmpty) return false;
    try {
      try {
        final rpc = await SupabaseService.client.rpc(
          'formazione_corsi_programmazione_rows',
          params: <String, dynamic>{'p_only_personale_uuid': pid},
        );
        final now = DateTime.now();
        final refDay = DateTime(now.year, now.month, now.day);
        for (final e in (rpc as List)) {
          final row = Map<String, dynamic>.from(e as Map);
          if (!FormazioneProgrammazioneService.shouldClearAfterProgrammazione(
            row,
            refDay,
          )) {
            return true;
          }
        }
        return false;
      } catch (_) {
        final res = await SupabaseService.client
            .from('formazione_corsi')
            .select('id, prima_data, seconda_data')
            .eq('personale_id', pid)
            .not('prima_data', 'is', null);
        final now = DateTime.now();
        final refDay = DateTime(now.year, now.month, now.day);
        for (final e in (res as List)) {
          final row = Map<String, dynamic>.from(e as Map);
          if (!FormazioneProgrammazioneService.shouldClearAfterProgrammazione(
            row,
            refDay,
          )) {
            return true;
          }
        }
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Corsi RFI programmati (data dal) ancora visibili per il dipendente corrente.
  static Future<bool> hasRfiScheduledForCurrentUser({
    String? employeeFullName,
  }) async {
    final pid = await resolveOwnPersonaleUuid(employeeFullName: employeeFullName);
    if (pid == null || pid.isEmpty) return false;
    try {
      final rows = await FormazioneRfiProgrammazioneService.loadProgrammazioneRows(
        onlyPersonaleUuid: pid,
        purgeExpired: false,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
