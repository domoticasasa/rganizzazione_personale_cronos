import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/carburante_euro_litro_guard.dart';

void main() {
  test('non blocca AdBlue oltre soglia', () {
    expect(
      CarburanteEuroLitroGuard.blockMessage(
        tipoCarburante: 'AdBlue',
        litri: 10,
        euro: 80,
      ),
      isNull,
    );
  });

  test('non blocca gasolio sotto soglia', () {
    expect(
      CarburanteEuroLitroGuard.blockMessage(
        tipoCarburante: 'Gasolio',
        litri: 50,
        euro: 100,
      ),
      isNull,
    );
  });

  test('blocca benzina oltre 4 euro al litro', () {
    final msg = CarburanteEuroLitroGuard.blockMessage(
      tipoCarburante: 'Benzina',
      litri: 10,
      euro: 50,
    );
    expect(msg, isNotNull);
    expect(msg, contains('Benzina'));
    expect(msg, contains('5,000/L'));
  });

  test('blocca HVO oltre 4 euro al litro', () {
    final msg = CarburanteEuroLitroGuard.blockMessage(
      tipoCarburante: 'HVO',
      litri: 10,
      euro: 50,
    );
    expect(msg, isNotNull);
    expect(msg, contains('HVO'));
  });

  test('blocca gasolio oltre 4 euro al litro', () {
    final msg = CarburanteEuroLitroGuard.blockMessage(
      tipoCarburante: 'Gasolio',
      litri: 20,
      euro: 90,
    );
    expect(msg, isNotNull);
    expect(msg, contains('Gasolio'));
    expect(msg, contains('4,500/L'));
  });

  test('ignora se litri o euro mancanti', () {
    expect(
      CarburanteEuroLitroGuard.blockMessage(
        tipoCarburante: 'Gasolio',
        litri: null,
        euro: 50,
      ),
      isNull,
    );
    expect(
      CarburanteEuroLitroGuard.blockMessage(
        tipoCarburante: 'Benzina',
        litri: 10,
        euro: null,
      ),
      isNull,
    );
  });
}
