import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/simple_excel_table_io.dart';

void main() {
  test('buildTemplate with const headers does not throw', () {
    final bytes = SimpleExcelTableIo.buildTemplate(
      sheetName: 'Commesse',
      titleRow: 'Test',
      headers: const ['Codice', 'Attiva'],
      exampleRows: const [
        ['MLD-001', 'SI'],
      ],
    );
    expect(bytes.length, greaterThan(100));
  });
}
