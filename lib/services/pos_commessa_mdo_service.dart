import 'pos_mdo_ferroviari_import_parser.dart';
import 'supabase_service.dart';

class PosCommessaMdoRow {
  final String id;
  final String commessaId;
  final String mdoId;
  final String? codificaImport;
  final String? targaImport;
  final String? descrizioneImport;
  final String? proprietaImport;
  final String matricolaInterna;
  final String targaRfi;
  final String descrizioneMezzo;

  const PosCommessaMdoRow({
    required this.id,
    required this.commessaId,
    required this.mdoId,
    required this.matricolaInterna,
    required this.targaRfi,
    required this.descrizioneMezzo,
    this.codificaImport,
    this.targaImport,
    this.descrizioneImport,
    this.proprietaImport,
  });

  String get displayLabel {
    final d = descrizioneMezzo.trim();
    if (d.isNotEmpty) return d;
    return (descrizioneImport ?? '').trim().isEmpty
        ? matricolaInterna
        : descrizioneImport!.trim();
  }
}

class PosCommessaMdoRiepilogo {
  final String commessaId;
  final String nome;
  final int mezziCount;
  final DateTime? ultimoAggiornamentoInApp;

  const PosCommessaMdoRiepilogo({
    required this.commessaId,
    required this.nome,
    required this.mezziCount,
    this.ultimoAggiornamentoInApp,
  });
}

class PosMdoImportMatchPreview {
  final PosMdoFerroviariImportRow importRow;
  final String? mdoId;
  final String? mdoLabel;

  bool get matched => (mdoId ?? '').isNotEmpty;

  const PosMdoImportMatchPreview({
    required this.importRow,
    this.mdoId,
    this.mdoLabel,
  });

  PosMdoImportMatchPreview copyWith({
    String? mdoId,
    String? mdoLabel,
    bool clearMatch = false,
  }) {
    return PosMdoImportMatchPreview(
      importRow: importRow,
      mdoId: clearMatch ? null : (mdoId ?? this.mdoId),
      mdoLabel: clearMatch ? null : (mdoLabel ?? this.mdoLabel),
    );
  }
}

abstract final class PosCommessaMdoService {
  PosCommessaMdoService._();

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
      s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

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

  static Future<Map<String, Map<String, dynamic>>> loadMdoAttivi() async {
    final res = await SupabaseService.client
        .from('logistica_mdo_ferroviari')
        .select(
          'id_uuid,matricola_interna,codice_identificativo_targa_rfi,descrizione_mezzo',
        )
        .eq('active', true)
        .order('matricola_interna');
    final out = <String, Map<String, dynamic>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) out[id] = m;
    }
    return out;
  }

  static String mdoLabel(Map<String, dynamic> m) {
    final mat = (m['matricola_interna'] ?? '').toString().trim();
    final desc = (m['descrizione_mezzo'] ?? '').toString().trim();
    final targa = (m['codice_identificativo_targa_rfi'] ?? '').toString().trim();
    final parts = <String>[
      if (mat.isNotEmpty) mat,
      if (desc.isNotEmpty) desc,
      if (targa.isNotEmpty) '($targa)',
    ];
    return parts.isEmpty ? (m['id_uuid'] ?? '').toString() : parts.join(' · ');
  }

  static String? findBestMdoId({
    required PosMdoFerroviariImportRow row,
    required Map<String, Map<String, dynamic>> mdoById,
  }) {
    final cod = normalizeKey(row.codifica);
    final targa = normalizeKey(row.targaMatricola);
    String? best;
    for (final e in mdoById.entries) {
      final m = e.value;
      final mat = normalizeKey((m['matricola_interna'] ?? '').toString());
      final tr = normalizeKey((m['codice_identificativo_targa_rfi'] ?? '').toString());
      if (cod.isNotEmpty && mat == cod) return e.key;
      if (targa.isNotEmpty && tr == targa) best ??= e.key;
      if (targa.isNotEmpty && tr.contains(targa)) best ??= e.key;
    }
    return best;
  }

  static Future<List<PosCommessaMdoRiepilogo>> loadCommesseRiepilogo(
    Map<String, String> commesseAttive,
  ) async {
    if (commesseAttive.isEmpty) return const [];

    final mdoRes = await SupabaseService.client
        .from('pos_commessa_mdo_ferroviari')
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
        .from('pos_commessa_mdo_lista_meta')
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

    final out = <PosCommessaMdoRiepilogo>[];
    for (final e in commesseAttive.entries) {
      out.add(
        PosCommessaMdoRiepilogo(
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
        .from('pos_commessa_mdo_lista_meta')
        .select('updated_at')
        .eq('commessa_id', commessaId)
        .maybeSingle();
    if (meta != null) {
      latest = _maxDateTime(latest, _parseDateField(meta['updated_at']));
    }
    final rows = await SupabaseService.client
        .from('pos_commessa_mdo_ferroviari')
        .select('updated_at')
        .eq('commessa_id', commessaId);
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      latest = _maxDateTime(latest, _parseDateField(m['updated_at']));
    }
    return latest;
  }

  static Future<List<PosCommessaMdoRow>> loadMezziPos(String commessaId) async {
    final res = await SupabaseService.client
        .from('pos_commessa_mdo_ferroviari')
        .select(
          'id, commessa_id, mdo_id, codifica_import, targa_import, descrizione_import, proprieta_import, '
          'logistica_mdo_ferroviari(matricola_interna,codice_identificativo_targa_rfi,descrizione_mezzo)',
        )
        .eq('commessa_id', commessaId);

    final out = <PosCommessaMdoRow>[];
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final mdoRaw = m['logistica_mdo_ferroviari'];
      final mdo = mdoRaw is Map
          ? Map<String, dynamic>.from(mdoRaw)
          : <String, dynamic>{};
      out.add(
        PosCommessaMdoRow(
          id: (m['id'] ?? '').toString(),
          commessaId: (m['commessa_id'] ?? '').toString(),
          mdoId: (m['mdo_id'] ?? '').toString(),
          codificaImport: m['codifica_import']?.toString(),
          targaImport: m['targa_import']?.toString(),
          descrizioneImport: m['descrizione_import']?.toString(),
          proprietaImport: m['proprieta_import']?.toString(),
          matricolaInterna: (mdo['matricola_interna'] ?? '').toString(),
          targaRfi: (mdo['codice_identificativo_targa_rfi'] ?? '').toString(),
          descrizioneMezzo: (mdo['descrizione_mezzo'] ?? '').toString(),
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
    await SupabaseService.client.from('pos_commessa_mdo_lista_meta').upsert({
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
      await SupabaseService.client.from('pos_commessa_mdo_ferroviari').upsert({
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
          .from('pos_commessa_mdo_ferroviari')
          .select('id')
          .eq('commessa_id', commessaId)
          .isFilter('mdo_id', null)
          .eq('codifica_import', (codificaImport ?? '').trim())
          .maybeSingle();
      if (existing != null) {
        await SupabaseService.client
            .from('pos_commessa_mdo_ferroviari')
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

    await SupabaseService.client.from('pos_commessa_mdo_ferroviari').insert({
      'commessa_id': commessaId,
      'codifica_import': codificaImport,
      'targa_import': targaImport,
      'descrizione_import': descrizioneImport,
      'proprieta_import': proprietaImport,
      'created_by_user_uuid': createdByUserUuid,
    });
  }

  static Future<void> removeMezzo(String id) async {
    await SupabaseService.client.from('pos_commessa_mdo_ferroviari').delete().eq('id', id);
  }

  static List<PosMdoImportMatchPreview> previewImportMatches({
    required List<PosMdoFerroviariImportRow> righe,
    required Map<String, Map<String, dynamic>> mdoById,
  }) {
    return righe
        .map((r) {
          final id = findBestMdoId(row: r, mdoById: mdoById);
          return PosMdoImportMatchPreview(
            importRow: r,
            mdoId: id,
            mdoLabel: id != null ? mdoLabel(mdoById[id]!) : null,
          );
        })
        .toList(growable: false);
  }

  static Future<({int added, int updated, int skipped, int importOnly})> applyImport({
    required String commessaId,
    required List<PosMdoImportMatchPreview> previews,
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
