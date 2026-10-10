import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/carburante_giustificativi_stats_service.dart';

void main() {
  test('totali aggregati RCC e MDO', () {
    const stats = CarburanteGiustificativiStats(
      rccCount: 2,
      mdoCount: 1,
      rccLitri: 100.5,
      mdoLitri: 40,
      rccEuro: 200,
      mdoEuro: 80,
    );
    expect(stats.totalCount, 3);
    expect(stats.totalLitri, 140.5);
    expect(stats.totalEuro, 280);
  });

  test('buildReport raggruppa per mese e per tipo carburante', () {
    final report = CarburanteGiustificativiStatsService.buildReport(
      rccRows: [
        {
          'data_rifornimento': '2026-03-15',
          'litri': 50,
          'euro': 100,
          'tipo_carburante': 'Benzina',
        },
        {
          'data_rifornimento': '2026-03-16',
          'litri': 30,
          'euro': 60,
          'tipo_carburante': 'Gasolio',
        },
        {
          'data_rifornimento': '2026-02-10',
          'litri': 20,
          'euro': 40,
          'tipo_carburante': 'AdBlue',
        },
      ],
      mdoRows: [
        {
          'data_rifornimento': '2026-03-01',
          'litri': 10,
          'euro': 20,
        },
      ],
    );

    expect(report.totals.rccCount, 3);
    expect(report.totals.mdoCount, 1);
    expect(report.totals.perTipo.benzina.litri, 50);
    expect(report.totals.perTipo.gasolio.litri, 30);
    expect(report.totals.perTipo.adBlue.litri, 20);
    expect(report.months.length, 2);
    expect(report.months.first.monthKey, '2026-03');
    expect(report.months.first.stats.perTipo.benzina.count, 1);
    expect(report.months.first.stats.perTipo.gasolio.count, 1);
    expect(report.months.first.stats.perTipo.gasolio.litri, 30);
  });

  test('MDO con tipo carburante entra nella ripartizione corretta', () {
    final report = CarburanteGiustificativiStatsService.buildReport(
      rccRows: const [],
      mdoRows: [
        {
          'data_rifornimento': '2026-06-10',
          'litri': 40,
          'euro': 100,
          'tipo_carburante': 'Benzina',
        },
        {
          'data_rifornimento': '2026-06-11',
          'litri': 10,
          'euro': 30,
          'tipo_carburante': 'AdBlue',
        },
      ],
    );

    expect(report.totals.mdoLitri, 50);
    expect(report.totals.perTipo.benzina.litri, 40);
    expect(report.totals.perTipo.adBlue.litri, 10);
    expect(report.totals.perTipo.gasolio.litri, 0);
  });

  test('classifica diesel come gasolio', () {
    expect(
      CarburanteGiustificativiStatsService.buildReport(
        rccRows: [
          {
            'data_rifornimento': '2026-01-01',
            'litri': 5,
            'euro': 10,
            'tipo_carburante': 'DIESEL',
          },
        ],
        mdoRows: const [],
      ).totals.perTipo.gasolio.litri,
      5,
    );
  });

  test('classifica HVO in categoria dedicata', () {
    expect(
      CarburanteGiustificativiStatsService.buildReport(
        rccRows: [
          {
            'data_rifornimento': '2026-01-01',
            'litri': 12,
            'euro': 24,
            'tipo_carburante': 'HVO',
          },
        ],
        mdoRows: const [],
      ).totals.perTipo.hvo.litri,
      12,
    );
  });

  test('findRifornimentiOltreSoglia filtra per mese e soglia', () {
    final rccRows = [
      {
        'id_uuid': 'rcc-1',
        'data_rifornimento': '2026-03-15',
        'litri': 50,
        'euro': 100,
        'tipo_carburante': 'Benzina',
        'nome_cognome': 'Rossi',
        'n_carta_carburante': '1234',
        'cantiere': 'Roma',
      },
      {
        'id_uuid': 'rcc-2',
        'data_rifornimento': '2026-03-16',
        'litri': 40,
        'euro': 72,
        'tipo_carburante': 'Gasolio',
      },
      {
        'data_rifornimento': '2026-02-01',
        'litri': 10,
        'euro': 30,
        'tipo_carburante': 'Gasolio',
      },
    ];
    final mdoRows = [
      {
        'id_uuid': 'mdo-1',
        'data_rifornimento': '2026-03-01',
        'litri': 20,
        'euro': 50,
        'nome_cognome': 'Bianchi',
        'automezzo_mdo': 'Treno 1',
      },
    ];

    final oltre = CarburanteGiustificativiStatsService.findRifornimentiOltreSoglia(
      rccRows: rccRows,
      mdoRows: mdoRows,
      year: 2026,
      month: 3,
      sogliaEuroLitro: 1.9,
    );

    expect(oltre.length, 2);
    expect(oltre.first.idUuid, 'mdo-1');
    expect(oltre.first.euroLitro, 2.5);
    expect(oltre.first.fonte, CarburanteRifornimentoFonte.mdo);
    expect(
      oltre.any((v) => v.fonte == CarburanteRifornimentoFonte.rcc && v.euroLitro == 2),
      isTrue,
    );
    expect(
      CarburanteGiustificativiStatsService.findRifornimentiOltreSoglia(
        rccRows: rccRows,
        mdoRows: mdoRows,
        year: 2026,
        month: 3,
        sogliaEuroLitro: 3,
      ),
      isEmpty,
    );
  });

  test('consumo L/100km medio per modello da km consecutivi', () {
    final mezziById = {
      'm1': {
        'id_uuid': 'm1',
        'targa': 'AA111AA',
        'marca': 'Fiat',
        'modello': 'Ducato',
      },
      'm2': {
        'id_uuid': 'm2',
        'targa': 'BB222BB',
        'marca': 'Fiat',
        'modello': 'Ducato',
      },
      'm3': {
        'id_uuid': 'm3',
        'targa': 'CC333CC',
        'marca': 'Iveco',
        'modello': 'Daily',
      },
    };

    final rows = CarburanteGiustificativiStatsService.buildConsumoPerModello(
      rccRows: [
        // Ducato m1: 50 L / 500 km = 10 L/100
        {
          'id_uuid': 'r1',
          'mezzo_stradale_id_uuid': 'm1',
          'data_rifornimento': '2026-07-01',
          'km_ore': '10000',
          'litri': 40,
          'euro': 80,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': 'r2',
          'mezzo_stradale_id_uuid': 'm1',
          'data_rifornimento': '2026-07-10',
          'km_ore': '10500',
          'litri': 50,
          'euro': 100,
          'tipo_carburante': 'Gasolio',
        },
        // Ducato m2: 40 L / 400 km = 10 L/100 → media modello resta 10
        {
          'id_uuid': 'r3',
          'mezzo_stradale_id_uuid': 'm2',
          'data_rifornimento': '2026-07-02',
          'km_ore': '20000',
          'litri': 30,
          'euro': 60,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': 'r4',
          'mezzo_stradale_id_uuid': 'm2',
          'data_rifornimento': '2026-07-12',
          'km_ore': '20400',
          'litri': 40,
          'euro': 80,
          'tipo_carburante': 'Gasolio',
        },
        // Daily: 30 L / 200 km = 15 L/100
        {
          'id_uuid': 'r5',
          'mezzo_stradale_id_uuid': 'm3',
          'data_rifornimento': '2026-07-05',
          'km_ore': '5000',
          'litri': 20,
          'euro': 40,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': 'r6',
          'mezzo_stradale_id_uuid': 'm3',
          'data_rifornimento': '2026-07-15',
          'km_ore': '5200',
          'litri': 30,
          'euro': 60,
          'tipo_carburante': 'Gasolio',
        },
        // AdBlue ignorato nei litri
        {
          'id_uuid': 'r7',
          'mezzo_stradale_id_uuid': 'm3',
          'data_rifornimento': '2026-07-16',
          'km_ore': '5250',
          'litri': 10,
          'euro': 20,
          'tipo_carburante': 'AdBlue',
        },
      ],
      mezziById: mezziById,
      year: 2026,
      month: 7,
    );

    expect(rows.length, 2);
    final ducato = rows.firstWhere((r) => r.modello == 'Fiat Ducato');
    expect(ducato.mezziCount, 2);
    expect(ducato.km, 900);
    expect(ducato.litri, 90);
    expect(ducato.litriPer100Km, closeTo(10, 0.01));

    final daily = rows.firstWhere((r) => r.modello == 'Iveco Daily');
    expect(daily.mezziCount, 1);
    expect(daily.litriPer100Km, closeTo(15, 0.01));
  });

  test('unifica modelli con casing diverso e somma litri senza km intermedi', () {
    final mezziById = {
      'a': {
        'id_uuid': 'a',
        'marca': 'Fiat',
        'modello': 'Tipo Sedan',
        'targa': 'AA111AA',
      },
      'b': {
        'id_uuid': 'b',
        'marca': 'FIAT',
        'modello': 'TIPO SEDAN',
        'targa': 'BB222BB',
      },
    };

    final rows = CarburanteGiustificativiStatsService.buildConsumoPerModello(
      rccRows: [
        {
          'id_uuid': '1',
          'mezzo_stradale_id_uuid': 'a',
          'data_rifornimento': '2026-07-01',
          'km_ore': '1000',
          'litri': 10,
          'euro': 20,
          'tipo_carburante': 'Gasolio',
        },
        // Rifornimento intermedio SENZA km → deve entrare nel tratto
        {
          'id_uuid': '2',
          'mezzo_stradale_id_uuid': 'a',
          'data_rifornimento': '2026-07-05',
          'litri': 20,
          'euro': 40,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': '3',
          'mezzo_stradale_id_uuid': 'a',
          'data_rifornimento': '2026-07-10',
          'km_ore': '1500',
          'litri': 20,
          'euro': 40,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': '4',
          'mezzo_stradale_id_uuid': 'b',
          'data_rifornimento': '2026-07-02',
          'km_ore': '2000',
          'litri': 5,
          'euro': 10,
          'tipo_carburante': 'Gasolio',
        },
        {
          'id_uuid': '5',
          'mezzo_stradale_id_uuid': 'b',
          'data_rifornimento': '2026-07-12',
          'km_ore': '2500',
          'litri': 40,
          'euro': 80,
          'tipo_carburante': 'Gasolio',
        },
      ],
      mezziById: mezziById,
      year: 2026,
      month: 7,
    );

    expect(rows.length, 1);
    final tipo = rows.single;
    expect(tipo.modello.toLowerCase(), 'fiat tipo sedan');
    expect(tipo.mezziCount, 2);
    // a: 40 L / 500 km ; b: 40 L / 500 km → 80 L / 1000 km = 8 L/100
    expect(tipo.litri, closeTo(80, 0.01));
    expect(tipo.km, closeTo(1000, 0.01));
    expect(tipo.litriPer100Km, closeTo(8, 0.01));
    // a: 2 rif. nel tratto (intermedio+finale); b: 1 rif. (solo finale)
    expect(tipo.rifornimenti, 3);
  });
}
