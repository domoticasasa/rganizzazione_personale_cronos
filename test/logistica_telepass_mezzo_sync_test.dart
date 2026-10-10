import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/logistica_telepass_mezzo_sync.dart';

void main() {
  test('isTelepassValueEmpty riconosce valori vuoti', () {
    expect(isTelepassValueEmpty(null), isTrue);
    expect(isTelepassValueEmpty(''), isTrue);
    expect(isTelepassValueEmpty('--'), isTrue);
    expect(isTelepassValueEmpty('no telepass'), isTrue);
    expect(isTelepassValueEmpty('SENZA'), isTrue);
    expect(isTelepassValueEmpty('Senza Telepass'), isTrue);
    expect(isTelepassValueEmpty('SENZA: PASSATO A N58'), isTrue);
    expect(isTelepassValueEmpty('TP12345'), isFalse);
  });

  test('telepassKeysEqual confronto case-insensitive', () {
    expect(telepassKeysEqual('ABC123', 'abc123'), isTrue);
    expect(telepassKeysEqual('ABC123', 'ABC124'), isFalse);
  });

  test('findMezzoForTelepassKey preferisce mezzo con telepass esatto', () {
    final mezzi = [
      {
        'targa': 'GW734JW',
        'telepass': 'TP-001',
        'assegnatario_attuale': 'Afflitto Gregorio',
      },
      {
        'targa': 'OP123XX',
        'telepass': 'TP-002',
        'assegnatario_attuale': 'Scopece Francesco',
      },
    ];
    final found = findMezzoForTelepassKey('tp-002', mezzi);
    expect(found?['targa'], 'OP123XX');
    expect(found?['assegnatario_attuale'], 'Scopece Francesco');
  });

  test('assegnazione nessuna / targa', () {
    expect(isTelepassVehicleAssignment('GW734JW'), isTrue);
    expect(isTelepassVehicleAssignment(''), isFalse);
    expect(
      telepassAssegnazioneKeyFromTarga(null),
      telepassAssegnazioneKeyFromTarga(''),
    );
    expect(
      mezzoTargaFromTelepassAssegnazioneKey(
        telepassAssegnazioneKeyFromTarga(null),
      ),
      '',
    );
    expect(labelTelepassAssegnazione(''), 'Nessuna assegnazione');
    expect(labelTelepassAssegnazione('AB123CD'), 'AB123CD');
  });

  test('findMezzoForTelepassKey fallback su targa', () {
    final mezzi = [
      {
        'targa': 'GW734JW',
        'telepass': '',
        'assegnatario_attuale': 'Afflitto Gregorio',
      },
    ];
    final found = findMezzoForTelepassKey('TP-999', mezzi, fallbackTarga: 'GW734JW');
    expect(found?['targa'], 'GW734JW');
  });
}
