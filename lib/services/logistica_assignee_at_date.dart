import 'package:supabase_flutter/supabase_flutter.dart';

import 'logistica_asset_storico_service.dart';
import 'mezzi_km_service.dart';
import 'qt_multicard_storico_assignee.dart';

/// Verifica assegnatario mezzo/multicard alla data del rifornimento (anche storico).
abstract final class LogisticaAssigneeAtDate {
  LogisticaAssigneeAtDate._();

  static bool userMatchesResolvedName({
    required String? responsabileAllaData,
    required String nameNorm,
  }) {
    final resp = (responsabileAllaData ?? '').trim();
    if (resp.isEmpty || nameNorm.trim().isEmpty) return false;
    return MezziKmService.namesReferToSamePerson(resp, nameNorm);
  }

  static bool wasMulticardAssigneeAtDate({
    required QtMulticardAssigneeProfile? profile,
    required DateTime date,
    required String nameNorm,
    required String userUuid,
    Map<String, dynamic>? multicardRow,
  }) {
    if (profile != null) {
      final resolved = profile.resolveAt(date);
      if (userMatchesResolvedName(
        responsabileAllaData: resolved.responsabile,
        nameNorm: nameNorm,
      )) {
        return true;
      }
    }
    if (multicardRow != null) {
      return MezziKmService.isRowAssignedToCurrentUser(
        multicardRow,
        userUuid,
        nameNorm,
      );
    }
    return false;
  }

  static bool wasMezzoAssigneeAtDate({
    required QtMulticardAssigneeProfile? profile,
    required DateTime date,
    required String nameNorm,
    required String userUuid,
    Map<String, dynamic>? mezzoRow,
  }) {
    if (profile != null) {
      final resolved = profile.resolveAt(date);
      if (userMatchesResolvedName(
        responsabileAllaData: resolved.responsabile,
        nameNorm: nameNorm,
      )) {
        return true;
      }
    }
    if (mezzoRow != null) {
      return MezziKmService.isRowAssignedToCurrentUser(
        mezzoRow,
        userUuid,
        nameNorm,
      );
    }
    return false;
  }
}

/// Timeline assegnatari mezzo stradale (stessa struttura multicard).
abstract final class MezzoStoricoAssigneeLoader {
  MezzoStoricoAssigneeLoader._();

  static Future<List<QtMulticardAssigneeProfile>> load(
    SupabaseClient supa,
  ) async {
    try {
      final mezziRes = await supa.from('logistica_mezzi_stradali').select(
            'id_uuid,targa,assegnatario_attuale,'
            'periodo_assegnatario_attuale,data_fine_assegnatario_attuale',
          );
      final storicoRes = await supa
          .from(LogisticaAssetStoricoService.table)
          .select(
            'identificativo,passaggio,assegnatario,periodo_dal,periodo_al',
          )
          .eq('tipo_asset', LogisticaAssetStoricoService.tipoMezzo);

      final storicoByTarga = <String, List<Map<String, dynamic>>>{};
      for (final raw in storicoRes as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = (row['identificativo'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        storicoByTarga.putIfAbsent(id, () => []).add(row);
      }

      final out = <QtMulticardAssigneeProfile>[];
      for (final raw in mezziRes as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final targa = (m['targa'] ?? '').toString().trim();
        if (targa.isEmpty) continue;
        final targaKey = targa.toLowerCase();
        final storicoRows = storicoByTarga[targa] ??
            storicoByTarga[targaKey] ??
            const <Map<String, dynamic>>[];
        out.add(_profileFromMezzo(m, storicoRows));
      }
      return out;
    } catch (_) {
      return const <QtMulticardAssigneeProfile>[];
    }
  }

  static QtMulticardAssigneeProfile? findByTarga(
    String targa,
    List<QtMulticardAssigneeProfile> pool,
  ) {
    final t = targa.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final p in pool) {
      if ((p.targa ?? '').trim().toLowerCase() == t) return p;
      if (p.cartaRaw.trim().toLowerCase() == t) return p;
    }
    return null;
  }

  static QtMulticardAssigneeProfile _profileFromMezzo(
    Map<String, dynamic> m,
    List<Map<String, dynamic>> storicoRows,
  ) {
    final targa = (m['targa'] ?? '').toString().trim();
    final attuale = (m['assegnatario_attuale'] ?? '').toString().trim();
    final periods = <QtMulticardAssigneePeriod>[];

    final sortedStorico = [...storicoRows]
      ..sort((a, b) {
        final pa = int.tryParse((a['passaggio'] ?? '').toString()) ?? 0;
        final pb = int.tryParse((b['passaggio'] ?? '').toString()) ?? 0;
        return pa.compareTo(pb);
      });

    for (final row in sortedStorico) {
      final nome = (row['assegnatario'] ?? '').toString().trim();
      final dal = _isoFromDb(row['periodo_dal']);
      final al = _isoFromDb(row['periodo_al']);
      if (nome.isEmpty || dal.isEmpty) continue;
      periods.add(
        QtMulticardAssigneePeriod(
          nome: nome,
          dal: dal,
          al: al.isEmpty ? null : al,
          isHistorical: true,
        ),
      );
    }

    final dalAtt = _isoFromDb(m['periodo_assegnatario_attuale']);
    final alAtt = _isoFromDb(m['data_fine_assegnatario_attuale']);
    if (attuale.isNotEmpty && dalAtt.isNotEmpty) {
      periods.add(
        QtMulticardAssigneePeriod(
          nome: attuale,
          dal: dalAtt,
          al: alAtt.isEmpty ? null : alAtt,
          isHistorical: false,
        ),
      );
    }

    return QtMulticardAssigneeProfile(
      cartaNorm: targa.toLowerCase(),
      cartaRaw: targa,
      assegnatarioAttuale: attuale.isEmpty ? null : attuale,
      targa: targa,
      periods: periods,
    );
  }

  static String _isoFromDb(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    return s.split('T').first.split(' ').first;
  }
}
