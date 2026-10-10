import 'package:supabase_flutter/supabase_flutter.dart';

import 'logistica_asset_storico_service.dart';
import 'qt_carburante_fatturazione_parser.dart';

/// Periodo di assegnazione multicard (storico o attuale).
class QtMulticardAssigneePeriod {
  const QtMulticardAssigneePeriod({
    required this.nome,
    required this.dal,
    this.al,
    required this.isHistorical,
  });

  final String nome;
  final String dal;
  final String? al;
  final bool isHistorical;

  bool containsIsoDate(String iso) {
    if (dal.isEmpty || nome.isEmpty) return false;
    if (iso.compareTo(dal) < 0) return false;
    final fine = al?.trim();
    if (fine != null && fine.isNotEmpty && iso.compareTo(fine) > 0) {
      return false;
    }
    return true;
  }

  int get spanDays {
    final start = DateTime.tryParse(dal);
    if (start == null) return 999999;
    final endIso = al?.trim();
    final end = (endIso != null && endIso.isNotEmpty)
        ? DateTime.tryParse(endIso)
        : DateTime(start.year + 50, start.month, start.day);
    if (end == null) return 999999;
    return end.difference(start).inDays.abs().clamp(0, 999999);
  }
}

/// Risultato risoluzione assegnatario per data transazione.
class QtMulticardAssigneeResolveResult {
  const QtMulticardAssigneeResolveResult({
    this.responsabile,
    this.assegnatarioAttuale,
    this.daStorico = false,
  });

  /// Chi doveva giustificare alla data del rifornimento.
  final String? responsabile;

  /// Assegnatario attuale sulla multicard (se noto).
  final String? assegnatarioAttuale;

  /// True se il responsabile alla data differisce dall'assegnatario attuale.
  final bool daStorico;
}

/// Profilo multicard con timeline assegnatari.
class QtMulticardAssigneeProfile {
  const QtMulticardAssigneeProfile({
    required this.cartaNorm,
    required this.cartaRaw,
    this.assegnatarioAttuale,
    this.targa,
    this.periods = const [],
  });

  final String cartaNorm;
  final String cartaRaw;
  final String? assegnatarioAttuale;
  final String? targa;
  final List<QtMulticardAssigneePeriod> periods;

  QtMulticardAssigneeResolveResult resolveAt(DateTime date) {
    final iso = QtMulticardStoricoAssigneeLoader.isoDay(date);
    final attuale = (assegnatarioAttuale ?? '').trim();

    final matches =
        periods.where((p) => p.containsIsoDate(iso)).toList(growable: false);
    if (matches.isEmpty) {
      return QtMulticardAssigneeResolveResult(
        responsabile: attuale.isEmpty ? null : attuale,
        assegnatarioAttuale: attuale.isEmpty ? null : attuale,
        daStorico: false,
      );
    }

    matches.sort((a, b) {
      if (a.isHistorical != b.isHistorical) {
        return a.isHistorical ? -1 : 1;
      }
      return a.spanDays.compareTo(b.spanDays);
    });

    final picked = matches.first.nome.trim();
    final diverso = attuale.isNotEmpty &&
        picked.toLowerCase() != attuale.toLowerCase();

    return QtMulticardAssigneeResolveResult(
      responsabile: picked.isEmpty ? null : picked,
      assegnatarioAttuale: attuale.isEmpty ? null : attuale,
      daStorico: diverso,
    );
  }

  QtMulticardAssigneeProfile withAssigneeFallback(String nome) {
    final n = nome.trim();
    if (n.isEmpty) return this;
    if ((assegnatarioAttuale ?? '').trim().isNotEmpty) return this;
    return QtMulticardAssigneeProfile(
      cartaNorm: cartaNorm,
      cartaRaw: cartaRaw,
      assegnatarioAttuale: n,
      targa: targa,
      periods: periods,
    );
  }
}

abstract final class QtMulticardStoricoAssigneeLoader {
  QtMulticardStoricoAssigneeLoader._();

  static Future<List<QtMulticardAssigneeProfile>> load(
    SupabaseClient supa,
  ) async {
    try {
      final multicardRes = await supa.from('logistica_multicard').select(
            'multicard,assegnatario_attuale,mezzo_targa,'
            'periodo_assegnatario_attuale,data_fine_assegnatario_attuale',
          );
      final storicoRes = await supa
          .from(LogisticaAssetStoricoService.table)
          .select(
            'identificativo,passaggio,assegnatario,periodo_dal,periodo_al',
          )
          .eq('tipo_asset', LogisticaAssetStoricoService.tipoMulticard);

      final storicoById = <String, List<Map<String, dynamic>>>{};
      for (final raw in storicoRes as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = (row['identificativo'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        storicoById.putIfAbsent(id, () => []).add(row);
      }

      final out = <QtMulticardAssigneeProfile>[];
      for (final raw in multicardRes as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final cartaRaw = (m['multicard'] ?? '').toString().trim();
        if (cartaRaw.isEmpty) continue;
        final cartaNorm = QtCarburanteTrxRow.normCarta(cartaRaw);
        final storicoRows = _storicoForCarta(
          cartaRaw: cartaRaw,
          cartaNorm: cartaNorm,
          storicoById: storicoById,
        );
        out.add(_profileFromMulticard(m, storicoRows));
      }
      return out;
    } catch (_) {
      return const <QtMulticardAssigneeProfile>[];
    }
  }

  static QtMulticardAssigneeProfile? findProfile(
    String cartaNorm,
    List<QtMulticardAssigneeProfile> pool,
  ) {
    for (final p in pool) {
      if (_carteMatch(cartaNorm, p.cartaNorm)) return p;
    }
    return null;
  }

  static List<Map<String, dynamic>> _storicoForCarta({
    required String cartaRaw,
    required String cartaNorm,
    required Map<String, List<Map<String, dynamic>>> storicoById,
  }) {
    final direct = storicoById[cartaRaw];
    if (direct != null && direct.isNotEmpty) return direct;

    for (final entry in storicoById.entries) {
      if (_carteMatch(cartaNorm, QtCarburanteTrxRow.normCarta(entry.key))) {
        return entry.value;
      }
    }
    return const [];
  }

  static QtMulticardAssigneeProfile _profileFromMulticard(
    Map<String, dynamic> m,
    List<Map<String, dynamic>> storicoRows,
  ) {
    final cartaRaw = (m['multicard'] ?? '').toString().trim();
    final cartaNorm = QtCarburanteTrxRow.normCarta(cartaRaw);
    final attuale = (m['assegnatario_attuale'] ?? '').toString().trim();
    final targa = (m['mezzo_targa'] ?? '').toString().trim();

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
      cartaNorm: cartaNorm,
      cartaRaw: cartaRaw,
      assegnatarioAttuale: attuale.isEmpty ? null : attuale,
      targa: targa.isEmpty ? null : targa,
      periods: periods,
    );
  }

  static bool _carteMatch(String a, String b) {
    final da = QtCarburanteTrxRow.normCarta(a);
    final db = QtCarburanteTrxRow.normCarta(b);
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    if (da.length > db.length && da.endsWith(db)) return true;
    if (db.length > da.length && db.endsWith(da)) return true;
    return false;
  }

  static String _isoFromDb(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    return s.split('T').first.split(' ').first;
  }

  static String isoDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
