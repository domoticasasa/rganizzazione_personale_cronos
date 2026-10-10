import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/rcc_ricevuta_carburante_parser.dart';

void main() {
  const sample = '''
Ricevuta
Completato
69,19 €
Dettagli acquisto
Carta
710200167346000648
Tipo
Acquisto
Data
29/06/2026 06:56
Importo
69,19 Euro
Info prodotto
Prodotto
Regular Unleaded
Quantità
37,83 L
Prezzo unitario
1,829 Euro
Info acquisto
Descr. compagnia
ENI
KM percorsi
28106
''';

  test('parse estrae campi da ricevuta ENI/QT', () {
    final p = RccRicevutaCarburanteParser.parse(sample);
    expect(p.dataGgMmAaaa, '29/06/2026');
    expect(p.numeroCarta, '710200167346000648');
    expect(p.litri, '37,83');
    expect(p.euro, '69,19');
    expect(p.km, '28106');
    expect(p.tipoCarburante, 'Benzina');
    expect(p.hasAnyField, isTrue);
  });

  test('parse estrae campi con OCR su una riga (senza a capo)', () {
    const ocrBlob = '''
Ricevuta Completato 69,19 € Dettagli acquisto Carta 710200167346000648 Tipo Acquisto Data 29/06/2026 06:56 Importo 69,19 Euro Info prodotto Prodotto Regular Unleaded Quantità 37,83 L KM percorsi 28106
''';
    final p = RccRicevutaCarburanteParser.parse(ocrBlob);
    expect(p.dataGgMmAaaa, '29/06/2026');
    expect(p.numeroCarta, '710200167346000648');
    expect(p.litri, '37,83');
    expect(p.euro, '69,19');
    expect(p.km, '28106');
    expect(p.tipoCarburante, 'Benzina');
  });

  test('parse estrae ricevuta destra (stesso formato, data diversa)', () {
    const sampleRight = '''
Ricevuta Completato 62,15 € Dettagli acquisto Carta 710200167346000648 Tipo Acquisto Data 16/06/2026 08:53 Importo 62,15 Euro Info prodotto Prodotto Regular Unleaded Quantità 33,43 L KM percorsi 25287
''';
    final p = RccRicevutaCarburanteParser.parse(sampleRight);
    expect(p.dataGgMmAaaa, '16/06/2026');
    expect(p.numeroCarta, '710200167346000648');
    expect(p.litri, '33,43');
    expect(p.euro, '62,15');
    expect(p.km, '25287');
  });

  test('normalizeOcrText corregge data OCR con l al posto di 1', () {
    const ocr = 'Data l6/06/2026 08:53';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.dataGgMmAaaa, '16/06/2026');
  });

  test('parse estrae campi layout due colonne QT', () {
    const twoCol = '''
Ricevuta
69,19 €
Dettagli acquisto
Carta                         710200167346000648
Tipo                          Acquisto
Data                          29/06/2026 06:56
Importo                       69,19 Euro
Info prodotto
Prodotto                      Regular Unleaded
Quantità                      37,83 L
KM percorsi                   28106
''';
    final p = RccRicevutaCarburanteParser.parse(twoCol);
    expect(p.dataGgMmAaaa, '29/06/2026');
    expect(p.numeroCarta, '710200167346000648');
    expect(p.litri, '37,83');
    expect(p.euro, '69,19');
    expect(p.km, '28106');
    expect(p.tipoCarburante, 'Benzina');
  });

  test('mapProdottoToTipoRcc diesel e adblue', () {
    expect(
      RccRicevutaCarburanteParser.mapProdottoToTipoRcc('DIESEL DISPENSED'),
      'Gasolio',
    );
    expect(
      RccRicevutaCarburanteParser.mapProdottoToTipoRcc('AdBlue tanica'),
      'AdBlue',
    );
    expect(
      RccRicevutaCarburanteParser.mapProdottoToTipoRcc('BENZSP'),
      'Benzina',
    );
  });

  test('parse estrae scontrino Enilive (layout diverso dallo screenshot app)', () {
    const scontrino = '''
enilive
DOLEMA SNC DI BARONI MAR
AUTOSTRADA A1 - ADS AR
FIORENZUOLA D'ARDA
ACQUISTO
28/09/2026 07:22 02647
MULTICARD ROUTEX
71020******0648
SCAD 07/31
NUMERO DOC 611239
CODICE AUT. 044701
27101245 BENZSP
L 39,84
EUR 1,990
IMPORTO EUR 79,28
KM:28450
TRANSAZIONE ESEGUITA
''';
    final p = RccRicevutaCarburanteParser.parse(scontrino);
    expect(p.dataGgMmAaaa, '28/09/2026');
    expect(p.numeroCarta, '71020******0648');
    expect(p.litri, '39,84');
    expect(p.euro, '79,28');
    expect(p.km, '28450');
    expect(p.tipoCarburante, 'Benzina');
    expect(RccRicevutaCarburanteParser.isCartaMascherata(p.numeroCarta), isTrue);
  });

  test('carta mascherata sullo scontrino abbina la Multicard completa', () {
    expect(
      RccRicevutaCarburanteParser.carteCompatibili(
        '71020******0648',
        '710200167346000648',
      ),
      isTrue,
    );
    expect(
      RccRicevutaCarburanteParser.carteCompatibili(
        '71020******0648',
        '7102999999999999',
      ),
      isFalse,
    );
  });

  test('parse estrae scontrino Enilive reale (foto in auto)', () {
    const scontrino = '''
enilive
DOLEMA SNC DI BARONI MAR
AUTOSTRADA A1 - ADS AR
FIORENZUOLA D'ARDA
ACQUISTO
28/09/2026 07:22 02647
MULTICARD ROUTEX
71020******0648
SCAD 07/31
AID A0000008371020
CHIP
NUMERO DOC 611239
CODICE AUT. 044701
27101245 BENZSP
L 39,84
EUR 1,990
IMPORTO EUR 79,28
KM:28450
TRANSAZIONE ESEGUITA
''';
    final p = RccRicevutaCarburanteParser.parse(scontrino);
    expect(p.dataGgMmAaaa, '28/09/2026');
    expect(p.numeroCarta, '71020******0648');
    expect(p.litri, '39,84');
    expect(p.euro, '79,28');
    expect(p.km, '28450');
    expect(p.tipoCarburante, 'Benzina');
    expect(RccRicevutaCarburanteParser.isCartaMascherata(p.numeroCarta), isTrue);
    expect(
      RccRicevutaCarburanteParser.carteCompatibili(
        p.numeroCarta!,
        '710200167346000648',
      ),
      isTrue,
    );
  });

  test('non usa AID EMV come numero Multicard', () {
    const ocr = '''
MULTICARD ROUTEX
AID A0000008371020
IMPORTO EUR 79,28
''';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.numeroCarta, isNull);
    expect(p.euro, '79,28');
  });

  test('ricostruisce Multicard mascherata da OCR senza asterischi', () {
    const ocr = '''
MULTICARD ROUTEX
71020 0648
SCAD 07/31
AID A0000008371020
L 39,84
IMPORTO EUR 79,28
''';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.numeroCarta, '71020******0648');
  });

  test('corregge OCR 7I020 e puntini al posto degli asterischi', () {
    const ocr = '''
MULTICARD ROUTEX
7I020......0648
L 39,84
IMPORTO EUR 79,28
''';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.numeroCarta, '71020******0648');
  });

  test('OCR Enilive: carta sulla stessa riga di SCAD e anno 2020→corrente', () {
    const ocr = '''
ACQUISTO
28/09/2020 07:22 02647
MULTICARD ROUTEX 71020******0648 SCAD 07/31
AID A0000008371020
27101245 BENZSP
L 39,84
IMPORTO EUR 79,28
KM:28450
''';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.numeroCarta, '71020******0648');
    expect(p.tipoCarburante, 'Benzina');
    expect(p.dataGgMmAaaa, isNot('28/09/2020'));
    expect(p.dataGgMmAaaa, startsWith('28/09/'));
    expect(p.litri, '39,84');
    expect(p.euro, '79,28');
  });

  test('OCR Enilive: Multicard senza asterischi attaccata a SCAD', () {
    const ocr = '''
MULTICARD ROUTEX
710200648 SCAD 07/31
27101245 BENZSP
L 39,84
IMPORTO EUR 79,28
''';
    final p = RccRicevutaCarburanteParser.parse(ocr);
    expect(p.numeroCarta, '71020******0648');
    expect(p.tipoCarburante, 'Benzina');
  });

  test('parse screenshot app QT resta invariato', () {
    const app = '''
Dettagli acquisto
Carta                         710200167346000648
Tipo                          Acquisto
Data                          30/09/2026 09:21
Importo                       79,26 Euro
Prodotto                      Regular Unleaded
Quantità                      39,83 L
Prezzo unitario               1,990 Euro
KM percorsi                   21103
''';
    final p = RccRicevutaCarburanteParser.parse(app);
    expect(p.dataGgMmAaaa, '30/09/2026');
    expect(p.numeroCarta, '710200167346000648');
    expect(p.litri, '39,83');
    expect(p.euro, '79,26');
    expect(p.km, '21103');
    expect(p.tipoCarburante, 'Benzina');
  });
}
