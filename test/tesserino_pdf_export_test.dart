import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/tesserino_pdf_export.dart';
import 'package:organizzazione_personale_cronos/widgets/cronos_tesserino_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildTesserinoPdfBytes con due righe extra genera PDF', () async {
    final data = CronosTesserinoViewData(
      nome: 'Alexandru',
      cognome: 'Cibuc',
      natoIl: '08/02/1988',
      assuntoDal: '06/09/2021',
      numeroTesserino: 'ALECIB01001',
      righeExtra: const [
        r'RFI.DOIT.MI.ING\A0011\P\2026\0006448',
        'Data di autorizzazione 2/4/2026',
      ],
    );

    final bytes = await buildTesserinoPdfBytes(data: data);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
