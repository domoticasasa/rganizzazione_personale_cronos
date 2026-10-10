import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/pos_mezzi_stradali_import_parser.dart';

void main() {
  test('template Excel mezzi stradali is parseable', () async {
    final bytes = PosMezziStradaliImportParser.buildTemplateExcelBytes();
    expect(bytes, isNotEmpty);

    final parsed = await PosMezziStradaliImportParser.parseFile(
      fileName: 'modello.xlsx',
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThanOrEqualTo(2));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(parsed.righe.first.codifica, 'N07');
    expect(parsed.righe.first.targa, 'FZ811NS');
  });

  test('example mezzi stradali xlsx parses rows', () async {
    const path =
        r'c:\Users\alexandru.cibuc\Desktop\logistica\qsa\02.1 Elenco Mezzi Stradali_xx.xx.xx.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = Uint8List.fromList(await file.readAsBytes());
    final parsed = await PosMezziStradaliImportParser.parseFile(
      fileName: file.uri.pathSegments.last,
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThan(0));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(
      parsed.righe.any((r) => r.codifica == 'N07' && r.targa == 'FZ811NS'),
      isTrue,
    );
  });
}
