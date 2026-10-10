/// Risorsa logistica collegata a una commessa (MDO, BOX, estintore, …).
class CommessaLinkedItem {
  const CommessaLinkedItem({
    required this.assetType,
    required this.idUuid,
    required this.label,
    this.subtitle,
    this.lat,
    this.lon,
  });

  final String assetType;
  final String idUuid;
  final String label;
  final String? subtitle;
  final double? lat;
  final double? lon;

  bool get hasGps => lat != null && lon != null;
}

/// Elenco commessa → tutte le risorse abbinatе.
class CommessaLinkedAssets {
  const CommessaLinkedAssets({
    required this.commessaIdUuid,
    required this.commessaNome,
    this.commessaLat,
    this.commessaLon,
    this.mdo = const [],
    this.box = const [],
    this.estintori = const [],
    this.attrezzature = const [],
    this.casettePs = const [],
  });

  final String commessaIdUuid;
  final String commessaNome;
  final double? commessaLat;
  final double? commessaLon;
  final List<CommessaLinkedItem> mdo;
  final List<CommessaLinkedItem> box;
  final List<CommessaLinkedItem> estintori;
  final List<CommessaLinkedItem> attrezzature;
  final List<CommessaLinkedItem> casettePs;

  int get totalCount =>
      mdo.length +
      box.length +
      estintori.length +
      attrezzature.length +
      casettePs.length;

  Iterable<CommessaLinkedItem> get allItems sync* {
    yield* mdo;
    yield* box;
    yield* estintori;
    yield* attrezzature;
    yield* casettePs;
  }

  List<CommessaLinkedItem> get withGps =>
      allItems.where((i) => i.hasGps).toList(growable: false);
}

class CommessaOption {
  const CommessaOption({required this.idUuid, required this.nome});

  final String idUuid;
  final String nome;
}
