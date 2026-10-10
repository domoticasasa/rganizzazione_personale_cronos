import 'pos_mdo_proprieta_import_parser.dart';
import 'supabase_service.dart';

class PosCommessaMdoProprietaRow {
  final String id;
  final String commessaId;
  final String mdoId;
  final String? codificaImport;
  final String? targaImport;
  final String? descrizioneImport;
  final String? proprietaImport;
  final String? codifica;
  final String matricola;
  final String tipologia;
  final String? definizioneClasse;
  final bool isMezzoPrincipale;

  const PosCommessaMdoProprietaRow({
    required this.id,
    required this.commessaId,
    required this.mdoId,
    required this.matricola,
    required this.tipologia,
    required this.isMezzoPrincipale,
    this.codificaImport,
    this.targaImport,
    this.descrizioneImport,
    this.proprietaImport,
    this.codifica,
    this.definizioneClasse,
  });

  String get displayLabel {
    final d = (descrizioneImport ?? '').trim();
    if (d.isNotEmpty) return d;
    final t = tipologia.trim();
    if (t.isNotEmpty) return t;
    return matricola.isEmpty ? (codifica ?? '—') : matricola;
  }

  bool get isNoleggio {
    final p = (proprietaImport ?? '').toUpperCase();
    return p.contains('NOLEGGIO');
  }
}

class PosCommessaMdoProprietaRiepilogo {
  final String commessaId;
  final String nome;
  final int mezziCount;
  final DateTime? ultimoAggiornamentoInApp;

  const PosCommessaMdoProprietaRiepilogo({
    required this.commessaId,
    required this.nome,
    required this.mezziCount,
    this.ultimoAggiornamentoInApp,
  });
}

class PosMdoProprietaImportMatchPreview {
  final PosMdoProprietaImportRow importRow;
  final String? mdoId;
  final String? mdoLabel;

  bool get matched => (mdoId ?? '').isNotEmpty;

  const PosMdoProprietaImportMatchPreview({
    required this.importRow,
    this.mdoId,
    this.mdoLabel,
  });

  PosMdoProprietaImportMatchPreview copyWith({
    String? mdoId,
    String? mdoLabel,
    bool clearMatch = false,
  }) {
    return PosMdoProprietaImportMatchPreview(
      importRow: importRow,
      mdoId: clearMatch ? null : (mdoId ?? this.mdoId),
      mdoLabel: clearMatch ? null : (mdoLabel ?? this.mdoLabel),
    );
  }
}

abstract final class PosCommessaMdoProprietaService {
  PosCommessaMdoProprietaService._();

  static DateTime? _parseDateField(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static DateTime? _maxDateTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String normalizeKey(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'\s+'), '').trim();

  /// Es. "MdO 01" → "MDO1", "MdO1" → "MDO1"
  static String normalizeCodifica(String codifica) {
    var c = normalizeKey(codifica);
    final m = RegExp(r'^MDO0*(\d+)$').firstMatch(c);
    if (m != null) return 'MDO${m.group(1)}';
    return c;
  }

  static Future<Map<String, String>> loadCommesseAttive() async {
    final res = await SupabaseService.client
        .from('commesse')
        .select('id_uuid,nome')
        .eq('active', true)
        .order('nome');
    return {
      for (final raw in res as List)
        (raw['id_uuid'] ?? '').toString(): (raw['nome'] ?? '').toString(),
    }..removeWhere((k, v) => k.isEmpty);
  }

  /// Mezzi principali attivi per aggiunta manuale (proprietà e noleggio in anagrafica).
  static Future<Map<String, Map<String, dynamic>>> loadMdoPrincipaliAttivi() async {
    final res = await SupabaseService.client
        .from('logistica_mdo_proprieta')
        .select(
          'id_uuid,codifica,codifica_gruppo,matricola,tipologia,definizione_classe_mezzo,is_mezzo_principale',
        )
        .eq('active', true)
        .eq('is_mezzo_principale', true)
        .order('codifica_gruppo');
    final out = <String, Map<String, dynamic>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) out[id] = m;
    }
    return out;
  }

  /// Tutti i record attivi per abbinamento import (anche accessori se matricola coincide).
  static Future<Map<String, Map<String, dynamic>>> loadMdoAttiviPerImport() async {
    final res = await SupabaseService.client
        .from('logistica_mdo_proprieta')
        .select(
          'id_uuid,codifica,codifica_gruppo,matricola,tipologia,definizione_classe_mezzo,is_mezzo_principale',
        )
        .eq('active', true)
        .order('codifica_gruppo')
        .order('ordine');
    final out = <String, Map<String, dynamic>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) out[id] = m;
    }
    return out;
  }

  static String mdoLabel(Map<String, dynamic> m) {
    final cod = (m['codifica'] ?? m['codifica_gruppo'] ?? '').toString().trim();
    final mat = (m['matricola'] ?? '').toString().trim();
    final tip = (m['tipologia'] ?? '').toString().trim();
    final parts = <String>[
      if (cod.isNotEmpty) cod,
      if (tip.isNotEmpty) tip,
      if (mat.isNotEmpty) '($mat)',
    ];
    return parts.isEmpty ? (m['id_uuid'] ?? '').toString() : parts.join(' · ');
  }

  static String? findBestMdoId({
    required PosMdoProprietaImportRow row,
    required Map<String, Map<String, dynamic>> mdoById,
  }) {
    final mat = normalizeKey(row.targaMatricola);
    final cod = normalizeCodifica(row.codifica);
    String? principalMatch;
    String? accessoryMatch;

    for (final e in mdoById.entries) {
      final m = e.value;
      final dbMat = normalizeKey((m['matricola'] ?? '').toString());
      final dbCod = normalizeCodifica(
        (m['codifica'] ?? m['codifica_gruppo'] ?? '').toString(),
      );
      final isPrincipal = m['is_mezzo_principale'] == true;

      if (mat.isNotEmpty && dbMat == mat) {
        if (isPrincipal) return e.key;
        accessoryMatch ??= e.key;
      }
      if (cod.isNotEmpty && dbCod == cod) {
        if (isPrincipal) principalMatch ??= e.key;
      }
    }
    return principalMatch ?? accessoryMatch;
  }

  static Future<List<PosCommessaMdoProprietaRiepilogo>> loadCommesseRiepilogo(
    Map<String, String> commesseAttive,
  ) async {
    if (commesseAttive.isEmpty) return const [];

    final mdoRes = await SupabaseService.client
        .from('pos_commessa_mdo_proprieta')
        .select('commessa_id, updated_at');

    final countByCommessa = <String, int>{};
    final lastUpdate = <String, DateTime>{};
    for (final raw in mdoRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = (m['commessa_id'] ?? '').toString().trim();
      if (cid.isEmpty) continue;
      countByCommessa[cid] = (countByCommessa[cid] ?? 0) + 1;
      final upd = _parseDateField(m['updated_at']);
      if (upd != null) {
        lastUpdate[cid] = _maxDateTime(lastUpdate[cid], upd)!;
      }
    }

    final metaRes = await SupabaseService.client
        .from('pos_commessa_mdo_proprieta_lista_meta')
        .select('commessa_id, updated_at');
    for (final raw in metaRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = (m['commessa_id'] ?? '').toString().trim();
      if (cid.isEmpty) continue;
      lastUpdate[cid] = _maxDateTime(
        lastUpdate[cid],
        _parseDateField(m['updated_at']),
      )!;
    }

    final out = <PosCommessaMdoProprietaRiepilogo>[];
    for (final e in commesseAttive.entries) {
      out.add(
        PosCommessaMdoProprietaRiepilogo(
          commessaId: e.key,
          nome: e.value,
          mezziCount: countByCommessa[e.key] ?? 0,
          ultimoAggiornamentoInApp: lastUpdate[e.key],
        ),
      );
    }
    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  static Future<DateTime?> loadUltimoAggiornamentoApp(String commessaId) async {
    DateTime? latest;
    final meta = await SupabaseService.client
        .from('pos_commessa_mdo_proprieta_lista_meta')
        .select('updated_at')
        .eq('commessa_id', commessaId)
        .maybeSingle();
    if (meta != null) {
      latest = _maxDateTime(latest, _parseDateField(meta['updated_at']));
    }
    final rows = await SupabaseService.client
        .from('pos_commessa_mdo_proprieta')
        .select('updated_at')
        .eq('commessa_id', commessaId);
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      latest = _maxDateTime(latest, _parseDateField(m['updated_at']));
    }
    return latest;
  }

  static Future<List<PosCommessaMdoProprietaRow>> loadMezziPos(String commessaId) async {
    final res = await SupabaseService.client
        .from('pos_commessa_mdo_proprieta')
        .select(
          'id, commessa_id, mdo_id, codifica_import, targa_import, descrizione_import, proprieta_import, '
          'logistica_mdo_proprieta(codifica,matricola,tipologia,definizione_classe_mezzo,is_mezzo_principale)',
        )
        .eq('commessa_id', commessaId);

    final out = <PosCommessaMdoProprietaRow>[];
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final mdoRaw = m['logistica_mdo_proprieta'];
      final mdo = mdoRaw is Map
          ? Map<String, dynamic>.from(mdoRaw)
          : <String, dynamic>{};
      out.add(
        PosCommessaMdoProprietaRow(
          id: (m['id'] ?? '').toString(),
          commessaId: (m['commessa_id'] ?? '').toString(),
          mdoId: (m['mdo_id'] ?? '').toString(),
          codificaImport: m['codifica_import']?.toString(),
          targaImport: m['targa_import']?.toString(),
          descrizioneImport: m['descrizione_import']?.toString(),
          proprietaImport: m['proprieta_import']?.toString(),
          codifica: mdo['codifica']?.toString(),
          matricola: (mdo['matricola'] ?? '').toString(),
          tipologia: (mdo['tipologia'] ?? '').toString(),
          definizioneClasse: mdo['definizione_classe_mezzo']?.toString(),
          isMezzoPrincipale: mdo['is_mezzo_principale'] == true,
        ),
      );
    }
    out.sort(
      (a, b) => a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()),
    );
    return out;
  }

  static Future<void> upsertListaMeta({
    required String commessaId,
    DateTime? dataUltimoAggiornamento,
    String? updatedByUserUuid,
  }) async {
    await SupabaseService.client.from('pos_commessa_mdo_proprieta_lista_meta').upsert({
      'commessa_id': commessaId,
      'data_ultimo_aggiornamento':
          dataUltimoAggiornamento?.toIso8601String().substring(0, 10),
      'updated_by_user_uuid': updatedByUserUuid,
    }, onConflict: 'commessa_id');
  }

  static String _importOnlyRowKey(String? codifica, String? targa) {
    final c = normalizeKey(codifica ?? '');
    if (c.isNotEmpty) return c;
    return normalizeKey(targa ?? '');
  }

  static Future<void> addMezzo({
    required String commessaId,
    String? mdoId,
    String? codificaImport,
    String? targaImport,
    String? descrizioneImport,
    String? proprietaImport,
    String? createdByUserUuid,
  }) async {
    final mid = (mdoId ?? '').trim();
    if (mid.isNotEmpty) {
      await SupabaseService.client.from('pos_commessa_mdo_proprieta').upsert({
        'commessa_id': commessaId,
        'mdo_id': mid,
        'codifica_import': codificaImport,
        'targa_import': targaImport,
        'descrizione_import': descrizioneImport,
        'proprieta_import': proprietaImport,
        'created_by_user_uuid': createdByUserUuid,
      }, onConflict: 'commessa_id,mdo_id');
      return;
    }

    final codificaKey = normalizeKey(codificaImport ?? '');
    if (codificaKey.isNotEmpty) {
      final existing = await SupabaseService.client
          .from('pos_commessa_mdo_proprieta')
          .select('id')
          .eq('commessa_id', commessaId)
          .isFilter('mdo_id', null)
          .eq('codifica_import', (codificaImport ?? '').trim())
          .maybeSingle();
      if (existing != null) {
        await SupabaseService.client
            .from('pos_commessa_mdo_proprieta')
            .update({
              'codifica_import': codificaImport,
              'targa_import': targaImport,
              'descrizione_import': descrizioneImport,
              'proprieta_import': proprietaImport,
            })
            .eq('id', (existing['id'] ?? '').toString());
        return;
      }
    }

    await SupabaseService.client.from('pos_commessa_mdo_proprieta').insert({
      'commessa_id': commessaId,
      'codifica_import': codificaImport,
      'targa_import': targaImport,
      'descrizione_import': descrizioneImport,
      'proprieta_import': proprietaImport,
      'created_by_user_uuid': createdByUserUuid,
    });
  }

  static Future<void> removeMezzo(String id) async {
    await SupabaseService.client.from('pos_commessa_mdo_proprieta').delete().eq('id', id);
  }

  static List<PosMdoProprietaImportMatchPreview> previewImportMatches({
    required List<PosMdoProprietaImportRow> righe,
    required Map<String, Map<String, dynamic>> mdoById,
  }) {
    return righe
        .map((r) {
          final id = findBestMdoId(row: r, mdoById: mdoById);
          return PosMdoProprietaImportMatchPreview(
            importRow: r,
            mdoId: id,
            mdoLabel: id != null ? mdoLabel(mdoById[id]!) : null,
          );
        })
        .toList(growable: false);
  }

  static Future<({int added, int updated, int skipped, int importOnly})> applyImport({
    required String commessaId,
    required List<PosMdoProprietaImportMatchPreview> previews,
    DateTime? dataUltimoAggiornamento,
    String? userUuid,
  }) async {
    final existing = await loadMezziPos(commessaId);
    final existingMdoIds = existing
        .map((r) => r.mdoId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final existingImportOnlyKeys = <String, String>{};
    for (final row in existing) {
      if (row.mdoId.isNotEmpty) continue;
      final key = _importOnlyRowKey(row.codificaImport, row.targaImport);
      if (key.isNotEmpty) existingImportOnlyKeys[key] = row.id;
    }

    var added = 0;
    var updated = 0;
    var importOnly = 0;
    for (final p in previews) {
      final mid = (p.mdoId ?? '').trim();
      final imp = p.importRow;
      if (mid.isEmpty) {
        final key = _importOnlyRowKey(imp.codifica, imp.targaMatricola);
        final wasExisting = key.isNotEmpty && existingImportOnlyKeys.containsKey(key);
        await addMezzo(
          commessaId: commessaId,
          codificaImport: imp.codifica,
          targaImport: imp.targaMatricola,
          descrizioneImport: imp.descrizione,
          proprietaImport: imp.proprietaNoleggio,
          createdByUserUuid: userUuid,
        );
        importOnly++;
        if (wasExisting) {
          updated++;
        } else {
          added++;
          if (key.isNotEmpty) existingImportOnlyKeys[key] = 'new';
        }
        continue;
      }

      final wasExisting = existingMdoIds.contains(mid);
      await addMezzo(
        commessaId: commessaId,
        mdoId: mid,
        codificaImport: imp.codifica,
        targaImport: imp.targaMatricola,
        descrizioneImport: imp.descrizione,
        proprietaImport: imp.proprietaNoleggio,
        createdByUserUuid: userUuid,
      );
      if (wasExisting) {
        updated++;
      } else {
        added++;
        existingMdoIds.add(mid);
      }
    }

    if (dataUltimoAggiornamento != null) {
      await upsertListaMeta(
        commessaId: commessaId,
        dataUltimoAggiornamento: dataUltimoAggiornamento,
        updatedByUserUuid: userUuid,
      );
    }

    return (added: added, updated: updated, skipped: 0, importOnly: importOnly);
  }
}
