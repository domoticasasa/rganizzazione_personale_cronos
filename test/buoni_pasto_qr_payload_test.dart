import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/buoni_pasto_qr_payload.dart';

void main() {
  test('encode e parse payload QR', () {
    const token = 'abc123def';
    final payload = encodeBuoniPastoQrPayload(token);
    expect(payload, 'CRONOS-BP:abc123def');
    expect(parseBuoniPastoQrToken(payload), token);
    expect(parseBuoniPastoQrToken(token), token);
  });

  test('tipoPastoFromHour', () {
    expect(tipoPastoFromHour(10), 'pranzo');
    expect(tipoPastoFromHour(16), 'pranzo');
    expect(tipoPastoFromHour(17), 'cena');
    expect(tipoPastoFromHour(21), 'cena');
  });
}
