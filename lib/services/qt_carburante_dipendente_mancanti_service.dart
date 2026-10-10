import 'package:supabase_flutter/supabase_flutter.dart';

import 'mezzi_km_service.dart';
import 'qt_carburante_fattura_storage_service.dart';
import 'qt_carburante_fatturazione_parser.dart';
import 'qt_carburante_verifica_service.dart';
import 'qt_multicard_storico_assignee.dart';
import 'supabase_service.dart';

/// Giorno con almeno una transazione QT in fattura non ancora giustificata in RCC.
class QtScontrinoMancanteGiorno {
  const QtScontrinoMancanteGiorno({
    required this.data,
    required this.transazioni,
  });

  final DateTime data;
  final int transazioni;
}

/// Dettaglio transazione QT da giustificare.
class QtScontrinoMancanteDettaglio {
  const QtScontrinoMancanteDettaglio({
    required this.transazione,
    this.assegnatario,
    this.nota,
  });

  final QtCarburanteTrxRow transazione;
  final String? assegnatario;
  final String? nota;

  DateTime get data => transazione.dataTransazione;
  String get numeroCarta => transazione.numeroCarta;
  String get prodotto => transazione.prodotto;
  double get volume => transazione.volume;
  double get importo => transazione.importo;
}

class QtMancantiMeseResult {
  const QtMancantiMeseResult({
    required this.anno,
    required this.mese,
    required this.hasImport,
    required this.giorni,
    required this.dettagli,
  });

  final int anno;
  final int mese;
  final bool hasImport;
  final List<QtScontrinoMancanteGiorno> giorni;
  final List<QtScontrinoMancanteDettaglio> dettagli;

  bool get isEmpty => dettagli.isEmpty;
  int get totale => dettagli.length;
}

abstract final class QtCarburanteDipendenteMancantiService {
  QtCarburanteDipendenteMancantiService._();

  static ({int anno, int mese}) previousCalendarMonth([DateTime? now]) {
    final n = now ?? DateTime.now();
    final d = DateTime(n.year, n.month - 1, 1);
    return (anno: d.year, mese: d.month);
  }

  static String monthLabelIt(int mese, int anno) {
    const names = <String>[
      '',
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ];
    final name = (mese >= 1 && mese <= 12) ? names[mese] : '$mese';
    return '$name $anno';
  }

  static Future<List<QtScontrinoMancanteGiorno>> loadDateMancanti({
    required SupabaseClient supa,
    required int anno,
    required int mese,
    required String dipendenteNomeNorm,
  }) async {
    final res = await loadMancantiMese(
      supa: supa,
      anno: anno,
      mese: mese,
      dipendenteNomeNorm: dipendenteNomeNorm,
    );
    return res.giorni;
  }

  static Future<QtMancantiMeseResult> loadMancantiMesePrecedente({
    SupabaseClient? client,
    String? dipendenteNomeNorm,
  }) async {
    final prev = previousCalendarMonth();
    return loadMancantiMese(
      supa: client ?? SupabaseService.client,
      anno: prev.anno,
      mese: prev.mese,
      dipendenteNomeNorm: dipendenteNomeNorm,
    );
  }

  /// Ultimi [monthsBack] mesi calendario (più recenti prima).
  /// Di default tiene solo i mesi con fattura QT importata.
  static Future<List<QtMancantiMeseResult>> loadMancantiUltimiMesi({
    SupabaseClient? client,
    String? dipendenteNomeNorm,
    int monthsBack = 18,
    bool onlyWithImport = true,
  }) async {
    final supa = client ?? SupabaseService.client;
    final now = DateTime.now();
    final n = monthsBack.clamp(1, 36);
    final futures = <Future<QtMancantiMeseResult>>[];
    for (var i = 0; i < n; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      futures.add(
        loadMancantiMese(
          supa: supa,
          anno: d.year,
          mese: d.month,
          dipendenteNomeNorm: dipendenteNomeNorm,
        ),
      );
    }
    final all = await Future.wait(futures);
    final out = onlyWithImport
        ? all.where((r) => r.hasImport).toList(growable: false)
        : all;
    return out;
  }

  static Future<QtMancantiMeseResult> loadMancantiMese({
    required SupabaseClient supa,
    required int anno,
    required int mese,
    String? dipendenteNomeNorm,
  }) async {
    // Preferisci RPC (funziona anche per ruolo dipendente).
    try {
      final viaRpc = await _loadViaRpc(
        supa: supa,
        anno: anno,
        mese: mese,
      );
      if (viaRpc != null) return viaRpc;
    } catch (_) {}

    // Fallback admin/logistica: lettura diretta tabelle.
    return _loadViaDirectTables(
      supa: supa,
      anno: anno,
      mese: mese,
      dipendenteNomeNorm: (dipendenteNomeNorm ?? '').trim(),
    );
  }

  static Future<QtMancantiMeseResult?> _loadViaRpc({
    required SupabaseClient supa,
    required int anno,
    required int mese,
  }) async {
    final raw = await supa.rpc(
      'qt_carburante_my_mancanti_payload',
      params: {'p_anno': anno, 'p_mese': mese},
    );
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final hasImport = map['has_import'] == true;
    final trxRaw = map['transazioni'];
    final listTrx = trxRaw is List ? trxRaw : const [];
    if (!hasImport || listTrx.isEmpty) {
      return QtMancantiMeseResult(
        anno: anno,
        mese: mese,
        hasImport: hasImport,
        giorni: const [],
        dettagli: const [],
      );
    }

    final transazioni = <QtCarburanteTrxRow>[];
    final responsabili = <String, String>{};
    for (final item in listTrx) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final dataRaw = (row['data_transazione'] ?? '').toString();
      final data = DateTime.tryParse(dataRaw.split('T').first);
      if (data == null) continue;
      final trx = QtCarburanteTrxRow(
        rigaExcel: (row['riga_excel'] as num?)?.toInt() ?? 0,
        numeroCarta: (row['numero_carta'] ?? '').toString(),
        prodotto: (row['prodotto'] ?? '').toString(),
        dataTransazione: data,
        volume: (row['volume'] as num?)?.toDouble() ?? 0,
        importo: (row['importo'] as num?)?.toDouble() ?? 0,
        fileSorgente: (row['file_sorgente'] ?? '').toString().trim().isEmpty
            ? null
            : (row['file_sorgente'] ?? '').toString(),
      );
      transazioni.add(trx);
      final resp = (row['responsabile'] ?? '').toString().trim();
      if (resp.isNotEmpty) {
        responsabili[QtCarburanteFatturazioneParser.dedupeKey(trx)] = resp;
      }
    }

    if (transazioni.isEmpty) {
      return QtMancantiMeseResult(
        anno: anno,
        mese: mese,
        hasImport: hasImport,
        giorni: const [],
        dettagli: const [],
      );
    }

    final rccStradali = _asMapList(map['rcc_stradali']);
    final rccMdo = _asMapList(map['rcc_mdo']);
    final verifica = QtCarburanteVerificaService.verificaWithLocalPools(
      transazioni: transazioni,
      rccStradali: rccStradali,
      rccMdo: rccMdo,
      responsabiliByKey: responsabili,
      riferimentoAnno: anno,
      riferimentoMese: mese,
    );
    return _fromVerifica(
      anno: anno,
      mese: mese,
      hasImport: hasImport,
      verifica: verifica,
    );
  }

  static Future<QtMancantiMeseResult> _loadViaDirectTables({
    required SupabaseClient supa,
    required int anno,
    required int mese,
    required String dipendenteNomeNorm,
  }) async {
    final nomeNorm = dipendenteNomeNorm.trim();
    if (nomeNorm.isEmpty) {
      return QtMancantiMeseResult(
        anno: anno,
        mese: mese,
        hasImport: false,
        giorni: const [],
        dettagli: const [],
      );
    }

    final stored = await QtCarburanteFatturaStorageService.loadMese(
      supa,
      anno: anno,
      mese: mese,
    );
    if (stored == null || stored.transazioni.isEmpty) {
      return QtMancantiMeseResult(
        anno: anno,
        mese: mese,
        hasImport: stored != null,
        giorni: const [],
        dettagli: const [],
      );
    }

    final profiles = await QtMulticardStoricoAssigneeLoader.load(supa);
    final mieTransazioni = stored.transazioni.where((t) {
      final profile = QtMulticardStoricoAssigneeLoader.findProfile(
        t.cartaNorm,
        profiles,
      );
      if (profile == null) return false;
      final resp = profile.resolveAt(t.dataTransazione).responsabile ?? '';
      final respNorm = MezziKmService.normalizePersonName(resp);
      return respNorm.isNotEmpty && respNorm == nomeNorm;
    }).toList(growable: false);

    if (mieTransazioni.isEmpty) {
      return QtMancantiMeseResult(
        anno: anno,
        mese: mese,
        hasImport: true,
        giorni: const [],
        dettagli: const [],
      );
    }

    final verifica = await QtCarburanteVerificaService.verifica(
      supa: supa,
      transazioni: mieTransazioni,
      riferimentoAnno: anno,
      riferimentoMese: mese,
    );
    return _fromVerifica(
      anno: anno,
      mese: mese,
      hasImport: true,
      verifica: verifica,
    );
  }

  static List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static QtMancantiMeseResult _fromVerifica({
    required int anno,
    required int mese,
    required bool hasImport,
    required QtCarburanteVerificaResult verifica,
  }) {
    final dettagli = <QtScontrinoMancanteDettaglio>[];
    final perGiorno = <String, int>{};
    for (final r in verifica.righe) {
      if (r.stato != QtCarburanteStatoVerifica.mancante) continue;
      dettagli.add(
        QtScontrinoMancanteDettaglio(
          transazione: r.transazione,
          assegnatario: r.assegnatario,
          nota: r.nota,
        ),
      );
      final d = r.transazione.dataTransazione;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      perGiorno[key] = (perGiorno[key] ?? 0) + 1;
    }
    dettagli.sort((a, b) => a.data.compareTo(b.data));

    final giorni = perGiorno.entries
        .map((e) {
          final parts = e.key.split('-');
          if (parts.length != 3) return null;
          final y = int.tryParse(parts[0]);
          final mo = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y == null || mo == null || d == null) return null;
          return QtScontrinoMancanteGiorno(
            data: DateTime(y, mo, d),
            transazioni: e.value,
          );
        })
        .whereType<QtScontrinoMancanteGiorno>()
        .toList(growable: false)
      ..sort((a, b) => a.data.compareTo(b.data));

    return QtMancantiMeseResult(
      anno: anno,
      mese: mese,
      hasImport: hasImport,
      giorni: giorni,
      dettagli: dettagli,
    );
  }
}
