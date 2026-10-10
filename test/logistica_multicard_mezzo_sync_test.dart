import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/logistica_multicard_mezzo_sync.dart';

void main() {
  test('extractMulticardNumbers da nota con smarrimento', () {
    const raw =
        '710200167346000564. -> SMARRITA RICHIESTA NUVA 02/03/26 710200163733001109';
    expect(
      extractMulticardNumbers(raw),
      ['710200167346000564', '710200163733001109'],
    );
    expect(primaryMulticardNumber(raw), '710200163733001109');
  });

  test('primaryMulticardNumber su campo pulito', () {
    expect(primaryMulticardNumber('710200163733001109.'), '710200163733001109');
  });

  test('assegnazione MDO / nessuna / targa', () {
    expect(isMulticardMdoAssignment('MDO'), isTrue);
    expect(isMulticardMdoAssignment('mdo'), isTrue);
    expect(isMulticardVehicleAssignment('GW734JW'), isTrue);
    expect(isMulticardVehicleAssignment('MDO'), isFalse);
    expect(isMulticardVehicleAssignment(''), isFalse);
    expect(isMulticardVehicleAssignment(kMulticardAssegnazioneNessuna), isFalse);
    expect(multicardAssegnazioneKeyFromTarga(null), kMulticardAssegnazioneNessuna);
    expect(mezzoTargaFromAssegnazioneKey(kMulticardAssegnazioneNessuna), '');
    expect(mezzoTargaFromAssegnazioneKey(''), '');
    expect(mezzoTargaFromAssegnazioneKey(kMulticardAssegnazioneMdo), 'MDO');
    expect(labelMulticardAssegnazione(''), 'Nessuna assegnazione');
    expect(labelMulticardAssegnazione('MDO'), 'MDO');
    expect(labelMulticardAssegnazione('AB123CD'), 'AB123CD');
  });

  test('findMezzoForMulticardKey preferisce mezzo con numero esatto', () {
    final mezzi = [
      {
        'targa': 'GW734JW',
        'multicard':
            '710200167346000564. -> SMARRITA RICHIESTA NUVA 02/03/26 710200163733001109',
        'assegnatario_attuale': 'Afflitto Gregorio',
      },
      {
        'targa': 'OP123XX',
        'multicard': '710200163733001109.',
        'assegnatario_attuale': 'Scopece Francesco',
      },
    ];
    final found = findMezzoForMulticardKey('710200163733001109', mezzi);
    expect(found?['targa'], 'OP123XX');
    expect(found?['assegnatario_attuale'], 'Scopece Francesco');
  });
}
