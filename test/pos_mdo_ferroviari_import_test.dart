import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/pos_mdo_ferroviari_import_parser.dart';

void main() {
  test('template Excel MdO ferroviari is parseable', () async {
    final bytes = PosMdoFerroviariImportParser.buildTemplateExcelBytes();
    expect(bytes, isNotEmpty);

    final parsed = await PosMdoFerroviariImportParser.parseFile(
      fileName: 'modello.xlsx',
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThanOrEqualTo(2));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(parsed.righe.first.codifica, 'A21');
    expect(parsed.righe.first.descrizione, 'AUTOSCALA');
  });

  test('example MdO ferroviari xlsx parses rows', () async {
    const path =
        r'c:\Users\alexandru.cibuc\Desktop\logistica\qsa\02.3 Elenco MdO Ferroviari_xx.xx.xx.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = Uint8List.fromList(await file.readAsBytes());
    final parsed = await PosMdoFerroviariImportParser.parseFile(
      fileName: file.uri.pathSegments.last,
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThan(0));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(
      parsed.righe.any((r) => r.codifica == 'A21' && r.descrizione == 'AUTOSCALA'),
      isTrue,
    );
  });
}
