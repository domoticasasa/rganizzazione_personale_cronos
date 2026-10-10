import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/buoni_pasto_qr_payload.dart';

void main() {
  test('parseBuoniPastoQrToken accetta prefisso CRONOS-BP', () {
    expect(parseBuoniPastoQrToken('CRONOS-BP:abc123'), 'abc123');
    expect(parseBuoniPastoQrToken('abc123'), 'abc123');
  });

  test('parseBuoniPastoQrToken accetta URL fotocamera ?bp=', () {
    expect(
      parseBuoniPastoQrToken('https://www.gestopro360.it/?bp=abc123'),
      'abc123',
    );
    expect(
      parseBuoniPastoQrToken('https://www.gestopro360.it/?bp=abc123#/'),
      'abc123',
    );
    expect(
      parseBuoniPastoQrTokenFromUri(
        Uri.parse('https://www.gestopro360.it/?bp=deadbeef'),
      ),
      'deadbeef',
    );
  });

  test('encodeBuoniPastoQrPrintPayload è un link HTTPS', () {
    expect(
      encodeBuoniPastoQrPrintPayload('abc123'),
      'https://www.gestopro360.it/?bp=abc123',
    );
  });
}
