import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/pos_commessa_mdo_proprieta_service.dart';
import 'package:organizzazione_personale_cronos/services/pos_mdo_proprieta_import_parser.dart';

void main() {
  test('template Excel MdO proprietà is parseable', () async {
    final bytes = PosMdoProprietaImportParser.buildTemplateExcelBytes();
    expect(bytes, isNotEmpty);

    final parsed = await PosMdoProprietaImportParser.parseFile(
      fileName: 'modello.xlsx',
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThanOrEqualTo(3));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(parsed.righe.first.codifica, 'MdO 01');
    expect(parsed.righe.last.proprietaNoleggio, 'NOLEGGIO');
  });

  test('normalizeCodifica maps MdO 01 to MDO1', () {
    expect(
      PosCommessaMdoProprietaService.normalizeCodifica('MdO 01'),
      'MDO1',
    );
    expect(
      PosCommessaMdoProprietaService.normalizeCodifica('MdO4'),
      'MDO4',
    );
  });

  test('example MdO xlsx parses rows', () async {
    const path =
        r'c:\Users\alexandru.cibuc\Desktop\logistica\qsa\02.2 Elenco MdO_xx.xx.xx.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = Uint8List.fromList(await file.readAsBytes());
    final parsed = await PosMdoProprietaImportParser.parseFile(
      fileName: file.uri.pathSegments.last,
      bytes: bytes,
    );
    expect(parsed.righe.length, greaterThan(0));
    expect(parsed.dataUltimoAggiornamento, isNotNull);
    expect(
      parsed.righe.any(
        (r) => r.codifica == 'MdO 01' && r.targaMatricola == 'VCE0C15DE00001525',
      ),
      isTrue,
    );
  });
}
