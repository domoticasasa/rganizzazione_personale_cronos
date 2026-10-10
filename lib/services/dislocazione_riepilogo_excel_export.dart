import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../utils/dislocazione_period_utils.dart';

/// Riga esportabile del riepilogo (stessi dati/colori della UI).
class DislocazioneRiepilogoExcelRow {
  const DislocazioneRiepilogoExcelRow({
    required this.label,
    required this.values,
    this.totaliGiorno,
    this.showPct = false,
    this.emphasize = false,
    this.isStato = false,
    this.bgHex,
  });

  final String label;
  final List<int> values;
  final List<int>? totaliGiorno;
  final bool showPct;
  final bool emphasize;
  final bool isStato;
  /// Sfondo riga, es. `A9D08E` (senza #).
  final String? bgHex;
}

class DislocazioneRiepilogoExcelSection {
  const DislocazioneRiepilogoExcelSection({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<DislocazioneRiepilogoExcelRow> rows;
}

/// Excel del riepilogo dislocazione: struttura e colori come in pagina.
abstract final class DislocazioneRiepilogoExcelExport {
  DislocazioneRiepilogoExcelExport._();

  static final _dateFmt = DateFormat('dd/MM');
  static final _weekdayFmt = DateFormat('E', 'it_IT');

  static Uint8List build({
    required DateTime dal,
    required DateTime al,
    required int nominativiCount,
    required List<DateTime> giorni,
    required List<DislocazioneRiepilogoExcelSection> sections,
  }) {
    final workbook = Workbook();
    try {
      final sheet = workbook.worksheets[0];
      sheet.name = 'Riepilogo';

      final oggi = dateOnly(DateTime.now());
      final colCount = 1 + giorni.length + 1; // Voce + giorni + Media

      var row = 1;
      _mergeTitle(sheet, row, colCount, 'CRONOS GESTOPRO360 — Riepilogo dislocazione');
      _styleTitle(sheet.getRangeByIndex(row, 1, row, colCount));
      row++;

      sheet.getRangeByIndex(row, 1).setText(
            'Periodo: ${_dateFmt.format(dal)} – ${_dateFmt.format(al)} · '
            '${giorni.length} giorni · $nominativiCount nominativi',
          );
      sheet.getRangeByIndex(row, 1, row, colCount).merge();
      sheet.getRangeByIndex(row, 1).cellStyle.fontSize = 11;
      row += 2;

      for (final section in sections) {
        if (section.rows.isEmpty) continue;
        _mergeTitle(sheet, row, colCount, section.title);
        final titleRange = sheet.getRangeByIndex(row, 1, row, colCount);
        titleRange.cellStyle.bold = true;
        titleRange.cellStyle.fontSize = 13;
        titleRange.cellStyle.fontColor = '#263238';
        titleRange.cellStyle.backColor = '#CFD8DC';
        row++;

        // Header giorni
        _writeHeader(sheet, row, giorni, oggi);
        row++;

        for (final dataRow in section.rows) {
          _writeDataRow(sheet, row, dataRow, giorni, oggi);
          row++;
        }
        row += 2; // spazio tra sezioni
      }

      sheet.getRangeByIndex(1, 1).columnWidth = 36;
      for (var c = 2; c <= colCount; c++) {
        sheet.getRangeByIndex(1, c).columnWidth = 9;
      }

      return Uint8List.fromList(workbook.saveAsStream());
    } finally {
      workbook.dispose();
    }
  }

  static void _mergeTitle(Worksheet sheet, int row, int colCount, String text) {
    sheet.getRangeByIndex(row, 1).setText(text);
    if (colCount > 1) {
      sheet.getRangeByIndex(row, 1, row, colCount).merge();
    }
  }

  static void _styleTitle(Range range) {
    range.cellStyle.bold = true;
    range.cellStyle.fontSize = 14;
    range.cellStyle.fontColor = '#FFFFFF';
    range.cellStyle.backColor = '#1565C0';
    range.cellStyle.hAlign = HAlignType.left;
    range.cellStyle.vAlign = VAlignType.center;
  }

  static void _writeHeader(
    Worksheet sheet,
    int row,
    List<DateTime> giorni,
    DateTime oggi,
  ) {
    final voce = sheet.getRangeByIndex(row, 1);
    voce.setText('Voce');
    _applyHeaderStyle(voce, isToday: false);

    for (var i = 0; i < giorni.length; i++) {
      final g = giorni[i];
      final cell = sheet.getRangeByIndex(row, i + 2);
      final isToday = dateOnly(g) == oggi;
      final wd = _weekdayFmt.format(g).toUpperCase();
      final label = isToday
          ? '$wd\n${_dateFmt.format(g)}\nOGGI'
          : '$wd\n${_dateFmt.format(g)}';
      cell.setText(label);
      _applyHeaderStyle(cell, isToday: isToday);
    }

    final media = sheet.getRangeByIndex(row, giorni.length + 2);
    media.setText('Media');
    _applyHeaderStyle(media, isToday: false);
    sheet.getRangeByIndex(row, 1, row, giorni.length + 2).rowHeight = 36;
  }

  static void _applyHeaderStyle(Range cell, {required bool isToday}) {
    cell.cellStyle.bold = true;
    cell.cellStyle.fontSize = 9;
    cell.cellStyle.hAlign = HAlignType.center;
    cell.cellStyle.vAlign = VAlignType.center;
    cell.cellStyle.wrapText = true;
    cell.cellStyle.borders.all.lineStyle = LineStyle.thin;
    cell.cellStyle.borders.all.color = '#90A4AE';
    if (isToday) {
      cell.cellStyle.backColor = '#FFE082';
      cell.cellStyle.fontColor = '#4E342E';
    } else {
      cell.cellStyle.backColor = '#ECEFF1';
      cell.cellStyle.fontColor = '#37474F';
    }
  }

  static void _writeDataRow(
    Worksheet sheet,
    int row,
    DislocazioneRiepilogoExcelRow data,
    List<DateTime> giorni,
    DateTime oggi,
  ) {
    final bg = _resolveBg(data);
    final labelCell = sheet.getRangeByIndex(row, 1);
    labelCell.setText(data.label);
    _applyDataStyle(
      labelCell,
      bgHex: bg,
      emphasize: data.emphasize,
      align: HAlignType.left,
      isToday: false,
    );

    final dayCount = giorni.length;
    final somma = data.values.fold<int>(0, (a, b) => a + b);
    final media = dayCount == 0 ? 0.0 : somma / dayCount;
    final mediaTxt = media == media.roundToDouble()
        ? media.toInt().toString()
        : media.toStringAsFixed(1);

    for (var i = 0; i < data.values.length; i++) {
      final cell = sheet.getRangeByIndex(row, i + 2);
      final n = data.values[i];
      final isToday = i < giorni.length && dateOnly(giorni[i]) == oggi;
      String text;
      if (data.showPct &&
          data.totaliGiorno != null &&
          i < data.totaliGiorno!.length) {
        text = '$n\n${_pct(n, data.totaliGiorno![i])}';
      } else {
        text = '$n';
      }
      cell.setText(text);
      _applyDataStyle(
        cell,
        bgHex: bg,
        emphasize: data.emphasize,
        align: HAlignType.center,
        isToday: isToday,
        mutedZero: n == 0 && !data.emphasize,
      );
    }

    final mediaCell = sheet.getRangeByIndex(row, giorni.length + 2);
    mediaCell.setText(mediaTxt);
    _applyDataStyle(
      mediaCell,
      bgHex: bg,
      emphasize: true,
      align: HAlignType.center,
      isToday: false,
    );

    if (data.showPct) {
      sheet.getRangeByIndex(row, 1).rowHeight = 28;
    }
  }

  static String? _resolveBg(DislocazioneRiepilogoExcelRow data) {
    if (data.bgHex != null && data.bgHex!.trim().isNotEmpty) {
      return data.bgHex!.replaceAll('#', '').toUpperCase();
    }
    if (data.emphasize) return 'F5F5F5';
    if (data.isStato) return 'FFF3E0';
    return null;
  }

  static void _applyDataStyle(
    Range cell, {
    required String? bgHex,
    required bool emphasize,
    required HAlignType align,
    required bool isToday,
    bool mutedZero = false,
  }) {
    cell.cellStyle.fontSize = emphasize ? 11 : 10;
    cell.cellStyle.bold = emphasize;
    cell.cellStyle.hAlign = align;
    cell.cellStyle.vAlign = VAlignType.center;
    cell.cellStyle.wrapText = true;
    cell.cellStyle.borders.all.lineStyle = LineStyle.thin;
    cell.cellStyle.borders.all.color = '#B0BEC5';
    if (mutedZero) {
      cell.cellStyle.fontColor = '#BDBDBD';
    } else {
      cell.cellStyle.fontColor = '#212121';
    }
    if (isToday) {
      // Evidenzia colonna oggi sopra lo sfondo riga.
      cell.cellStyle.backColor = '#FFECB3';
    } else if (bgHex != null) {
      cell.cellStyle.backColor = '#$bgHex';
    }
  }

  static String _pct(int n, int tot) {
    if (tot <= 0) return '0,00%';
    final p = (n * 10000 / tot).round() / 100;
    return '${p.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  /// Hex da Color Flutter (0xAARRGGBB) → RRGGBB.
  static String hexFromArgb(int colorValue) {
    final rgb = colorValue & 0xFFFFFF;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }
}
