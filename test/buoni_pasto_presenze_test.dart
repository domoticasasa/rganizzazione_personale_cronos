import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/buoni_pasto_service.dart';
import 'package:organizzazione_personale_cronos/utils/buoni_pasto_export.dart';

void main() {
  test('BuoniPastoStatoOggi blocca secondo pasto dello stesso tipo', () {
    final stato = BuoniPastoStatoOggi(
      dataPasto: DateTime(2026, 7, 7),
      tipoCorrente: 'pranzo',
      pranzoRegistrato: true,
      cenaRegistrata: false,
    );
    expect(stato.giaRegistratoTipoCorrente, isTrue);
    expect(stato.registratoPerTipo('pranzo'), isTrue);
    expect(stato.registratoPerTipo('cena'), isFalse);
  });

  test('BuoniPastoGiornoPasti riepilogo', () {
    expect(const BuoniPastoGiornoPasti().riepilogo, '—');
    expect(const BuoniPastoGiornoPasti(pranzo: true).riepilogo, 'P');
    expect(const BuoniPastoGiornoPasti(cena: true).riepilogo, 'C');
    expect(
      const BuoniPastoGiornoPasti(pranzo: true, cena: true).riepilogo,
      'P+C',
    );
  });

  test('buildPresenzeCsv include dipendenti e giorni', () {
    final report = BuoniPastoPresenzeReport(
      dal: DateTime(2026, 7, 1),
      al: DateTime(2026, 7, 2),
      giorni: [DateTime(2026, 7, 1), DateTime(2026, 7, 2)],
      dipendenti: [
        BuoniPastoDipendentePresenza(
          personaleIdUuid: 'a',
          nome: 'Mario Rossi',
          matricola: '100',
          pastiPerGiorno: {
            '2026-07-01': const BuoniPastoGiornoPasti(pranzo: true),
          },
        ),
      ],
    );
    final csv = BuoniPastoExport.buildPresenzeCsv(report);
    expect(csv, contains('Dipendente'));
    expect(csv, contains('Mario Rossi'));
    expect(csv, contains('P'));
    expect(csv, contains('—'));
  });

  test('presenzeXlsxBytes genera file non vuoto', () {
    final report = BuoniPastoPresenzeReport(
      dal: DateTime(2026, 7, 1),
      al: DateTime(2026, 7, 1),
      giorni: [DateTime(2026, 7, 1)],
      dipendenti: const [
        BuoniPastoDipendentePresenza(
          personaleIdUuid: 'a',
          nome: 'Mario Rossi',
          matricola: '100',
        ),
      ],
    );
    final bytes = BuoniPastoExport.presenzeXlsxBytes(report);
    expect(bytes.length, greaterThan(100));
  });
}
