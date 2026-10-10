import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/mezzi_km_service.dart';

void main() {
  test('parseKmOreValue accetta numeri con separatori', () {
    expect(MezziKmService.parseKmOreValue('125430'), 125430);
    expect(MezziKmService.parseKmOreValue('125.430'), 125430);
    expect(MezziKmService.parseKmOreValue(''), isNull);
  });

  test('kmUltimoAggiornamentoLabel formatta data mezzo', () {
    expect(
      MezziKmService.kmUltimoAggiornamentoLabel({'km_aggiornato_il': null}),
      '—',
    );
    expect(
      MezziKmService.kmUltimoAggiornamentoLabel({
        'km_aggiornato_il': '2026-06-22T10:15:00+00:00',
      }),
      isNot('—'),
    );
  });
}
