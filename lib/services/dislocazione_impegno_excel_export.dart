import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/dislocazione_period_utils.dart';
import '../utils/excel_template_assets.dart';
import 'dislocazione_personale_service.dart';
import 'template_xlsx_zip_fill.dart';

class _FillTemplateJob {
  const _FillTemplateJob(this.templateBytes, this.payload);

  final Uint8List templateBytes;
  final Map<String, String> payload;
}

Uint8List _fillTemplateInIsolate(_FillTemplateJob job) {
  return TemplateXlsxZipFill.fill(
    templateBytes: job.templateBytes,
    sheetName: DislocazioneImpegnoExcelExport.sheetName,
    payload: job.payload,
    forceTextValues: true,
  );
}

/// Compila [Programma_impegno_personale_mod.xlsx] preservando layout e stili.
class DislocazioneImpegnoExcelExport {
  DislocazioneImpegnoExcelExport._();

  static const sheetName = 'Maestranze';  static const _firstDataRow = 4;
  static const _maxPersonRows = 500;
  static const _dateColCount = 407;
  static const _firstDateCol = 2; // B

  /// Intervallo date del template (01/12/2025 – 30/12/2026).
  static final DateTime templatePeriodStart = DateTime(2025, 12, 1);
  static final DateTime templatePeriodEnd = DateTime(2026, 12, 30);

  static Future<Uint8List> build({
    required List<PersonaRiga> persone,
    required Map<String, Map<DateTime, DislocazioneGiornoValore>> cacheGiorni,
    required Map<String, String> commesse,
  }) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.programmaImpegnoPersonale);
    final templateBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError(
        'Template Programma_impegno_personale_mod.xlsx non disponibile negli asset.',
      );
    }

    final payload = _buildPayload(
      persone: persone,
      cacheGiorni: cacheGiorni,
      commesse: commesse,
    );

    return compute(
      _fillTemplateInIsolate,
      _FillTemplateJob(templateBytes, payload),
    );
  }

  static Map<String, String> _buildPayload({
    required List<PersonaRiga> persone,
    required Map<String, Map<DateTime, DislocazioneGiornoValore>> cacheGiorni,
    required Map<String, String> commesse,
  }) {
    final dateCols = _dateColumnsTemplate();
    final nomKeys = _nominativoKeys(cacheGiorni);
    final sorted = List<PersonaRiga>.from(persone)
      ..sort((a, b) => a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase()));

    if (sorted.length > _maxPersonRows) {
      throw StateError(
        'Troppi nominativi (${sorted.length}): il template supporta al massimo $_maxPersonRows.',
      );
    }

    final payload = <String, String>{};

    const weekdays = <String>[
      'lunedi',
      'martedi',
      'mercoledi',
      'giovedi',
      'venerdi',
      'sabato',
      'domenica',
    ];
    for (final dc in dateCols.entries) {
      payload[TemplateXlsxZipFill.cellRef(dc.value, 2)] = weekdays[dc.key.weekday - 1];
    }

    for (var i = 0; i < sorted.length; i++) {
      final persona = sorted[i];
      final row = _firstDataRow + i;
      payload[TemplateXlsxZipFill.cellRef(1, row)] = persona.nominativo;
      for (final dc in dateCols.entries) {
        final val = _valorePerNominativo(
          persona.nominativo,
          dc.key,
          cacheGiorni,
          nomKeys,
        );
        if (val == null || val.isEmpty) continue;
        payload[TemplateXlsxZipFill.cellRef(dc.value, row)] = _testoCella(val, commesse);
      }
    }

    return payload;
  }

  static Map<String, Map<DateTime, DislocazioneGiornoValore>> cacheDaRighe(
    Iterable<Map<String, dynamic>> righe,
  ) {
    final byNom = <String, List<Map<String, dynamic>>>{};
    for (final r in righe) {
      final n = (r['nominativo'] ?? '').toString().trim();
      if (n.isEmpty) continue;
      byNom.putIfAbsent(n, () => <Map<String, dynamic>>[]).add(r);
    }
    final out = <String, Map<DateTime, DislocazioneGiornoValore>>{};
    for (final e in byNom.entries) {
      out[e.key] = espandiPeriodi(e.value);
    }
    return out;
  }

  static Map<DateTime, int> _dateColumnsTemplate() {
    final out = <DateTime, int>{};
    for (var i = 0; i < _dateColCount; i++) {
      final d = dateOnly(templatePeriodStart.add(Duration(days: i)));
      out[d] = _firstDateCol + i;
    }
    return out;
  }

  static Map<String, String> _nominativoKeys(
    Map<String, Map<DateTime, DislocazioneGiornoValore>> cache,
  ) {
    final out = <String, String>{};
    for (final k in cache.keys) {
      out[k.trim().toUpperCase()] = k;
    }
    return out;
  }

  static DislocazioneGiornoValore? _valorePerNominativo(
    String nominativo,
    DateTime giorno,
    Map<String, Map<DateTime, DislocazioneGiornoValore>> cache,
    Map<String, String> nomKeys,
  ) {
    final d = dateOnly(giorno);
    final direct = cache[nominativo]?[d];
    if (direct != null && !direct.isEmpty) return direct;
    final key = nomKeys[nominativo.trim().toUpperCase()];
    if (key != null) {
      final v = cache[key]?[d];
      if (v != null && !v.isEmpty) return v;
    }
    for (final entry in cache.entries) {
      if (entry.key.trim().toUpperCase() != nominativo.trim().toUpperCase()) continue;
      final v = entry.value[d];
      if (v != null && !v.isEmpty) return v;
    }
    return null;
  }

  static String _testoCella(
    DislocazioneGiornoValore valore,
    Map<String, String> commesse,
  ) {
    if (valore.commessaId != null && valore.commessaId!.isNotEmpty) {
      final nome = (commesse[valore.commessaId!] ?? '').trim();
      if (nome.isEmpty) return valore.commessaId!;
      final sp = nome.indexOf(' ');
      return sp > 0 ? nome.substring(0, sp) : nome;
    }
    return valore.stato ?? '';
  }
}
