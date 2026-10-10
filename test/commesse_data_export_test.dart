import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/commesse_data_export.dart';

void main() {
  test('buildCsv include intestazioni e separatore punto e virgola', () {
    final csv = CommesseDataExport.buildCsv([
      {
        'nome': 'TLC-05-20 DOTE FI-BO',
        'cig': '7169564F5D',
        'cig_derivato': '',
        'cup': 'J44H14000090005',
        'cliente': 'ATLANTE (HITACHI)',
        'pm': 'PIZZORNO',
        'dt': 'CASTRONOVO',
        'dt2': '',
        'latitudine': 41.9,
        'longitudine': 12.5,
        'active': true,
      },
    ]);

    expect(csv.startsWith('Nome;CIG;CIG derivato;CUP;'), isTrue);
    expect(csv, contains('TLC-05-20 DOTE FI-BO'));
    expect(csv, contains('PIZZORNO'));
    expect(csv, contains('Sì'));
  });
}
