import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/personale_data_export.dart';

void main() {
  test('buildCsv include intestazioni e separatore punto e virgola', () {
    final csv = PersonaleDataExport.buildCsv([
      {
        'full_name': 'Rossi Mario',
        'email': 'mario@example.com',
        'matricola': 'A001',
        'numero_tesserino': 'PAT001',
        'telefono': '3331234567',
        'data_nascita': '1990-05-10',
        'data_assunzione': '2020-01-15',
        'camera_tipo_default': 'singola',
        'active': true,
        'user_id': 'uuid-1',
      },
    ]);
    expect(csv.startsWith('Cognome e Nome;Email;'), isTrue);
    expect(csv, contains('Rossi Mario'));
    expect(csv, contains('Sì'));
    expect(csv, isNot(contains('+')));
  });
}
