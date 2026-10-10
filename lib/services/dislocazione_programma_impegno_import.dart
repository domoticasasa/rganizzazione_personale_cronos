import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../utils/personale_name_matcher.dart';

class DislocazioneExcelPersona {
  const DislocazioneExcelPersona({
    required this.nominativoExcel,
    this.abilitazioni,
    this.attivita,
    required this.giorni,
  });

  final String nominativoExcel;
  final String? abilitazioni;
  final String? attivita;
  final Map<DateTime, String> giorni;
}

class DislocazioneExcelParseResult {
  const DislocazioneExcelParseResult({
    required this.persone,
    required this.dateColCount,
  });

  final List<DislocazioneExcelPersona> persone;
  final int dateColCount;
}

class DislocazioneImportEsito {
  const DislocazioneImportEsito({
    required this.importati,
    required this.saltatiExcel,
    required this.periodi,
    this.attivitaImportate = 0,
  });

  final int importati;
  final int saltatiExcel;
  final int periodi;
  final int attivitaImportate;
}

/// Parser del file «Programma impegno personale» (foglio Maestranze).
abstract final class DislocazioneProgrammaImpegnoImport {
  DislocazioneProgrammaImpegnoImport._();

  static DislocazioneExcelParseResult parseBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('File Excel senza fogli.');
    }
    final sheet = excel.tables['Maestranze'] ?? excel.tables.values.first;
    return parseSheet(sheet);
  }

  static DislocazioneExcelParseResult parseSheet(Sheet sheet) {
    final header = _trovaRigaNominativi(sheet);
    if (header == null) {
      throw const FormatException(
        'Colonna Nominativi non trovata. Serve il foglio Maestranze.',
      );
    }
    final headerRow = header.$1;
    final nomeCol = header.$2;
    final abilitaCol = nomeCol > 0 ? nomeCol - 1 : null;
    final attivitaCol = _trovaColonnaAttivita(sheet, headerRow, nomeCol);

    final dateCols = <({int col, DateTime giorno})>[];
    for (var c = nomeCol + 1; c < sheet.maxCols; c++) {
      final d = _cellDate(sheet, headerRow, c);
      if (d == null) continue;
      dateCols.add((col: c, giorno: d));
    }
    if (dateCols.isEmpty) {
      throw const FormatException('Nessuna colonna data nel file Excel.');
    }

    final persone = <DislocazioneExcelPersona>[];
    for (var r = headerRow + 1; r < sheet.maxRows; r++) {
      final nome = _cellStr(sheet, r, nomeCol);
      if (nome.isEmpty) continue;
      if (_sembraRigaNonPersona(nome)) continue;

      String? ab;
      if (abilitaCol != null) {
        final raw = _cellStr(sheet, r, abilitaCol);
        if (raw.isNotEmpty) ab = raw;
      }
      String? at;
      if (attivitaCol != null) {
        at = normalizzaAttivita(_cellStr(sheet, r, attivitaCol));
      }

      final giorni = <DateTime, String>{};
      for (final dc in dateCols) {
        final v = _cellStr(sheet, r, dc.col);
        if (v.isEmpty) continue;
        giorni[dc.giorno] = v;
      }
      persone.add(
        DislocazioneExcelPersona(
          nominativoExcel: nome,
          abilitazioni: ab,
          attivita: at,
          giorni: giorni,
        ),
      );
    }

    if (persone.isEmpty) {
      throw const FormatException('Nessun nominativo nel file Excel.');
    }
    return DislocazioneExcelParseResult(
      persone: persone,
      dateColCount: dateCols.length,
    );
  }

  static String? matchNominativoEsistente({
    required String nominativoExcel,
    required List<String> nominativiEsistenti,
  }) {
    final key = nominativoExcel.trim().toUpperCase();
    if (key.isEmpty) return null;
    for (final n in nominativiEsistenti) {
      if (n.trim().toUpperCase() == key) return n;
    }
    final byId = <String, String>{
      for (final n in nominativiEsistenti) n: n,
    };
    return PersonaleNameMatcher.findPersonaleIdByNominativoDislocazione(
      nominativoExcel,
      byId,
    );
  }

  static (int, int)? _trovaRigaNominativi(Sheet sheet) {
    final maxR = sheet.maxRows < 40 ? sheet.maxRows : 40;
    final maxC = sheet.maxCols < 40 ? sheet.maxCols : 40;
    for (var r = 0; r < maxR; r++) {
      for (var c = 0; c < maxC; c++) {
        final t = _cellStr(sheet, r, c).toLowerCase();
        if (t == 'nominativi' || t == 'nominativo') {
          return (r, c);
        }
      }
    }
    return null;
  }

  /// Colonna «Attività» a sinistra del nominativo (Excel Maestranze).
  static int? _trovaColonnaAttivita(Sheet sheet, int headerRow, int nomeCol) {
    for (var c = 0; c < nomeCol; c++) {
      final t = _normHeader(_cellStr(sheet, headerRow, c));
      if (t.contains('attivit')) return c;
    }
    // A volte l'intestazione è sulla riga sopra.
    if (headerRow > 0) {
      for (var c = 0; c < nomeCol; c++) {
        final t = _normHeader(_cellStr(sheet, headerRow - 1, c));
        if (t.contains('attivit')) return c;
      }
    }
    // Layout tipico: Attività | Abilitazioni | Nominativi
    if (nomeCol >= 2) return nomeCol - 2;
    return null;
  }

  static String _normHeader(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a');
  }

  /// Normalizza etichette tipiche Excel (LFM, IS, TE, OP. CIVILI).
  static String? normalizzaAttivita(String? raw) {
    final t = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || t == '-' || t == '—' || t == '/') return null;
    if (t == 'OP CIVILI' || t == 'OP.CIVILI' || t == 'OPCIVILI') {
      return 'OP. CIVILI';
    }
    if (t.startsWith('OP.') && t.contains('CIVIL')) return 'OP. CIVILI';
    return t;
  }

  static bool _sembraRigaNonPersona(String nome) {
    final u = nome.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2,5}-\d+-\d+').hasMatch(u)) return true;
    if (u.contains('PAIPL') || u.contains('PAI-PL')) return true;
    if (u.startsWith('ASSISTENZA ')) return true;
    if (u.contains('MANUTENZIONE TLC')) return true;
    if (u.contains('_CA') || u.contains(' CA ')) return true;
    if (u.contains('-CATANIA') || u.contains('-CASTELBUONO')) return true;
    if (u.startsWith('DOTE ')) return true;
    if (u.startsWith('AQ ')) return true;
    return false;
  }

  static String _cellStr(Sheet sheet, int row, int col) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.day.toString().padLeft(2, '0')}/'
          '${v.month.toString().padLeft(2, '0')}/'
          '${v.year}';
    }
    return v.toString().replaceAll('\u00a0', ' ').trim();
  }

  static DateTime? _cellDate(Sheet sheet, int row, int col) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is num) {
      final base = DateTime.utc(1899, 12, 30);
      final d = base.add(
        Duration(milliseconds: (v.toDouble() * 86400000).round()),
      );
      return DateTime(d.year, d.month, d.day);
    }
    final text = _cellStr(sheet, row, col);
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(text);
    if (m != null) {
      final d = int.tryParse(m.group(1) ?? '');
      final mo = int.tryParse(m.group(2) ?? '');
      var y = int.tryParse(m.group(3) ?? '');
      if (d != null && mo != null && y != null) {
        if (y < 100) y += 2000;
        return DateTime(y, mo, d);
      }
    }
    return null;
  }
}
