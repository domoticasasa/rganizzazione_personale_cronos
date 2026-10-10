import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import 'qt_carburante_verifica_service.dart';

abstract final class QtCarburanteVerificaExport {
  QtCarburanteVerificaExport._();

  static Uint8List buildExcelBytes({
    required QtCarburanteVerificaResult result,
    String? fileName,
    List<String>? fileNames,
    DateFormat? dateFmt,
    NumberFormat? numFmt,
  }) {
    final df = dateFmt ?? DateFormat('dd/MM/yyyy');
    final nf = numFmt ?? NumberFormat('#,##0.00', 'it_IT');
    final sources = _resolveFileNames(fileName, fileNames);
    final showSourceFile = _hasMultipleSources(result, sources);

    final workbook = Workbook();
    try {
      final transazioni = workbook.worksheets[0];
      transazioni.name = 'Transazioni';
      _writeTransazioniSheet(
        transazioni,
        result: result,
        fileNames: sources,
        showSourceFile: showSourceFile,
        df: df,
        nf: nf,
      );

      final perScheda = workbook.worksheets.addWithName('Per_scheda');
      _writeSchedeSheet(
        perScheda,
        result: result,
        fileNames: sources,
        df: df,
        nf: nf,
      );

      return Uint8List.fromList(workbook.saveAsStream());
    } finally {
      workbook.dispose();
    }
  }

  static List<String> _resolveFileNames(String? fileName, List<String>? fileNames) {
    if (fileNames != null && fileNames.isNotEmpty) {
      return fileNames.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    final single = fileName?.trim();
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  static bool _hasMultipleSources(
    QtCarburanteVerificaResult result,
    List<String> fileNames,
  ) {
    if (fileNames.length > 1) return true;
    final sources = result.righe
        .map((r) => r.transazione.fileSorgente?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    return sources.length > 1;
  }

  static int _writeRow(Worksheet sheet, int row, List<Object?> values) {
    for (var col = 0; col < values.length; col++) {
      final value = values[col];
      if (value == null) continue;
      final cell = sheet.getRangeByIndex(row, col + 1);
      if (value is num) {
        cell.number = value.toDouble();
      } else {
        cell.setText(value.toString());
      }
    }
    return row + 1;
  }

  static void _writeTransazioniSheet(
    Worksheet sheet, {
    required QtCarburanteVerificaResult result,
    required List<String> fileNames,
    required bool showSourceFile,
    required DateFormat df,
    required NumberFormat nf,
  }) {
    var row = 1;
    row = _writeRow(sheet, row, [
      'Verifica fatturazione carburante QT — transazioni',
    ]);
    for (var i = 0; i < fileNames.length; i++) {
      row = _writeRow(sheet, row, [
        fileNames.length == 1 ? 'File importato' : 'File ${i + 1}',
        fileNames[i],
      ]);
    }
    row = _writeRow(sheet, row, [
      'Periodo',
      '${df.format(result.dataMin)} – ${df.format(result.dataMax)}',
    ]);
    row = _writeRow(sheet, row, ['Totale transazioni', result.totale]);
    row = _writeRow(sheet, row, ['Giustificati', result.giustificati]);
    row = _writeRow(sheet, row, ['Mancanti', result.mancanti]);
    row = _writeRow(sheet, row, ['']);

    final headers = <String>[
      'Stato',
      if (showSourceFile) 'File fattura',
      'Responsabile alla data',
      'Assegnatario attuale multicard',
      'Da storico',
      'Commessa giustificativo',
      'Numero carta',
      'Data transazione',
      'Prodotto',
      'Volume (L)',
      'Importo (€)',
      'Registro',
      'Compilatore RCC',
      'Nota',
    ];
    row = _writeRow(sheet, row, headers);

    for (final r in result.righe) {
      final t = r.transazione;
      final ok = r.stato == QtCarburanteStatoVerifica.giustificato;
      row = _writeRow(sheet, row, [
        ok ? 'Giustificato' : 'Mancante',
        if (showSourceFile) (t.fileSorgente ?? ''),
        r.assegnatario ?? '',
        r.assegnatarioAttuale ?? '',
        r.responsabileDaStorico ? 'Sì' : '',
        r.rccCommessa ?? '',
        t.numeroCarta.trim(),
        df.format(t.dataTransazione),
        t.prodotto,
        nf.format(t.volume),
        nf.format(t.importo),
        ok ? 'Registro ${_fonteLabel(r.fonte)}' : '',
        r.rccNomeCognome ?? '',
        ok ? '' : (r.nota ?? ''),
      ]);
    }
  }

  static void _writeSchedeSheet(
    Worksheet sheet, {
    required QtCarburanteVerificaResult result,
    required List<String> fileNames,
    required DateFormat df,
    required NumberFormat nf,
  }) {
    var row = 1;
    row = _writeRow(sheet, row, [
      'Verifica fatturazione carburante QT — riepilogo per scheda',
    ]);
    for (var i = 0; i < fileNames.length; i++) {
      row = _writeRow(sheet, row, [
        fileNames.length == 1 ? 'File importato' : 'File ${i + 1}',
        fileNames[i],
      ]);
    }
    row = _writeRow(sheet, row, [
      'Periodo',
      '${df.format(result.dataMin)} – ${df.format(result.dataMax)}',
    ]);
    row = _writeRow(sheet, row, ['Schede nel file', result.perScheda.length]);
    row = _writeRow(sheet, row, ['']);

    row = _writeRow(sheet, row, [
      'Responsabile alla data',
      'Assegnatario attuale multicard',
      'Da storico',
      'Numero carta',
      'Commessa giustificativo',
      'Transazioni',
      'Giustificati',
      'Mancanti',
      'Importo totale (€)',
      'Importo giustificato (€)',
      'Importo da giustificare (€)',
    ]);

    for (final s in result.perScheda) {
      row = _writeRow(sheet, row, [
        s.assegnatario ?? '',
        s.assegnatarioAttuale ?? '',
        s.responsabileDaStorico ? 'Sì' : '',
        s.numeroCarta.trim(),
        s.commessa ?? '',
        s.totale,
        s.giustificati,
        s.mancanti,
        nf.format(s.importoTotale),
        nf.format(s.importoGiustificato),
        nf.format(s.importoMancante),
      ]);
    }
  }

  static String _fonteLabel(QtCarburanteFonteGiustificativo? fonte) {
    return switch (fonte) {
      QtCarburanteFonteGiustificativo.rccMdo => 'MDO',
      QtCarburanteFonteGiustificativo.rccStradali => 'Stradali',
      null => '',
    };
  }
}
