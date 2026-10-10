import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Legge i valori delle celle dal foglio principale di un .xlsx compilato.
Map<String, String> readXlsxSheetCellValues(Uint8List xlsxBytes) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);
  final sheetFile = archive.files.firstWhere(
    (f) => f.name == 'xl/worksheets/sheet1.xml' && f.isFile,
    orElse: () => throw StateError('sheet1.xml mancante nel file Excel.'),
  );
  final sheetXml = utf8.decode(sheetFile.content as List<int>);

  final shared = <String>[];
  final ssFile = archive.files.where(
    (f) => f.name == 'xl/sharedStrings.xml' && f.isFile,
  );
  if (ssFile.isNotEmpty) {
    shared.addAll(_parseSharedStrings(utf8.decode(ssFile.first.content as List<int>)));
  }

  final cells = <String, String>{};

  final withBody = RegExp(
    r'<c r="([A-Z]+\d+)"([^>]*)>(.*?)</c>',
    dotAll: true,
  );
  for (final m in withBody.allMatches(sheetXml)) {
    final ref = m.group(1)!.toUpperCase();
    final attrs = m.group(2) ?? '';
    final body = m.group(3) ?? '';
    cells[ref] = _decodeCellValue(attrs, body, shared);
  }

  final selfClosing = RegExp(r'<c r="([A-Z]+\d+)"([^>]*)/>');
  for (final m in selfClosing.allMatches(sheetXml)) {
    final ref = m.group(1)!.toUpperCase();
    cells.putIfAbsent(ref, () => '');
  }

  return cells;
}

List<String> _parseSharedStrings(String xml) {
  final out = <String>[];
  final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
  for (final m in siRe.allMatches(xml)) {
    final block = m.group(1) ?? '';
    if (block.contains('<r>')) {
      final parts = <String>[];
      final tRe = RegExp(r'<t(?:[^>]*)>([^<]*)</t>', dotAll: true);
      for (final t in tRe.allMatches(block)) {
        parts.add(t.group(1) ?? '');
      }
      out.add(parts.join());
    } else {
      final t = RegExp(r'<t(?:[^>]*)>([^<]*)</t>', dotAll: true).firstMatch(block);
      out.add(t?.group(1) ?? '');
    }
  }
  return out;
}

String _decodeCellValue(String attrs, String body, List<String> shared) {
  final inline = RegExp(r'<is>\s*<t(?:[^>]*)>(.*?)</t>\s*</is>', dotAll: true)
      .firstMatch(body);
  if (inline != null) {
    return _xmlUnescape(inline.group(1) ?? '');
  }

  final vMatch = RegExp(r'<v>([^<]*)</v>').firstMatch(body);
  if (vMatch == null) return '';

  final raw = vMatch.group(1) ?? '';
  if (attrs.contains(' t="s"')) {
    final idx = int.tryParse(raw);
    if (idx != null && idx >= 0 && idx < shared.length) {
      return shared[idx];
    }
  }
  return raw;
}

String _xmlUnescape(String text) {
  return text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

String xlsxCell(Map<String, String> cells, String ref, [String fallback = '']) {
  final v = cells[ref.trim().toUpperCase()];
  if (v == null || v.trim().isEmpty) return fallback;
  return v.trim();
}
