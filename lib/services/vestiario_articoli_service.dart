import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Definizione articolo vestiario (magazzino, assegnazione, fabbisogno).
class VestiarioArticoloDef {
  final String key;
  final String label;
  final bool active;
  final String sizeType;
  final bool inMagazzino;
  final bool inAssegnazione;
  final bool stagioneEstivo;
  final bool stagioneInvernale;
  final bool modelloUnico;
  final bool isDpiIii;
  final String? magazzinoStagioneUnica;
  final int moltiplicatoreEstivo;
  final int moltiplicatoreInvernale;
  final int sortOrder;
  final List<int> excelRows;
  final String? sizeLabel;
  final String? tagliaPersonaleField;

  const VestiarioArticoloDef({
    required this.key,
    required this.label,
    this.active = true,
    this.sizeType = 'top',
    this.inMagazzino = false,
    this.inAssegnazione = false,
    this.stagioneEstivo = true,
    this.stagioneInvernale = true,
    this.modelloUnico = false,
    this.isDpiIii = false,
    this.magazzinoStagioneUnica,
    this.moltiplicatoreEstivo = 0,
    this.moltiplicatoreInvernale = 0,
    this.sortOrder = 100,
    this.excelRows = const <int>[],
    this.sizeLabel,
    this.tagliaPersonaleField,
  });

  VestiarioArticoloDef copyWith({
    String? label,
    bool? active,
    String? sizeType,
    bool? inMagazzino,
    bool? inAssegnazione,
    bool? stagioneEstivo,
    bool? stagioneInvernale,
    bool? modelloUnico,
    bool? isDpiIii,
    String? magazzinoStagioneUnica,
    int? moltiplicatoreEstivo,
    int? moltiplicatoreInvernale,
    int? sortOrder,
    List<int>? excelRows,
    String? sizeLabel,
    String? tagliaPersonaleField,
  }) {
    return VestiarioArticoloDef(
      key: key,
      label: label ?? this.label,
      active: active ?? this.active,
      sizeType: sizeType ?? this.sizeType,
      inMagazzino: inMagazzino ?? this.inMagazzino,
      inAssegnazione: inAssegnazione ?? this.inAssegnazione,
      stagioneEstivo: stagioneEstivo ?? this.stagioneEstivo,
      stagioneInvernale: stagioneInvernale ?? this.stagioneInvernale,
      modelloUnico: modelloUnico ?? this.modelloUnico,
      isDpiIii: isDpiIii ?? this.isDpiIii,
      magazzinoStagioneUnica:
          magazzinoStagioneUnica ?? this.magazzinoStagioneUnica,
      moltiplicatoreEstivo: moltiplicatoreEstivo ?? this.moltiplicatoreEstivo,
      moltiplicatoreInvernale:
          moltiplicatoreInvernale ?? this.moltiplicatoreInvernale,
      sortOrder: sortOrder ?? this.sortOrder,
      excelRows: excelRows ?? this.excelRows,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      tagliaPersonaleField: tagliaPersonaleField ?? this.tagliaPersonaleField,
    );
  }

  static VestiarioArticoloDef fromRow(Map<String, dynamic> row) {
    final excelRaw = (row['excel_rows'] ?? '').toString().trim();
    final excelRows = excelRaw.isEmpty
        ? const <int>[]
        : excelRaw
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toList();
    return VestiarioArticoloDef(
      key: (row['articolo_key'] ?? '').toString().trim(),
      label: (row['label'] ?? '').toString().trim(),
      active: row['active'] == true,
      sizeType: (row['size_type'] ?? 'top').toString(),
      inMagazzino: row['in_magazzino'] == true,
      inAssegnazione: row['in_assegnazione'] == true,
      stagioneEstivo: row['stagione_estivo'] != false,
      stagioneInvernale: row['stagione_invernale'] != false,
      modelloUnico: row['modello_unico'] == true,
      isDpiIii: row['is_dpi_iii'] == true,
      magazzinoStagioneUnica:
          (row['magazzino_stagione_unica'] ?? '').toString().trim().isEmpty
              ? null
              : (row['magazzino_stagione_unica'] ?? '').toString().trim(),
      moltiplicatoreEstivo: _parseNonNeg(row['moltiplicatore_estivo']),
      moltiplicatoreInvernale: _parseNonNeg(row['moltiplicatore_invernale']),
      sortOrder: _parseNonNeg(row['sort_order'], fallback: 100),
      excelRows: excelRows,
      sizeLabel: _nullableStr(row['size_label']),
      tagliaPersonaleField: _nullableStr(row['taglia_personale_field']),
    );
  }

  Map<String, dynamic> toUpsertMap() {
    return <String, dynamic>{
      'articolo_key': key,
      'label': label,
      'active': active,
      'size_type': sizeType,
      'in_magazzino': inMagazzino,
      'in_assegnazione': inAssegnazione,
      'stagione_estivo': stagioneEstivo,
      'stagione_invernale': stagioneInvernale,
      'modello_unico': modelloUnico,
      'is_dpi_iii': isDpiIii,
      'magazzino_stagione_unica': magazzinoStagioneUnica,
      'moltiplicatore_estivo': moltiplicatoreEstivo,
      'moltiplicatore_invernale': moltiplicatoreInvernale,
      'sort_order': sortOrder,
      'excel_rows':
          excelRows.isEmpty ? null : excelRows.map((e) => '$e').join(','),
      'size_label': sizeLabel,
      'taglia_personale_field': tagliaPersonaleField,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static String? _nullableStr(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static int _parseNonNeg(dynamic v, {int fallback = 0}) {
    final n = (v is int) ? v : int.tryParse(v?.toString() ?? '');
    if (n == null || n < 0) return fallback;
    return n;
  }
}

/// Catalogo runtime articoli vestiario (DB + fallback incorporato).
abstract final class VestiarioArticoliService {
  VestiarioArticoliService._();

  static const String table = 'vestiario_articoli';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<VestiarioArticoloDef> _cache = List<VestiarioArticoloDef>.from(
    kBuiltinVestiarioArticoli,
  );

  static bool _loaded = false;

  static List<VestiarioArticoloDef> get all => List.unmodifiable(_cache);

  static List<VestiarioArticoloDef> get activeArticoli => _cache
      .where((a) => a.active)
      .toList(growable: false)
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

  static VestiarioArticoloDef? byKey(String key) {
    final k = key.trim();
    for (final a in _cache) {
      if (a.key == k) return a;
    }
    return null;
  }

  static String labelFor(String key) => byKey(key)?.label ?? key;

  static List<String> activeMagazzinoKeys() => activeArticoli
      .where((a) => a.inMagazzino)
      .map((a) => a.key)
      .toList(growable: false);

  static List<String> activeDpiMagazzinoKeys() => activeArticoli
      .where((a) => a.inMagazzino && a.isDpiIii)
      .map((a) => a.key)
      .toList(growable: false);

  static List<String> activeAssegnazioneKeys() => activeArticoli
      .where((a) => a.inAssegnazione)
      .map((a) => a.key)
      .toList(growable: false);

  static const List<String> _estivoDefaultKeys = <String>[
    'tshirt',
    'pantalone',
    'giacca_leggera',
    'scarpe',
  ];

  static const List<String> _invernaleDefaultKeys = <String>[
    'felpa',
    'giacca',
    'gilet',
    'guanti_pelle',
    'guanti_tessuto',
    'pantalone',
    'scarpe',
  ];

  static List<String> defaultAssegnazioneForSeason(String season) {
    final keys = season == 'estivo' ? _estivoDefaultKeys : _invernaleDefaultKeys;
    return activeArticoli
        .where((a) => a.inAssegnazione && keys.contains(a.key))
        .map((a) => a.key)
        .toList(growable: false);
  }

  static Future<void> ensureLoaded() async {
    if (!_loaded) await refresh();
  }

  static Future<void> refresh() async {
    try {
      final res = await SupabaseService.client
          .from(table)
          .select()
          .order('sort_order')
          .order('label');
      final fromDb = (res as List)
          .map((e) => VestiarioArticoloDef.fromRow(
                Map<String, dynamic>.from(e as Map),
              ))
          .where((a) => a.key.isNotEmpty && a.label.isNotEmpty)
          .toList();
      if (fromDb.isEmpty) {
        _cache = List<VestiarioArticoloDef>.from(kBuiltinVestiarioArticoli);
      } else {
        final byKey = <String, VestiarioArticoloDef>{
          for (final b in kBuiltinVestiarioArticoli) b.key: b,
        };
        for (final row in fromDb) {
          byKey[row.key] = row;
        }
        _cache = byKey.values.toList();
      }
      _loaded = true;
      revision.value++;
    } catch (_) {
      _cache = List<VestiarioArticoloDef>.from(kBuiltinVestiarioArticoli);
      _loaded = true;
    }
  }

  static String keyFromLabel(String label) {
    var s = label
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty) s = 'articolo';
    var candidate = s;
    var i = 2;
    while (byKey(candidate) != null) {
      candidate = '${s}_$i';
      i++;
    }
    return candidate;
  }

  static Future<List<Map<String, dynamic>>> listAllRows() async {
    final res = await SupabaseService.client
        .from(table)
        .select()
        .order('sort_order')
        .order('label');
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<VestiarioArticoloDef> addArticolo({
    required String label,
    String? key,
    String sizeType = 'top',
    bool inMagazzino = false,
    bool inAssegnazione = true,
    bool stagioneEstivo = true,
    bool stagioneInvernale = true,
    bool modelloUnico = false,
    bool isDpiIii = false,
    String? magazzinoStagioneUnica,
    int moltiplicatoreEstivo = 1,
    int moltiplicatoreInvernale = 1,
    String? sizeLabel,
    String? tagliaPersonaleField,
    List<int> excelRows = const <int>[],
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nome articolo obbligatorio');
    }
    final articoloKey = (key ?? keyFromLabel(trimmed)).trim();
    if (articoloKey.isEmpty) {
      throw ArgumentError('Chiave articolo non valida');
    }
    final maxSort = _cache.isEmpty
        ? 100
        : _cache.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b);
    final def = VestiarioArticoloDef(
      key: articoloKey,
      label: trimmed,
      active: true,
      sizeType: sizeType,
      inMagazzino: inMagazzino,
      inAssegnazione: inAssegnazione,
      stagioneEstivo: stagioneEstivo,
      stagioneInvernale: stagioneInvernale,
      modelloUnico: modelloUnico,
      isDpiIii: isDpiIii,
      magazzinoStagioneUnica: magazzinoStagioneUnica,
      moltiplicatoreEstivo: inMagazzino && stagioneEstivo
          ? moltiplicatoreEstivo
          : 0,
      moltiplicatoreInvernale: inMagazzino && stagioneInvernale
          ? moltiplicatoreInvernale
          : 0,
      sortOrder: maxSort + 1,
      excelRows: excelRows,
      sizeLabel: sizeLabel,
      tagliaPersonaleField: tagliaPersonaleField,
    );
    await SupabaseService.client.from(table).upsert(
          def.toUpsertMap(),
          onConflict: 'articolo_key',
        );
    await refresh();
    return def;
  }

  static Future<void> updateArticolo(VestiarioArticoloDef def) async {
    await SupabaseService.client.from(table).upsert(
          def.toUpsertMap(),
          onConflict: 'articolo_key',
        );
    await refresh();
  }

  static Future<void> setActive({
    required String articoloKey,
    required bool active,
  }) async {
    final key = articoloKey.trim();
    if (key.isEmpty) return;
    await SupabaseService.client.from(table).update({
      'active': active,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (!active) ...{
        'in_magazzino': false,
        'in_assegnazione': false,
      },
    }).eq('articolo_key', key);
    await refresh();
  }

  static Future<void> deleteArticolo(String articoloKey) async {
    final key = articoloKey.trim();
    if (key.isEmpty) return;
    await SupabaseService.client.from(table).delete().eq('articolo_key', key);
    await refresh();
  }

  static Future<void> saveMoltiplicatori({
    required Map<String, int> estivo,
    required Map<String, int> invernale,
  }) async {
    for (final a in activeArticoli.where((e) => e.inMagazzino)) {
      final me = estivo[a.key];
      final mi = invernale[a.key];
      if (me == null && mi == null) continue;
      await SupabaseService.client.from(table).update({
        'moltiplicatore_estivo': ?me,
        'moltiplicatore_invernale': ?mi,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('articolo_key', a.key);
    }
    await refresh();
  }

  static int moltiplicatoreFallback(String key, String season) {
    final a = byKey(key);
    if (a == null) return 0;
    return season == 'estivo' ? a.moltiplicatoreEstivo : a.moltiplicatoreInvernale;
  }
}

/// Fallback locale se la tabella non è ancora migrata.
const List<VestiarioArticoloDef> kBuiltinVestiarioArticoli = <VestiarioArticoloDef>[
  VestiarioArticoloDef(
    key: 'scarpe',
    label: 'Scarpe',
    sizeType: 'shoe',
    inMagazzino: true,
    inAssegnazione: true,
    modelloUnico: true,
    moltiplicatoreEstivo: 1,
    moltiplicatoreInvernale: 1,
    sortOrder: 10,
    excelRows: <int>[15],
    sizeLabel: 'Scarpe',
    tagliaPersonaleField: 'taglia_scarpe',
  ),
  VestiarioArticoloDef(
    key: 'occhiali',
    label: 'Occhiale Paraschegge',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 16,
    excelRows: <int>[16],
  ),
  VestiarioArticoloDef(
    key: 'archetti',
    label: 'Archetti Antirumore',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 17,
    excelRows: <int>[17],
  ),
  VestiarioArticoloDef(
    key: 'cuffie',
    label: 'Cuffie Antirumore',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 18,
    excelRows: <int>[18],
  ),
  VestiarioArticoloDef(
    key: 'guanti_pelle',
    label: 'Guanti pelle',
    sizeType: 'glove',
    inMagazzino: true,
    inAssegnazione: true,
    stagioneEstivo: false,
    modelloUnico: true,
    magazzinoStagioneUnica: 'invernale',
    moltiplicatoreInvernale: 1,
    sortOrder: 19,
    excelRows: <int>[19],
    sizeLabel: 'Guanti',
    tagliaPersonaleField: 'taglia_guanti',
  ),
  VestiarioArticoloDef(
    key: 'guanti_tessuto',
    label: 'Guanti tessuto (nylon/poliuretano)',
    sizeType: 'glove',
    inMagazzino: true,
    inAssegnazione: true,
    stagioneEstivo: false,
    modelloUnico: true,
    magazzinoStagioneUnica: 'invernale',
    moltiplicatoreInvernale: 1,
    sortOrder: 20,
    excelRows: <int>[20],
    sizeLabel: 'Guanti',
    tagliaPersonaleField: 'taglia_guanti',
  ),
  VestiarioArticoloDef(
    key: 'gilet',
    label: 'Gilet',
    sizeType: 'top',
    inMagazzino: true,
    inAssegnazione: true,
    modelloUnico: true,
    moltiplicatoreEstivo: 1,
    moltiplicatoreInvernale: 1,
    sortOrder: 21,
    excelRows: <int>[21],
    sizeLabel: 'Gilet',
    tagliaPersonaleField: 'taglia_gilet',
  ),
  VestiarioArticoloDef(
    key: 'tshirt',
    label: 'T-shirt',
    sizeType: 'top',
    inMagazzino: true,
    inAssegnazione: true,
    modelloUnico: true,
    moltiplicatoreEstivo: 1,
    moltiplicatoreInvernale: 1,
    sortOrder: 22,
    excelRows: <int>[22],
    sizeLabel: 'T-shirt',
    tagliaPersonaleField: 'taglia_tshirt',
  ),
  VestiarioArticoloDef(
    key: 'pantalone',
    label: 'Pantalone',
    sizeType: 'trouser',
    inMagazzino: true,
    inAssegnazione: true,
    moltiplicatoreEstivo: 1,
    moltiplicatoreInvernale: 1,
    sortOrder: 24,
    excelRows: <int>[24],
    sizeLabel: 'Pantalone',
    tagliaPersonaleField: 'taglia_pantalone',
  ),
  VestiarioArticoloDef(
    key: 'felpa',
    label: 'Felpa',
    sizeType: 'top',
    inMagazzino: true,
    inAssegnazione: true,
    stagioneEstivo: false,
    moltiplicatoreInvernale: 1,
    sortOrder: 25,
    excelRows: <int>[25],
    sizeLabel: 'Felpa',
    tagliaPersonaleField: 'taglia_felpa',
  ),
  VestiarioArticoloDef(
    key: 'giacca_leggera',
    label: 'Giacca leggera',
    sizeType: 'top',
    inMagazzino: true,
    inAssegnazione: true,
    stagioneInvernale: false,
    moltiplicatoreEstivo: 1,
    sortOrder: 26,
    excelRows: <int>[26],
    sizeLabel: 'Giacca',
    tagliaPersonaleField: 'taglia_giacca',
  ),
  VestiarioArticoloDef(
    key: 'giacca',
    label: 'Giacca',
    sizeType: 'top',
    inMagazzino: true,
    inAssegnazione: true,
    stagioneEstivo: false,
    moltiplicatoreInvernale: 1,
    sortOrder: 27,
    excelRows: <int>[26],
    sizeLabel: 'Giacca',
    tagliaPersonaleField: 'taglia_giacca',
  ),
  VestiarioArticoloDef(
    key: 'borsa_dpi',
    label: 'Borsa Porta DPI 48x50x35',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 28,
    excelRows: <int>[27],
  ),
  VestiarioArticoloDef(
    key: 'lampada_frontale',
    label: 'Lampada Frontale',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 29,
    excelRows: <int>[28],
  ),
  VestiarioArticoloDef(
    key: 'completo_antipioggia',
    label: 'Completo Antipioggia',
    sizeType: 'none',
    inAssegnazione: true,
    sortOrder: 30,
    excelRows: <int>[29],
  ),
  VestiarioArticoloDef(
    key: 'berretto_lana',
    label: 'Berretto in Lana',
    sizeType: 'none',
    inAssegnazione: true,
    stagioneEstivo: false,
    sortOrder: 31,
    excelRows: <int>[30],
  ),
  VestiarioArticoloDef(
    key: 'elmetto',
    label: 'Elmetto',
    sizeType: 'unit',
    inMagazzino: true,
    isDpiIii: true,
    magazzinoStagioneUnica: 'estivo',
    sortOrder: 40,
  ),
  VestiarioArticoloDef(
    key: 'imbracatura',
    label: 'Imbracatura',
    sizeType: 'unit',
    inMagazzino: true,
    isDpiIii: true,
    magazzinoStagioneUnica: 'estivo',
    sortOrder: 41,
  ),
  VestiarioArticoloDef(
    key: 'cordino_singolo_dissipatore',
    label: 'Cordino singolo con dissipatore',
    sizeType: 'unit',
    inMagazzino: true,
    isDpiIii: true,
    magazzinoStagioneUnica: 'estivo',
    sortOrder: 42,
  ),
  VestiarioArticoloDef(
    key: 'cordino_posizionamento',
    label: 'Cordino di posizionamento',
    sizeType: 'unit',
    inMagazzino: true,
    isDpiIii: true,
    magazzinoStagioneUnica: 'estivo',
    sortOrder: 43,
  ),
  VestiarioArticoloDef(
    key: 'cordino_y_dissipatore',
    label: 'Cordino Shock Absorber Doppio',
    sizeType: 'unit',
    inMagazzino: true,
    isDpiIii: true,
    magazzinoStagioneUnica: 'estivo',
    sortOrder: 44,
  ),
];
