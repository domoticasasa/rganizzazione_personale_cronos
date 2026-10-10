import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/tesserino_helpers.dart';

void main() {
  test('tesserinoRigheExtraFromPersonale legge array json', () {
    expect(
      tesserinoRigheExtraFromPersonale({
        'tesserino_righe_extra': ['COMMESSA: A', 'QUALIFICA: B'],
      }),
      ['COMMESSA: A', 'QUALIFICA: B'],
    );
  });

  test('tesserinoRigheExtraFromPersonale usa legacy singola riga', () {
    expect(
      tesserinoRigheExtraFromPersonale({
        'tesserino_extra_etichetta': 'QUALIFICA',
        'tesserino_extra_testo': 'OPERAIO',
      }),
      ['QUALIFICA: OPERAIO'],
    );
  });

  test('normalizeTesserinoRigheExtra rimuove righe vuote', () {
    expect(
      normalizeTesserinoRigheExtra([' A ', '', 'B']),
      ['A', 'B'],
    );
  });
}
