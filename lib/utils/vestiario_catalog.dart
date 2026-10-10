// Articoli vestiario condivisi tra fabbisogno, assegnazione e magazzino.

import '../services/vestiario_articoli_service.dart';

abstract final class VestiarioCatalog {
  static const String tagliaInventarioUnitaria = 'UN';

  static const String articoloGiaccaLeggera = 'giacca_leggera';

  static const String articoloGiaccaInvernale = 'giacca';

  static const String magazzinoStagioneGuanti = 'invernale';

  /// DPI III categoria: una riga unitaria in inventario (taglia [tagliaInventarioUnitaria]).
  static List<String> get articoliDpiMagazzino =>
      VestiarioArticoliService.activeDpiMagazzinoKeys();

  static List<String> get articoliMagazzino =>
      VestiarioArticoliService.activeMagazzinoKeys();

  static bool isArticoloDpiMagazzino(String articolo) =>
      articoliDpiMagazzino.contains(articolo);

  static bool isArticoloInventarioUnitario(String articolo) {
    final def = VestiarioArticoliService.byKey(articolo);
    if (def != null) {
      return def.isDpiIii || def.sizeType == 'unit';
    }
    return isArticoloDpiMagazzino(articolo);
  }

  /// Chiave riga magazzino per una variante DPI (marca/modello distinta).
  static String nuovaTagliaDpiVariante() =>
      'dpi_${DateTime.now().millisecondsSinceEpoch}';

  static int compareDpiVarianti(String marcaA, String marcaB) =>
      marcaA.trim().toLowerCase().compareTo(marcaB.trim().toLowerCase());

  /// Taglie abiti (T-shirt, felpa, giacca, gilet).
  static const List<String> topClothingSizes = <String>[
    'XS',
    'S',
    'M',
    'L',
    'XL',
    '2XL',
    '3XL',
    '4XL',
    '5XL',
  ];

  static const List<String> trouserSizes = <String>[
    '40',
    '42',
    '44',
    '46',
    '48',
    '50',
    '52',
    '54',
    '56',
    '58',
    '60',
    '62',
    '64',
  ];

  static const List<String> shoeSizes = <String>[
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48',
    '49',
    '50',
  ];

  static const List<String> gloveSizes = <String>[
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    '2XL',
    '3XL',
    '4XL',
  ];

  static List<String> get estivoDefaultAssegnazione =>
      VestiarioArticoliService.defaultAssegnazioneForSeason('estivo');

  static List<String> get invernaleDefaultAssegnazione =>
      VestiarioArticoliService.defaultAssegnazioneForSeason('invernale');

  static List<String> get articoliMagazzinoStagioneInvernale =>
      VestiarioArticoliService.activeArticoli
          .where((a) => a.magazzinoStagioneUnica == 'invernale')
          .map((a) => a.key)
          .toList(growable: false);

  static bool isArticoloMagazzinoStagioneUnica(String articolo) {
    final def = VestiarioArticoliService.byKey(articolo);
    return def?.magazzinoStagioneUnica != null;
  }

  static List<String> get articoliModelloUnico =>
      VestiarioArticoliService.activeArticoli
          .where((a) => a.inMagazzino && a.modelloUnico)
          .map((a) => a.key)
          .toList(growable: false);

  static bool isArticoloModelloUnico(String articolo) {
    final def = VestiarioArticoliService.byKey(articolo);
    if (def != null) return def.inMagazzino && def.modelloUnico;
    return articoliModelloUnico.contains(articolo);
  }

  /// Fabbisogno annuo unico (evita doppio conteggio se presente in entrambe le stagioni).
  static int fabbisognoModelloUnico(int estivo, int invernale) {
    if (estivo <= 0) return invernale;
    if (invernale <= 0) return estivo;
    return estivo > invernale ? estivo : invernale;
  }

  /// true se [articolo] può avere righe magazzino in [stagione].
  static bool magazzinoStagioneValida(String articolo, String stagione) {
    final def = VestiarioArticoliService.byKey(articolo);
    if (def != null && !def.inMagazzino) return false;
    if (def?.magazzinoStagioneUnica != null) {
      return stagione == def!.magazzinoStagioneUnica;
    }
    if (articolo == articoloGiaccaLeggera) {
      return stagione == 'estivo';
    }
    if (articolo == articoloGiaccaInvernale) {
      return stagione == 'invernale';
    }
    if (isArticoloDpiMagazzino(articolo)) {
      return stagione == 'estivo';
    }
    if (def != null) {
      if (stagione == 'estivo') return def.stagioneEstivo;
      if (stagione == 'invernale') return def.stagioneInvernale;
    }
    return stagione == 'estivo' || stagione == 'invernale';
  }

  static List<String> articoliPerStagione(String stagione) => articoliMagazzino
      .where((k) => magazzinoStagioneValida(k, stagione))
      .toList(growable: false);

  /// Stagione DB per giacenza/ordini/arrivi (una sola riga per articolo+taglia).
  static String stagioneRegistrazioneMagazzino(String articolo) {
    final def = VestiarioArticoliService.byKey(articolo);
    if (def?.magazzinoStagioneUnica != null) {
      return def!.magazzinoStagioneUnica!;
    }
    return isArticoloMagazzinoStagioneUnica(articolo)
        ? magazzinoStagioneGuanti
        : 'estivo';
  }

  /// Stagione effettiva per upsert/scarico (allineata a [stagioneRegistrazioneMagazzino]).
  static String magazzinoStagioneEffettiva(String articolo, String stagione) =>
      stagioneRegistrazioneMagazzino(articolo);

  static String label(String key) {
    final normalized = key == 'guanti' ? 'guanti_tessuto' : key;
    return VestiarioArticoliService.labelFor(normalized);
  }

  static int compareSizes(String a, String b) {
    return sizeSortKey(a).compareTo(sizeSortKey(b));
  }

  static String sizeSortKey(String s) {
    final t = s.trim().toUpperCase();
    var idx = topClothingSizes.indexWhere((e) => e.toUpperCase() == t);
    if (idx >= 0) return idx.toString().padLeft(4, '0');
    idx = gloveSizes.indexWhere((e) => e.toUpperCase() == t);
    if (idx >= 0) return (500 + idx).toString().padLeft(4, '0');
    final n = int.tryParse(t);
    if (n != null) return (1000 + n).toString().padLeft(4, '0');
    return 'z$t';
  }

  static bool isMagazzinoArticolo(String articolo) =>
      articoliMagazzino.contains(articolo);

  /// Chiave magazzino da voce assegnazione (es. giubbino_estivo → giacca_leggera).
  static String? magazzinoArticoloDaChiaveAssegnazione(String itemKey) {
    switch (itemKey) {
      case 'giubbino_estivo':
        return articoloGiaccaLeggera;
      case 'guanti':
      case 'guanti_tessuto':
        return 'guanti_tessuto';
      case 'guanti_pelle':
        return 'guanti_pelle';
      default:
        final def = VestiarioArticoliService.byKey(itemKey);
        if (def != null && def.inMagazzino) return itemKey;
        return isMagazzinoArticolo(itemKey) ? itemKey : null;
    }
  }

  /// Griglia taglie in inventario (include 4XL anche senza dipendenti censiti).
  static List<String> tagliePerArticolo(String articolo) {
    if (isArticoloInventarioUnitario(articolo)) {
      return const <String>[];
    }
    final def = VestiarioArticoliService.byKey(articolo);
    final sizeType = def?.sizeType ?? _legacySizeType(articolo);
    switch (sizeType) {
      case 'trouser':
        return trouserSizes;
      case 'shoe':
        return shoeSizes;
      case 'glove':
        return gloveSizes;
      case 'none':
      case 'unit':
        return const <String>[];
      default:
        return topClothingSizes;
    }
  }

  static String _legacySizeType(String articolo) {
    switch (articolo) {
      case 'pantalone':
        return 'trouser';
      case 'scarpe':
        return 'shoe';
      case 'guanti':
      case 'guanti_pelle':
      case 'guanti_tessuto':
        return 'glove';
      default:
        return 'top';
    }
  }
}
