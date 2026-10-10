import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/dislocazione_programma_impegno_import.dart';

void main() {
  test('parse Programma impegno 07-09-26', () {
    const path =
        r'c:\Users\alexandru.cibuc\Desktop\37-Programma impegno personale 07-09-26.xlsx';
    final f = File(path);
    if (!f.existsSync()) {
      return;
    }
    final parsed = DislocazioneProgrammaImpegnoImport.parseBytes(
      Uint8List.fromList(f.readAsBytesSync()),
    );
    expect(parsed.dateColCount, greaterThan(300));
    expect(parsed.persone.length, greaterThan(100));
    expect(
      parsed.persone.any(
        (p) => p.nominativoExcel.toUpperCase().contains('AIBECHE'),
      ),
      isTrue,
    );
    expect(
      parsed.persone.any(
        (p) => p.nominativoExcel.toUpperCase().contains('ASSISTENZA PAI'),
      ),
      isFalse,
    );
  });
}
