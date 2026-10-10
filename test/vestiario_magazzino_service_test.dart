import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/vestiario_magazzino_service.dart';
import 'package:organizzazione_personale_cronos/utils/vestiario_catalog.dart';

void main() {
  group('VestiarioCatalog fabbisogno modello unico', () {
    test('tshirt scarpe gilet guanti pelle/tessuto sono modello unico', () {
      expect(VestiarioCatalog.isArticoloModelloUnico('tshirt'), isTrue);
      expect(VestiarioCatalog.isArticoloModelloUnico('scarpe'), isTrue);
      expect(VestiarioCatalog.isArticoloModelloUnico('gilet'), isTrue);
      expect(VestiarioCatalog.isArticoloModelloUnico('guanti_pelle'), isTrue);
      expect(VestiarioCatalog.isArticoloModelloUnico('guanti_tessuto'), isTrue);
      expect(VestiarioCatalog.isArticoloModelloUnico('pantalone'), isFalse);
    });

    test('fabbisogno non somma estivo e invernale', () {
      expect(VestiarioCatalog.fabbisognoModelloUnico(18, 0), 18);
      expect(VestiarioCatalog.fabbisognoModelloUnico(10, 12), 12);
      expect(VestiarioCatalog.fabbisognoModelloUnico(0, 7), 7);
    });
  });

  group('VestiarioCatalog magazzino mapping', () {
    test('giubbino_estivo maps to giacca_leggera', () {
      expect(
        VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione('giubbino_estivo'),
        'giacca_leggera',
      );
    });

    test('scarpe maps to scarpe', () {
      expect(
        VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione('scarpe'),
        'scarpe',
      );
    });

    test('guanti pelle e tessuto mappano al magazzino', () {
      expect(
        VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione('guanti_pelle'),
        'guanti_pelle',
      );
      expect(
        VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione('guanti_tessuto'),
        'guanti_tessuto',
      );
      expect(
        VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione('guanti'),
        'guanti_tessuto',
      );
    });

    test('articoli DPI III in inventario magazzino', () {
      expect(VestiarioCatalog.articoliMagazzino, contains('elmetto'));
      expect(VestiarioCatalog.articoliMagazzino, contains('cordino_y_dissipatore'));
      expect(VestiarioCatalog.tagliePerArticolo('elmetto'), isEmpty);
      expect(VestiarioCatalog.nuovaTagliaDpiVariante(), startsWith('dpi_'));
      expect(VestiarioCatalog.label('cordino_y_dissipatore'),
          'Cordino di connessione a Y con dissipatore');
    });
  });

  group('VestiarioMagazzinoService.lookupRecord', () {
    test('uses estivo stock for scarpe when invernale row is empty', () {
      final records = <String, VestiarioMagazzinoRecord>{
        VestiarioMagazzinoService.stockKey('estivo', 'scarpe', '43'):
            const VestiarioMagazzinoRecord(magazzino: 5),
        VestiarioMagazzinoService.stockKey('invernale', 'scarpe', '43'):
            VestiarioMagazzinoRecord.empty,
      };
      final rec = VestiarioMagazzinoService.lookupRecord(
        records,
        articolo: 'scarpe',
        taglia: '43',
      );
      expect(rec.magazzino, 5);
    });

    test('falls back to invernale legacy stock', () {
      final records = <String, VestiarioMagazzinoRecord>{
        VestiarioMagazzinoService.stockKey('invernale', 'scarpe', '43'):
            const VestiarioMagazzinoRecord(magazzino: 3),
      };
      final rec = VestiarioMagazzinoService.lookupRecord(
        records,
        articolo: 'scarpe',
        taglia: '43',
      );
      expect(rec.magazzino, 3);
    });

    test('righePerSalvataggio includes elmetto DPI with marca', () {
      final batch = VestiarioMagazzinoService.righePerSalvataggio([
        const VestiarioInventarioRiga(
          stagione: 'estivo',
          articolo: 'elmetto',
          taglia: 'UN',
          magazzino: 12,
          fabbisogno: 0,
          marca: '3M',
        ),
      ]);
      expect(batch, hasLength(1));
      expect(batch.first['articolo'], 'elmetto');
      expect(batch.first['marca'], '3M');
      expect(batch.first['quantita'], 12);
    });

    test('righePerSalvataggio includes giacca invernale with canonical estivo row', () {
      final batch = VestiarioMagazzinoService.righePerSalvataggio([
        const VestiarioInventarioRiga(
          stagione: 'estivo',
          articolo: 'giacca',
          taglia: 'M',
          magazzino: 4,
          fabbisogno: 0,
          ordinato: 2,
        ),
      ]);
      expect(batch, hasLength(1));
      expect(batch.first['stagione'], 'estivo');
      expect(batch.first['articolo'], 'giacca');
      expect(batch.first['quantita'], 4);
      expect(batch.first['quantita_ordinata'], 2);
    });

    test('guanti tessuto use invernale canonical row', () {
      final records = <String, VestiarioMagazzinoRecord>{
        VestiarioMagazzinoService.stockKey('invernale', 'guanti_tessuto', '10'):
            const VestiarioMagazzinoRecord(magazzino: 8),
      };
      final rec = VestiarioMagazzinoService.lookupRecord(
        records,
        articolo: 'guanti_tessuto',
        taglia: '10',
      );
      expect(rec.magazzino, 8);
    });
  });
}
