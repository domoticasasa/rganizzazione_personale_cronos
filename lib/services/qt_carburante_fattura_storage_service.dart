import 'package:supabase_flutter/supabase_flutter.dart';

import 'qt_carburante_fatturazione_parser.dart';

class QtFatturaMeseIndex {
  const QtFatturaMeseIndex({
    required this.anno,
    required this.mese,
    required this.fileNames,
    required this.transazioniCount,
    required this.importedAt,
  });

  final int anno;
  final int mese;
  final List<String> fileNames;
  final int transazioniCount;
  final DateTime? importedAt;
}

class QtFatturaMeseCaricato {
  const QtFatturaMeseCaricato({
    required this.fileNames,
    required this.transazioni,
    this.avviso,
  });

  final List<String> fileNames;
  final List<QtCarburanteTrxRow> transazioni;
  final String? avviso;
}

abstract final class QtCarburanteFatturaStorageService {
  QtCarburanteFatturaStorageService._();

  static Future<List<QtFatturaMeseIndex>> listMesi(SupabaseClient supa) async {
    final res = await supa
        .from('logistica_qt_fattura_import')
        .select(
          'anno,mese,file_names,imported_at,'
          'logistica_qt_fattura_transazione(count)',
        )
        .order('anno', ascending: false)
        .order('mese', ascending: false);

    final out = <QtFatturaMeseIndex>[];
    for (final raw in res as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final anno = (row['anno'] as num?)?.toInt();
      final mese = (row['mese'] as num?)?.toInt();
      if (anno == null || mese == null) continue;

      var count = 0;
      final countRaw = row['logistica_qt_fattura_transazione'];
      if (countRaw is List && countRaw.isNotEmpty) {
        final first = countRaw.first;
        if (first is Map) {
          count = (first['count'] as num?)?.toInt() ?? 0;
        }
      }

      final filesRaw = row['file_names'];
      final fileNames = filesRaw is List
          ? filesRaw.map((e) => e.toString()).toList(growable: false)
          : const <String>[];

      out.add(
        QtFatturaMeseIndex(
          anno: anno,
          mese: mese,
          fileNames: fileNames,
          transazioniCount: count,
          importedAt: DateTime.tryParse((row['imported_at'] ?? '').toString()),
        ),
      );
    }
    return out;
  }

  static Future<QtFatturaMeseCaricato?> loadMese(
    SupabaseClient supa, {
    required int anno,
    required int mese,
  }) async {
    final importRes = await supa
        .from('logistica_qt_fattura_import')
        .select('id_uuid,file_names,avviso')
        .eq('anno', anno)
        .eq('mese', mese)
        .maybeSingle();
    if (importRes == null) return null;

    final importId = (importRes['id_uuid'] ?? '').toString();
    if (importId.isEmpty) return null;

    final trxRes = await supa
        .from('logistica_qt_fattura_transazione')
        .select(
          'riga_excel,numero_carta,prodotto,data_transazione,volume,importo,file_sorgente',
        )
        .eq('import_id_uuid', importId)
        .order('data_transazione')
        .order('numero_carta');

    final filesRaw = importRes['file_names'];
    final fileNames = filesRaw is List
        ? filesRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final transazioni = <QtCarburanteTrxRow>[];
    for (final raw in trxRes as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final dataRaw = (row['data_transazione'] ?? '').toString();
      final data = DateTime.tryParse(dataRaw.split('T').first);
      if (data == null) continue;
      transazioni.add(
        QtCarburanteTrxRow(
          rigaExcel: (row['riga_excel'] as num?)?.toInt() ?? 0,
          numeroCarta: (row['numero_carta'] ?? '').toString(),
          prodotto: (row['prodotto'] ?? '').toString(),
          dataTransazione: DateTime(data.year, data.month, data.day),
          volume: (row['volume'] as num?)?.toDouble() ?? 0,
          importo: (row['importo'] as num?)?.toDouble() ?? 0,
          fileSorgente: (row['file_sorgente'] ?? '').toString().trim().isEmpty
              ? null
              : (row['file_sorgente'] ?? '').toString(),
        ),
      );
    }

    return QtFatturaMeseCaricato(
      fileNames: fileNames,
      transazioni: transazioni,
      avviso: (importRes['avviso'] ?? '').toString().trim().isEmpty
          ? null
          : (importRes['avviso'] ?? '').toString(),
    );
  }

  static Future<void> saveMese(
    SupabaseClient supa, {
    required int anno,
    required int mese,
    required QtCarburanteMergedParseResult merged,
  }) async {
    final userUuidRes = await supa.rpc('current_user_uuid');
    final userUuid = userUuidRes?.toString().trim();

    final existing = await supa
        .from('logistica_qt_fattura_import')
        .select('id_uuid')
        .eq('anno', anno)
        .eq('mese', mese)
        .maybeSingle();

    late final String importId;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (existing != null) {
      importId = (existing['id_uuid'] ?? '').toString();
      await supa.from('logistica_qt_fattura_import').update({
        'file_names': merged.fileNames,
        'avviso': merged.avviso,
        'imported_by_user_uuid': userUuid,
        'updated_at': nowIso,
        'imported_at': nowIso,
      }).eq('id_uuid', importId);

      await supa
          .from('logistica_qt_fattura_transazione')
          .delete()
          .eq('import_id_uuid', importId);
    } else {
      final inserted = await supa
          .from('logistica_qt_fattura_import')
          .insert({
            'anno': anno,
            'mese': mese,
            'file_names': merged.fileNames,
            'avviso': merged.avviso,
            'imported_by_user_uuid': userUuid,
          })
          .select('id_uuid')
          .single();
      importId = (inserted['id_uuid'] ?? '').toString();
    }

    if (merged.righe.isEmpty) return;

    final payload = merged.righe
        .map(
          (r) => {
            'import_id_uuid': importId,
            'riga_excel': r.rigaExcel,
            'numero_carta': r.numeroCarta,
            'prodotto': r.prodotto,
            'data_transazione': r.isoData,
            'volume': r.volume,
            'importo': r.importo,
            'file_sorgente': r.fileSorgente,
            'dedup_key': QtCarburanteFatturazioneParser.dedupeKey(r),
          },
        )
        .toList(growable: false);

    await supa.from('logistica_qt_fattura_transazione').insert(payload);
  }
}
