import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Compila un .xlsx esistente modificando solo il foglio XML (preserva layout, immagini, stili).
class TemplateXlsxZipFill {
  TemplateXlsxZipFill._();

  static Uint8List fill({
    required Uint8List templateBytes,
    required String sheetName,
    required Map<String, String> payload,
    bool Function(String cellRef)? allowCell,
    bool hideGridLinesForPdf = false,
    Map<int, double>? rowHeights,
    /// Righe da nascondere (es. blocchi DATA vuoti 2–5 per PDF su una pagina).
    Iterable<int>? hiddenRows,
    /// Scrive sempre testo (evita che ExcelTS mostri «1» al posto di «10»).
    bool forceTextValues = false,
  }) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final sheetPath = _resolveSheetPath(archive, sheetName);
    final sheetFileIndex =
        archive.files.indexWhere((f) => f.name == sheetPath && f.isFile);
    if (sheetFileIndex < 0) {
      throw StateError('Foglio $sheetName non trovato nel template ($sheetPath).');
    }

    final sheetFile = archive.files[sheetFileIndex];
    var sheetXml = utf8.decode(sheetFile.content as List<int>);
    final mergeAnchor = _buildMergeAnchorMap(sheetXml);

    if (payload.length > 500) {
      sheetXml = _applyPayloadBatch(
        sheetXml,
        payload,
        mergeAnchor,
        forceText: forceTextValues,
      );
    } else {
      for (final entry in payload.entries) {
        final ref = entry.key.trim().toUpperCase();
        if (ref.isEmpty || ref.startsWith('__')) continue;
        if (allowCell != null && !allowCell(ref)) continue;
        final target = mergeAnchor[ref] ?? ref;
        sheetXml = _setCellValue(
          sheetXml,
          target,
          entry.value,
          forceText: forceTextValues,
        );
      }
    }

    if (rowHeights != null && rowHeights.isNotEmpty) {
      for (final e in rowHeights.entries) {
        sheetXml = _setRowHeight(sheetXml, e.key, e.value);
      }
    }

    if (hiddenRows != null) {
      for (final row in hiddenRows) {
        sheetXml = _hideRow(sheetXml, row);
      }
    }

    // Sempre: niente pageBreakPreview («Pagina 1») e niente griglia in stampa/PDF.
    if (hideGridLinesForPdf || hiddenRows != null) {
      sheetXml = _hideGridLinesInSheetXml(sheetXml);
    } else {
      sheetXml = sheetXml.replaceAll(
        'view="pageBreakPreview"',
        'view="normal"',
      );
    }

    final out = Archive();
    for (var i = 0; i < archive.files.length; i++) {
      final f = archive.files[i];
      if (!f.isFile) continue;
      if (i == sheetFileIndex) {
        final bytes = utf8.encode(sheetXml);
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else if (_isDrawingRelsPath(f.name)) {
        // Excel salva Target="/xl/media/..." (assoluto): ExcelTS non carica le
        // immagini → PDF ~8KB senza logo/firme. Normalizza a path relativi.
        final raw = f.content;
        final src = raw is Uint8List
            ? utf8.decode(raw)
            : utf8.decode(List<int>.from(raw as List));
        final fixed = _normalizeDrawingMediaTargets(src);
        final bytes = utf8.encode(fixed);
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      } else {
        // Copia esplicita: su web il content zip può essere una lista non modificabile.
        final raw = f.content;
        final bytes = raw is Uint8List
            ? Uint8List.fromList(raw)
            : Uint8List.fromList(List<int>.from(raw as List));
        out.addFile(ArchiveFile(f.name, bytes.length, bytes));
      }
    }

    final encoded = ZipEncoder().encode(out);
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Impossibile ricreare il file Excel.');
    }
    return Uint8List.fromList(encoded);
  }

  static bool _isDrawingRelsPath(String name) {
    final n = name.replaceAll('\\', '/').toLowerCase();
    return n.contains('/drawings/_rels/') && n.endsWith('.rels');
  }

  /// Target="/xl/media/image1.png") → Target="../media/image1.png"
  static String _normalizeDrawingMediaTargets(String relsXml) {
    return relsXml
        .replaceAllMapped(
          RegExp(r'Target="/xl/media/([^"]+)"'),
          (m) => 'Target="../media/${m[1]}"',
        )
        .replaceAllMapped(
          RegExp(r"Target='/xl/media/([^']+)'"),
          (m) => "Target='../media/${m[1]}'",
        );
  }

  static String _resolveSheetPath(Archive archive, String sheetName) {
    final workbookFile = archive.files.firstWhere(
      (f) => f.name == 'xl/workbook.xml' && f.isFile,
      orElse: () => throw StateError('workbook.xml mancante nel template.'),
    );
    final workbookXml = utf8.decode(workbookFile.content as List<int>);

    final relsFile = archive.files.firstWhere(
      (f) => f.name == 'xl/_rels/workbook.xml.rels' && f.isFile,
      orElse: () => throw StateError('workbook.xml.rels mancante nel template.'),
    );
    final relsXml = utf8.decode(relsFile.content as List<int>);

    String? rid;
    final sheetRe = RegExp(
      '<sheet[^>]+name="${RegExp.escape(sheetName)}"[^>]*/?>',
    );
    final m = sheetRe.firstMatch(workbookXml);
    if (m != null) {
      rid = RegExp(r'r:id="([^"]+)"').firstMatch(m.group(0)!)?.group(1);
    }
    if (rid == null) {
      throw StateError('Foglio "$sheetName" non presente in workbook.xml.');
    }

    String? target;
    final relRe = RegExp(r'<Relationship\b[^>]*?/?>');
    for (final rel in relRe.allMatches(relsXml)) {
      final tag = rel.group(0)!;
      final id = RegExp(r'\bId="([^"]+)"').firstMatch(tag)?.group(1);
      if (id != rid) continue;
      target = RegExp(r'\bTarget="([^"]+)"').firstMatch(tag)?.group(1);
      break;
    }
    if (target == null || target.isEmpty) {
      throw StateError('Relazione foglio $rid non trovata.');
    }

    // Target può essere "worksheets/sheet1.xml", "xl/...", oppure "/xl/...".
    var path = target.replaceAll('\\', '/');
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('xl/')) path = 'xl/$path';
    return path;
  }

  static Map<String, String> _buildMergeAnchorMap(String sheetXml) {
    final anchor = <String, String>{};
    final re = RegExp(r'<mergeCell ref="([^"]+)"/>');
    for (final m in re.allMatches(sheetXml)) {
      final range = m.group(1);
      if (range == null || !range.contains(':')) continue;
      final parts = range.split(':');
      if (parts.length != 2) continue;
      final topLeft = parts[0].trim().toUpperCase();
      final c1 = _splitCellRef(parts[0]);
      final c2 = _splitCellRef(parts[1]);
      if (c1 == null || c2 == null) continue;
      for (var col = c1.$1; col <= c2.$1; col++) {
        for (var row = c1.$2; row <= c2.$2; row++) {
          anchor[_cellRef(col, row)] = topLeft;
        }
      }
    }
    return anchor;
  }

  static (int col, int row)? _splitCellRef(String ref) {
    final r = ref.trim().toUpperCase();
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(r);
    if (m == null) return null;
    return (_colLettersToIndex(m.group(1)!), int.parse(m.group(2)!));
  }

  static int _colLettersToIndex(String letters) {
    var n = 0;
    for (var i = 0; i < letters.length; i++) {
      n = n * 26 + (letters.codeUnitAt(i) - 64);
    }
    return n;
  }

  static String _colIndexToLetters(int index) {
    var n = index;
    final chars = <int>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      chars.add(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(chars.reversed);
  }

  static String _cellRef(int col, int row) =>
      '${_colIndexToLetters(col)}$row';

  /// Riferimento cella Excel (colonna 1 = A, riga 1-based).
  static String cellRef(int col, int row) => _cellRef(col, row);

  /// Applica molte celle riga per riga (evita regex su tutto il foglio).
  static String _applyPayloadBatch(
    String xml,
    Map<String, String> payload,
    Map<String, String> mergeAnchor, {
    bool forceText = false,
  }) {
    final updates = <String, String>{};
    for (final entry in payload.entries) {
      final ref = entry.key.trim().toUpperCase();
      if (ref.isEmpty || ref.startsWith('__')) continue;
      final target = mergeAnchor[ref] ?? ref;
      updates[target] = entry.value;
    }
    if (updates.isEmpty) return xml;

    final byRow = <int, Map<String, String>>{};
    for (final entry in updates.entries) {
      final parts = _splitCellRef(entry.key);
      if (parts == null) continue;
      byRow.putIfAbsent(parts.$2, () => <String, String>{})[entry.key] =
          entry.value;
    }
    if (byRow.isEmpty) return xml;

    final rowRe = RegExp(r'<row r="(\d+)"([^>]*)>([\s\S]*?)</row>');
    final cellSelfClose = RegExp(r'<c r="([A-Z]+\d+)"([^>]*)/>');
    final cellWithBody =
        RegExp(r'<c r="([A-Z]+\d+)"([^>]*)>(?!/)([\s\S]*?)</c>');

    return xml.replaceAllMapped(rowRe, (rowMatch) {
      final rowNum = int.parse(rowMatch.group(1)!);
      final rowUpdates = byRow[rowNum];
      if (rowUpdates == null || rowUpdates.isEmpty) return rowMatch.group(0)!;

      final rowOpen = rowMatch
          .group(0)!
          .substring(0, rowMatch.group(0)!.indexOf('>') + 1);
      var rowBody = rowMatch.group(3)!;
      final pending = Map<String, String>.from(rowUpdates);

      rowBody = rowBody.replaceAllMapped(cellSelfClose, (m) {
        final ref = m.group(1)!.toUpperCase();
        final val = pending.remove(ref);
        if (val == null) return m.group(0)!;
        return _buildCellXml(ref, m.group(2) ?? '', val, forceText: forceText);
      });
      rowBody = rowBody.replaceAllMapped(cellWithBody, (m) {
        final ref = m.group(1)!.toUpperCase();
        final val = pending.remove(ref);
        if (val == null) return m.group(0)!;
        return _buildCellXml(ref, m.group(2) ?? '', val, forceText: forceText);
      });

      if (pending.isNotEmpty) {
        final extra = StringBuffer();
        for (final entry in pending.entries) {
          extra.write(
            _buildCellXml(
              entry.key,
              ' s="5"',
              entry.value,
              forceText: forceText,
            ),
          );
        }
        rowBody = '$rowBody$extra';
      }

      rowBody = _sortAndDedupeRowCells(rowBody);
      return '$rowOpen$rowBody</row>';
    });
  }

  /// Excel richiede le celle di una riga in ordine di colonna crescente.
  static String _sortAndDedupeRowCells(String rowBody) {
    final matches = _rowCellRe.allMatches(rowBody).toList();
    if (matches.length <= 1) return rowBody;
    final byCol = <int, String>{};
    for (final m in matches) {
      final letters = m.group(1) ?? m.group(3);
      if (letters == null || letters.isEmpty) continue;
      byCol[_colLettersToIndex(letters)] = m.group(0)!;
    }
    if (byCol.isEmpty) return rowBody;
    final cols = byCol.keys.toList()..sort();
    return cols.map((c) => byCol[c]!).join();
  }

  static final RegExp _rowCellRe = RegExp(
    r'<c r="([A-Z]+)(\d+)"[^>]*/>|<c r="([A-Z]+)(\d+)"[^>]*>[\s\S]*?</c>',
  );

  static String _setCellValue(
    String xml,
    String ref,
    String value, {
    bool forceText = false,
  }) {
    final escapedRef = RegExp.escape(ref);
    // Prima le celle vuote (<c .../>): altrimenti il ">" in "/>" fa matchare il ramo sbagliato.
    final selfClosing = RegExp('<c r="$escapedRef"([^>]*)/>');
    final withBody = RegExp(
      '<c r="$escapedRef"([^>]*)>(?!/)(.*?)</c>',
      dotAll: true,
    );

    String styleAttrs = '';
    final mSelf = selfClosing.firstMatch(xml);
    final mBody = mSelf == null ? withBody.firstMatch(xml) : null;
    if (mSelf != null) {
      styleAttrs = mSelf.group(1) ?? '';
    } else if (mBody != null) {
      styleAttrs = mBody.group(1) ?? '';
    }

    final newCell =
        _buildCellXml(ref, styleAttrs, value, forceText: forceText);

    if (mSelf != null) {
      return xml.replaceFirst(mSelf.group(0)!, newCell);
    }
    if (mBody != null) {
      return xml.replaceFirst(mBody.group(0)!, newCell);
    }
    return xml;
  }

  /// Attributi stile/tipo dalla cella template (senza `t=` né `/` spurio da parse errato).
  static String _normalizeCellAttrs(String raw) {
    var a = raw.trim();
    if (a.endsWith('/')) {
      a = a.substring(0, a.length - 1).trimRight();
    }
    a = a.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
    if (a.isEmpty) return '';
    return a.startsWith(' ') ? a : ' $a';
  }

  static String _buildCellXml(
    String ref,
    String styleAttrs,
    String value, {
    bool forceText = false,
  }) {
    final attrs = _normalizeCellAttrs(styleAttrs);

    if (value.isEmpty) {
      return '<c r="$ref"$attrs/>';
    }

    if (!forceText) {
      final asNumber = _tryNumericCellValue(value);
      if (asNumber != null) {
        return '<c r="$ref"$attrs><v>$asNumber</v></c>';
      }
    }

    final preserve = value.contains('\n') ||
        value.contains('\r') ||
        value.startsWith(' ') ||
        value.endsWith(' ');
    final tOpen = preserve ? '<t xml:space="preserve">' : '<t>';
    return '<c r="$ref"$attrs t="inlineStr"><is>$tOpen${_xmlEscape(value)}</t></is></c>';
  }

  /// Imposta altezza riga Excel (ht + customHeight).
  static String _setRowHeight(String xml, int row, double height) {
    final ht = height.toStringAsFixed(2);
    final re = RegExp('<row r="$row"([^>]*)>');
    final m = re.firstMatch(xml);
    if (m == null) return xml;
    var attrs = m.group(1) ?? '';
    if (RegExp(r'\bht="').hasMatch(attrs)) {
      attrs = attrs.replaceAll(RegExp(r'\bht="[^"]*"'), 'ht="$ht"');
    } else {
      attrs = '$attrs ht="$ht"';
    }
    if (RegExp(r'\bcustomHeight="').hasMatch(attrs)) {
      attrs =
          attrs.replaceAll(RegExp(r'\bcustomHeight="[^"]*"'), 'customHeight="1"');
    } else {
      attrs = '$attrs customHeight="1"';
    }
    return xml.replaceFirst(m.group(0)!, '<row r="$row"$attrs>');
  }

  /// Nasconde una riga (hidden + altezza 0) per export PDF compatto.
  static String _hideRow(String xml, int row) {
    final re = RegExp('<row r="$row"([^>]*)>');
    final m = re.firstMatch(xml);
    if (m == null) return xml;
    var attrs = m.group(1) ?? '';
    if (RegExp(r'\bhidden="').hasMatch(attrs)) {
      attrs = attrs.replaceAll(RegExp(r'\bhidden="[^"]*"'), 'hidden="1"');
    } else {
      attrs = '$attrs hidden="1"';
    }
    if (RegExp(r'\bht="').hasMatch(attrs)) {
      attrs = attrs.replaceAll(RegExp(r'\bht="[^"]*"'), 'ht="0"');
    } else {
      attrs = '$attrs ht="0"';
    }
    if (RegExp(r'\bcustomHeight="').hasMatch(attrs)) {
      attrs =
          attrs.replaceAll(RegExp(r'\bcustomHeight="[^"]*"'), 'customHeight="1"');
    } else {
      attrs = '$attrs customHeight="1"';
    }
    return xml.replaceFirst(m.group(0)!, '<row r="$row"$attrs>');
  }

  /// Caratteri non validi in XML 1.0 (testo elemento).
  static String _xmlEscape(String text) {
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final c = rune;
      if (c == 0x9 ||
          c == 0xA ||
          c == 0xD ||
          (c >= 0x20 && c <= 0xD7FF) ||
          (c >= 0xE000 && c <= 0xFFFD) ||
          (c >= 0x10000 && c <= 0x10FFFF)) {
        final ch = String.fromCharCode(c);
        if (ch == '&') {
          buf.write('&amp;');
        } else if (ch == '<') {
          buf.write('&lt;');
        } else if (ch == '>') {
          buf.write('&gt;');
        } else if (ch == '"') {
          buf.write('&quot;');
        } else {
          buf.write(ch);
        }
      }
    }
    return buf.toString();
  }

  static String? _tryNumericCellValue(String value) {
    final t = value.trim();
    if (t.isEmpty || t.contains('/') || t.contains(':')) return null;
    final n = double.tryParse(t.replaceAll(',', '.'));
    if (n == null) return null;
    if (n == n.roundToDouble()) {
      return n.toStringAsFixed(0);
    }
    return t.replaceAll(',', '.');
  }

  /// Nasconde griglie Excel nel foglio (export PDF senza sfondo a tabella).
  static String _hideGridLinesInSheetXml(String sheetXml) {
    var xml = sheetXml.replaceAll('view="pageBreakPreview"', 'view="normal"');
    xml = xml.replaceAll('view="pageLayout"', 'view="normal"');
    if (xml.contains('showGridLines=')) {
      xml = xml.replaceAll(
        RegExp(r'showGridLines="[01]"'),
        'showGridLines="0"',
      );
    } else {
      xml = xml.replaceFirst(
        RegExp(r'<sheetView\b'),
        '<sheetView showGridLines="0" showRowColHeaders="0"',
      );
    }
    // Rimuove etichette «Pagina N» tipiche del page break preview.
    xml = xml.replaceAll(RegExp(r'\s*showZeros="1"'), ' showZeros="0"');
    if (!xml.contains('showZeros=')) {
      xml = xml.replaceFirst(
        RegExp(r'<sheetView\b'),
        '<sheetView showZeros="0"',
      );
    }
    return xml;
  }

}

/// Filtro celle consentite per [Giustificativo_Carburante_MDO.xlsx] (allineato a Python).
bool allowMdoGiustificativoCell(String cell) {
  const header = {'C4', 'F4', 'H4', 'L4', 'B29', 'C29', 'F29'};
  if (header.contains(cell)) return true;
  if (RegExp(r'^[E-N]5$').hasMatch(cell)) return true;
  if (RegExp(r'^[B-P](?:[6-9]|1\d|2[0-8])$').hasMatch(cell)) return true;
  return false;
}
