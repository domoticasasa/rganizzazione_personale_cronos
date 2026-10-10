/// Ripartizione litri su più mezzi per rifornimento MDO.
class MdoRifornimentoDest {
  final String mezzo;
  final double litri;
  final String? mdoIdUuid;

  const MdoRifornimentoDest({
    required this.mezzo,
    required this.litri,
    this.mdoIdUuid,
  });

  Map<String, dynamic> toJson() => {
        'mezzo': mezzo,
        'litri': litri,
        if ((mdoIdUuid ?? '').trim().isNotEmpty) 'mdo_id_uuid': mdoIdUuid,
      };

  static MdoRifornimentoDest? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final mezzo = (m['mezzo'] ?? '').toString().trim();
    final litri = _toDouble(m['litri']);
    if (mezzo.isEmpty || litri == null || litri <= 0) return null;
    final id = (m['mdo_id_uuid'] ?? '').toString().trim();
    return MdoRifornimentoDest(
      mezzo: mezzo,
      litri: litri,
      mdoIdUuid: id.isEmpty ? null : id,
    );
  }
}

List<MdoRifornimentoDest> parseMdoDestinationsFromRow(Map<String, dynamic> row) {
  final raw = row['mezzi_riforniti_json'];
  if (raw is List) {
    final out = <MdoRifornimentoDest>[];
    for (final e in raw) {
      final d = MdoRifornimentoDest.fromJson(e);
      if (d != null) out.add(d);
    }
    if (out.isNotEmpty) return out;
  }
  final mezzo = (row['automezzo_mdo'] ?? '').toString().trim();
  final litri = _toDouble(row['litri']);
  if (mezzo.isNotEmpty && litri != null && litri > 0) {
    return [MdoRifornimentoDest(mezzo: mezzo, litri: litri)];
  }
  return const [];
}

/// Chiave di merge: stesso `mdo_id_uuid` oppure stesso testo mezzo (case-insensitive).
String mdoDestinationMergeKey({
  required String mezzo,
  String? mdoIdUuid,
}) {
  final id = (mdoIdUuid ?? '').trim();
  if (id.isNotEmpty) return 'id:$id';
  return 'txt:${mezzo.trim().toLowerCase()}';
}

/// Unisce righe con stesso mezzo sommando i litri.
List<MdoRifornimentoDest> mergeMdoDestinations(List<MdoRifornimentoDest> items) {
  final map = <String, MdoRifornimentoDest>{};
  for (final d in items) {
    final key = mdoDestinationMergeKey(mezzo: d.mezzo, mdoIdUuid: d.mdoIdUuid);
    if (key == 'txt:') continue;
    final prev = map[key];
    if (prev == null) {
      map[key] = d;
    } else {
      map[key] = MdoRifornimentoDest(
        mezzo: prev.mezzo,
        litri: prev.litri + d.litri,
        mdoIdUuid: prev.mdoIdUuid ?? d.mdoIdUuid,
      );
    }
  }
  return map.values.toList();
}

/// Salva ogni riga form separatamente (stesso mezzo ripetuto = traccia distinta).
List<Map<String, dynamic>> mdoDestinationsToJsonList(List<MdoRifornimentoDest> items) =>
    items.map((e) => e.toJson()).toList(growable: false);

/// Somma litri di tutte le righe (anche stesso mezzo ripetuto).
double sumMdoDestinationLitri(List<MdoRifornimentoDest> items) =>
    items.fold<double>(0, (s, d) => s + d.litri);

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

/// Codice corto mezzo (es. A56, A33-BLE), non la targa IT-RFI.
bool mdoLooksLikeMatricolaInterna(String value) {
  final s = value.trim();
  if (s.isEmpty) return false;
  if (RegExp(r'^IT[\s-]*RFI', caseSensitive: false).hasMatch(s)) return false;
  return RegExp(r'^[A-Za-z]\d').hasMatch(s);
}

/// Solo matricola (es. «A56»), senza descrizione mezzo né targa IT-RFI.
String mdoExtractMatricolaCode(String value) {
  final s = value.trim();
  if (s.isEmpty) return '—';

  final code = RegExp(r'^([A-Za-z]\d[A-Za-z0-9-]*)').firstMatch(s)?.group(1);
  if (code != null && code.isNotEmpty) return code;

  final parts = s
      .split(RegExp(r'[·,;]+'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toList();
  for (final p in parts) {
    final c = RegExp(r'^([A-Za-z]\d[A-Za-z0-9-]*)').firstMatch(p)?.group(1);
    if (c != null && c.isNotEmpty) return c;
  }

  for (final p in parts) {
    final token = p.split(RegExp(r'\s+')).first.trim();
    if (token.isEmpty) continue;
    if (RegExp(r'^IT[\s-]*RFI', caseSensitive: false).hasMatch(token)) continue;
    if (mdoLooksLikeMatricolaInterna(token)) return token;
    if (token.length <= 8 && RegExp(r'^[A-Za-z]').hasMatch(token)) return token;
  }

  final first = s.split(RegExp(r'\s+')).first.trim();
  if (first.isNotEmpty &&
      !RegExp(r'^IT[\s-]*RFI', caseSensitive: false).hasMatch(first) &&
      first.length <= 12) {
    return first;
  }
  return first.isEmpty ? '—' : first;
}

String mdoMatricolaFromRecord(Map<String, dynamic> m) {
  final mat = (m['matricola_interna'] ?? '').toString().trim();
  if (mat.isNotEmpty) return mat;
  final targa = (m['codice_identificativo_targa_rfi'] ?? '').toString().trim();
  return targa;
}

String formatMdoFerroviarioLabel(Map<String, dynamic> m) {
  final parts = <String>[
    (m['matricola_interna'] ?? '').toString().trim(),
    (m['codice_identificativo_targa_rfi'] ?? '').toString().trim(),
    (m['descrizione_mezzo'] ?? '').toString().trim(),
  ].where((x) => x.isNotEmpty);
  final joined = parts.join(' · ');
  return joined.isEmpty ? (m['id_uuid'] ?? '').toString() : joined;
}

/// Numero mezzo per colonna «Mezzi» e export Excel (matricola interna, es. A56).
String mdoMezzoNumeroDisplay(
  MdoRifornimentoDest d,
  Map<String, Map<String, dynamic>> mdoById,
) {
  final id = (d.mdoIdUuid ?? '').trim();
  if (id.isNotEmpty) {
    final m = mdoById[id];
    if (m != null) {
      final label = mdoMatricolaFromRecord(m);
      if (label.isNotEmpty) return label;
    }
  }
  return mdoExtractMatricolaCode(d.mezzo);
}

/// Elenco numeri mezzi riforniti (es. «A33-BLE, motosega»).
String mdoMezziNumeriSummary(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> mdoById,
) {
  final dests = parseMdoDestinationsFromRow(row);
  if (dests.isEmpty) {
    final t = (row['targa_matricola'] ?? '').toString().trim();
    return t.isEmpty ? '—' : t;
  }
  return dests.map((d) => mdoMezzoNumeroDisplay(d, mdoById)).join(', ');
}
