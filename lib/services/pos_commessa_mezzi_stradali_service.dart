import 'pos_mezzi_stradali_import_parser.dart';
import 'supabase_service.dart';

class PosCommessaMezzoStradaleRow {
  final String id;
  final String commessaId;
  final String mezzoId;
  final String? codificaImport;
  final String? targaImport;
  final String? modelloImport;
  final String? tipologiaImport;
  final String? proprietaImport;
  final int? numerazione;
  final String targa;
  final String marca;
  final String modello;
  final String tipologiaMezzo;
  final String? assegnatarioAttuale;

  const PosCommessaMezzoStradaleRow({
    required this.id,
    required this.commessaId,
    required this.mezzoId,
    required this.targa,
    required this.marca,
    required this.modello,
    required this.tipologiaMezzo,
    this.codificaImport,
    this.targaImport,
    this.modelloImport,
    this.tipologiaImport,
    this.proprietaImport,
    this.numerazione,
    this.assegnatarioAttuale,
  });

  String get displayLabel {
    final m = modello.trim();
    if (m.isNotEmpty) return m;
    final imp = (modelloImport ?? '').trim();
    if (imp.isNotEmpty) return imp;
    return targa.isEmpty ? (targaImport ?? '—') : targa;
  }

  /// Tipologia da anagrafica Mezzi Stradali, con fallback import POS.
  String get displayTipologia {
    final t = tipologiaMezzo.trim();
    if (t.isNotEmpty) return t;
    final imp = (tipologiaImport ?? '').trim();
    return imp.isEmpty ? '—' : imp;
  }

  String get displayTarga {
    final t = targa.trim();
    if (t.isNotEmpty) return t;
    final imp = (targaImport ?? '').trim();
    return imp.isEmpty ? '—' : imp;
  }
}

class PosCommessaMezziStradaliRiepilogo {
  final String commessaId;
  final String nome;
  final int mezziCount;
  final DateTime? ultimoAggiornamentoInApp;

  const PosCommessaMezziStradaliRiepilogo({
    required this.commessaId,
    required this.nome,
    required this.mezziCount,
    this.ultimoAggiornamentoInApp,
  });
}

class PosMezziStradaliImportMatchPreview {
  final PosMezziStradaliImportRow importRow;
  final String? mezzoId;
  final String? mezzoLabel;

  bool get matched => (mezzoId ?? '').isNotEmpty;

  const PosMezziStradaliImportMatchPreview({
    required this.importRow,
    this.mezzoId,
    this.mezzoLabel,
  });

  PosMezziStradaliImportMatchPreview copyWith({
    String? mezzoId,
    String? mezzoLabel,
    bool clearMatch = false,
  }) {
    return PosMezziStradaliImportMatchPreview(
      importRow: importRow,
      mezzoId: clearMatch ? null : (mezzoId ?? this.mezzoId),
      mezzoLabel: clearMatch ? null : (mezzoLabel ?? this.mezzoLabel),
    );
  }
}

abstract final class PosCommessaMezziStradaliService {
  PosCommessaMezziStradaliService._();

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

  static int? parseNumerazioneFromCodifica(String codifica) {
    final c = codifica.trim().toUpperCase();
    if (c.isEmpty) return null;
    final digits = c.startsWith('N') ? c.substring(1) : c;
    return int.tryParse(digits);
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

  static Future<Map<String, Map<String, dynamic>>> loadMezziAttivi() async {
    final res = await SupabaseService.client
        .from('logistica_mezzi_stradali')
        .select('id_uuid,numerazione,targa,marca,modello,tipologia_mezzo')
        .eq('active', true)
        .order('numerazione');
    final out = <String, Map<String, dynamic>>{};
    for (final raw in res as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) out[id] = m;
    }
    return out;
  }

  static String mezzoLabel(Map<String, dynamic> m) {
    final targa = (m['targa'] ?? '').toString().trim();
    final modello = (m['modello'] ?? '').toString().trim();
    final marca = (m['marca'] ?? '').toString().trim();
    final num = m['numerazione'];
    final parts = <String>[
      if (targa.isNotEmpty) targa,
      if (marca.isNotEmpty && modello.isNotEmpty) '$marca $modello' else if (modello.isNotEmpty) modello,
      if (num != null) '(N$num)',
    ];
    return parts.isEmpty ? (m['id_uuid'] ?? '').toString() : parts.join(' · ');
  }

  static String? findBestMezzoId({
    required PosMezziStradaliImportRow row,
    required Map<String, Map<String, dynamic>> mezziById,
  }) {
    final targa = normalizeKey(row.targa);
    final codNum = parseNumerazioneFromCodifica(row.codifica);
    String? best;

    for (final e in mezziById.entries) {
      final m = e.value;
      final dbTarga = normalizeKey((m['targa'] ?? '').toString());
      if (targa.isNotEmpty && dbTarga == targa) return e.key;

      if (codNum != null) {
        final dbNum = m['numerazione'];
        final n = dbNum is int ? dbNum : int.tryParse('$dbNum');
        if (n != null && n == codNum) best ??= e.key;
      }
    }
    return best;
  }

  static Future<List<PosCommessaMezziStradaliRiepilogo>> loadCommesseRiepilogo(
    Map<String, String> commesseAttive,
  ) async {
    if (commesseAttive.isEmpty) return const [];

    final mezziRes = await SupabaseService.client
        .from('pos_commessa_mezzi_stradali')
        .select('commessa_id, updated_at');

    final countByCommessa = <String, int>{};
    final lastUpdate = <String, DateTime>{};
    for (final raw in mezziRes as List) {
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
        .from('pos_commessa_mezzi_stradali_lista_meta')
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

    final out = <PosCommessaMezziStradaliRiepilogo>[];
    for (final e in commesseAttive.entries) {
      out.add(
        PosCommessaMezziStradaliRiepilogo(
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
        .from('pos_commessa_mezzi_stradali_lista_meta')
        .select('updated_at')
        .eq('commessa_id', commessaId)
        .maybeSingle();
    if (meta != null) {
      latest = _maxDateTime(latest, _parseDateField(meta['updated_at']));
    }
    final rows = await SupabaseService.client
        .from('pos_commessa_mezzi_stradali')
        .select('updated_at')
        .eq('commessa_id', commessaId);
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      latest = _maxDateTime(latest, _parseDateField(m['updated_at']));
    }
    return latest;
  }

  static Future<List<PosCommessaMezzoStradaleRow>> loadMezziPos(String commessaId) async {
    final res = await SupabaseService.client
        .from('pos_commessa_mezzi_stradali')
        .select(
          'id, commessa_id, mezzo_id, codifica_import, targa_import, modello_import, tipologia_import, proprieta_import, '
          'logistica_mezzi_stradali(numerazione,targa,marca,modello,tipologia_mezzo,assegnatario_attuale)',
        )
        .eq('commessa_id', commessaId);

    return _mapMezziPosRows(res as List);
  }

  /// Tutti i mezzi POS (tutte le commesse), con tipologia da Mezzi Stradali.
  static Future<List<PosCommessaMezzoStradaleRow>> loadAllMezziPos() async {
    final res = await SupabaseService.client
        .from('pos_commessa_mezzi_stradali')
        .select(
          'id, commessa_id, mezzo_id, codifica_import, targa_import, modello_import, tipologia_import, proprieta_import, '
          'logistica_mezzi_stradali(numerazione,targa,marca,modello,tipologia_mezzo,assegnatario_attuale)',
        );
    return _mapMezziPosRows(res as List);
  }

  static List<PosCommessaMezzoStradaleRow> _mapMezziPosRows(List rawList) {
    final out = <PosCommessaMezzoStradaleRow>[];
    for (final raw in rawList) {
      final m = Map<String, dynamic>.from(raw as Map);
      final mezzoRaw = m['logistica_mezzi_stradali'];
      final mezzo = mezzoRaw is Map
          ? Map<String, dynamic>.from(mezzoRaw)
          : <String, dynamic>{};
      final numRaw = mezzo['numerazione'];
      out.add(
        PosCommessaMezzoStradaleRow(
          id: (m['id'] ?? '').toString(),
          commessaId: (m['commessa_id'] ?? '').toString(),
          mezzoId: (m['mezzo_id'] ?? '').toString(),
          codificaImport: m['codifica_import']?.toString(),
          targaImport: m['targa_import']?.toString(),
          modelloImport: m['modello_import']?.toString(),
          tipologiaImport: m['tipologia_import']?.toString(),
          proprietaImport: m['proprieta_import']?.toString(),
          numerazione: numRaw is int ? numRaw : int.tryParse('$numRaw'),
          targa: (mezzo['targa'] ?? '').toString(),
          marca: (mezzo['marca'] ?? '').toString(),
          modello: (mezzo['modello'] ?? '').toString(),
          tipologiaMezzo: (mezzo['tipologia_mezzo'] ?? '').toString(),
          assegnatarioAttuale: mezzo['assegnatario_attuale']?.toString(),
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
    await SupabaseService.client.from('pos_commessa_mezzi_stradali_lista_meta').upsert({
      'commessa_id': commessaId,
      'data_ultimo_aggiornamento':
          dataUltimoAggiornamento?.toIso8601String().substring(0, 10),
      'updated_by_user_uuid': updatedByUserUuid,
    }, onConflict: 'commessa_id');
  }

  static Future<void> addMezzo({
    required String commessaId,
    String? mezzoId,
    String? codificaImport,
    String? targaImport,
    String? modelloImport,
    String? tipologiaImport,
    String? proprietaImport,
    String? createdByUserUuid,
  }) async {
    final mid = (mezzoId ?? '').trim();
    if (mid.isNotEmpty) {
      await SupabaseService.client.from('pos_commessa_mezzi_stradali').upsert({
        'commessa_id': commessaId,
        'mezzo_id': mid,
        'codifica_import': codificaImport,
        'targa_import': targaImport,
        'modello_import': modelloImport,
        'tipologia_import': tipologiaImport,
        'proprieta_import': proprietaImport,
        'created_by_user_uuid': createdByUserUuid,
      }, onConflict: 'commessa_id,mezzo_id');
      return;
    }

    final targaKey = normalizeKey(targaImport ?? '');
    if (targaKey.isNotEmpty) {
      final existing = await SupabaseService.client
          .from('pos_commessa_mezzi_stradali')
          .select('id')
          .eq('commessa_id', commessaId)
          .isFilter('mezzo_id', null)
          .eq('targa_import', (targaImport ?? '').trim())
          .maybeSingle();
      if (existing != null) {
        await SupabaseService.client
            .from('pos_commessa_mezzi_stradali')
            .update({
              'codifica_import': codificaImport,
              'targa_import': targaImport,
              'modello_import': modelloImport,
              'tipologia_import': tipologiaImport,
              'proprieta_import': proprietaImport,
            })
            .eq('id', (existing['id'] ?? '').toString());
        return;
      }
    }

    await SupabaseService.client.from('pos_commessa_mezzi_stradali').insert({
      'commessa_id': commessaId,
      'codifica_import': codificaImport,
      'targa_import': targaImport,
      'modello_import': modelloImport,
      'tipologia_import': tipologiaImport,
      'proprieta_import': proprietaImport,
      'created_by_user_uuid': createdByUserUuid,
    });
  }

  static Future<void> removeMezzo(String id) async {
    await SupabaseService.client.from('pos_commessa_mezzi_stradali').delete().eq('id', id);
  }

  static List<PosMezziStradaliImportMatchPreview> previewImportMatches({
    required List<PosMezziStradaliImportRow> righe,
    required Map<String, Map<String, dynamic>> mezziById,
  }) {
    return righe
        .map((r) {
          final id = findBestMezzoId(row: r, mezziById: mezziById);
          return PosMezziStradaliImportMatchPreview(
            importRow: r,
            mezzoId: id,
            mezzoLabel: id != null ? mezzoLabel(mezziById[id]!) : null,
          );
        })
        .toList(growable: false);
  }

  static Future<({int added, int updated, int skipped, int importOnly})> applyImport({
    required String commessaId,
    required List<PosMezziStradaliImportMatchPreview> previews,
    DateTime? dataUltimoAggiornamento,
    String? userUuid,
  }) async {
    final existing = await loadMezziPos(commessaId);
    final existingMezzoIds = existing
        .map((r) => r.mezzoId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final existingImportOnlyIds = <String, String>{};
    for (final row in existing) {
      if (row.mezzoId.isNotEmpty) continue;
      final targa = normalizeKey(row.targaImport ?? '');
      if (targa.isNotEmpty) {
        existingImportOnlyIds[targa] = row.id;
      }
    }

    var added = 0;
    var updated = 0;
    var importOnly = 0;
    for (final p in previews) {
      final mid = (p.mezzoId ?? '').trim();
      final imp = p.importRow;
      if (mid.isEmpty) {
        final targaKey = normalizeKey(imp.targa);
        final wasExisting =
            targaKey.isNotEmpty && existingImportOnlyIds.containsKey(targaKey);
        await addMezzo(
          commessaId: commessaId,
          codificaImport: imp.codifica,
          targaImport: imp.targa,
          modelloImport: imp.modello,
          tipologiaImport: imp.definizioneClasse,
          proprietaImport: imp.proprietaNoleggio,
          createdByUserUuid: userUuid,
        );
        importOnly++;
        if (wasExisting) {
          updated++;
        } else {
          added++;
          if (targaKey.isNotEmpty) {
            existingImportOnlyIds[targaKey] = 'new';
          }
        }
        continue;
      }

      final wasExisting = existingMezzoIds.contains(mid);
      await addMezzo(
        commessaId: commessaId,
        mezzoId: mid,
        codificaImport: imp.codifica,
        targaImport: imp.targa,
        modelloImport: imp.modello,
        tipologiaImport: imp.definizioneClasse,
        proprietaImport: imp.proprietaNoleggio,
        createdByUserUuid: userUuid,
      );
      if (wasExisting) {
        updated++;
      } else {
        added++;
        existingMezzoIds.add(mid);
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
