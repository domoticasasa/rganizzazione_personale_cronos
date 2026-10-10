import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/mdo_rifornimento_service.dart';

void main() {
  group('isMdoRifornimentoCompleteFromRow', () {
    test('parziale: litri totali > somma mezzi', () {
      final row = {
        'litri': 158.81,
        'rifornimento_completo': true,
        'mezzi_riforniti_json': [
          {'mezzo': 'A23', 'litri': 40},
        ],
      };
      expect(isMdoRifornimentoCompleteFromRow(row), isFalse);
      expect(
        isMdoRifornimentoLockedForDipendente(row, dipendenteMode: true),
        isFalse,
      );
    });

    test('completo: litri totali = somma mezzi', () {
      final row = {
        'litri': 40,
        'rifornimento_completo': false,
        'mezzi_riforniti_json': [
          {'mezzo': 'A23', 'litri': 40},
        ],
      };
      expect(isMdoRifornimentoCompleteFromRow(row), isTrue);
      expect(
        isMdoRifornimentoLockedForDipendente(row, dipendenteMode: true),
        isTrue,
      );
    });

    test('admin non bloccato anche se completo', () {
      final row = {
        'litri': 10,
        'mezzi_riforniti_json': [
          {'mezzo': 'A23', 'litri': 10},
        ],
      };
      expect(
        isMdoRifornimentoLockedForDipendente(row, dipendenteMode: false),
        isFalse,
      );
    });
  });
}
