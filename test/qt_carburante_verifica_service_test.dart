import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/qt_carburante_fatturazione_parser.dart';
import 'package:organizzazione_personale_cronos/services/qt_carburante_verifica_service.dart';

void main() {
  test('isoDayFromDb ignora fuso orario', () {
    expect(
      QtCarburanteVerificaService.isoDayFromDbForTest(
        '2026-05-13T23:00:00.000Z',
      ),
      '2026-05-13',
    );
    expect(
      QtCarburanteVerificaService.isoDayFromDbForTest('2026-05-04'),
      '2026-05-04',
    );
  });

  test('volumeMatch tollera arrotondamento RCC', () {
    expect(QtCarburanteVerificaService.volumeMatchForTest(42.35, 42), isTrue);
    expect(QtCarburanteVerificaService.volumeMatchForTest(63.91, 63.91), isTrue);
    expect(QtCarburanteVerificaService.volumeMatchForTest(70, 58), isFalse);
  });

  test('euroMatch tollera piccole differenze fattura vs RCC', () {
    expect(QtCarburanteVerificaService.euroMatchForTest(90.50, 90.45), isTrue);
    expect(QtCarburanteVerificaService.euroMatchForTest(130.40, 130), isTrue);
    expect(QtCarburanteVerificaService.euroMatchForTest(200, 130), isFalse);
  });

  test('dateSkewDays consente scarto di pochi giorni', () {
    expect(
      QtCarburanteVerificaService.dateSkewDaysForTest(
        '2026-05-05',
        '2026-05-04',
      ),
      1,
    );
    expect(
      QtCarburanteVerificaService.dateSkewDaysForTest(
        '2026-05-07',
        '2026-05-04',
      ),
      3,
    );
  });

  test('prodottiCompatibili allinea Diesel QT e Gasolio RCC', () {
    expect(
      QtCarburanteVerificaService.prodottiCompatibiliForTest(
        'DIESEL DISPENSED',
        'Gasolio',
      ),
      isTrue,
    );
    expect(
      QtCarburanteVerificaService.prodottiCompatibiliForTest(
        'ADBLUE DISPENSED',
        'AdBlue',
      ),
      isTrue,
    );
    expect(
      QtCarburanteVerificaService.prodottiCompatibiliForTest(
        'DIESEL DISPENSED',
        'Benzina',
      ),
      isFalse,
    );
  });

  test('prodottiCompatibili rifiuta Diesel QT vs Benzina MDO con tipo', () {
    expect(
      QtCarburanteVerificaService.prodottiCompatibiliForTest(
        'DIESEL DISPENSED',
        'Benzina',
      ),
      isFalse,
    );
    expect(
      QtCarburanteVerificaService.prodottiCompatibiliForTest(
        'DIESEL DISPENSED',
        'Gasolio',
      ),
      isTrue,
    );
  });

  test('quantitaMatch AdBlue tanica QT vs litri RCC', () {
    expect(
      QtCarburanteVerificaService.quantitaMatchForTest(
        prodottoQt: 'ADBLUE CANISTERS',
        volumeQt: 1,
        importoQt: 28,
        litriRcc: 10,
        euroRcc: 28,
        tipoRcc: 'AdBlue',
      ),
      isTrue,
    );
    expect(
      QtCarburanteVerificaService.quantitaMatchForTest(
        prodottoQt: 'ADBLUE CANISTERS',
        volumeQt: 1,
        importoQt: 28,
        litriRcc: 10,
        euroRcc: 28,
      ),
      isTrue,
    );
    expect(
      QtCarburanteVerificaService.quantitaMatchForTest(
        prodottoQt: 'ADBLUE CANISTERS',
        volumeQt: 1,
        importoQt: 28,
        litriRcc: 10,
        euroRcc: 28,
        tipoRcc: 'Gasolio',
      ),
      isFalse,
    );
  });

  test('nearMatchScore rileva errore su data con litri ed euro uguali', () {
    final rcc = QtCarburanteRccSenzaFatturaRow(
      fonte: QtCarburanteFonteGiustificativo.rccMdo,
      idUuid: 'r1',
      numeroCarta: '1234567890614',
      dataRifornimento: DateTime(2026, 6, 2),
      litri: 172.75,
      euro: 350,
      tipoCarburante: 'Gasolio',
      nomeCognome: 'Rossi Mario',
    );
    final qt = QtCarburanteTrxRow(
      rigaExcel: 1,
      numeroCarta: '1234567890614',
      prodotto: 'DIESEL DISPENSED',
      dataTransazione: DateTime(2026, 6, 5),
      volume: 172.75,
      importo: 350,
    );
    final note = <String>[];
    final score = QtCarburanteVerificaService.nearMatchScoreForTest(
      rcc: rcc,
      qt: qt,
      differenze: note,
    );
    expect(score, isNotNull);
    expect(score!, greaterThanOrEqualTo(45));
    expect(note.any((n) => n.contains('Data:')), isTrue);
  });

  test('nearMatchScore rileva errore su importo con data e litri uguali', () {
    final rcc = QtCarburanteRccSenzaFatturaRow(
      fonte: QtCarburanteFonteGiustificativo.rccStradali,
      idUuid: 'r2',
      numeroCarta: '9876543210713',
      dataRifornimento: DateTime(2026, 6, 3),
      litri: 31.17,
      euro: 62,
      tipoCarburante: 'Gasolio',
      nomeCognome: 'Verdi Luca',
    );
    final qt = QtCarburanteTrxRow(
      rigaExcel: 2,
      numeroCarta: '9876543210713',
      prodotto: 'DIESEL DISPENSED',
      dataTransazione: DateTime(2026, 6, 3),
      volume: 31.17,
      importo: 76,
    );
    final note = <String>[];
    final score = QtCarburanteVerificaService.nearMatchScoreForTest(
      rcc: rcc,
      qt: qt,
      differenze: note,
    );
    expect(score, isNotNull);
    expect(note.any((n) => n.contains('Euro:')), isTrue);
  });

  test('nearMatchScore ignora abbinamenti perfetti', () {
    final rcc = QtCarburanteRccSenzaFatturaRow(
      fonte: QtCarburanteFonteGiustificativo.rccMdo,
      idUuid: 'r3',
      numeroCarta: '111',
      dataRifornimento: DateTime(2026, 6, 1),
      litri: 40,
      euro: 90,
      tipoCarburante: 'Gasolio',
    );
    final qt = QtCarburanteTrxRow(
      rigaExcel: 1,
      numeroCarta: '111',
      prodotto: 'DIESEL DISPENSED',
      dataTransazione: DateTime(2026, 6, 1),
      volume: 40,
      importo: 90,
    );
    expect(
      QtCarburanteVerificaService.nearMatchScoreForTest(rcc: rcc, qt: qt),
      isNull,
    );
  });
}
