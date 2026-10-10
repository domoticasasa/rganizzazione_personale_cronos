import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/viaggi_mezzi_qr_payload.dart';

void main() {
  test('parseViaggiMezziQrToken accetta prefisso CRONOS-VM', () {
    expect(parseViaggiMezziQrToken('CRONOS-VM:abc123'), 'abc123');
    expect(parseViaggiMezziQrToken('abc123'), 'abc123');
  });

  test('parseViaggiMezziQrToken accetta URL fotocamera ?vm=', () {
    expect(
      parseViaggiMezziQrToken('https://www.gestopro360.it/?vm=abc123'),
      'abc123',
    );
    expect(
      parseViaggiMezziQrToken('https://www.gestopro360.it/?vm=abc123#/'),
      'abc123',
    );
    expect(
      parseViaggiMezziQrTokenFromUri(
        Uri.parse('https://www.gestopro360.it/?vm=deadbeef'),
      ),
      'deadbeef',
    );
  });

  test('encodeViaggiMezziQrPrintPayload è un link HTTPS', () {
    expect(
      encodeViaggiMezziQrPrintPayload('abc123'),
      'https://www.gestopro360.it/?vm=abc123',
    );
  });

  test('mezzoLabelFromParts compone targa e modello', () {
    expect(
      mezzoLabelFromParts(targa: 'AB123CD', marca: 'Fiat', modello: 'Ducato'),
      'AB123CD · Fiat Ducato',
    );
  });
}
