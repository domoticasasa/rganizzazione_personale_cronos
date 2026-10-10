import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/logistica_box_linked_sync.dart';

void main() {
  test('isUbicazioneLinkedRef riconosce BOX, CON e MDO Axx', () {
    expect(isUbicazioneLinkedRef('BOX09'), isTrue);
    expect(isUbicazioneLinkedRef('CON15'), isTrue);
    expect(isUbicazioneLinkedRef('A31'), isTrue);
    expect(isUbicazioneLinkedRef('UFF03'), isFalse);
  });

  test('linkedAssetFieldsFromLogisticaBoxRow copia commessa e GPS', () {
    final fields = linkedAssetFieldsFromLogisticaBoxRow({
      'commessa_id': 'comm-1',
      'latitudine': 45.489045,
      'longitudine': 9.216067,
      'posizione_gps': '45.489045, 9.216067',
    });
    expect(fields['commessa_id'], 'comm-1');
    expect(fields['latitudine'], 45.489045);
    expect(fields['longitudine'], 9.216067);
  });

  test('linkedAssetFieldsFromMdoRow risolve commessa da testo', () {
    final fields = linkedAssetFieldsFromMdoRow(
      {
        'commessa': 'TE-15-24 ACC MI CENTRALE',
        'latitudine': 45.1,
        'longitudine': 9.2,
      },
      {'uuid-1': 'TE-15-24 ACC MI CENTRALE'},
    );
    expect(fields['commessa_id'], 'uuid-1');
    expect(fields['latitudine'], 45.1);
  });

  test('logisticaBoxRefLinkedFieldsIndex mappa CON15', () {
    final index = logisticaBoxRefLinkedFieldsIndex([
      {
        'numero_interno': 'CON15',
        'codice_box': 'CON15',
        'commessa_id': 'comm-1',
        'latitudine': 45.1,
        'longitudine': 9.2,
      },
    ]);
    expect(index['CON15']?['commessa_id'], 'comm-1');
  });

  test('linkedAssetRowNeedsUbicazioneSync rileva differenze', () {
    expect(
      linkedAssetRowNeedsUbicazioneSync(
        {'commessa_id': 'old', 'latitudine': 1.0},
        {'commessa_id': 'new', 'latitudine': 1.0},
      ),
      isTrue,
    );
    expect(
      linkedAssetRowNeedsUbicazioneSync(
        {'commessa_id': 'same', 'latitudine': 1.0},
        {'commessa_id': 'same', 'latitudine': 1.0},
      ),
      isFalse,
    );
  });
}
