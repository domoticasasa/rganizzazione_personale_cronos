import 'casetta_ps_catalogo.dart';

class CasettaPsMaterialeRiga {
  final String id;
  final String descrizione;
  bool presente;
  String scadenzaMmYyyy;

  CasettaPsMaterialeRiga({
    required this.id,
    required this.descrizione,
    this.presente = false,
    this.scadenzaMmYyyy = '',
  });

  factory CasettaPsMaterialeRiga.fromJson(Map<String, dynamic> json) {
    return CasettaPsMaterialeRiga(
      id: (json['id'] ?? '').toString(),
      descrizione: (json['descrizione'] ?? '').toString(),
      presente: json['presente'] == true,
      scadenzaMmYyyy: _scadenzaFromStored(json['scadenza']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'descrizione': descrizione,
        'presente': presente,
        'scadenza': scadenzaMmYyyyToIso(scadenzaMmYyyy),
      };

  static String _scadenzaFromStored(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) {
      final m = RegExp(r'^(\d{2})\/(\d{4})$').firstMatch(s);
      if (m != null) return s;
      return '';
    }
    final mm = d.month.toString().padLeft(2, '0');
    return '$mm/${d.year}';
  }

  static String? scadenzaMmYyyyToIso(String mmYyyy) {
    final s = mmYyyy.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{2})\/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final mm = int.tryParse(m.group(1)!);
    final yyyy = int.tryParse(m.group(2)!);
    if (mm == null || yyyy == null || mm < 1 || mm > 12) return null;
    return '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-01';
  }
}

List<CasettaPsMaterialeRiga> mergeCasettaPsMateriale({
  required String? tipoCassetta,
  required dynamic stored,
}) {
  final catalogo = CasettaPsCatalogo.vociPerTipo(tipoCassetta);
  final byId = <String, CasettaPsMaterialeRiga>{};
  if (stored is List) {
    for (final e in stored) {
      if (e is! Map) continue;
      final r = CasettaPsMaterialeRiga.fromJson(Map<String, dynamic>.from(e));
      if (r.id.isNotEmpty) byId[r.id] = r;
    }
  }
  return catalogo
      .map((v) {
        final existing = byId[v.id];
        if (existing != null) {
          return CasettaPsMaterialeRiga(
            id: v.id,
            descrizione: v.descrizione,
            presente: existing.presente,
            scadenzaMmYyyy: existing.scadenzaMmYyyy,
          );
        }
        return CasettaPsMaterialeRiga(
          id: v.id,
          descrizione: v.descrizione,
        );
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> casettaPsMaterialeToJsonList(
  List<CasettaPsMaterialeRiga> righe,
) {
  return righe.map((r) => r.toJson()).toList(growable: false);
}

String? earliestMaterialeScadenzaIso(List<CasettaPsMaterialeRiga> righe) {
  DateTime? min;
  for (final r in righe) {
    if (!r.presente) continue;
    final iso = CasettaPsMaterialeRiga.scadenzaMmYyyyToIso(r.scadenzaMmYyyy);
    if (iso == null) continue;
    final d = DateTime.tryParse(iso);
    if (d == null) continue;
    if (min == null || d.isBefore(min)) min = d;
  }
  return min?.toIso8601String().split('T').first;
}

({int presenti, int totali}) casettaPsMaterialeSummary(
  Map<String, dynamic> row,
) {
  final tipo = (row['tipo_cassetta'] ?? '').toString();
  if (!CasettaPsCatalogo.isAllegato1Tipo(tipo) &&
      !CasettaPsCatalogo.isAllegato2Tipo(tipo)) {
    return (presenti: 0, totali: 0);
  }
  final righe = mergeCasettaPsMateriale(
    tipoCassetta: tipo,
    stored: row['materiale_contenuto'],
  );
  final presenti = righe.where((r) => r.presente).length;
  return (presenti: presenti, totali: righe.length);
}
