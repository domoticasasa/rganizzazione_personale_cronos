import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;

import '../services/carburante_giustificativi_stats_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_web_safe.dart';

class CarburanteGiustificativiExcelExport {
  static const List<String> _monthNames = <String>[
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

  static String monthLabel(int year, int month) =>
      '${_monthNames[month - 1]} $year';

  static Uint8List build({
    required int year,
    required int month,
    required CarburanteGiustificativiStats stats,
    required List<Map<String, dynamic>> rccRows,
    required List<Map<String, dynamic>> mdoRows,
  }) {
    final excel = Excel.createExcel();
    final riepilogo = excelUseDefaultSheet(excel);
    final dettaglioRcc = excel['Dettaglio RCC'];
    final dettaglioMdo = excel['Dettaglio MDO'];

    riepilogo.appendRow([
      'Mese',
      monthLabel(year, month),
    ]);
    riepilogo.appendRow(const []);
    riepilogo.appendRow([
      'Categoria',
      'Giustificativi',
      'Litri',
      'Euro',
      '€/litro medio',
    ]);

    void addSummaryRow(
      String label,
      int count,
      double litri,
      double euro,
    ) {
      riepilogo.appendRow([
        label,
        count,
        litri,
        euro,
        litri > 0 ? euro / litri : null,
      ]);
    }

    final perTipo = stats.perTipo;
    addSummaryRow('RCC Stradali', stats.rccCount, stats.rccLitri, stats.rccEuro);
    addSummaryRow('MDO', stats.mdoCount, stats.mdoLitri, stats.mdoEuro);
    addSummaryRow('Totale', stats.totalCount, stats.totalLitri, stats.totalEuro);
    addSummaryRow(
      'Totale Benzina',
      perTipo.benzina.count,
      perTipo.benzina.litri,
      perTipo.benzina.euro,
    );
    addSummaryRow(
      'Totale Gasolio',
      perTipo.gasolio.count,
      perTipo.gasolio.litri,
      perTipo.gasolio.euro,
    );
    addSummaryRow(
      'Totale HVO',
      perTipo.hvo.count,
      perTipo.hvo.litri,
      perTipo.hvo.euro,
    );
    addSummaryRow(
      'Totale AdBlue',
      perTipo.adBlue.count,
      perTipo.adBlue.litri,
      perTipo.adBlue.euro,
    );

    dettaglioRcc.appendRow([
      'Data',
      'Tipo carburante',
      'Litri',
      'Euro',
      'Carta',
      'Nome',
      'Cantiere',
    ]);
    for (final r in rccRows) {
      dettaglioRcc.appendRow([
        formatDateDdMmYyyy(r['data_rifornimento']),
        (r['tipo_carburante'] ?? '').toString(),
        _toNum(r['litri']),
        _toNum(r['euro']),
        (r['n_carta_carburante'] ?? '').toString(),
        (r['nome_cognome'] ?? '').toString(),
        (r['cantiere'] ?? '').toString(),
      ]);
    }

    dettaglioMdo.appendRow([
      'Data',
      'Tipo carburante',
      'Litri',
      'Euro',
      'Nome',
      'Mezzo MDO',
      'Cantiere',
    ]);
    for (final r in mdoRows) {
      dettaglioMdo.appendRow([
        formatDateDdMmYyyy(r['data_rifornimento']),
        (r['tipo_carburante'] ?? '').toString(),
        _toNum(r['litri']),
        _toNum(r['euro']),
        (r['nome_cognome'] ?? '').toString(),
        (r['automezzo_mdo'] ?? '').toString(),
        (r['cantiere'] ?? '').toString(),
      ]);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  static double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  static String fileNameForMonth(int year, int month) {
    final m = month.toString().padLeft(2, '0');
    return 'Riepilogo_giustificativi_${year}_$m';
  }
}
