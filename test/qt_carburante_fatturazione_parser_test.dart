import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/qt_carburante_fatturazione_parser.dart';

QtCarburanteTrxRow _trx({
  required String carta,
  required String data,
  double volume = 40,
  double importo = 100,
  String? file,
}) {
  final d = DateTime.parse(data);
  return QtCarburanteTrxRow(
    rigaExcel: 2,
    numeroCarta: carta,
    prodotto: 'DIESEL',
    dataTransazione: d,
    volume: volume,
    importo: importo,
    fileSorgente: file,
  );
}

void main() {
  test('mergeParsed unisce due file ed esclude duplicati', () {
    final a = QtCarburanteParseResult(
      fileName: 'QT_15052026.xlsx',
      righe: [
        _trx(carta: '710200163733000150', data: '2026-05-05', file: 'QT_15052026.xlsx'),
        _trx(carta: '710200163733000150', data: '2026-05-10', file: 'QT_15052026.xlsx'),
      ],
    );
    final b = QtCarburanteParseResult(
      fileName: 'QT_31052026.xlsx',
      righe: [
        _trx(carta: '710200163733000150', data: '2026-05-20', file: 'QT_31052026.xlsx'),
        _trx(carta: '710200163733000150', data: '2026-05-10', file: 'QT_31052026.xlsx'),
      ],
    );

    final merged = QtCarburanteFatturazioneParser.mergeParsed([a, b]);
    expect(merged.fileNames, ['QT_15052026.xlsx', 'QT_31052026.xlsx']);
    expect(merged.righe.length, 3);
    expect(merged.avviso, contains('duplicate escluse'));
  });
}
