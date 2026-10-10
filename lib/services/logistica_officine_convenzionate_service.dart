import 'package:supabase_flutter/supabase_flutter.dart';

class OfficinaConvenzionata {
  const OfficinaConvenzionata({
    required this.id,
    required this.fornitore,
    this.marchio = '',
    this.tipologia = '',
    this.citta = '',
    this.via = '',
    this.provincia = '',
    this.telefono = '',
    this.latitudine,
    this.longitudine,
    this.mapsUrl = '',
    this.note = '',
    this.attivo = true,
  });

  final String id;
  final String fornitore;
  final String marchio;
  final String tipologia;
  final String citta;
  final String via;
  final String provincia;
  final String telefono;
  final double? latitudine;
  final double? longitudine;
  final String mapsUrl;
  final String note;
  final bool attivo;

  factory OfficinaConvenzionata.fromMap(Map<String, dynamic> m) {
    double? numOrNull(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    return OfficinaConvenzionata(
      id: (m['id_uuid'] ?? '').toString(),
      fornitore: (m['fornitore'] ?? '').toString().trim(),
      marchio: (m['marchio'] ?? '').toString().trim(),
      tipologia: (m['tipologia'] ?? '').toString().trim(),
      citta: (m['citta'] ?? '').toString().trim(),
      via: (m['via'] ?? '').toString().trim(),
      provincia: (m['provincia'] ?? '').toString().trim(),
      telefono: (m['telefono'] ?? '').toString().trim(),
      latitudine: numOrNull(m['latitudine']),
      longitudine: numOrNull(m['longitudine']),
      mapsUrl: (m['maps_url'] ?? '').toString().trim(),
      note: (m['note'] ?? '').toString().trim(),
      attivo: m['attivo'] != false,
    );
  }

  Map<String, dynamic> toPayload() => {
        'fornitore': fornitore.trim(),
        'marchio': marchio.trim().isEmpty ? null : marchio.trim(),
        'tipologia': tipologia.trim().isEmpty ? null : tipologia.trim(),
        'citta': citta.trim().isEmpty ? null : citta.trim(),
        'via': via.trim().isEmpty ? null : via.trim(),
        'provincia': provincia.trim().isEmpty ? null : provincia.trim(),
        'telefono': telefono.trim().isEmpty ? null : telefono.trim(),
        'latitudine': latitudine,
        'longitudine': longitudine,
        'maps_url': mapsUrl.trim().isEmpty ? null : mapsUrl.trim(),
        'note': note.trim().isEmpty ? null : note.trim(),
        'attivo': attivo,
      };

  List<String> get tipologiaTags => _splitCsv(tipologia);
  List<String> get marchioTags => _splitCsv(marchio);

  /// Categorie servizio normalizzate (PNEUMATICI, CARROZZERIA…).
  List<String> get tipoKeys {
    final keys = <String>[];
    final seen = <String>{};
    for (final raw in tipologiaTags) {
      final k = normalizeOfficinaTipoKey(raw);
      if (k == null || !seen.add(k)) continue;
      keys.add(k);
    }
    return keys;
  }

  /// Marchi normalizzati (FIAT, FORD…). Senza marca → `ALTRE`.
  List<String> get brandKeys {
    final keys = <String>[];
    final seen = <String>{};
    for (final raw in marchioTags) {
      final k = raw.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
      if (k.isEmpty || !seen.add(k)) continue;
      keys.add(k);
    }
    return keys.isEmpty ? const ['ALTRE'] : keys;
  }

  String get luogoLabel {
    final parts = [
      if (citta.isNotEmpty) citta,
      if (provincia.isNotEmpty) provincia,
    ];
    return parts.join(' · ');
  }

  bool get hasMaps =>
      mapsUrl.isNotEmpty || (latitudine != null && longitudine != null);
}

List<String> _splitCsv(String raw) {
  return raw
      .split(RegExp(r'[,;/]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

String? normalizeOfficinaTipoKey(String raw) {
  final u = raw.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  if (u.isEmpty) return null;
  if (u.contains('PNEUMATIC') || u.contains('GOMM')) return 'PNEUMATICI';
  if (u.contains('CARROZZ')) return 'CARROZZERIA';
  if (u.contains('TAGLIAND')) return 'TAGLIANDI';
  if (u.contains('CRISTALL')) return 'CRISTALLI';
  if (u.contains('REVISION')) return 'REVISIONI';
  if (u.contains('ELETTR')) return 'ELETTRAUTO';
  if (u.contains('MECCANIC')) return 'MECCANICA';
  if (u.contains('CAMION')) return 'CAMION';
  return u;
}

abstract final class LogisticaOfficineConvenzionateService {
  LogisticaOfficineConvenzionateService._();

  static const table = 'logistica_officine_convenzionate';

  static Future<List<OfficinaConvenzionata>> list(SupabaseClient supa) async {
    final res = await supa
        .from(table)
        .select()
        .order('provincia', ascending: true)
        .order('citta', ascending: true)
        .order('fornitore', ascending: true);
    return (res as List)
        .map((e) => OfficinaConvenzionata.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  static Future<OfficinaConvenzionata> insert(
    SupabaseClient supa,
    OfficinaConvenzionata row,
  ) async {
    final res = await supa.from(table).insert(row.toPayload()).select().single();
    return OfficinaConvenzionata.fromMap(Map<String, dynamic>.from(res));
  }

  static Future<void> update(
    SupabaseClient supa,
    OfficinaConvenzionata row,
  ) async {
    await supa.from(table).update(row.toPayload()).eq('id_uuid', row.id);
  }

  static Future<void> delete(SupabaseClient supa, String id) async {
    await supa.from(table).delete().eq('id_uuid', id);
  }
}
