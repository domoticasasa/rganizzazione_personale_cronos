import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

enum UqsaExportTone { ok, warn, critical, empty }

class UqsaSediSicurezzaAssetLine {
  const UqsaSediSicurezzaAssetLine({
    required this.label,
    required this.scadenza,
    required this.tone,
  });

  final String label;
  final String scadenza;
  final UqsaExportTone tone;
}

class UqsaSediSicurezzaExportRow {
  const UqsaSediSicurezzaExportRow({
    required this.index,
    required this.ubicante,
    required this.tipologia,
    required this.commessa,
    required this.posizione,
    required this.estintori,
    required this.casette,
    required this.stato,
    required this.statoTone,
  });

  final int index;
  final String ubicante;
  final String tipologia;
  final String commessa;
  final String posizione;
  final List<UqsaSediSicurezzaAssetLine> estintori;
  final List<UqsaSediSicurezzaAssetLine> casette;
  final String stato;
  final UqsaExportTone statoTone;
}

class UqsaSediSicurezzaExportSheet {
  const UqsaSediSicurezzaExportSheet({
    required this.name,
    required this.tabLabel,
    required this.summary,
    required this.rows,
  });

  final String name;
  final String tabLabel;
  final String summary;
  final List<UqsaSediSicurezzaExportRow> rows;
}

/// Excel UQSA Sedi sicurezza: stesse colonne, colori e celle multilinea della pagina.
abstract final class UqsaSediSicurezzaExcelExport {
  UqsaSediSicurezzaExcelExport._();

  static const _colCount = 8;
  static const _headerGreen = '#D6E4C7';
  static const _headerEst = '#F3C4C4';
  static const _headerCas = '#C9D6F2';
  static const _titleBlue = '#1565C0';
  static const _evenRow = '#FFFFFF';
  static const _oddRow = '#EEF3EA';
  static const _text = '#212121';
  static const _muted = '#607D8B';
  static const _critical = '#B71C1C';
  static const _warn = '#E65100';
  static const _ok = '#1B5E20';
  static const _incompleteBg = '#ECEFF1';
  static const _incompleteFg = '#37474F';
  static const _statoScadutoBg = '#F8D7DA';
  static const _statoWarnBg = '#FFE0B2';
  static const _statoOkBg = '#C8E6C9';
  static const _border = '#C5CDD6';

  static Uint8List build({
    required List<UqsaSediSicurezzaExportSheet> sheets,
    DateTime? generatedAt,
  }) {
    if (sheets.isEmpty) {
      throw ArgumentError('Nessun foglio da esportare');
    }
    final when = generatedAt ?? DateTime.now();
    final stamp = DateFormat('dd/MM/yyyy HH:mm').format(when);
    final workbook = Workbook();
    try {
      for (var i = 0; i < sheets.length; i++) {
        final data = sheets[i];
        final ws = i == 0
            ? workbook.worksheets[0]
            : workbook.worksheets.addWithName(_safeSheetName(data.name, i));
        if (i == 0) {
          ws.name = _safeSheetName(data.name, 0);
        }
        _writeSheet(ws, data, stamp: stamp);
      }
      return Uint8List.fromList(workbook.saveAsStream());
    } finally {
      workbook.dispose();
    }
  }

  static String _safeSheetName(String raw, int index) {
    var s = raw.trim().replaceAll(RegExp(r'[\\/*?:\[\]]'), '_');
    if (s.isEmpty) s = 'Foglio_${index + 1}';
    if (s.length > 31) s = s.substring(0, 31);
    return s;
  }

  static void _writeSheet(
    Worksheet sheet,
    UqsaSediSicurezzaExportSheet data, {
    required String stamp,
  }) {
    sheet.pageSetup.orientation = ExcelPageOrientation.landscape;
    sheet.pageSetup.paperSize = ExcelPaperSize.paperA4;
    sheet.pageSetup.isFitToPage = true;
    sheet.pageSetup.fitToPagesWide = 1;
    sheet.pageSetup.fitToPagesTall = 0;
    sheet.pageSetup.leftMargin = 0.4;
    sheet.pageSetup.rightMargin = 0.4;
    sheet.pageSetup.topMargin = 0.4;
    sheet.pageSetup.bottomMargin = 0.4;
    sheet.pageSetup.printTitleRows = 'A1:H4';

    const widths = <double>[6, 24, 28, 26, 24, 34, 34, 14];
    for (var c = 0; c < widths.length; c++) {
      sheet.getRangeByIndex(1, c + 1).columnWidth = widths[c];
    }

    var row = 1;
    final title = sheet.getRangeByIndex(row, 1, row, _colCount);
    title.merge();
    title.setText('CRONOS GESTOPRO360  —  UQSA Sedi sicurezza');
    _paint(
      title,
      back: _titleBlue,
      font: '#FFFFFF',
      bold: true,
      size: 14,
      vAlign: VAlignType.center,
    );
    sheet.getRangeByIndex(row, 1).rowHeight = 24;
    row++;

    final sub = sheet.getRangeByIndex(row, 1, row, _colCount);
    sub.merge();
    sub.setText('${data.tabLabel}  ·  ${data.summary}  ·  Esportato $stamp');
    _paint(
      sub,
      back: '#E3F2FD',
      font: '#0D47A1',
      bold: true,
      size: 10,
      vAlign: VAlignType.center,
    );
    sheet.getRangeByIndex(row, 1).rowHeight = 18;
    row++;

    final spacer = sheet.getRangeByIndex(row, 1, row, _colCount);
    spacer.merge();
    _paint(spacer, back: '#FFFFFF', font: _text, size: 8);
    sheet.getRangeByIndex(row, 1).rowHeight = 6;
    row++;

    const headers = <String>[
      '#',
      'UBICANTE',
      'TIPO',
      'COMMESSA',
      'POSIZIONE',
      'ESTINTORI',
      'CASSETTE P.S.',
      'STATO',
    ];
    final headerBacks = <String>[
      _headerGreen,
      _headerGreen,
      _headerGreen,
      _headerGreen,
      _headerGreen,
      _headerEst,
      _headerCas,
      _headerGreen,
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(row, c + 1);
      cell.setText(headers[c]);
      _paint(
        cell,
        back: headerBacks[c],
        font: '#1B1B1B',
        bold: true,
        size: 11,
        vAlign: VAlignType.center,
      );
    }
    sheet.getRangeByIndex(row, 1).rowHeight = 22;
    final headerRow = row;
    row++;

    if (data.rows.isEmpty) {
      final empty = sheet.getRangeByIndex(row, 1, row, _colCount);
      empty.merge();
      empty.setText('Nessun risultato.');
      _paint(empty, back: _evenRow, font: _muted, size: 11);
      return;
    }

    for (final item in data.rows) {
      final bg = item.index.isOdd ? _evenRow : _oddRow;
      final lines = _maxLines(item);
      _writePlain(sheet, row, 1, '${item.index}', bg, bold: true);
      _writePlain(sheet, row, 2, _dash(item.ubicante), bg, bold: true, size: 11);
      _writePlain(sheet, row, 3, _dash(item.tipologia), bg);
      _writePlain(sheet, row, 4, _dash(item.commessa), bg);
      _writePlain(sheet, row, 5, _dash(item.posizione), bg);
      _writeAssets(
        sheet,
        row,
        6,
        item.estintori,
        emptyLabel: 'Nessun estintore',
        rowBg: bg,
      );
      _writeAssets(
        sheet,
        row,
        7,
        item.casette,
        emptyLabel: 'Nessuna cassetta',
        rowBg: bg,
      );
      _writeStato(sheet, row, 8, item);
      sheet.getRangeByIndex(row, 1).rowHeight =
          (18 + (lines * 14)).clamp(22, 220).toDouble();
      row++;
    }

    if (data.rows.isNotEmpty) {
      try {
        sheet.autoFilters.filterRange =
            sheet.getRangeByIndex(headerRow, 1, row - 1, _colCount);
      } catch (_) {}
    }
  }

  static int _maxLines(UqsaSediSicurezzaExportRow item) {
    final n = item.estintori.isEmpty ? 1 : item.estintori.length;
    final c = item.casette.isEmpty ? 1 : item.casette.length;
    final t = item.tipologia.trim().isEmpty
        ? 1
        : 1 + (item.tipologia.length / 28).floor();
    return [n, c, t, 1].reduce((a, b) => a > b ? a : b);
  }

  static String _dash(String v) {
    final t = v.trim();
    return t.isEmpty ? '—' : t;
  }

  static void _writePlain(
    Worksheet sheet,
    int row,
    int col,
    String text,
    String bg, {
    bool bold = false,
    double size = 10,
  }) {
    final cell = sheet.getRangeByIndex(row, col);
    cell.setText(text);
    _paint(
      cell,
      back: bg,
      font: _text,
      bold: bold,
      size: size,
      vAlign: VAlignType.top,
    );
  }

  static void _writeAssets(
    Worksheet sheet,
    int row,
    int col,
    List<UqsaSediSicurezzaAssetLine> items, {
    required String emptyLabel,
    required String rowBg,
  }) {
    final cell = sheet.getRangeByIndex(row, col);
    if (items.isEmpty) {
      cell.setText(emptyLabel);
      _paint(
        cell,
        back: rowBg,
        font: emptyLabel.contains('estintore') ? _critical : '#0D47A1',
        bold: true,
        size: 10,
        vAlign: VAlignType.top,
      );
      return;
    }
    cell.setText(
      items.map((e) => '${e.label}  ·  ${e.scadenza}').join('\n'),
    );
    _paint(
      cell,
      back: rowBg,
      font: _toneFont(_worstTone(items)),
      bold: true,
      size: 10,
      vAlign: VAlignType.top,
    );
  }

  static void _writeStato(
    Worksheet sheet,
    int row,
    int col,
    UqsaSediSicurezzaExportRow item,
  ) {
    final cell = sheet.getRangeByIndex(row, col);
    cell.setText(item.stato);
    late final String bg;
    late final String fg;
    switch (item.statoTone) {
      case UqsaExportTone.critical:
        bg = _statoScadutoBg;
        fg = _critical;
      case UqsaExportTone.warn:
        bg = _statoWarnBg;
        fg = _warn;
      case UqsaExportTone.empty:
        bg = _incompleteBg;
        fg = _incompleteFg;
      case UqsaExportTone.ok:
        bg = _statoOkBg;
        fg = _ok;
    }
    _paint(
      cell,
      back: bg,
      font: fg,
      bold: true,
      size: 10,
      hAlign: HAlignType.center,
      vAlign: VAlignType.center,
    );
  }

  static UqsaExportTone _worstTone(List<UqsaSediSicurezzaAssetLine> items) {
    var worst = UqsaExportTone.ok;
    for (final item in items) {
      if (item.tone == UqsaExportTone.critical) return UqsaExportTone.critical;
      if (item.tone == UqsaExportTone.warn) worst = UqsaExportTone.warn;
    }
    return worst;
  }

  static String _toneFont(UqsaExportTone tone) {
    switch (tone) {
      case UqsaExportTone.critical:
        return _critical;
      case UqsaExportTone.warn:
        return _warn;
      case UqsaExportTone.empty:
        return _muted;
      case UqsaExportTone.ok:
        return _text;
    }
  }

  static void _paint(
    Range cell, {
    required String back,
    required String font,
    bool bold = false,
    double size = 10,
    HAlignType hAlign = HAlignType.left,
    VAlignType vAlign = VAlignType.center,
  }) {
    void applyTo(Range c, {required bool withBorders}) {
      c.cellStyle.backColor = back;
      c.cellStyle.fontColor = font;
      c.cellStyle.bold = bold;
      c.cellStyle.fontSize = size;
      c.cellStyle.hAlign = hAlign;
      c.cellStyle.vAlign = vAlign;
      c.cellStyle.wrapText = true;
      if (!withBorders) return;
      c.cellStyle.borders.all.lineStyle = LineStyle.thin;
      c.cellStyle.borders.all.color = _border;
    }

    final multi = cell.row != cell.lastRow || cell.column != cell.lastColumn;
    if (multi) {
      for (var r = cell.row; r <= cell.lastRow; r++) {
        for (var c = cell.column; c <= cell.lastColumn; c++) {
          applyTo(cell.worksheet.getRangeByIndex(r, c), withBorders: false);
        }
      }
      return;
    }
    applyTo(cell, withBorders: true);
  }
}
