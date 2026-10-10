import '../utils/vestiario_catalog.dart';
import 'supabase_service.dart';
import 'vestiario_articoli_service.dart';

class VestiarioFabbisognoRow {
  final String item;
  final String size;
  final int employeeCount;

  const VestiarioFabbisognoRow({
    required this.item,
    required this.size,
    required this.employeeCount,
  });

  int annualNeed(Map<String, int> multiplierByItem) =>
      employeeCount * (multiplierByItem[item] ?? 0);
}

class VestiarioSeasonMultipliers {
  final Map<String, int> estivo;
  final Map<String, int> invernale;

  const VestiarioSeasonMultipliers({
    required this.estivo,
    required this.invernale,
  });
}

/// Calcolo fabbisogno annuo per taglia (stesso criterio della pagina Fabbisogno taglie).
abstract final class VestiarioFabbisognoService {
  VestiarioFabbisognoService._();

  static const String configTable = 'vestiario_fabbisogno_annuo_config';

  static int _parseNonNeg(dynamic v, {int fallback = 0}) {
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    if (n == null || n < 0) return fallback;
    return n;
  }

  /// Articoli con moltiplicatore «quantità / anno» in sezione estiva.
  static List<String> get articoliMoltiplicatoreEstivo =>
      VestiarioCatalog.articoliPerStagione('estivo');

  /// Articoli con moltiplicatore in sezione invernale (include guanti).
  static List<String> get articoliMoltiplicatoreInvernale =>
      VestiarioCatalog.articoliPerStagione('invernale');

  static Map<String, int> defaultMultipliersEstivo() => {
        for (final k in articoliMoltiplicatoreEstivo) k: 1,
      };

  static Map<String, int> defaultMultipliersInvernale() => {
        for (final k in articoliMoltiplicatoreInvernale) k: 1,
      };

  static Future<VestiarioSeasonMultipliers> loadMultipliers() async {
    await VestiarioArticoliService.ensureLoaded();
    final estivo = defaultMultipliersEstivo();
    final invernale = defaultMultipliersInvernale();
    final legacy = defaultMultipliersInvernale();

    for (final k in estivo.keys) {
      estivo[k] = VestiarioArticoliService.moltiplicatoreFallback(k, 'estivo');
      if ((estivo[k] ?? 0) <= 0) estivo[k] = 1;
    }
    for (final k in invernale.keys) {
      invernale[k] = VestiarioArticoliService.moltiplicatoreFallback(k, 'invernale');
      if ((invernale[k] ?? 0) <= 0) invernale[k] = 1;
    }

    try {
      final row = await SupabaseService.client
          .from(configTable)
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) {
        return VestiarioSeasonMultipliers(estivo: estivo, invernale: invernale);
      }
      for (final k in legacy.keys) {
        legacy[k] = _parseNonNeg(row[k], fallback: legacy[k] ?? 0);
      }
      for (final k in estivo.keys) {
        var col = row['${k}_estivo'];
        if (k == VestiarioCatalog.articoloGiaccaLeggera && col == null) {
          col = row['giacca_estivo'];
        }
        estivo[k] = _parseNonNeg(col, fallback: legacy[k] ?? legacy['giacca'] ?? 0);
      }
      for (final k in invernale.keys) {
        var fallback = legacy[k] ?? 0;
        if (k == 'guanti_tessuto') {
          fallback = _parseNonNeg(
            row['guanti_tessuto_invernale'],
            fallback: _parseNonNeg(row['guanti_invernale'], fallback: _parseNonNeg(row['guanti'], fallback: fallback)),
          );
        } else if (k == 'guanti_pelle') {
          fallback = _parseNonNeg(
            row['guanti_pelle_invernale'],
            fallback: _parseNonNeg(row['guanti_invernale'], fallback: _parseNonNeg(row['guanti'], fallback: fallback)),
          );
        }
        invernale[k] = _parseNonNeg(row['${k}_invernale'], fallback: fallback);
      }
    } catch (_) {
      // tabella assente: default locali.
    }
    return VestiarioSeasonMultipliers(estivo: estivo, invernale: invernale);
  }

  /// Payload upsert allineato alla pagina Fabbisogno taglie (tutte le colonne stagionali).
  static Map<String, dynamic> buildConfigUpsertPayload({
    required Map<String, int> estivo,
    required Map<String, int> invernale,
  }) {
    final payload = <String, dynamic>{'id': 1};
    for (final k in articoliMoltiplicatoreEstivo) {
      payload['${k}_estivo'] = estivo[k] ?? 0;
    }
    for (final k in articoliMoltiplicatoreInvernale) {
      payload['${k}_invernale'] = invernale[k] ?? 0;
    }
    payload['tshirt'] = invernale['tshirt'] ?? estivo['tshirt'] ?? 0;
    payload['pantalone'] = invernale['pantalone'] ?? estivo['pantalone'] ?? 0;
    payload['felpa'] = invernale['felpa'] ?? estivo['felpa'] ?? 0;
    payload['giacca'] = invernale['giacca'] ?? 0;
    payload['giacca_estivo'] = estivo[VestiarioCatalog.articoloGiaccaLeggera] ?? 0;
    payload['gilet'] = invernale['gilet'] ?? estivo['gilet'] ?? 0;
    payload['scarpe'] = invernale['scarpe'] ?? estivo['scarpe'] ?? 0;
    payload['guanti_pelle_invernale'] = invernale['guanti_pelle'] ?? 0;
    payload['guanti_tessuto_invernale'] = invernale['guanti_tessuto'] ?? 0;
    payload['guanti'] = invernale['guanti_tessuto'] ?? 0;
    return payload;
  }

  static Future<void> saveMultipliers({
    required Map<String, int> estivo,
    required Map<String, int> invernale,
  }) async {
    await SupabaseService.client.from(configTable).upsert(
          buildConfigUpsertPayload(estivo: estivo, invernale: invernale),
          onConflict: 'id',
        );
    await VestiarioArticoliService.saveMoltiplicatori(
      estivo: estivo,
      invernale: invernale,
    );
  }

  static Future<List<VestiarioFabbisognoRow>> loadAggregations() async {
    final activeRows = await SupabaseService.client
        .from('personale')
        .select('id_uuid')
        .eq('active', true);
    final active = (activeRows as List)
        .map((e) => (e['id_uuid'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final taglieRows = await SupabaseService.client.from('personale_taglie').select(
        'personale_id, taglia_tshirt, taglia_pantalone, taglia_felpa, taglia_giacca, taglia_gilet, taglia_scarpe, taglia_guanti');

    final byItemSize = <String, Map<String, int>>{};
    for (final raw in (taglieRows as List)) {
      final r = Map<String, dynamic>.from(raw as Map);
      final pid = (r['personale_id'] ?? '').toString().trim();
      if (!active.contains(pid)) continue;
      _acc(byItemSize, 'tshirt', (r['taglia_tshirt'] ?? '').toString());
      _acc(byItemSize, 'pantalone', (r['taglia_pantalone'] ?? '').toString());
      _acc(byItemSize, 'felpa', (r['taglia_felpa'] ?? '').toString());
      final tagliaGiacca = (r['taglia_giacca'] ?? '').toString();
      _acc(byItemSize, VestiarioCatalog.articoloGiaccaInvernale, tagliaGiacca);
      _acc(byItemSize, VestiarioCatalog.articoloGiaccaLeggera, tagliaGiacca);
      _acc(byItemSize, 'gilet', (r['taglia_gilet'] ?? '').toString());
      _acc(byItemSize, 'scarpe', (r['taglia_scarpe'] ?? '').toString());
      final tagliaGuanti = (r['taglia_guanti'] ?? '').toString();
      _acc(byItemSize, 'guanti_pelle', tagliaGuanti);
      _acc(byItemSize, 'guanti_tessuto', tagliaGuanti);
    }

    final out = <VestiarioFabbisognoRow>[];
    for (final item in byItemSize.keys) {
      final sizes = byItemSize[item]!;
      final orderedSizes = sizes.keys.toList()
        ..sort(VestiarioCatalog.compareSizes);
      for (final size in orderedSizes) {
        out.add(
          VestiarioFabbisognoRow(
            item: item,
            size: size,
            employeeCount: sizes[size] ?? 0,
          ),
        );
      }
    }
    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.item).compareTo(VestiarioCatalog.label(b.item));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.size, b.size);
    });
    return out;
  }

  static void _acc(Map<String, Map<String, int>> map, String item, String rawSize) {
    final s = rawSize.trim();
    if (s.isEmpty) return;
    map.putIfAbsent(item, () => <String, int>{});
    map[item]![s] = (map[item]![s] ?? 0) + 1;
  }
}
