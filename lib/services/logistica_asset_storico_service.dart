import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/date_formatters.dart';

/// Snapshot assegnatario corrente (prima/dopo modifica).
class LogisticaAssigneeSnapshot {
  final String? name;
  final String? userUuid;
  final String? dataInizioIso;
  final String? dataFineIso;

  const LogisticaAssigneeSnapshot({
    this.name,
    this.userUuid,
    this.dataInizioIso,
    this.dataFineIso,
  });

  factory LogisticaAssigneeSnapshot.fromMezzoRow(Map<String, dynamic>? row) {
    if (row == null) return const LogisticaAssigneeSnapshot();
    return LogisticaAssigneeSnapshot(
      name: LogisticaAssetStoricoService._trim(row['assegnatario_attuale']),
      userUuid: LogisticaAssetStoricoService._trim(row['assegnatario_user_uuid']),
      dataInizioIso:
          LogisticaAssetStoricoService._trim(row['periodo_assegnatario_attuale']),
      dataFineIso:
          LogisticaAssetStoricoService._trim(row['data_fine_assegnatario_attuale']),
    );
  }

  factory LogisticaAssigneeSnapshot.fromMulticardRow(Map<String, dynamic>? row) {
    if (row == null) return const LogisticaAssigneeSnapshot();
    return LogisticaAssigneeSnapshot(
      name: LogisticaAssetStoricoService._trim(row['assegnatario_attuale']),
      userUuid: LogisticaAssetStoricoService._trim(row['assegnatario_user_uuid']),
      dataInizioIso:
          LogisticaAssetStoricoService._trim(row['periodo_assegnatario_attuale']),
      dataFineIso:
          LogisticaAssetStoricoService._trim(row['data_fine_assegnatario_attuale']),
    );
  }

  factory LogisticaAssigneeSnapshot.fromTelepassRow(Map<String, dynamic>? row) {
    if (row == null) return const LogisticaAssigneeSnapshot();
    return LogisticaAssigneeSnapshot(
      name: LogisticaAssetStoricoService._trim(row['assegnatario_attuale']),
      userUuid: LogisticaAssetStoricoService._trim(row['assegnatario_user_uuid']),
      dataInizioIso:
          LogisticaAssetStoricoService._trim(row['periodo_assegnatario_attuale']),
      dataFineIso:
          LogisticaAssetStoricoService._trim(row['data_fine_assegnatario_attuale']),
    );
  }

  bool get hasAssignee =>
      (name ?? '').isNotEmpty || (userUuid ?? '').isNotEmpty;
}

/// Registro storico assegnatari (4 passaggi) per mezzi, multicard e telepass.
abstract final class LogisticaAssetStoricoService {
  static const String table = 'logistica_asset_assegnatari_storico';
  static const String tipoMezzo = 'mezzo_stradale';
  static const String tipoMulticard = 'multicard';
  static const String tipoTelepass = 'telepass';

  static String _trim(dynamic v) => (v ?? '').toString().trim();

  static String todayIsoDate() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String todayDisplayDate() =>
      formatDateDdMmYyyyFromDate(DateTime.now());

  static bool isTelepassVuoto(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == '--' || s == '-' || s == '—') return true;
    if (s.contains('no telepass')) return true;
    if (s == 'senza' || s.startsWith('senza ') || s.startsWith('senza:')) {
      return true;
    }
    if (s == 'n/a' || s == 'na' || s == 'nessuno' || s == 'nessuna') {
      return true;
    }
    return false;
  }

  static bool assigneeChanged(
    LogisticaAssigneeSnapshot? previous,
    LogisticaAssigneeSnapshot next,
  ) {
    final p = previous;
    if (p == null) return next.hasAssignee;
    final prevKey = _assigneeKey(p.name, p.userUuid);
    final nextKey = _assigneeKey(next.name, next.userUuid);
    return prevKey != nextKey;
  }

  static String _assigneeKey(String? name, String? uuid) {
    final u = (uuid ?? '').trim().toLowerCase();
    if (u.isNotEmpty) return 'u:$u';
    return 'n:${(name ?? '').trim().toLowerCase()}';
  }

  /// Crea/aggiorna i 4 passaggi vuoti per un asset (idempotente).
  static Future<void> ensureRegistry({
    required SupabaseClient supa,
    required String tipoAsset,
    required String identificativo,
    String? mezzoTarga,
    String? mezzoIdUuid,
    String? multicardIdUuid,
  }) async {
    final id = identificativo.trim();
    if (id.isEmpty) return;

    final rows = <Map<String, dynamic>>[];
    for (var p = 1; p <= 4; p++) {
      rows.add({
        'tipo_asset': tipoAsset,
        'identificativo': id,
        'passaggio': p,
        'mezzo_targa': _nullIfEmpty(mezzoTarga),
        'mezzo_id_uuid': _nullIfEmpty(mezzoIdUuid),
        'multicard_id_uuid': _nullIfEmpty(multicardIdUuid),
      });
    }

    await supa.from(table).upsert(
      rows,
      onConflict: 'tipo_asset,identificativo,passaggio',
    );
  }

  /// Sposta l'assegnatario uscente nel passaggio 1 e scala i precedenti (max 4).
  static Future<void> archiveAssigneeChange({
    required SupabaseClient supa,
    required String tipoAsset,
    required String identificativo,
    required LogisticaAssigneeSnapshot previous,
    String? mezzoTarga,
    String? mezzoIdUuid,
    String? multicardIdUuid,
    String? note,
  }) async {
    if (!previous.hasAssignee) return;
    final id = identificativo.trim();
    if (id.isEmpty) return;

    final today = todayIsoDate();
    final res = await supa
        .from(table)
        .select()
        .eq('tipo_asset', tipoAsset)
        .eq('identificativo', id)
        .order('passaggio', ascending: true);

    final existing = <int, Map<String, dynamic>>{};
    for (final row in (res as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      final p = int.tryParse((m['passaggio'] ?? '').toString()) ?? 0;
      if (p >= 1 && p <= 4) existing[p] = m;
    }

    Map<String, dynamic>? slotFrom(
      int passaggio, {
      String? assegnatario,
      String? dal,
      String? al,
      String? noteText,
      Map<String, dynamic>? keep,
    }) {
      if ((assegnatario ?? '').trim().isEmpty &&
          (dal ?? '').trim().isEmpty &&
          (al ?? '').trim().isEmpty &&
          (noteText ?? '').trim().isEmpty) {
        return null;
      }
      return {
        'tipo_asset': tipoAsset,
        'identificativo': id,
        'passaggio': passaggio,
        'assegnatario': _nullIfEmpty(assegnatario),
        'periodo_dal': _nullIfEmpty(dal),
        'periodo_al': _nullIfEmpty(al),
        'note': _nullIfEmpty(noteText),
        'mezzo_targa': _nullIfEmpty(mezzoTarga),
        'mezzo_id_uuid': _nullIfEmpty(mezzoIdUuid),
        'multicard_id_uuid': _nullIfEmpty(multicardIdUuid),
        if (keep != null) 'id_uuid': keep['id_uuid'],
      };
    }

    final outgoing = previous.name;
    final outgoingDal = _nullIfEmpty(previous.dataInizioIso) ?? today;
    final outgoingAl = today;

    final newSlots = <int, Map<String, dynamic>?>{};
    newSlots[1] = slotFrom(
      1,
      assegnatario: outgoing,
      dal: outgoingDal,
      al: outgoingAl,
      noteText: note,
      keep: existing[1],
    );
    for (var i = 1; i <= 3; i++) {
      final src = existing[i];
      if (src == null || !_passaggioHasData(src)) {
        newSlots[i + 1] = null;
        continue;
      }
      newSlots[i + 1] = slotFrom(
        i + 1,
        assegnatario: _trim(src['assegnatario']),
        dal: _trim(src['periodo_dal']),
        al: _trim(src['periodo_al']),
        noteText: _trim(src['note']),
        keep: existing[i + 1],
      );
    }

    for (var p = 1; p <= 4; p++) {
      final slot = newSlots[p];
      final oldId = (existing[p]?['id_uuid'] ?? '').toString().trim();
      if (slot == null) {
        if (oldId.isNotEmpty) {
          await supa.from(table).delete().eq('id_uuid', oldId);
        }
        continue;
      }
      if (oldId.isEmpty) {
        await supa.from(table).insert(slot);
      } else {
        await supa.from(table).update(slot).eq('id_uuid', oldId);
      }
    }
  }

  static bool _passaggioHasData(Map<String, dynamic> p) {
    return _trim(p['assegnatario']).isNotEmpty ||
        _trim(p['periodo_dal']).isNotEmpty ||
        _trim(p['periodo_al']).isNotEmpty ||
        _trim(p['note']).isNotEmpty;
  }

  /// Gestisce cambio assegnatario su mezzo (+ telepass collegato).
  static Future<void> handleMezzoAssigneeOnSave({
    required SupabaseClient supa,
    required Map<String, dynamic>? previousRow,
    required String targa,
    String? mezzoIdUuid,
    required LogisticaAssigneeSnapshot next,
    String? telepass,
    String? note,
  }) async {
    final t = targa.trim();
    if (t.isEmpty) return;

    final prev = LogisticaAssigneeSnapshot.fromMezzoRow(previousRow);
    final changed = assigneeChanged(prev, next);

    if (changed && prev.hasAssignee) {
      await archiveAssigneeChange(
        supa: supa,
        tipoAsset: tipoMezzo,
        identificativo: t,
        previous: prev,
        mezzoTarga: t,
        mezzoIdUuid: mezzoIdUuid,
        note: note,
      );
      if (!isTelepassVuoto(telepass)) {
        await archiveAssigneeChange(
          supa: supa,
          tipoAsset: tipoTelepass,
          identificativo: telepass!.trim(),
          previous: prev,
          mezzoTarga: t,
          mezzoIdUuid: mezzoIdUuid,
          note: note,
        );
      }
    }

  }

  /// Gestisce cambio assegnatario su multicard.
  static Future<void> handleMulticardAssigneeOnSave({
    required SupabaseClient supa,
    required Map<String, dynamic>? previousRow,
    required String multicard,
    required String mezzoTarga,
    String? mezzoIdUuid,
    String? multicardIdUuid,
    required LogisticaAssigneeSnapshot next,
    String? note,
  }) async {
    final mc = multicard.trim();
    if (mc.isEmpty) return;

    final prev = LogisticaAssigneeSnapshot.fromMulticardRow(previousRow);
    if (assigneeChanged(prev, next) && prev.hasAssignee) {
      await archiveAssigneeChange(
        supa: supa,
        tipoAsset: tipoMulticard,
        identificativo: mc,
        previous: prev,
        mezzoTarga: mezzoTarga,
        mezzoIdUuid: mezzoIdUuid,
        multicardIdUuid: multicardIdUuid,
        note: note,
      );
    }

  }

  /// Gestisce cambio assegnatario su telepass.
  static Future<void> handleTelepassAssigneeOnSave({
    required SupabaseClient supa,
    required Map<String, dynamic>? previousRow,
    required String telepass,
    required String mezzoTarga,
    String? mezzoIdUuid,
    required LogisticaAssigneeSnapshot next,
    String? note,
  }) async {
    final tp = telepass.trim();
    if (tp.isEmpty || isTelepassVuoto(tp)) return;

    final prev = LogisticaAssigneeSnapshot.fromTelepassRow(previousRow);
    if (assigneeChanged(prev, next) && prev.hasAssignee) {
      await archiveAssigneeChange(
        supa: supa,
        tipoAsset: tipoTelepass,
        identificativo: tp,
        previous: prev,
        mezzoTarga: mezzoTarga,
        mezzoIdUuid: mezzoIdUuid,
        note: note,
      );
    }
  }

  /// Data inizio da usare nel payload dopo salvataggio.
  static String? resolveDataInizioOnSave({
    required LogisticaAssigneeSnapshot? previous,
    required LogisticaAssigneeSnapshot next,
    String? manualInizioIso,
  }) {
    if (!next.hasAssignee) return null;
    if (assigneeChanged(previous, next)) return todayIsoDate();
    return manualInizioIso?.trim().isEmpty ?? true
        ? (previous?.dataInizioIso?.trim().isEmpty ?? true
            ? todayIsoDate()
            : previous!.dataInizioIso)
        : manualInizioIso;
  }

  static Future<void> ensureForMezzo({
    required SupabaseClient supa,
    required String targa,
    String? mezzoIdUuid,
    String? telepass,
  }) async {
    final t = targa.trim();
    if (t.isEmpty) return;

    await ensureRegistry(
      supa: supa,
      tipoAsset: tipoMezzo,
      identificativo: t,
      mezzoTarga: t,
      mezzoIdUuid: mezzoIdUuid,
    );

    if (!isTelepassVuoto(telepass)) {
      await ensureRegistry(
        supa: supa,
        tipoAsset: tipoTelepass,
        identificativo: telepass!.trim(),
        mezzoTarga: t,
        mezzoIdUuid: mezzoIdUuid,
      );
    }
  }

  static Future<void> ensureForMulticard({
    required SupabaseClient supa,
    required String multicard,
    required String mezzoTarga,
    String? mezzoIdUuid,
    String? multicardIdUuid,
  }) async {
    final mc = multicard.trim();
    final targa = mezzoTarga.trim();
    if (mc.isEmpty) return;

    await ensureRegistry(
      supa: supa,
      tipoAsset: tipoMulticard,
      identificativo: mc,
      mezzoTarga: targa.isEmpty ? null : targa,
      mezzoIdUuid: mezzoIdUuid,
      multicardIdUuid: multicardIdUuid,
    );
  }

  static Future<void> ensureForTelepass({
    required SupabaseClient supa,
    required String telepass,
    required String mezzoTarga,
    String? mezzoIdUuid,
  }) async {
    final tp = telepass.trim();
    final targa = mezzoTarga.trim();
    if (tp.isEmpty || isTelepassVuoto(tp)) return;

    await ensureRegistry(
      supa: supa,
      tipoAsset: tipoTelepass,
      identificativo: tp,
      mezzoTarga: targa.isEmpty ? null : targa,
      mezzoIdUuid: mezzoIdUuid,
    );
  }

  static String? _nullIfEmpty(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? null : s;
  }
}
