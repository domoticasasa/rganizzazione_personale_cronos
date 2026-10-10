import '../hub/app_ui_hub_registry.dart';
import '../hub/app_ui_custom_hub.dart';
import '../hub/custom_hub_page_config.dart';
import '../hub/custom_hub_structure_templates.dart';
import '../hub/custom_hub_structure_type.dart';
import '../hub/dpi_hub_nav_items.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/module_visibility_flags.dart';
import '../utils/roles.dart';
import 'supabase_service.dart';

/// Ordine globale tile/pulsanti (Supabase [app_ui_layout_order]).
abstract final class AppUiLayoutService {
  static const String layoutDashboardAdmin = 'dashboard_admin';
  /// Layout ordine/griglia per la dashboard admin in UI futuristica.
  static const String layoutDashboardAdminFuturistic = 'dashboard_admin_futuristic';
  static const String layoutLogisticaHub = 'logistica_hub';
  /// Sotto-hub Carburante (Rifornimento MDO + RCC stradali).
  static const String layoutCarburanteHub = 'carburante_hub';
  static const String layoutUqsaHub = 'uqsa_hub';
  static const String layoutListePosHub = 'liste_pos_hub';
  static const String layoutImpostazioniHub = 'impostazioni_hub';
  static const String layoutHomeDipendente = 'home_dipendente';
  static const String layoutHomeMain = 'home_main';
  static const String layoutHomeAdmin = 'home_admin';
  static const String layoutHomeDt = 'home_dt';
  /// Layout Vista DT in GESTOPRO (indipendente da [layoutHomeDt] classico).
  static const String layoutHomeDtFuturistic = 'home_dt_futuristic';
  static const String layoutDpiHub = 'dpi_hub';

  /// Voci rimosse dagli admin (non reinserite dai default).
  static const String layoutHiddenItemKeys = '__hidden_item_keys__';

  static bool canEditGlobalLayout(String role) => canMutateAsAdmin(role);

  /// Override personali (non usati per Home DT: quella è globale, la salva l'admin).
  static bool usesPersonalLayoutPersistence(String role) =>
      canEditHomePageLayout(role) && !canEditGlobalLayout(role);

  /// Home DT classica e GESTOPRO: un solo layout per tutti i DT.
  static bool isAdminManagedDtHomeLayout(String layoutKey) =>
      layoutKey == layoutHomeDt || layoutKey == layoutHomeDtFuturistic;

  /// Ordine canonico Home DT: inietta tile obbligatorie se assenti dal salvataggio.
  static const List<String> _legacyDtPosListaKeys = <String>[
    'pos_dipendenti_lista',
    'pos_mdo_ferroviari_lista',
    'pos_mezzi_stradali_lista',
    'pos_mdo_proprieta_lista',
  ];

  static List<String> ensureDtHomeOrderKeys(List<String> keys) {
    final base = List<String>.from(keys);
    if (!ModuleVisibilityFlags.showDtRichiesteFeriePermessi) {
      base.remove('richieste_ferie_permessi');
    }

    // POS, tesserini e moduli UQSA stanno nell'hub UQSA (un solo tile in home).
    base.remove(layoutListePosHub);
    base.remove('il_mio_tesserino');
    base.remove('tesserini');
    base.remove('dpi_hub');
    base.removeWhere(_legacyDtPosListaKeys.contains);
    base.removeWhere(
      (k) => k.startsWith('vestiario_') || k.startsWith('dpi_'),
    );

    if (!base.contains('uqsa')) {
      base.insert(0, 'uqsa');
    }

    if (!base.contains('visite_mediche')) {
      final idx = base.indexOf('richieste_ferie_permessi');
      if (idx >= 0) {
        base.insert(idx + 1, 'visite_mediche');
      } else {
        base.add('visite_mediche');
      }
    }
    if (!base.contains('segnalazione_assenze')) {
      base.add('segnalazione_assenze');
    }
    if (!base.contains('carburante')) {
      final idx = base.indexOf('logistica');
      if (idx >= 0) {
        base.insert(idx + 1, 'carburante');
      } else {
        base.add('carburante');
      }
    }
    if (!base.contains('mdo_mappa_gps')) {
      final idx = base.indexOf('carburante');
      if (idx >= 0) {
        base.insert(idx + 1, 'mdo_mappa_gps');
      } else {
        base.add('mdo_mappa_gps');
      }
    }
    if (!base.contains('bacheca')) {
      final idx = base.indexOf('mdo_mappa_gps');
      if (idx >= 0) {
        base.insert(idx + 1, 'bacheca');
      } else {
        base.add('bacheca');
      }
    }
    if (!base.contains('rubrica')) {
      final idx = base.indexOf('visite_mediche');
      if (idx >= 0) {
        base.insert(idx + 1, 'rubrica');
      } else {
        final s = base.indexOf('segnalazione_assenze');
        if (s >= 0) {
          base.insert(s, 'rubrica');
        } else {
          base.add('rubrica');
        }
      }
    }
    return base;
  }

  /// Inietta tile nuovi se assenti (hub già salvato in precedenza).
  static const String importDatiExcelKey = 'import_dati_excel';
  static const String accessiAppKey = 'accessi_app';
  static const String logAppKey = 'log_app';
  static const String videoIstruzioniKey = 'video_istruzioni';
  static const String personalizzazioneAppKey = 'personalizzazione_app';
  static const String temaAppKey = 'tema_app';
  static const String utilizzoSupabaseKey = 'utilizzo_supabase';
  static const String backupDatiKey = 'backup_dati';
  static const String incidentiSicurezzaKey = 'incidenti_sicurezza';

  static List<String> ensureImpostazioniHubOrderKeys(List<String> keys) {
    var out = List<String>.from(keys);
    if (!out.contains(importDatiExcelKey)) {
      out = <String>[importDatiExcelKey, ...out];
    }
    if (!out.contains(accessiAppKey)) {
      out.add(accessiAppKey);
    }
    if (!out.contains(logAppKey)) {
      final idx = out.indexOf(accessiAppKey);
      if (idx >= 0) {
        out.insert(idx + 1, logAppKey);
      } else {
        out.add(logAppKey);
      }
    }
    if (!out.contains(videoIstruzioniKey)) {
      final idx = out.indexOf(personalizzazioneAppKey);
      if (idx >= 0) {
        out.insert(idx, videoIstruzioniKey);
      } else {
        out.add(videoIstruzioniKey);
      }
    }
    if (!out.contains(temaAppKey)) {
      final idx = out.indexOf(personalizzazioneAppKey);
      if (idx >= 0) {
        out.insert(idx, temaAppKey);
      } else {
        out.add(temaAppKey);
      }
    }
    if (!out.contains(personalizzazioneAppKey)) {
      out.add(personalizzazioneAppKey);
    }
    if (!out.contains(utilizzoSupabaseKey)) {
      final idx = out.indexOf(personalizzazioneAppKey);
      if (idx >= 0) {
        out.insert(idx + 1, utilizzoSupabaseKey);
      } else {
        out.add(utilizzoSupabaseKey);
      }
    }
    if (!out.contains(backupDatiKey)) {
      final idx = out.indexOf(utilizzoSupabaseKey);
      if (idx >= 0) {
        out.insert(idx + 1, backupDatiKey);
      } else {
        out.add(backupDatiKey);
      }
    }
    if (!out.contains(incidentiSicurezzaKey)) {
      final idx = out.indexOf(backupDatiKey);
      if (idx >= 0) {
        out.insert(idx + 1, incidentiSicurezzaKey);
      } else {
        out.add(incidentiSicurezzaKey);
      }
    }
    return out;
  }

  static const String uqsaSediSicurezzaKey = 'uqsa_sedi_sicurezza';
  static const String attestatiDipendentiKey = 'attestati_dipendenti';

  /// Inietta moduli UQSA nuovi nei layout già salvati, vicino ai sibling.
  static List<String> ensureUqsaHubOrderKeys(List<String> keys) {
    final out = List<String>.from(keys);
    // Rimuove eventuali chiavi split (rollback) se presenti.
    out.remove('uqsa_sedi_sicurezza_box');
    out.remove('uqsa_sedi_sicurezza_mdo');
    if (!out.contains(layoutListePosHub)) {
      out.insert(0, layoutListePosHub);
    }
    if (!out.contains(uqsaSediSicurezzaKey)) {
      final casIdx = out.indexOf('casette_ps');
      final estIdx = out.indexOf('estintori');
      final insertAt = casIdx >= 0
          ? casIdx + 1
          : (estIdx >= 0 ? estIdx + 1 : out.length);
      out.insert(insertAt.clamp(0, out.length), uqsaSediSicurezzaKey);
    }
    if (!out.contains('il_mio_tesserino')) {
      out.add('il_mio_tesserino');
    }
    if (!out.contains('tesserini')) {
      out.add('tesserini');
    }
    return out;
  }

  static const List<String> _carburanteHubDefaultKeys = <String>[
    'giustificativi_riepilogo',
    'rifornimento_mdo',
    'rcc_carburante',
    'qt_fatturazione_verifica',
  ];

  static const Set<String> _carburanteModuleKeys = <String>{
    'giustificativi_riepilogo',
    'rifornimento_mdo',
    'rcc_carburante',
    'qt_fatturazione_verifica',
  };

  static const String _legacyCarburanteHubLayoutKey = 'carburante';

  /// Chiave legacy esposta per pagine che usano ancora `carburante` come layout.
  static const String legacyCarburanteHubLayoutKey = _legacyCarburanteHubLayoutKey;

  /// Hub canonico per moduli riorganizzati (rispetta spostamenti richiesti in app).
  static const Map<String, String> _canonicalHubForModule = <String, String>{
    'estintori': layoutUqsaHub,
    'casette_ps': layoutUqsaHub,
    'uqsa_sedi_sicurezza': layoutUqsaHub,
    'rifornimento_mdo': layoutCarburanteHub,
    'rcc_carburante': layoutCarburanteHub,
    'qt_fatturazione_verifica': layoutCarburanteHub,
    'giustificativi_riepilogo': layoutCarburanteHub,
    'mdo_mappa_gps': layoutDashboardAdmin,
    'documenti_firma': layoutDashboardAdmin,
    'officine_convenzionate': layoutLogisticaHub,
    'mdo_ferroviari_documenti': layoutLogisticaHub,
    'multicard_mdo_assegnazioni': layoutLogisticaHub,
    'mdo_per_commessa': layoutLogisticaHub,
    'bacheca': layoutDashboardAdmin,
  };

  /// Gruppi di moduli correlati: un tile nuovo finisce nello stesso hub
  /// dove l'utente ha già spostato un sibling (layout salvato in Supabase).
  static const List<List<String>> _moduleAffinityGroups = <List<String>>[
    <String>[
      'giustificativi_riepilogo',
      'rifornimento_mdo',
      'rcc_carburante',
      'qt_fatturazione_verifica',
    ],
    <String>[
      'attrezzature',
      'box',
    ],
    <String>[
      'mdo_ferroviari',
      'mdo_proprieta',
    ],
    <String>[
      'estintori',
      'casette_ps',
      'uqsa_sedi_sicurezza',
    ],
    <String>[
      'pos_dipendenti_lista',
      'pos_mdo_ferroviari_lista',
      'pos_mezzi_stradali_lista',
      'pos_mdo_proprieta_lista',
    ],
    <String>[
      'formazione_dlgs',
      'formazione_rfi',
      'strutture_rfi',
      'programmazione_formazioni',
      'programmazione_formazioni_rfi',
      'attestati_dipendenti',
    ],
    <String>[
      'gestione_dipendenti',
      'gestione_dati',
      'verifica_costo_stradale',
      'dislocazione_personale',
    ],
    <String>[
      'accessi_app',
      'log_app',
      'tema_app',
      'personalizzazione_app',
      'utilizzo_supabase',
      'backup_dati',
    ],
    <String>[
      'visite_mediche',
      'visite_mediche_rfi',
      'segnalazione_assenze',
      'rubrica',
    ],
    <String>[
      'mezzi_stradali',
      'noleggio',
      'sim_telefoni',
    ],
  ];

  static const List<String> _posListeHubDefaultKeys = <String>[
    'pos_dipendenti_lista',
    'pos_mdo_ferroviari_lista',
    'pos_mdo_proprieta_lista',
    'pos_mezzi_stradali_lista',
  ];

  static const Set<String> _posListeModuleKeys = <String>{
    'pos_dipendenti_lista',
    'pos_mdo_ferroviari_lista',
    'pos_mdo_proprieta_lista',
    'pos_mezzi_stradali_lista',
  };

  static List<String> posListeHubDefaultKeys() =>
      List<String>.from(_posListeHubDefaultKeys);

  static List<String> ensureListePosHubOrderKeys(List<String> keys) {
    return mergeHubOrderWithCatalog(
      saved: keys,
      catalogKeys: _posListeHubDefaultKeys,
    );
  }

  static List<String> resolveListePosHubOrderKeys(
    List<String>? saved,
    List<String> defaults,
  ) =>
      ensureListePosHubOrderKeys(
        mergeHubOrderWithCatalog(
          saved: saved ?? const <String>[],
          catalogKeys: defaults.isNotEmpty
              ? defaults
              : _posListeHubDefaultKeys,
        ),
      );

  /// Hub Carburante: garantisce i moduli se l'ordine salvato è assente o incompleto.
  static List<String> ensureCarburanteHubOrderKeys(List<String> keys) {
    return mergeHubOrderWithCatalog(
      saved: keys,
      catalogKeys: _carburanteHubDefaultKeys,
    );
  }

  static List<String> carburanteHubDefaultKeys() =>
      List<String>.from(_carburanteHubDefaultKeys);

  /// Ordine hub Carburante già in memoria (dopo il primo caricamento globale).
  static List<String>? cachedCarburanteHubOrderKeys() {
    final cached = _cachedGlobalOrders;
    if (cached == null || cached.isEmpty) return null;

    final orders = _migrateLegacyCarburanteHubLayout(
      Map<String, List<String>>.from(cached),
    );
    var saved = orders[layoutCarburanteHub];
    if (saved == null || saved.isEmpty) {
      saved = orders[_legacyCarburanteHubLayoutKey];
    }
    if (saved == null || saved.isEmpty) return null;

    return ensureCarburanteHubOrderKeys(
      resolveCarburanteHubOrderKeys(saved, _carburanteHubDefaultKeys),
    );
  }

  /// Migra contenuti hub da layout_key legacy `carburante` → `carburante_hub`.
  static Map<String, List<String>> _migrateLegacyCarburanteHubLayout(
    Map<String, List<String>> orders,
  ) {
    final copy = <String, List<String>>{
      for (final e in orders.entries) e.key: List<String>.from(e.value),
    };
    final legacy = copy.remove(_legacyCarburanteHubLayoutKey);
    if (legacy != null && legacy.isNotEmpty) {
      final modules =
          legacy.where(_carburanteModuleKeys.contains).toList(growable: false);
      if (modules.isNotEmpty) {
        final hub = List<String>.from(
          copy[layoutCarburanteHub] ?? <String>[],
        );
        for (final key in modules) {
          if (!hub.contains(key)) hub.add(key);
        }
        copy[layoutCarburanteHub] = hub;
      }
    }
    return copy;
  }

  static void _ensureCarburanteHubSeeded(Map<String, List<String>> map) {
    map[layoutCarburanteHub] = ensureCarburanteHubOrderKeys(
      map[layoutCarburanteHub] ?? <String>[],
    );
  }

  static List<String> resolveDtHomeOrderKeys(
    List<String>? saved,
    List<String> defaults,
  ) =>
      ensureDtHomeOrderKeys(
        mergeHubOrderWithCatalog(
          saved: saved ?? const <String>[],
          catalogKeys: defaults,
        ),
      );

  /// Hub Logistica: unisce layout salvato e catalogo (es. Mappa MDO GPS).
  static List<String> resolveLogisticaHubOrderKeys(
    List<String>? saved,
    List<String> defaults,
  ) =>
      mergeHubOrderWithCatalog(
        saved: saved ?? const <String>[],
        catalogKeys: defaults,
      );

  /// Hub Carburante: unisce layout salvato e catalogo moduli.
  static List<String> resolveCarburanteHubOrderKeys(
    List<String>? saved,
    List<String> defaults,
  ) =>
      mergeHubOrderWithCatalog(
        saved: saved ?? const <String>[],
        catalogKeys: defaults.isNotEmpty
            ? defaults
            : _carburanteHubDefaultKeys,
      );

  /// Moduli introdotti in release successive: inseriti solo se ancora assenti.
  static const Map<String, List<String>> _shippedHubModuleKeys =
      <String, List<String>>{};

  static void _enforceCanonicalHubModules(
    Map<String, List<String>> map, {
    required Set<String> hidden,
  }) {
    for (final entry in _canonicalHubForModule.entries) {
      final key = entry.key;
      final targetHub = entry.value;
      if (hidden.contains(key)) continue;
      final existsAnywhere = map.values.any((keys) => keys.contains(key));
      if (!existsAnywhere) {
        // Ensure canonical modules are always present even in legacy saved layouts.
        // Previously this auto-seeded only Carburante modules, causing some modules
        // (e.g. documenti_firma) to remain missing in certain dashboard variants.
        _addKeyToHubMap(map, targetHub, key);
        if (targetHub == layoutDashboardAdmin) {
          _addKeyToHubMap(map, layoutDashboardAdminFuturistic, key);
        }
        if (targetHub == layoutHomeDt) {
          _addKeyToHubMap(map, layoutHomeDtFuturistic, key);
        }
        continue;
      }
      for (final layoutKey in map.keys.toList()) {
        // Non togliere dalla dashboard futuristica: la riallineiamo subito sotto.
        if (layoutKey == layoutDashboardAdminFuturistic &&
            targetHub == layoutDashboardAdmin) {
          continue;
        }
        if (layoutKey == layoutHomeDtFuturistic && targetHub == layoutHomeDt) {
          continue;
        }
        final keys = List<String>.from(map[layoutKey] ?? <String>[]);
        if (keys.remove(key)) map[layoutKey] = keys;
      }
      _addKeyToHubMap(map, targetHub, key);
      if (targetHub == layoutDashboardAdmin) {
        _addKeyToHubMap(map, layoutDashboardAdminFuturistic, key);
      }
      if (targetHub == layoutHomeDt) {
        _addKeyToHubMap(map, layoutHomeDtFuturistic, key);
      }
    }
  }

  /// Rubrica deve stare su dashboard admin (classica + GESTOPRO) e su Vista DT.
  /// Non è un modulo canonico: `_canonicalHubForModule` la toglierebbe da un hub.
  static void _ensureRubricaOnAdminDashboard(
    Map<String, List<String>> map, {
    required Set<String> hidden,
  }) {
    const key = 'rubrica';
    if (!hidden.contains(key)) {
      if (map.containsKey(layoutDashboardAdmin)) {
        _addKeyToHubMapNearAffinitySiblings(map, layoutDashboardAdmin, key);
      }
      if (map.containsKey(layoutDashboardAdminFuturistic)) {
        _addKeyToHubMapNearAffinitySiblings(
          map,
          layoutDashboardAdminFuturistic,
          key,
        );
      }
    }
  }

  /// Salva in Supabase l'ordine hub Carburante se assente o vuoto (fix pagina vuota).
  static Future<void> ensureCarburanteHubLayoutPersisted({
    required List<String> keys,
    String? role,
  }) async {
    final normalized = ensureCarburanteHubOrderKeys(keys);
    if (normalized.isEmpty) return;

    bool needsSave(List<String>? existing) {
      if (existing == null || existing.isEmpty) return true;
      return !existing.any(_carburanteModuleKeys.contains);
    }

    if (usesPersonalLayoutPersistence(role ?? '')) {
      final userId = await currentUserDbId();
      if (userId == null) return;
      final existing = await _loadUserOrder(userId, layoutCarburanteHub);
      if (!needsSave(existing)) return;
      await _saveUserOrder(userId, layoutCarburanteHub, normalized);
      return;
    }

    final existing = await _loadGlobalOrder(layoutCarburanteHub);
    if (!needsSave(existing)) return;
    await saveOrder(layoutKey: layoutCarburanteHub, itemKeys: normalized);
  }

  static String? _layoutHubContainingAffinitySibling(
    String moduleKey,
    Map<String, List<String>> map,
  ) {
    for (final group in _moduleAffinityGroups) {
      if (!group.contains(moduleKey)) continue;
      for (final entry in map.entries) {
        for (final sibling in group) {
          if (sibling == moduleKey) continue;
          if (entry.value.contains(sibling)) return entry.key;
        }
      }
    }
    return null;
  }

  static String? _defaultHubForModuleKey(
    String key,
    Map<String, List<String>> defaultKeysByLayout,
  ) {
    for (final entry in defaultKeysByLayout.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    return null;
  }

  static void _addKeyToHubMap(
    Map<String, List<String>> map,
    String layoutKey,
    String key,
  ) {
    final keys = List<String>.from(map[layoutKey] ?? <String>[]);
    if (keys.contains(key)) return;
    keys.add(key);
    map[layoutKey] = keys;
  }

  static void _addKeyToHubMapNearAffinitySiblings(
    Map<String, List<String>> map,
    String layoutKey,
    String key,
  ) {
    final keys = List<String>.from(map[layoutKey] ?? <String>[]);
    if (keys.contains(key)) return;
    var insertAt = keys.length;
    for (final group in _moduleAffinityGroups) {
      if (!group.contains(key)) continue;
      for (final sibling in group) {
        if (sibling == key) continue;
        final i = keys.indexOf(sibling);
        if (i >= 0) insertAt = i + 1;
      }
    }
    keys.insert(insertAt.clamp(0, keys.length), key);
    map[layoutKey] = keys;
  }

  /// Moduli che devono stare nello stesso hub dei sibling Formazione
  /// (hub custom «Formazioni 81 e RFI»).
  static const Set<String> _followAffinityHubModules = <String>{
    attestatiDipendentiKey,
  };

  static String? _preferredAffinityHub(
    String moduleKey,
    Map<String, List<String>> map,
  ) {
    final hits = <String>[];
    for (final group in _moduleAffinityGroups) {
      if (!group.contains(moduleKey)) continue;
      for (final entry in map.entries) {
        for (final sibling in group) {
          if (sibling == moduleKey) continue;
          if (entry.value.contains(sibling) && !hits.contains(entry.key)) {
            hits.add(entry.key);
          }
        }
      }
    }
    if (hits.isEmpty) return null;
    String? custom;
    String? uqsa;
    String? other;
    for (final h in hits) {
      if (AppUiCustomHub.isCustomLayoutKey(h)) {
        custom ??= h;
      } else if (h == layoutUqsaHub) {
        uqsa ??= h;
      } else if (h != layoutDashboardAdminFuturistic) {
        other ??= h;
      }
    }
    return custom ?? uqsa ?? other ?? hits.first;
  }

  static String? _formazioniCustomHubLayoutKey(List<AppUiCustomHub> customHubs) {
    final byType = customHubs
        .where((h) => h.structureType == CustomHubStructureType.formazioni)
        .toList(growable: false);
    if (byType.length == 1) return byType.first.layoutKey;
    if (byType.length > 1) {
      for (final h in byType) {
        if (h.label.toLowerCase().contains('formazion')) return h.layoutKey;
      }
      return byType.first.layoutKey;
    }
    for (final h in customHubs) {
      final label = h.label.toLowerCase();
      if (label.contains('formazion')) return h.layoutKey;
    }
    return null;
  }

  /// Sposta i moduli nel hub dove l'utente ha già messo Formazione 81/RFI
  /// (anche pagine custom tipo «Formazioni 81 e RFI»).
  static void _enforceFollowAffinityHubModules(
    Map<String, List<String>> map, {
    required List<AppUiCustomHub> customHubs,
    required Set<String> hidden,
  }) {
    for (final key in _followAffinityHubModules) {
      if (hidden.contains(key)) continue;
      final targetHub = _formazioniCustomHubLayoutKey(customHubs) ??
          _preferredAffinityHub(key, map);
      if (targetHub == null || targetHub.isEmpty) continue;
      for (final layoutKey in map.keys.toList()) {
        if (layoutKey == targetHub) continue;
        final keys = List<String>.from(map[layoutKey] ?? <String>[]);
        if (keys.remove(key)) map[layoutKey] = keys;
      }
      _addKeyToHubMapNearAffinitySiblings(map, targetHub, key);
    }
  }

  static void _placeNewModuleKey({
    required Map<String, List<String>> map,
    required String key,
    required Map<String, List<String>> defaultKeysByLayout,
    required Set<String> assigned,
    required Set<String> hidden,
  }) {
    if (assigned.contains(key) || hidden.contains(key)) return;
    final affinityHub = _layoutHubContainingAffinitySibling(key, map);
    final targetHub = affinityHub ??
        _defaultHubForModuleKey(key, defaultKeysByLayout) ??
        layoutLogisticaHub;
    _addKeyToHubMap(map, targetHub, key);
    assigned.add(key);
  }

  static void _ensureShippedHubModuleKeys(
    Map<String, List<String>> map, {
    required Set<String> hidden,
    required Map<String, List<String>> defaultKeysByLayout,
  }) {
    final assigned = <String>{
      for (final keys in map.values) ...keys,
    };
    for (final entry in _shippedHubModuleKeys.entries) {
      for (final moduleKey in entry.value) {
        _placeNewModuleKey(
          map: map,
          key: moduleKey,
          defaultKeysByLayout: defaultKeysByLayout,
          assigned: assigned,
          hidden: hidden,
        );
      }
    }
  }

  /// Mantiene l'ordine salvato e aggiunge in coda i moduli DT ancora assenti.
  static List<String> mergeHubOrderWithCatalog({
    required List<String> saved,
    required List<String> catalogKeys,
    Set<String> hidden = const <String>{},
  }) {
    final catalog = catalogKeys
        .where((key) => key.isNotEmpty && !hidden.contains(key))
        .toList(growable: false);
    if (catalog.isEmpty) return List<String>.from(saved);

    final out = <String>[];
    final seen = <String>{};
    for (final key in saved) {
      if (!catalog.contains(key) || !seen.add(key)) continue;
      out.add(key);
    }
    for (final key in catalog) {
      if (seen.add(key)) out.add(key);
    }
    return out;
  }

  static int? _cachedUserDbId;

  static Map<String, List<String>>? _cachedGlobalOrders;
  static Map<String, HubTileStyle>? _cachedTileStyles;
  static Map<String, HubTileStyle>? _cachedFuturisticTileStyles;

  static void invalidateLayoutCaches() {
    _cachedGlobalOrders = null;
    _cachedTileStyles = null;
    _cachedFuturisticTileStyles = null;
  }

  /// Una sola query Supabase per tutti gli ordini hub globali.
  static Future<Map<String, List<String>>> loadAllGlobalOrders({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedGlobalOrders != null) {
      return Map<String, List<String>>.from(_cachedGlobalOrders!);
    }
    try {
      final rows = await SupabaseService.client
          .from('app_ui_layout_order')
          .select('layout_key, item_keys') as List;
      final out = <String, List<String>>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final layoutKey = (row['layout_key'] ?? '').toString().trim();
        if (layoutKey.isEmpty) continue;
        final raw = row['item_keys'];
        if (raw is! List) continue;
        out[layoutKey] = raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      _cachedGlobalOrders = out;
      return Map<String, List<String>>.from(out);
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  static List<String>? _normalizeLoadedOrder(
    String layoutKey,
    List<String> loaded,
  ) {
    if (layoutKey == layoutHomeDt) return ensureDtHomeOrderKeys(loaded);
    if (layoutKey == layoutHomeDtFuturistic) {
      return ensureDtHomeOrderKeys(loaded);
    }
    if (layoutKey == layoutImpostazioniHub) {
      return ensureImpostazioniHubOrderKeys(loaded);
    }
    if (layoutKey == layoutCarburanteHub) {
      return ensureCarburanteHubOrderKeys(loaded);
    }
    if (layoutKey == layoutListePosHub) {
      return ensureListePosHubOrderKeys(loaded);
    }
    if (layoutKey == layoutUqsaHub) {
      return ensureUqsaHubOrderKeys(loaded);
    }
    return loaded;
  }

  static Future<int?> currentUserDbId({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedUserDbId != null) return _cachedUserDbId;
    final authId = SupabaseService.client.auth.currentUser?.id;
    if (authId == null) {
      _cachedUserDbId = null;
      return null;
    }
    try {
      final row = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      final id = row?['id'];
      _cachedUserDbId = id is int ? id : int.tryParse('$id');
    } catch (_) {
      _cachedUserDbId = null;
    }
    return _cachedUserDbId;
  }

  static Future<Set<String>> loadHiddenItemKeys({String? role}) async {
    final global =
        (await loadOrder(layoutHiddenItemKeys, role: null))?.toSet() ??
            <String>{};
    if (!usesPersonalLayoutPersistence(role ?? '')) return global;
    final userId = await currentUserDbId();
    if (userId == null) return global;
    final personal = await _loadUserOrder(userId, layoutHiddenItemKeys);
    if (personal == null) return global;
    return {...global, ...personal};
  }

  static Future<void> hideItemKey(
    String itemKey, {
    String? role,
  }) async {
    await ensureCanPersistOrThrow();
    if (usesPersonalLayoutPersistence(role ?? '')) {
      final userId = await currentUserDbId();
      if (userId == null) return;
      final hidden = await loadHiddenItemKeys(role: role);
      if (hidden.contains(itemKey)) return;
      hidden.add(itemKey);
      await _saveUserOrder(
        userId,
        layoutHiddenItemKeys,
        hidden.toList(growable: false),
      );
      await _deleteUserTileStyle(userId, itemKey);
      return;
    }
    final hidden = await loadHiddenItemKeys();
    if (hidden.contains(itemKey)) return;
    hidden.add(itemKey);
    await saveOrder(
      layoutKey: layoutHiddenItemKeys,
      itemKeys: hidden.toList(growable: false),
    );
    await deleteTileStyle(itemKey);
  }

  static Future<Map<String, HubTileStyle>> loadTileStyles({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedTileStyles != null) {
      return Map<String, HubTileStyle>.from(_cachedTileStyles!);
    }
    final rows = await SupabaseService.client
        .from('app_ui_tile_styles')
        .select(
          'item_key, custom_label, custom_subtitle, background_color, text_color, icon_color, size_scale, icon_codepoint, font_family, title_font_size, icon_font_size',
        ) as List;
    final out = <String, HubTileStyle>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final key = (row['item_key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      out[key] = HubTileStyle.fromJson(Map<String, dynamic>.from(row));
    }
    _cachedTileStyles = out;
    return Map<String, HubTileStyle>.from(out);
  }

  static Future<Map<String, HubTileStyle>> _loadGridPlacements(
    String layoutKey,
  ) async {
    try {
      final rows = await SupabaseService.client
          .from('app_ui_tile_grid_placement')
          .select(
            'item_key, grid_col, grid_row, grid_col_span, grid_row_span',
          )
          .eq('layout_key', layoutKey) as List;
      final out = <String, HubTileStyle>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final key = (row['item_key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        out[key] = HubTileStyle.fromGridPlacementJson(
          Map<String, dynamic>.from(row),
        );
      }
      return out;
    } catch (e) {
      if (isGridPlacementTableMissing(e)) {
        return <String, HubTileStyle>{};
      }
      rethrow;
    }
  }

  /// Se il reload da DB non restituisce posizioni griglia, conserva quelle appena salvate.
  static Map<String, HubTileStyle> mergeLoadedTileStylesWithPrior({
    required Map<String, HubTileStyle> loaded,
    required Map<String, HubTileStyle> prior,
  }) {
    final loadedGridKeys = loaded.entries
        .where((e) => e.value.hasGridPlacement)
        .length;
    final priorGridKeys = prior.entries
        .where((e) => e.value.hasGridPlacement)
        .length;
    if (priorGridKeys <= loadedGridKeys) return loaded;

    final out = Map<String, HubTileStyle>.from(loaded);
    for (final entry in prior.entries) {
      final p = entry.value;
      if (!p.hasGridPlacement) continue;
      final base = out[entry.key] ?? const HubTileStyle();
      if (base.hasGridPlacement) continue;
      out[entry.key] = base.copyWith(
        gridCol: p.gridCol,
        gridRow: p.gridRow,
        gridColSpan: p.gridColSpan,
        gridRowSpan: p.gridRowSpan,
        sizeScale: p.sizeScale,
      );
    }
    return out;
  }

  /// Aspetto globale + posizione griglia solo per [layoutKey].
  /// Home DT è sempre globale (niente override personali).
  static Future<Map<String, HubTileStyle>> loadTileStylesForLayout(
    String layoutKey, {
    String? role,
  }) async {
    final results = await Future.wait<Object>([
      loadTileStyles(),
      _loadGridPlacements(layoutKey),
    ]);
    final global = results[0] as Map<String, HubTileStyle>;
    final placements = results[1] as Map<String, HubTileStyle>;
    var out = Map<String, HubTileStyle>.from(global);
    for (final entry in placements.entries) {
      final base = out[entry.key] ?? const HubTileStyle();
      final p = entry.value;
      out[entry.key] = base.copyWith(
        gridCol: p.gridCol,
        gridRow: p.gridRow,
        gridColSpan: p.gridColSpan,
        gridRowSpan: p.gridRowSpan,
      );
    }
    if (isAdminManagedDtHomeLayout(layoutKey) ||
        !usesPersonalLayoutPersistence(role ?? '')) {
      return out;
    }
    final userId = await currentUserDbId();
    if (userId == null) return out;
    final personalStyles = await _loadUserTileStyles(userId);
    for (final entry in personalStyles.entries) {
      final base = out[entry.key] ?? const HubTileStyle();
      out[entry.key] = mergeStyleForPersist(base, entry.value);
    }
    final personalGrid = await _loadUserGridPlacements(userId, layoutKey);
    for (final entry in personalGrid.entries) {
      final base = out[entry.key] ?? const HubTileStyle();
      final p = entry.value;
      out[entry.key] = base.copyWith(
        gridCol: p.gridCol,
        gridRow: p.gridRow,
        gridColSpan: p.gridColSpan,
        gridRowSpan: p.gridRowSpan,
      );
    }
    return out;
  }

  /// Applica le modifiche del draft agli stili già caricati.
  static Map<String, HubTileStyle> applyStyleDraft({
    required Map<String, HubTileStyle> saved,
    required Map<String, HubTileStyle> draft,
    Set<String>? removedKeys,
  }) {
    final out = Map<String, HubTileStyle>.from(saved);
    for (final key in removedKeys ?? const <String>{}) {
      out.remove(key);
    }
    for (final entry in draft.entries) {
      if (entry.value.hasOverrides) {
        out[entry.key] = entry.value;
      } else {
        out.remove(entry.key);
      }
    }
    return out;
  }

  /// Stili da inviare a Supabase (upsert o delete per voce).
  static Map<String, HubTileStyle> stylesToPersist({
    required Map<String, HubTileStyle> draft,
    Set<String>? clearedKeys,
  }) {
    final out = Map<String, HubTileStyle>.from(draft);
    for (final key in clearedKeys ?? const <String>{}) {
      out[key] = const HubTileStyle();
    }
    return out;
  }

  /// Unisce stile esistente (DB) con aggiornamento (draft/editor).
  /// I campi null in [update] significano «rimuovi personalizzazione», non «mantieni DB».
  static HubTileStyle mergeStyleForPersist(
    HubTileStyle? existing,
    HubTileStyle update,
  ) {
    return HubTileStyle(
      customLabel: update.customLabel,
      customSubtitle: update.customSubtitle,
      backgroundColor: update.backgroundColor,
      textColor: update.textColor,
      iconColor: update.iconColor,
      iconCodepoint: update.iconCodepoint,
      fontFamilyKey: update.fontFamilyKey,
      titleFontSize: update.titleFontSize,
      iconFontSize: update.iconFontSize,
      sizeScale: update.sizeScale,
      gridCol: update.gridCol ?? existing?.gridCol,
      gridRow: update.gridRow ?? existing?.gridRow,
      gridColSpan: update.gridColSpan ?? existing?.gridColSpan,
      gridRowSpan: update.gridRowSpan ?? existing?.gridRowSpan,
    );
  }

  static Future<int> saveTileStyles(Map<String, HubTileStyle> styles) async {
    if (styles.isEmpty) return 0;
    await ensureCanPersistOrThrow();
    final existing = await loadTileStyles();
    final now = supabaseNowIsoUtc();
    final payloads = <Map<String, dynamic>>[];
    var deleted = 0;
    for (final entry in styles.entries) {
      final merged = mergeStyleForPersist(existing[entry.key], entry.value);
      if (merged.hasOverrides) {
        payloads.add(merged.toPersistRow(
          itemKey: entry.key,
          updatedAt: now,
        ));
      } else {
        await deleteTileStyle(entry.key);
        deleted++;
      }
    }
    if (payloads.isNotEmpty) {
      await SupabaseService.client.from('app_ui_tile_styles').upsert(
        payloads,
        onConflict: 'item_key',
        ignoreDuplicates: false,
      );
    }
    _cachedTileStyles = null;
    await refreshHubLabelsFromTileStyles(partialStyles: styles);
    return payloads.length + deleted;
  }

  static const String _futuristicTileStylesTable = 'app_ui_futuristic_tile_styles';

  static Future<Map<String, HubTileStyle>> loadFuturisticTileStyles({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedFuturisticTileStyles != null) {
      return Map<String, HubTileStyle>.from(_cachedFuturisticTileStyles!);
    }
    try {
      final rows = await SupabaseService.client
          .from(_futuristicTileStylesTable)
          .select(
            'item_key, custom_label, custom_subtitle, background_color, text_color, icon_color, size_scale, icon_codepoint, font_family, title_font_size, icon_font_size',
          ) as List;
      final out = <String, HubTileStyle>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final key = (row['item_key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        out[key] = HubTileStyle.fromJson(Map<String, dynamic>.from(row));
      }
      _cachedFuturisticTileStyles = out;
      return Map<String, HubTileStyle>.from(out);
    } catch (e) {
      if (_isFuturisticTileStylesTableMissing(e)) {
        _cachedFuturisticTileStyles = <String, HubTileStyle>{};
        return <String, HubTileStyle>{};
      }
      rethrow;
    }
  }

  static bool _isFuturisticTileStylesTableMissing(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('app_ui_futuristic_tile_styles') &&
        (msg.contains('does not exist') ||
            msg.contains('pgrst205') ||
            msg.contains('relation'));
  }

  /// Aspetto futurista + posizione griglia sulla pagina futuristica.
  static Future<Map<String, HubTileStyle>> loadTileStylesForFuturisticLayout(
    String layoutKey,
  ) async {
    final results = await Future.wait<Object>([
      loadFuturisticTileStyles(),
      _loadGridPlacements(layoutKey),
    ]);
    final global = results[0] as Map<String, HubTileStyle>;
    final placements = results[1] as Map<String, HubTileStyle>;
    final out = Map<String, HubTileStyle>.from(global);
    for (final entry in placements.entries) {
      final base = out[entry.key] ?? const HubTileStyle();
      final p = entry.value;
      out[entry.key] = base.copyWith(
        gridCol: p.gridCol,
        gridRow: p.gridRow,
        gridColSpan: p.gridColSpan,
        gridRowSpan: p.gridRowSpan,
      );
    }
    return out;
  }

  static Future<int> saveFuturisticTileStyles(
    Map<String, HubTileStyle> styles,
  ) async {
    if (styles.isEmpty) return 0;
    final existing = await loadFuturisticTileStyles();
    final now = supabaseNowIsoUtc();
    final payloads = <Map<String, dynamic>>[];
    var deleted = 0;
    for (final entry in styles.entries) {
      final merged = mergeStyleForPersist(existing[entry.key], entry.value);
      if (merged.hasOverrides) {
        payloads.add(merged.toPersistRow(
          itemKey: entry.key,
          updatedAt: now,
        ));
      } else {
        await deleteFuturisticTileStyle(entry.key);
        deleted++;
      }
    }
    if (payloads.isNotEmpty) {
      await SupabaseService.client.from(_futuristicTileStylesTable).upsert(
        payloads,
        onConflict: 'item_key',
        ignoreDuplicates: false,
      );
    }
    _cachedFuturisticTileStyles = null;
    return payloads.length + deleted;
  }

  static Future<void> deleteFuturisticTileStyle(String itemKey) async {
    try {
      await SupabaseService.client
          .from(_futuristicTileStylesTable)
          .delete()
          .eq('item_key', itemKey);
    } catch (e) {
      if (!_isFuturisticTileStylesTableMissing(e)) rethrow;
    }
    await deleteGridPlacement(layoutDashboardAdminFuturistic, itemKey);
  }

  static Future<void> saveTileStyleForFuturisticLayout({
    required String layoutKey,
    required String itemKey,
    required HubTileStyle style,
  }) async {
    final appearance = mergeStyleForPersist(
      (await loadFuturisticTileStyles())[itemKey],
      style.copyWith(clearPosition: true, clearGridSpan: true),
    );
    if (appearance.hasOverrides) {
      await saveFuturisticTileStyles(<String, HubTileStyle>{itemKey: appearance});
    } else if (!style.hasGridPlacement) {
      await deleteFuturisticTileStyle(itemKey);
      return;
    }
    if (style.hasGridPlacement) {
      await saveTileGridPlacements(
        layoutKey: layoutKey,
        placements: <String, HubTileStyle>{itemKey: style},
      );
    } else {
      await deleteGridPlacement(layoutKey, itemKey);
    }
  }

  static const List<String> _dashboardSharedWithFuturisticKeys = <String>[
    'mdo_mappa_gps',
    'carburante',
    'documenti_firma',
    'rubrica',
  ];

  /// Garantisce che i tile condivisi dashboard (es. Firma digitale) siano
  /// presenti anche sul layout GESTOPRO, anche se il salvataggio futuristico
  /// è già popolato ma incompleto.
  static void ensureFuturisticSharedDashboardKeys(
    HubLayoutOrders orders, {
    Map<String, List<String>>? defaultKeysByLayout,
    Set<String> hidden = const <String>{},
  }) {
    final classic = orders.keysFor(layoutDashboardAdmin);
    final fut = List<String>.from(
      orders.keysFor(layoutDashboardAdminFuturistic),
    );
    final catalog =
        defaultKeysByLayout?[layoutDashboardAdmin] ?? const <String>[];
    var changed = false;
    for (final key in _dashboardSharedWithFuturisticKeys) {
      if (hidden.contains(key)) continue;
      final shouldHave =
          classic.contains(key) || catalog.contains(key);
      if (shouldHave && !fut.contains(key)) {
        fut.add(key);
        changed = true;
      }
    }
    if (changed) {
      orders.setKeysFor(layoutDashboardAdminFuturistic, fut);
    }
  }

  static Future<void> ensureFuturisticDashboardOrderFallback({
    required HubLayoutOrders orders,
    Map<String, List<String>>? defaultKeysByLayout,
    String? role,
  }) async {
    final before = List<String>.from(
      orders.keysFor(layoutDashboardAdminFuturistic),
    );

    if (before.isEmpty) {
      final saved = await loadOrder(layoutDashboardAdminFuturistic);
      if (saved != null && saved.isNotEmpty) {
        orders.setKeysFor(layoutDashboardAdminFuturistic, saved);
      } else {
        final defaults =
            defaultKeysByLayout?[layoutDashboardAdminFuturistic] ??
            defaultKeysByLayout?[layoutDashboardAdmin];
        if (defaults != null && defaults.isNotEmpty) {
          orders.setKeysFor(
            layoutDashboardAdminFuturistic,
            List<String>.from(defaults),
          );
        }
      }
    }

    ensureFuturisticSharedDashboardKeys(
      orders,
      defaultKeysByLayout: defaultKeysByLayout,
    );

    final after = orders.keysFor(layoutDashboardAdminFuturistic);
    if (after.isEmpty) return;
    if (before.length == after.length &&
        List.generate(before.length, (i) => before[i] == after[i])
            .every((ok) => ok)) {
      return;
    }

    // Persiste così GESTOPRO non riparte da un layout futuristico incompleto.
    try {
      if (usesPersonalLayoutPersistence(role ?? '')) {
        final userId = await currentUserDbId();
        if (userId == null) return;
        await _saveUserOrder(
          userId,
          layoutDashboardAdminFuturistic,
          after,
        );
      } else {
        await saveOrder(
          layoutKey: layoutDashboardAdminFuturistic,
          itemKeys: after,
        );
      }
    } catch (_) {
      // Non bloccare la dashboard se il salvataggio fallisce.
    }
  }

  /// Layout hub collegato a un item_key (es. open_custom_xxx → custom_xxx).
  static String? hubLayoutKeyFromItemKey(String itemKey) {
    if (AppUiCustomHub.isLauncherKey(itemKey)) {
      return itemKey.substring('open_'.length);
    }
    if (AppUiCustomHub.isCustomLayoutKey(itemKey)) {
      return itemKey;
    }
    return null;
  }

  /// Aggiorna il nome della pagina hub custom in DB.
  static Future<void> updateCustomHubLabel({
    required String layoutKey,
    required String label,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    await SupabaseService.client
        .from('app_ui_custom_hubs')
        .update({'label': trimmed})
        .eq('layout_key', layoutKey);
  }

  /// Costruisce override etichette da stili tile e sincronizza hub custom su DB.
  static Map<String, String> labelOverridesFromTileStyles(
    Map<String, HubTileStyle> styles,
  ) {
    final overrides = <String, String>{};
    for (final entry in styles.entries) {
      final label = entry.value.customLabel?.trim();
      if (label == null || label.isEmpty) continue;
      overrides[entry.key] = label;
      final hubKey = hubLayoutKeyFromItemKey(entry.key);
      if (hubKey != null) overrides[hubKey] = label;
    }
    return overrides;
  }

  /// Allinea breadcrumb, barre spostamento e catalogo con i nomi personalizzati dei tile.
  static Future<void> refreshHubLabelsFromTileStyles({
    Map<String, HubTileStyle>? partialStyles,
  }) async {
    final map = await loadTileStyles();
    if (partialStyles != null) {
      for (final e in partialStyles.entries) {
        map[e.key] = e.value;
      }
    }
    final overrides = labelOverridesFromTileStyles(map);
    AppUiHubRegistry.bindLabelOverrides(overrides);

    final hubs = await loadCustomHubs();
    final hubsToSync = partialStyles == null
        ? hubs
        : hubs.where(
            (h) =>
                partialStyles.containsKey(h.layoutKey) ||
                partialStyles.containsKey(h.launcherKey),
          );
    for (final hub in hubsToSync) {
      final newLabel = overrides[hub.layoutKey] ?? overrides[hub.launcherKey];
      if (newLabel == null || newLabel == hub.label) continue;
      await updateCustomHubLabel(layoutKey: hub.layoutKey, label: newLabel);
    }
    AppUiHubRegistry.bindCustomHubs(await loadCustomHubs());
    AppUiHubRegistry.bindLabelOverrides(overrides);
  }

  /// Hub custom con etichette allineate ai [custom_label] dei tile launcher.
  static Future<List<AppUiCustomHub>> loadCustomHubsWithSyncedLabels() async {
    await refreshHubLabelsFromTileStyles();
    return loadCustomHubs();
  }

  static Future<void> deleteTileStyle(String itemKey) async {
    await SupabaseService.client
        .from('app_ui_tile_styles')
        .delete()
        .eq('item_key', itemKey);
    await deleteGridPlacementsForItem(itemKey);
  }

  static Future<void> deleteGridPlacement(
    String layoutKey,
    String itemKey,
  ) async {
    try {
      await SupabaseService.client
          .from('app_ui_tile_grid_placement')
          .delete()
          .eq('layout_key', layoutKey)
          .eq('item_key', itemKey);
    } catch (_) {}
  }

  static Future<void> deleteGridPlacementsForItem(String itemKey) async {
    try {
      await SupabaseService.client
          .from('app_ui_tile_grid_placement')
          .delete()
          .eq('item_key', itemKey);
    } catch (_) {}
  }

  /// Elimina tutte le posizioni griglia salvate per un hub.
  static Future<void> deleteAllGridPlacements(String layoutKey) async {
    try {
      await SupabaseService.client
          .from('app_ui_tile_grid_placement')
          .delete()
          .eq('layout_key', layoutKey);
    } catch (_) {}
  }

  /// Ripristina ordine catalogo, toglie posizioni trascinate e
  /// riporta le voci [catalogKeys] su questo hub se erano finite altrove.
  static Future<void> resetHubOrderToCatalog({
    required String layoutKey,
    required List<String> catalogKeys,
    List<String> extraKeysToKeep = const <String>[],
    bool reclaimFromOtherLayouts = false,
  }) async {
    final catalogSet = catalogKeys.toSet();
    if (reclaimFromOtherLayouts) {
      final all = await loadAllGlobalOrders();
      for (final entry in all.entries) {
        if (entry.key == layoutKey) continue;
        final filtered =
            entry.value.where((k) => !catalogSet.contains(k)).toList();
        if (filtered.length != entry.value.length) {
          await saveOrder(layoutKey: entry.key, itemKeys: filtered);
        }
      }
    }
    final keys = <String>[
      ...catalogKeys,
      ...extraKeysToKeep.where((k) => !catalogSet.contains(k)),
    ];
    await saveOrder(layoutKey: layoutKey, itemKeys: keys);
    await deleteAllGridPlacements(layoutKey);
  }
  static Map<String, HubTileStyle> gridPlacementsResolved({
    required List<String> keysInOrder,
    required Map<String, HubTileStyle> styles,
  }) {
    final placements = HubTileGridLayout.resolve(
      keysInOrder: keysInOrder,
      styles: styles,
      scaleForKey: (key) => styles[key]?.sizeScale ?? 1.0,
    );
    final out = <String, HubTileStyle>{};
    for (final entry in placements.entries) {
      final style = styles[entry.key];
      final rect = entry.value;
      out[entry.key] = HubTileStyle(
        gridCol: rect.col,
        gridRow: rect.row,
        gridColSpan: rect.colSpan,
        gridRowSpan: rect.rowSpan,
        sizeScale: style?.sizeScale ?? 1.0,
      );
    }
    return out;
  }

  /// Copia gli stili tile e aggiunge le posizioni griglia risolte (anteprima freeform).
  static Map<String, HubTileStyle> seedStyleDraftForReorder({
    required List<String> keysInOrder,
    required Map<String, HubTileStyle> tileStyles,
  }) {
    final seeded = Map<String, HubTileStyle>.from(tileStyles);
    final resolved = gridPlacementsResolved(
      keysInOrder: keysInOrder,
      styles: tileStyles,
    );
    for (final entry in resolved.entries) {
      final base = seeded[entry.key] ?? const HubTileStyle();
      seeded[entry.key] = base.copyWith(
        gridCol: entry.value.gridCol,
        gridRow: entry.value.gridRow,
        gridColSpan: entry.value.gridColSpan,
        gridRowSpan: entry.value.gridRowSpan,
      );
    }
    return seeded;
  }

  /// Unisce posizioni auto-calcolate con override espliciti dal draft.
  static Map<String, HubTileStyle> mergeGridPlacementsForPersist({
    required List<String> keysInOrder,
    required Map<String, HubTileStyle> styles,
    required Map<String, HubTileStyle> fromDraft,
    Set<String>? clearedKeys,
  }) {
    final out = gridPlacementsResolved(
      keysInOrder: keysInOrder,
      styles: styles,
    );
    for (final entry in fromDraft.entries) {
      if (entry.value.hasGridPlacement) {
        out[entry.key] = entry.value;
      }
    }
    for (final key in clearedKeys ?? const <String>{}) {
      out.remove(key);
    }
    return out;
  }

  static Map<String, HubTileStyle> gridPlacementsFromDraft({
    required Map<String, HubTileStyle> draft,
    Set<String>? clearedKeys,
  }) {
    final out = <String, HubTileStyle>{};
    for (final entry in draft.entries) {
      if (entry.value.hasGridPlacement) {
        out[entry.key] = HubTileStyle(
          gridCol: entry.value.gridCol,
          gridRow: entry.value.gridRow,
          gridColSpan: entry.value.gridColSpan,
          gridRowSpan: entry.value.gridRowSpan,
          sizeScale: entry.value.sizeScale,
        );
      }
    }
    for (final key in clearedKeys ?? const <String>{}) {
      out.putIfAbsent(key, () => const HubTileStyle());
    }
    return out;
  }

  static bool isGridPlacementTableMissing(Object error) {
    final msg = error.toString();
    return (msg.contains('app_ui_tile_grid_placement') ||
            msg.contains('app_ui_user_tile_grid_placement')) &&
        (msg.contains('PGRST205') ||
            msg.contains('Could not find') ||
            msg.contains('Not Found'));
  }

  static bool isUserLayoutTableMissing(Object error) {
    final msg = error.toString();
    return msg.contains('app_ui_user_') &&
        (msg.contains('PGRST205') ||
            msg.contains('Could not find') ||
            msg.contains('42501') ||
            msg.contains('Not Found'));
  }

  /// Messaggio utente per errori salvataggio layout/stili.
  static String formatPersistError(Object error) {
    if (isUserLayoutTableMissing(error)) {
      return 'Mancano le tabelle layout personale su Supabase.\n'
          'Esegui supabase/migrations/20260531120000_app_ui_user_layout_overrides.sql '
          '(oppure supabase db push), poi «Reload schema» in API Settings.';
    }
    if (isGridPlacementTableMissing(error)) {
      return 'Manca la tabella posizioni griglia su Supabase.\n'
          'Apri SQL Editor ed esegui il file '
          'supabase/migrations/20260529120000_app_ui_tile_grid_per_layout.sql\n'
          '(oppure supabase db push). Poi in Dashboard → Settings → API '
          'clicca «Reload schema» se il salvataggio fallisce ancora.';
    }
    return error.toString();
  }

  static Future<void> saveTileGridPlacements({
    required String layoutKey,
    required Map<String, HubTileStyle> placements,
  }) async {
    await SupabaseService.client
        .from('app_ui_tile_grid_placement')
        .delete()
        .eq('layout_key', layoutKey);

    final now = supabaseNowIsoUtc();
    final payloads = <Map<String, dynamic>>[];
    for (final entry in placements.entries) {
      if (entry.value.hasGridPlacement) {
        payloads.add(
          entry.value.toGridPlacementDbRow(
            layoutKey: layoutKey,
            itemKey: entry.key,
            updatedAt: now,
          ),
        );
      }
    }
    if (payloads.isEmpty) return;
    await SupabaseService.client.from('app_ui_tile_grid_placement').insert(
      payloads,
    );
  }

  static Future<void> saveTileStyleForLayout({
    required String layoutKey,
    required String itemKey,
    required HubTileStyle style,
  }) async {
    final appearance = mergeStyleForPersist(
      (await loadTileStyles())[itemKey],
      style.copyWith(clearPosition: true, clearGridSpan: true),
    );
    if (appearance.hasOverrides) {
      await saveTileStyles(<String, HubTileStyle>{itemKey: appearance});
    } else if (!style.hasGridPlacement) {
      await deleteTileStyle(itemKey);
      await refreshHubLabelsFromTileStyles(
        partialStyles: <String, HubTileStyle>{itemKey: const HubTileStyle()},
      );
      return;
    }
    if (style.hasGridPlacement) {
      await saveTileGridPlacements(
        layoutKey: layoutKey,
        placements: <String, HubTileStyle>{itemKey: style},
      );
    } else {
      await deleteGridPlacement(layoutKey, itemKey);
    }
  }

  static Future<void> removeTileStylesForKeys(Iterable<String> itemKeys) async {
    for (final key in itemKeys) {
      await deleteTileStyle(key);
    }
  }

  static Future<void> deleteCustomHub(String layoutKey) async {
    final hub = await loadCustomHub(layoutKey);
    final launcher = 'open_$layoutKey';
    final slotKeys = hub?.slots.map((s) => s.key).toList() ?? <String>[];

    await SupabaseService.client
        .from('app_ui_custom_hubs')
        .delete()
        .eq('layout_key', layoutKey);

    try {
      await SupabaseService.client
          .from('app_ui_layout_order')
          .delete()
          .eq('layout_key', layoutKey);
    } catch (_) {}

    final layouts = <String>{
      ...AppUiHubRegistry.all.map((h) => h.layoutKey),
      layoutKey,
      layoutDashboardAdmin,
    };
    for (final lk in layouts) {
      final saved = await loadOrder(lk);
      if (saved == null) continue;
      final filtered = saved
          .where(
            (k) =>
                k != launcher &&
                k != layoutKey &&
                !slotKeys.contains(k),
          )
          .toList(growable: false);
      if (filtered.length != saved.length) {
        await saveOrder(layoutKey: lk, itemKeys: filtered);
      }
    }

    await hideItemKey(launcher);
    for (final sk in slotKeys) {
      await hideItemKey(sk);
    }
  }

  static Future<void> deleteCustomHubSlot(String slotKey) async {
    final sep = '__slot_';
    if (!slotKey.contains(sep)) return;
    final parent = slotKey.split(sep).first;
    if (parent.isEmpty) return;

    final hub = await loadCustomHub(parent);
    if (hub != null) {
      final slots =
          hub.slots.where((s) => s.key != slotKey).toList(growable: false);
      await updateCustomHubSlotLabels(layoutKey: parent, slots: slots);
    }

    final saved = await loadOrder(parent);
    if (saved != null) {
      await saveOrder(
        layoutKey: parent,
        itemKeys: saved.where((k) => k != slotKey).toList(growable: false),
      );
    }

    await hideItemKey(slotKey);
  }

  /// Rimuove tutte le occorrenze di [itemKey] da un solo hub.
  static HubLayoutOrders removeAllFromLayout(
    HubLayoutOrders orders,
    String layoutKey,
    String itemKey,
  ) {
    final copy = <String, List<String>>{};
    for (final lk in orders.allLayoutKeys) {
      copy[lk] = List<String>.from(orders.keysFor(lk));
    }
    copy[layoutKey] = copy[layoutKey]
            ?.where((k) => k != itemKey)
            .toList(growable: false) ??
        <String>[];
    return HubLayoutOrders(copy);
  }

  static bool itemExistsOnOtherLayouts(
    HubLayoutOrders orders,
    String currentLayoutKey,
    String itemKey,
  ) {
    for (final layoutKey in orders.allLayoutKeys) {
      if (layoutKey == currentLayoutKey) continue;
      if (orders.keysFor(layoutKey).contains(itemKey)) return true;
    }
    return false;
  }

  static HubLayoutOrders removeItemEverywhere(
    HubLayoutOrders orders,
    String itemKey,
  ) {
    final copy = <String, List<String>>{};
    for (final layoutKey in orders.allLayoutKeys) {
      copy[layoutKey] = List<String>.from(orders.keysFor(layoutKey))
        ..removeWhere((k) => k == itemKey);
    }
    return HubLayoutOrders(copy);
  }

  /// Rimuove una sola occorrenza dalla pagina indicata.
  static HubLayoutOrders removeOneFromLayout(
    HubLayoutOrders orders,
    String layoutKey,
    String itemKey,
  ) {
    final keys = List<String>.from(orders.keysFor(layoutKey));
    final idx = keys.indexOf(itemKey);
    if (idx >= 0) keys.removeAt(idx);
    final copy = <String, List<String>>{};
    for (final lk in orders.allLayoutKeys) {
      copy[lk] = List<String>.from(orders.keysFor(lk));
    }
    copy[layoutKey] = keys;
    return HubLayoutOrders(copy);
  }

  static Future<List<String>?> loadOrder(
    String layoutKey, {
    String? role,
  }) async {
    List<String>? loaded;
    if (!isAdminManagedDtHomeLayout(layoutKey) &&
        usesPersonalLayoutPersistence(role ?? '')) {
      final userId = await currentUserDbId();
      if (userId != null) {
        loaded = await _loadUserOrder(userId, layoutKey);
      }
    }
    loaded ??= await _loadGlobalOrder(layoutKey);
    if (layoutKey == layoutHomeDt && loaded != null) {
      return ensureDtHomeOrderKeys(loaded);
    }
    if (layoutKey == layoutImpostazioniHub && loaded != null) {
      return ensureImpostazioniHubOrderKeys(loaded);
    }
    if (layoutKey == layoutCarburanteHub) {
      return ensureCarburanteHubOrderKeys(loaded ?? <String>[]);
    }
    return loaded;
  }

  static Future<List<String>?> _loadGlobalOrder(String layoutKey) async {
    try {
      final row = await SupabaseService.client
          .from('app_ui_layout_order')
          .select('item_keys')
          .eq('layout_key', layoutKey)
          .maybeSingle();
      if (row == null) return null;
      final raw = row['item_keys'];
      if (raw is! List) return null;
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> _loadUserOrder(
    int userId,
    String layoutKey,
  ) async {
    try {
      final row = await SupabaseService.client
          .from('app_ui_user_layout_order')
          .select('item_keys')
          .eq('user_id', userId)
          .eq('layout_key', layoutKey)
          .maybeSingle();
      if (row == null) return null;
      final raw = row['item_keys'];
      if (raw is! List) return null;
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveUserOrder(
    int userId,
    String layoutKey,
    List<String> itemKeys,
  ) async {
    await SupabaseService.client.from('app_ui_user_layout_order').upsert(
      <String, dynamic>{
        'user_id': userId,
        'layout_key': layoutKey,
        'item_keys': itemKeys,
        'updated_at': supabaseNowIsoUtc(),
      },
      onConflict: 'user_id,layout_key',
    );
  }

  static Future<Map<String, HubTileStyle>> _loadUserTileStyles(
    int userId,
  ) async {
    try {
      final rows = await SupabaseService.client
          .from('app_ui_user_tile_style')
          .select(
            'item_key, custom_label, custom_subtitle, background_color, text_color, icon_color, size_scale, icon_codepoint, font_family, title_font_size, icon_font_size',
          )
          .eq('user_id', userId) as List;
      final out = <String, HubTileStyle>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final key = (row['item_key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        out[key] = HubTileStyle.fromJson(Map<String, dynamic>.from(row));
      }
      return out;
    } catch (_) {
      return <String, HubTileStyle>{};
    }
  }

  static Future<Map<String, HubTileStyle>> _loadUserGridPlacements(
    int userId,
    String layoutKey,
  ) async {
    try {
      final rows = await SupabaseService.client
          .from('app_ui_user_tile_grid_placement')
          .select(
            'item_key, grid_col, grid_row, grid_col_span, grid_row_span',
          )
          .eq('user_id', userId)
          .eq('layout_key', layoutKey) as List;
      final out = <String, HubTileStyle>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final key = (row['item_key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        out[key] = HubTileStyle.fromGridPlacementJson(
          Map<String, dynamic>.from(row),
        );
      }
      return out;
    } catch (_) {
      return <String, HubTileStyle>{};
    }
  }

  static Future<void> saveOrder({
    required String layoutKey,
    required List<String> itemKeys,
  }) async {
    await ensureCanPersistOrThrow();
    final saved = await SupabaseService.client
        .from('app_ui_layout_order')
        .upsert(
          <String, dynamic>{
            'layout_key': layoutKey,
            'item_keys': itemKeys,
            'updated_at': supabaseNowIsoUtc(),
          },
          onConflict: 'layout_key',
        )
        .select('layout_key')
        .maybeSingle();
    if (saved == null) {
      throw StateError(
        'Salvataggio layout non consentito o non applicato '
        '(verifica ruolo admin / RLS).',
      );
    }
    invalidateLayoutCaches();
  }

  /// Salva layout Home/hub solo per l'utente corrente (DT / Assistente DT).
  static Future<void> savePersonalHomeLayout({
    required String layoutKey,
    required List<String> itemKeys,
    required Map<String, HubTileStyle> styles,
    required Map<String, HubTileStyle> gridPlacements,
    required HubLayoutOrders hubOrders,
    Set<String> hiddenKeysToAdd = const {},
  }) async {
    await ensureCanPersistOrThrow();
    final userId = await currentUserDbId(forceRefresh: true);
    if (userId == null) {
      throw StateError('Utente non autenticato');
    }
    for (final layout in hubOrders.allLayoutKeys) {
      await _saveUserOrder(
        userId,
        layout,
        hubOrders.keysFor(layout),
      );
    }
    await _saveUserOrder(userId, layoutKey, itemKeys);
    await _saveUserTileStyles(userId, styles);
    await _saveUserGridPlacements(userId, layoutKey, gridPlacements);
    if (hiddenKeysToAdd.isNotEmpty) {
      final hidden = await loadHiddenItemKeys(role: 'dt');
      hidden.addAll(hiddenKeysToAdd);
      await _saveUserOrder(
        userId,
        layoutHiddenItemKeys,
        hidden.toList(growable: false),
      );
    }
  }

  static Future<void> _saveUserTileStyles(
    int userId,
    Map<String, HubTileStyle> styles,
  ) async {
    if (styles.isEmpty) return;
    final existing = await _loadUserTileStyles(userId);
    final now = supabaseNowIsoUtc();
    final payloads = <Map<String, dynamic>>[];
    for (final entry in styles.entries) {
      final appearance = entry.value.copyWith(
        clearPosition: true,
        clearGridSpan: true,
      );
      final merged = mergeStyleForPersist(existing[entry.key], appearance);
      if (merged.hasOverrides) {
        payloads.add({
          'user_id': userId,
          ...merged.toPersistRow(itemKey: entry.key, updatedAt: now),
        });
      } else {
        await _deleteUserTileStyle(userId, entry.key);
      }
    }
    if (payloads.isNotEmpty) {
      await SupabaseService.client.from('app_ui_user_tile_style').upsert(
        payloads,
        onConflict: 'user_id,item_key',
      );
    }
  }

  static Future<void> _deleteUserTileStyle(int userId, String itemKey) async {
    try {
      await SupabaseService.client
          .from('app_ui_user_tile_style')
          .delete()
          .eq('user_id', userId)
          .eq('item_key', itemKey);
    } catch (_) {}
  }

  static Future<void> _saveUserGridPlacements(
    int userId,
    String layoutKey,
    Map<String, HubTileStyle> placements,
  ) async {
    if (placements.isEmpty) return;
    final now = supabaseNowIsoUtc();
    final payloads = <Map<String, dynamic>>[];
    for (final entry in placements.entries) {
      if (entry.value.hasGridPlacement) {
        payloads.add({
          'user_id': userId,
          ...entry.value.toGridPlacementDbRow(
            layoutKey: layoutKey,
            itemKey: entry.key,
            updatedAt: now,
          ),
        });
      } else {
        try {
          await SupabaseService.client
              .from('app_ui_user_tile_grid_placement')
              .delete()
              .eq('user_id', userId)
              .eq('layout_key', layoutKey)
              .eq('item_key', entry.key);
        } catch (_) {}
      }
    }
    if (payloads.isNotEmpty) {
      await SupabaseService.client
          .from('app_ui_user_tile_grid_placement')
          .upsert(
        payloads,
        onConflict: 'user_id,layout_key,item_key',
      );
    }
  }

  static Future<List<dynamic>> _fetchAllCustomHubRows() async {
    try {
      return await SupabaseService.client
          .from('app_ui_custom_hubs')
          .select(
            'layout_key, label, structure_type, slot_labels, page_config',
          )
          .order('label', ascending: true) as List;
    } catch (_) {
      return await SupabaseService.client
          .from('app_ui_custom_hubs')
          .select('layout_key, label')
          .order('label', ascending: true) as List;
    }
  }

  static Future<Map<String, dynamic>?> _fetchCustomHubRow(String layoutKey) async {
    try {
      final row = await SupabaseService.client
          .from('app_ui_custom_hubs')
          .select(
            'layout_key, label, structure_type, slot_labels, page_config',
          )
          .eq('layout_key', layoutKey)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      final row = await SupabaseService.client
          .from('app_ui_custom_hubs')
          .select('layout_key, label')
          .eq('layout_key', layoutKey)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    }
  }

  static Future<List<AppUiCustomHub>> loadCustomHubs() async {
    try {
      final rows = await _fetchAllCustomHubRows();
      return rows
          .map((r) => _customHubFromRow(Map<String, dynamic>.from(r as Map)))
          .where((h) => h.layoutKey.isNotEmpty && h.label.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <AppUiCustomHub>[];
    }
  }

  static Future<AppUiCustomHub?> loadCustomHub(String layoutKey) async {
    try {
      final row = await _fetchCustomHubRow(layoutKey);
      if (row == null) return null;
      return _customHubFromRow(row);
    } catch (_) {
      return null;
    }
  }

  static CustomHubPageConfig? _pageConfigFromRow(
    Map<String, dynamic> row,
    CustomHubStructureType structureType,
  ) {
    final raw = row['page_config'];
    if (raw is Map) {
      return CustomHubPageConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    if (structureType == CustomHubStructureType.prenotazioni) {
      return CustomHubPageConfig.defaultPrenotazioni();
    }
    return null;
  }

  static AppUiCustomHub _customHubFromRow(Map<String, dynamic> row) {
    final layoutKey = (row['layout_key'] ?? '').toString();
    final label = (row['label'] ?? '').toString();
    final structureType = CustomHubStructureType.fromStorage(
          row['structure_type']?.toString(),
        ) ??
        CustomHubStructureType.home;
    final pageConfig = _pageConfigFromRow(row, structureType);
    final rawSlots = row['slot_labels'];
    var slots = <CustomHubSlot>[];
    if (rawSlots is List) {
      slots = rawSlots
          .whereType<Map>()
          .map((e) => CustomHubSlot.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.key.isNotEmpty && s.label.trim().isNotEmpty)
          .toList(growable: false);
    }
    if (slots.isEmpty &&
        layoutKey.isNotEmpty &&
        structureType != CustomHubStructureType.prenotazioni &&
        rawSlots == null) {
      slots = CustomHubStructureTemplates.buildSlots(
        layoutKey: layoutKey,
        type: structureType,
      );
    }
    return AppUiCustomHub(
      layoutKey: layoutKey,
      label: label,
      structureType: structureType,
      slots: slots,
      pageConfig: pageConfig,
    );
  }

  static Future<AppUiCustomHub> createCustomHub({
    required String label,
    required CustomHubStructureType structureType,
    required List<CustomHubSlot> slots,
    String? alsoShowOnLayoutKey,
    CustomHubPageConfig? pageConfig,
    bool onlyOnOriginLayout = false,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Il nome non può essere vuoto.');
    }
    final isPrenotazioni =
        structureType == CustomHubStructureType.prenotazioni;
    final slug = _slugifyLabel(trimmed);
    final layoutKey =
        'custom_${slug}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final resolvedSlots = slots
        .asMap()
        .entries
        .map(
          (e) => CustomHubSlot(
            key: '${layoutKey}__slot_${e.key}',
            label: e.value.label.trim(),
          ),
        )
        .where((s) => s.label.isNotEmpty)
        .toList(growable: false);
    final resolvedPageConfig = isPrenotazioni
        ? (pageConfig ?? CustomHubPageConfig.defaultPrenotazioni())
        : pageConfig;
    await _insertCustomHubRecord(
      layoutKey: layoutKey,
      label: trimmed,
      structureType: structureType,
      slotLabelsJson: resolvedSlots.map((s) => s.toJson()).toList(),
      pageConfig: resolvedPageConfig,
    );
    await saveOrder(
      layoutKey: layoutKey,
      itemKeys: isPrenotazioni
          ? <String>[]
          : resolvedSlots.map((s) => s.key).toList(growable: false),
    );
    final hub = AppUiCustomHub(
      layoutKey: layoutKey,
      label: trimmed,
      structureType: structureType,
      slots: resolvedSlots,
      pageConfig: resolvedPageConfig,
    );
    final origin = (alsoShowOnLayoutKey ?? '').trim();
    if (onlyOnOriginLayout) {
      await _ensureLauncherOnLayout(
        origin.isNotEmpty ? origin : layoutDashboardAdmin,
        hub.launcherKey,
      );
    } else {
      await _ensureLauncherOnLayout(layoutDashboardAdmin, hub.launcherKey);
      if (origin.isNotEmpty && origin != layoutDashboardAdmin) {
        await _ensureLauncherOnLayout(origin, hub.launcherKey);
      }
    }
    AppUiHubRegistry.bindCustomHubs(await loadCustomHubs());
    return hub;
  }

  static Future<void> _insertCustomHubRecord({
    required String layoutKey,
    required String label,
    required CustomHubStructureType structureType,
    required List<Map<String, dynamic>> slotLabelsJson,
    CustomHubPageConfig? pageConfig,
  }) async {
    final base = <String, dynamic>{
      'layout_key': layoutKey,
      'label': label,
      'updated_at': supabaseNowIsoUtc(),
    };
    final withStructure = <String, dynamic>{
      ...base,
      'structure_type': structureType.storageKey,
      'slot_labels': slotLabelsJson,
    };
    final withConfig = <String, dynamic>{
      ...withStructure,
      if (pageConfig != null) 'page_config': pageConfig.toJson(),
    };

    Object? lastError;
    for (final payload in <Map<String, dynamic>>[withConfig, withStructure, base]) {
      try {
        await SupabaseService.client.from('app_ui_custom_hubs').insert(payload);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Impossibile salvare la pagina custom. Applica su Supabase le migration '
      'app_ui_custom_hubs (structure_type, slot_labels, page_config). '
      'Dettaglio: $lastError',
    );
  }

  /// Corregge pagine create senza migration (salvate come Home a 8 pulsanti).
  static Future<AppUiCustomHub> convertCustomHubToPrenotazioni(
    String layoutKey,
  ) async {
    final config = CustomHubPageConfig.defaultPrenotazioni();
    await SupabaseService.client.from('app_ui_custom_hubs').update(
      <String, dynamic>{
        'structure_type': CustomHubStructureType.prenotazioni.storageKey,
        'slot_labels': <dynamic>[],
        'page_config': config.toJson(),
        'updated_at': supabaseNowIsoUtc(),
      },
    ).eq('layout_key', layoutKey);
    await saveOrder(layoutKey: layoutKey, itemKeys: <String>[]);
    final hub = await loadCustomHub(layoutKey);
    if (hub == null) {
      throw Exception('Pagina $layoutKey non trovata dopo conversione.');
    }
    return hub;
  }

  static Future<void> updateCustomHubPageConfig({
    required String layoutKey,
    required CustomHubPageConfig pageConfig,
  }) async {
    await SupabaseService.client.from('app_ui_custom_hubs').update(
      <String, dynamic>{
        'page_config': pageConfig.toJson(),
        'updated_at': supabaseNowIsoUtc(),
      },
    ).eq('layout_key', layoutKey);
  }

  static Future<void> updateCustomHubSlotLabels({
    required String layoutKey,
    required List<CustomHubSlot> slots,
  }) async {
    await SupabaseService.client.from('app_ui_custom_hubs').update(
      <String, dynamic>{
        'slot_labels': slots.map((s) => s.toJson()).toList(),
        'updated_at': supabaseNowIsoUtc(),
      },
    ).eq('layout_key', layoutKey);
  }

  static String _slugifyLabel(String label) {
    final slug = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? 'pagina' : slug;
  }

  static Future<void> _ensureLauncherOnLayout(
    String layoutKey,
    String launcherKey,
  ) async {
    final saved = await loadOrder(layoutKey);
    final keys = List<String>.from(saved ?? <String>[]);
    if (keys.contains(launcherKey)) return;
    keys.add(launcherKey);
    await saveOrder(layoutKey: layoutKey, itemKeys: keys);
  }

  /// Tile «apri pagina» su Dashboard se mancanti (es. create da UQSA).
  /// Solo in memoria: non salvare su DB durante il load (evita di ripristinare
  /// launcher rimossi dall'utente).
  static void _applyCustomHubLaunchersInMemory(
    Map<String, List<String>> map,
    List<AppUiCustomHub> customHubs, {
    Set<String> hidden = const <String>{},
  }) {
    final assigned = <String>{};
    for (final keys in map.values) {
      assigned.addAll(keys);
    }
    var dash = List<String>.from(map[layoutDashboardAdmin] ?? <String>[]);
    for (final hub in customHubs) {
      final launcher = hub.launcherKey;
      if (assigned.contains(launcher) || hidden.contains(launcher)) continue;
      dash.add(launcher);
      assigned.add(launcher);
    }
    map[layoutDashboardAdmin] = dash;
  }

  /// Aggiunge slot mancanti solo se la pagina ha già pulsanti (non ripopola vuote).
  static void _syncCustomHubSlotKeys(
    Map<String, List<String>> map,
    List<AppUiCustomHub> customHubs, {
    Set<String> hidden = const <String>{},
  }) {
    final assigned = <String>{};
    for (final keys in map.values) {
      assigned.addAll(keys);
    }
    for (final hub in customHubs) {
      if (hub.isPrenotazioniLayout) continue;
      final slotKeys = hub.slots
          .map((s) => s.key)
          .where((k) => !hidden.contains(k))
          .toList(growable: false);
      if (slotKeys.isEmpty) continue;
      final current = List<String>.from(map[hub.layoutKey] ?? <String>[]);
      if (current.isEmpty) continue;
      for (final key in slotKeys) {
        if (assigned.contains(key) || hidden.contains(key)) continue;
        current.add(key);
        assigned.add(key);
      }
      map[hub.layoutKey] = current;
    }
  }

  /// Rimuove chiavi slot orfane o slot su pagine senza sezioni definite.
  static List<String> _pruneCustomHubLayoutKeys({
    required List<String> keys,
    required AppUiCustomHub hub,
  }) {
    if (hub.isPrenotazioniLayout) return keys;
    final validSlotKeys = hub.slots.map((s) => s.key).toSet();
    return keys.where((key) {
      if (!AppUiCustomHub.isCustomSlotKey(key)) return true;
      if (hub.slots.isEmpty) return false;
      return validSlotKeys.contains(key);
    }).toList();
  }

  static Future<void> saveHubOrders(
    HubLayoutOrders orders, {
    List<AppUiCustomHub>? customHubs,
  }) async {
    await ensureCanPersistOrThrow();
    final custom = customHubs ?? await loadCustomHubs();
    final hubByLayout = {for (final h in custom) h.layoutKey: h};
    for (final layoutKey in orders.allLayoutKeys) {
      var keys = List<String>.from(orders.keysFor(layoutKey));
      final hub = hubByLayout[layoutKey];
      if (hub != null) {
        keys = _pruneCustomHubLayoutKeys(keys: keys, hub: hub);
      }
      await saveOrder(layoutKey: layoutKey, itemKeys: keys);
    }
  }

  static Future<HubLayoutOrders> loadHubOrders({
    required Map<String, List<String>> defaultKeysByLayout,
    List<AppUiCustomHub>? customHubs,
    String? role,
    bool skipLabelSync = false,
  }) async {
    final custom = customHubs ?? await loadCustomHubs();
    AppUiHubRegistry.bindCustomHubs(custom);
    if (!skipLabelSync) {
      try {
        await refreshHubLabelsFromTileStyles();
      } catch (_) {
        // Non bloccare il caricamento layout se gli stili tile non sono disponibili.
      }
    }
    final hidden = await loadHiddenItemKeys(role: role);
    final personal = usesPersonalLayoutPersistence(role ?? '');

    final map = <String, List<String>>{};
    final allSavedKeysEver = <String>{};
    final hubs = AppUiHubRegistry.all;

    Map<String, List<String>> globalOrders = const {};
    Map<String, List<String>> personalOrders = const {};
    if (personal) {
      final loaded = await Future.wait<List<String>?>(
        hubs.map((hub) => loadOrder(hub.layoutKey, role: role)),
      );
      var orderMap = <String, List<String>>{
        for (var i = 0; i < hubs.length; i++)
          hubs[i].layoutKey: loaded[i] ?? <String>[],
      };
      final legacyPersonal = await loadOrder(
        _legacyCarburanteHubLayoutKey,
        role: role,
      );
      if (legacyPersonal != null && legacyPersonal.isNotEmpty) {
        orderMap[_legacyCarburanteHubLayoutKey] = legacyPersonal;
      }
      orderMap = _migrateLegacyCarburanteHubLayout(orderMap);
      personalOrders = orderMap;
    } else {
      globalOrders = _migrateLegacyCarburanteHubLayout(
        await loadAllGlobalOrders(),
      );
    }

    for (final hub in hubs) {
      final defaults = defaultKeysByLayout[hub.layoutKey] ?? <String>[];
      List<String>? saved;
      if (personal) {
        saved = personalOrders[hub.layoutKey];
      } else {
        final raw = globalOrders[hub.layoutKey];
        if (raw != null) {
          saved = _normalizeLoadedOrder(hub.layoutKey, List<String>.from(raw));
        }
      }
      if (saved == null) {
        final seed = defaults.isNotEmpty
            ? defaults
            : (hub.layoutKey == layoutCarburanteHub
                ? _carburanteHubDefaultKeys
                : (hub.layoutKey == layoutListePosHub
                    ? _posListeHubDefaultKeys
                    : defaults));
        map[hub.layoutKey] = List<String>.from(seed);
      } else if ((hub.layoutKey == layoutDashboardAdminFuturistic ||
              hub.layoutKey == layoutListePosHub) &&
          saved.isEmpty) {
        map[hub.layoutKey] = List<String>.from(
          defaults.isNotEmpty
              ? defaults
              : (hub.layoutKey == layoutListePosHub
                  ? _posListeHubDefaultKeys
                  : defaults),
        );
      } else {
        var keys = List<String>.from(saved);
        if (hub.layoutKey == layoutHomeDt ||
            hub.layoutKey == layoutHomeDtFuturistic) {
          keys = resolveDtHomeOrderKeys(keys, defaults);
        } else if (hub.layoutKey == layoutLogisticaHub) {
          keys = resolveLogisticaHubOrderKeys(keys, defaults);
        } else if (hub.layoutKey == layoutCarburanteHub) {
          keys = resolveCarburanteHubOrderKeys(keys, defaults);
        } else if (hub.layoutKey == layoutListePosHub) {
          keys = resolveListePosHubOrderKeys(keys, defaults);
          if (keys.isEmpty || !keys.any(_posListeModuleKeys.contains)) {
            keys = List<String>.from(_posListeHubDefaultKeys);
          }
        } else if (hub.layoutKey == layoutUqsaHub) {
          keys = ensureUqsaHubOrderKeys(keys);
        }
        map[hub.layoutKey] = keys;
        allSavedKeysEver.addAll(keys);
      }
    }

    expandLegacyDpiUqsaKey(map);
    ensureVestiarioCategorieInDpiHub(map);
    _syncCustomHubSlotKeys(map, custom, hidden: hidden);
    if (!personal) {
      _applyCustomHubLaunchersInMemory(map, custom, hidden: hidden);
    }

    for (final hub in custom) {
      final keys = map[hub.layoutKey];
      if (keys == null) continue;
      map[hub.layoutKey] = _pruneCustomHubLayoutKeys(
        keys: keys,
        hub: hub,
      );
    }

    // Tile nuove in app: rispetta hub dove l'utente ha già messo moduli correlati.
    final assigned = <String>{
      for (final keys in map.values) ...keys,
    };
    final newKeys = <String>{};
    for (final hub in AppUiHubRegistry.all) {
      for (final key in defaultKeysByLayout[hub.layoutKey] ?? const <String>[]) {
        if (assigned.contains(key) || hidden.contains(key)) continue;
        if (allSavedKeysEver.contains(key)) continue;
        newKeys.add(key);
      }
    }
    for (final key in newKeys) {
      _placeNewModuleKey(
        map: map,
        key: key,
        defaultKeysByLayout: defaultKeysByLayout,
        assigned: assigned,
        hidden: hidden,
      );
    }

    _ensureShippedHubModuleKeys(
      map,
      hidden: hidden,
      defaultKeysByLayout: defaultKeysByLayout,
    );

    _enforceCanonicalHubModules(map, hidden: hidden);

    _ensureRubricaOnAdminDashboard(map, hidden: hidden);

    _ensureCarburanteHubSeeded(map);

    // Tile dashboard condivisi tra classica e futuristica (GESTOPRO).
    if (map.containsKey(layoutDashboardAdmin)) {
      final classic = map[layoutDashboardAdmin] ?? <String>[];
      final fut = List<String>.from(
        map[layoutDashboardAdminFuturistic] ?? <String>[],
      );
      var futChanged = false;
      for (final key in _dashboardSharedWithFuturisticKeys) {
        if (hidden.contains(key)) continue;
        final onClassic = classic.contains(key);
        final inCatalog = (defaultKeysByLayout[layoutDashboardAdmin] ??
                const <String>[])
            .contains(key);
        if ((onClassic || inCatalog) && !fut.contains(key)) {
          fut.add(key);
          futChanged = true;
        }
      }
      if (futChanged) {
        map[layoutDashboardAdminFuturistic] = fut;
      }
    }

    _ensurePosHubLauncherOnUqsaHub(map, hidden: hidden);

    if (map.containsKey(layoutImpostazioniHub)) {
      map[layoutImpostazioniHub] = ensureImpostazioniHubOrderKeys(
        map[layoutImpostazioniHub] ?? <String>[],
      );
    }

    if (map.containsKey(layoutUqsaHub)) {
      map[layoutUqsaHub] = ensureUqsaHubOrderKeys(
        map[layoutUqsaHub] ?? <String>[],
      );
    }

    _enforceFollowAffinityHubModules(
      map,
      customHubs: custom,
      hidden: hidden,
    );

    return HubLayoutOrders(map);
  }

  /// Toglie le liste POS dal hub DPI (assegnazione legacy) e mette il
  /// launcher POS su UQSA se ancora assente.
  static void _ensurePosHubLauncherOnUqsaHub(
    Map<String, List<String>> map, {
    required Set<String> hidden,
  }) {
    final dpiKeys = map[layoutDpiHub];
    if (dpiKeys != null) {
      final cleaned = List<String>.from(dpiKeys)
        ..removeWhere(_legacyDtPosListaKeys.contains);
      if (cleaned.length != dpiKeys.length) {
        map[layoutDpiHub] = cleaned;
      }
    }

    if (hidden.contains(layoutListePosHub)) return;
    if (!map.containsKey(layoutUqsaHub)) return;
    final uqsaKeys = List<String>.from(map[layoutUqsaHub] ?? <String>[]);
    if (uqsaKeys.contains(layoutListePosHub)) return;
    uqsaKeys.insert(0, layoutListePosHub);
    map[layoutUqsaHub] = uqsaKeys;
  }

  /// Rimuove la voce da tutti gli hub e la aggiunge alla destinazione scelta.
  static HubLayoutOrders moveItemToLayout({
    required HubLayoutOrders orders,
    required String itemKey,
    required String targetLayoutKey,
  }) {
    final allLayouts = <String>{
      ...orders.allLayoutKeys,
      ...AppUiHubRegistry.all.map((h) => h.layoutKey),
      targetLayoutKey,
    };
    final copy = <String, List<String>>{};
    for (final layoutKey in allLayouts) {
      copy[layoutKey] = List<String>.from(orders.keysFor(layoutKey))
        ..remove(itemKey);
    }
    final target = List<String>.from(copy[targetLayoutKey] ?? <String>[]);
    if (!target.contains(itemKey)) target.add(itemKey);
    copy[targetLayoutKey] = target;
    return HubLayoutOrders(copy);
  }

  /// Applica ordine salvato; voci nuove o non in lista restano in coda.
  static List<T> applyOrder<T>({
    required List<T> items,
    required List<String>? savedOrder,
    required String Function(T item) keyOf,
  }) {
    if (savedOrder == null || savedOrder.isEmpty) return items;
    final byKey = <String, T>{};
    for (final item in items) {
      byKey[keyOf(item)] = item;
    }
    final out = <T>[];
    for (final key in savedOrder) {
      final item = byKey.remove(key);
      if (item != null) out.add(item);
    }
    out.addAll(byKey.values);
    return out;
  }

  static List<T> itemsForHub<T>({
    required Map<String, T> catalog,
    required List<String> hubKeyOrder,
  }) {
    final out = <T>[];
    for (final key in hubKeyOrder) {
      final item = catalog[key];
      if (item != null) out.add(item);
    }
    return out;
  }
}

class HubLayoutOrders {
  HubLayoutOrders(this._keysByLayout);

  final Map<String, List<String>> _keysByLayout;

  List<String> get allLayoutKeys => _keysByLayout.keys.toList(growable: false);

  List<String> keysFor(String layoutKey) =>
      List<String>.from(_keysByLayout[layoutKey] ?? <String>[]);

  void setKeysFor(String layoutKey, List<String> keys) {
    _keysByLayout[layoutKey] = List<String>.from(keys);
  }
}
