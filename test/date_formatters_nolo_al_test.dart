import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/date_formatters.dart';

void main() {
  test('formatDateDdMmYyyy extracts date from nolo_al note', () {
    const raw = '17/01/2025 - IN ATTESA INFO GCF X SICILIAZ';
    expect(formatDateDdMmYyyy(raw), '17/01/2025');
    expect(parseFlexibleDateToIsoDate(raw), '2025-01-17');
    expect(parseFlexibleDateToDateTime(raw), DateTime(2025, 1, 17));
  });

  test('parseSupabaseTimestampToItaly does not throw on SICILIAZ suffix', () {
    const raw = '17/01/2025 - IN ATTESA INFO GCF X SICILIAZ';
    expect(() => parseSupabaseTimestampToItaly(raw), returnsNormally);
    expect(parseSupabaseTimestampToItaly(raw), isNull);
  });
}
