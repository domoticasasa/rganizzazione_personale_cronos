import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/pos_maestranze_import_parser.dart';

void main() {
  test('template Excel is parseable', () async {
    final bytes = PosMaestranzeImportParser.buildTemplateExcelBytes();
    expect(bytes, isNotEmpty);

    final parsed = await PosMaestranzeImportParser.parseFile(
      fileName: 'modello.xlsx',
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThanOrEqualTo(2));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(parsed.righe.first.cognome, 'Rossi');
    expect(parsed.righe.first.nome, 'Mario');
  });

  test('example maestranze xlsx parses names', () async {
    const path =
        r'c:\Users\alexandru.cibuc\Desktop\logistica\qsa\01 Elenco Maestranze_ xx.xx.xx.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = Uint8List.fromList(await file.readAsBytes());
    final parsed = await PosMaestranzeImportParser.parseFile(
      fileName: file.uri.pathSegments.last,
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThan(10));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(
      parsed.righe.any((r) => r.cognome == 'Cibuc' && r.nome == 'Alexandru'),
      isTrue,
    );
  });
}
