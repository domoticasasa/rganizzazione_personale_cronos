import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/logistica_mdo_dotazioni.dart';
import '../utils/date_formatters.dart';

class MdoCheckRiepilogoEntry {
  const MdoCheckRiepilogoEntry({
    required this.mdoIdUuid,
    required this.matricolaInterna,
    required this.targaRfi,
    required this.descrizioneMezzo,
    required this.commessa,
    required this.dtNome,
    required this.cantiere,
    required this.tipoCheck,
    required this.isCheckGenerale,
    this.checkedAt,
    this.checkedByUserUuid,
    this.checkedByName,
  });

  final String mdoIdUuid;
  final String matricolaInterna;
  final String targaRfi;
  final String descrizioneMezzo;
  final String commessa;
  final String dtNome;
  final String cantiere;
  final String tipoCheck;
  final bool isCheckGenerale;
  final DateTime? checkedAt;
  final String? checkedByUserUuid;
  final String? checkedByName;

  String get mezzoLabel {
    final m = matricolaInterna.trim();
    if (m.isNotEmpty) return m;
    return targaRfi.trim();
  }

  String get checkedAtLabel {
    if (checkedAt == null) return '—';
    return formatDateTimeItFromSupabase(checkedAt!.toUtc().toIso8601String());
  }

  String get assegnatarioDisplay {
    final dt = dtNome.trim();
    if (dt.isNotEmpty) return dt;
    return '—';
  }

  String get operatoreDisplay {
    final n = (checkedByName ?? '').trim();
    if (n.isNotEmpty) return n;
    final u = (checkedByUserUuid ?? '').trim();
    return u.isEmpty ? '—' : u;
  }
}

/// Un mezzo MDO con tutti i check registrati (vista compatta espandibile).
class MdoCheckRiepilogoGruppo {
  MdoCheckRiepilogoGruppo({
    required this.mdoIdUuid,
    required this.mezzoLabel,
    required this.descrizioneMezzo,
    required this.commessa,
    required this.dtNome,
    required this.cantiere,
    required this.checks,
  });

  final String mdoIdUuid;
  final String mezzoLabel;
  final String descrizioneMezzo;
  final String commessa;
  final String dtNome;
  final String cantiere;
  final List<MdoCheckRiepilogoEntry> checks;

  bool get hasCheckGenerale => checks.any((c) => c.isCheckGenerale);

  int get dotazioniCount => checks.where((c) => !c.isCheckGenerale).length;

  DateTime? get ultimoCheckAt {
    DateTime? latest;
    for (final c in checks) {
      final t = c.checkedAt;
      if (t == null) continue;
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    return latest;
  }

  String get ultimoCheckLabel {
    final t = ultimoCheckAt;
    if (t == null) return '—';
    return formatDateTimeItFromSupabase(t.toUtc().toIso8601String());
  }

  String get assegnatarioDisplay {
    final dt = dtNome.trim();
    return dt.isEmpty ? '—' : dt;
  }

  String get operatorePrincipale {
    final gen = checks.where((c) => c.isCheckGenerale).firstOrNull;
    if (gen != null) return gen.operatoreDisplay;
    for (final c in checks) {
      if (c.operatoreDisplay != '—') return c.operatoreDisplay;
    }
    return '—';
  }

  String get riepilogoCheckLabel {
    final parts = <String>[];
    if (hasCheckGenerale) parts.add('Check generale');
    final n = dotazioniCount;
    if (n > 0) parts.add('$n dotazion${n == 1 ? 'e' : 'i'}');
    if (parts.isEmpty) return 'Nessun dettaglio';
    return parts.join(' · ');
  }

  /// Raggruppa per mezzo; ordine per ultimo check decrescente.
  static List<MdoCheckRiepilogoGruppo> raggruppaPerMezzo(
    List<MdoCheckRiepilogoEntry> entries,
  ) {
    final byMdo = <String, List<MdoCheckRiepilogoEntry>>{};
    for (final e in entries) {
      final id = e.mdoIdUuid.trim();
      if (id.isEmpty) continue;
      byMdo.putIfAbsent(id, () => <MdoCheckRiepilogoEntry>[]).add(e);
    }

    final groups = <MdoCheckRiepilogoGruppo>[];
    for (final list in byMdo.values) {
      if (list.isEmpty) continue;
      list.sort(_ordinaCheckNelGruppo);
      final head = list.first;
      groups.add(
        MdoCheckRiepilogoGruppo(
          mdoIdUuid: head.mdoIdUuid,
          mezzoLabel: head.mezzoLabel,
          descrizioneMezzo: head.descrizioneMezzo,
          commessa: head.commessa,
          dtNome: head.dtNome,
          cantiere: head.cantiere,
          checks: List<MdoCheckRiepilogoEntry>.from(list),
        ),
      );
    }

    groups.sort((a, b) {
      final ta = a.ultimoCheckAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.ultimoCheckAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return groups;
  }

  static int _ordinaCheckNelGruppo(MdoCheckRiepilogoEntry a, MdoCheckRiepilogoEntry b) {
    if (a.isCheckGenerale != b.isCheckGenerale) {
      return a.isCheckGenerale ? -1 : 1;
    }
    final ta = a.checkedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = b.checkedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byDate = tb.compareTo(ta);
    if (byDate != 0) return byDate;
    return a.tipoCheck.toLowerCase().compareTo(b.tipoCheck.toLowerCase());
  }
}

class LogisticaMdoCheckRiepilogoService {
  LogisticaMdoCheckRiepilogoService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _mdoSelect =
      'id_uuid, matricola_interna, codice_identificativo_targa_rfi, '
      'descrizione_mezzo, commessa, dt_nome, cantiere_attuale, active, '
      'check_eseguito, check_confermato_at, check_confermato_by_user_uuid';

  Future<List<MdoCheckRiepilogoEntry>> fetchEntries() async {
    final selectCols = StringBuffer(_mdoSelect);
    for (final d in logisticaMdoDotazioni) {
      final key = d['key']!;
      final base = key.replaceAll('_check', '');
      selectCols.write(', $key, ${base}_checked_at, ${base}_checked_by_user_uuid');
    }

    final res = await _client
        .from('logistica_mdo_ferroviari')
        .select(selectCols.toString())
        .eq('active', true);

    final rows = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final userIds = <String>{};
    final entries = <MdoCheckRiepilogoEntry>[];

    for (final row in rows) {
      _collectUserIds(row, userIds);
    }

    final namesByUuid = await _loadUserNames(userIds);

    for (final row in rows) {
      entries.addAll(_entriesForRow(row, namesByUuid));
    }

    entries.sort((a, b) {
      final ta = a.checkedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.checkedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });

    return entries;
  }

  void _collectUserIds(Map<String, dynamic> row, Set<String> ids) {
    for (final id in [
      row['check_confermato_by_user_uuid'],
    ]) {
      final s = (id ?? '').toString().trim();
      if (s.isNotEmpty) ids.add(s);
    }
    for (final d in logisticaMdoDotazioni) {
      final key = d['key']!;
      final byCol = key.replaceAll('_check', '_checked_by_user_uuid');
      final s = (row[byCol] ?? '').toString().trim();
      if (s.isNotEmpty) ids.add(s);
    }
  }

  Future<Map<String, String>> _loadUserNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final list = ids.toList();
    final map = <String, String>{};
    const chunk = 200;
    for (var i = 0; i < list.length; i += chunk) {
      final part = list.sublist(i, i + chunk > list.length ? list.length : i + chunk);
      final res = await _client
          .from('users')
          .select('id_uuid, full_name, username')
          .inFilter('id_uuid', part);
      for (final raw in res as List) {
        final u = Map<String, dynamic>.from(raw as Map);
        final id = (u['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final full = (u['full_name'] ?? '').toString().trim();
        final user = (u['username'] ?? '').toString().trim();
        map[id] = full.isNotEmpty ? full : user;
      }
    }
    return map;
  }

  List<MdoCheckRiepilogoEntry> _entriesForRow(
    Map<String, dynamic> row,
    Map<String, String> namesByUuid,
  ) {
    final out = <MdoCheckRiepilogoEntry>[];
    final base = _baseFields(row);

    if ((row['check_eseguito'] ?? false) == true) {
      final byUuid = (row['check_confermato_by_user_uuid'] ?? '').toString().trim();
      out.add(
        MdoCheckRiepilogoEntry(
          mdoIdUuid: base.mdoIdUuid,
          matricolaInterna: base.matricolaInterna,
          targaRfi: base.targaRfi,
          descrizioneMezzo: base.descrizioneMezzo,
          commessa: base.commessa,
          dtNome: base.dtNome,
          cantiere: base.cantiere,
          tipoCheck: 'Check generale',
          isCheckGenerale: true,
          checkedAt: parseSupabaseTimestampToItaly(row['check_confermato_at']),
          checkedByUserUuid: byUuid.isEmpty ? null : byUuid,
          checkedByName: byUuid.isEmpty ? null : namesByUuid[byUuid],
        ),
      );
    }

    for (final d in logisticaMdoDotazioni) {
      final key = d['key']!;
      if ((row[key] ?? false) != true) continue;
      final baseKey = key.replaceAll('_check', '');
      final atCol = '${baseKey}_checked_at';
      final byCol = '${baseKey}_checked_by_user_uuid';
      final byUuid = (row[byCol] ?? '').toString().trim();
      out.add(
        MdoCheckRiepilogoEntry(
          mdoIdUuid: base.mdoIdUuid,
          matricolaInterna: base.matricolaInterna,
          targaRfi: base.targaRfi,
          descrizioneMezzo: base.descrizioneMezzo,
          commessa: base.commessa,
          dtNome: base.dtNome,
          cantiere: base.cantiere,
          tipoCheck: d['label'] ?? key,
          isCheckGenerale: false,
          checkedAt: parseSupabaseTimestampToItaly(row[atCol]),
          checkedByUserUuid: byUuid.isEmpty ? null : byUuid,
          checkedByName: byUuid.isEmpty ? null : namesByUuid[byUuid],
        ),
      );
    }

    return out;
  }

  ({
    String mdoIdUuid,
    String matricolaInterna,
    String targaRfi,
    String descrizioneMezzo,
    String commessa,
    String dtNome,
    String cantiere,
  }) _baseFields(Map<String, dynamic> row) {
    return (
      mdoIdUuid: (row['id_uuid'] ?? '').toString(),
      matricolaInterna: (row['matricola_interna'] ?? '').toString(),
      targaRfi: (row['codice_identificativo_targa_rfi'] ?? '').toString(),
      descrizioneMezzo: (row['descrizione_mezzo'] ?? '').toString(),
      commessa: (row['commessa'] ?? '').toString(),
      dtNome: (row['dt_nome'] ?? '').toString(),
      cantiere: (row['cantiere_attuale'] ?? '').toString(),
    );
  }

  /// Matrice export: ogni mezzo con check generale + tutte le dotazioni
  /// (Presente / Non presente), non solo quelle spuntate.
  Future<List<MdoCheckExportMezzo>> fetchExportMatrix() async {
    final selectCols = StringBuffer(_mdoSelect);
    for (final d in logisticaMdoDotazioni) {
      final key = d['key']!;
      final base = key.replaceAll('_check', '');
      selectCols.write(', $key, ${base}_checked_at, ${base}_checked_by_user_uuid');
    }

    final res = await _client
        .from('logistica_mdo_ferroviari')
        .select(selectCols.toString())
        .eq('active', true);

    final rows =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final userIds = <String>{};
    for (final row in rows) {
      _collectUserIds(row, userIds);
    }
    final namesByUuid = await _loadUserNames(userIds);

    final out = <MdoCheckExportMezzo>[];
    for (final row in rows) {
      final base = _baseFields(row);
      final mezzoLabel = base.matricolaInterna.trim().isNotEmpty
          ? base.matricolaInterna.trim()
          : base.targaRfi.trim();

      final items = <MdoCheckExportItem>[];
      final genPresent = (row['check_eseguito'] ?? false) == true;
      final genBy =
          (row['check_confermato_by_user_uuid'] ?? '').toString().trim();
      items.add(
        MdoCheckExportItem(
          tipo: 'Check generale',
          isCheckGenerale: true,
          presente: genPresent,
          checkedAt: parseSupabaseTimestampToItaly(row['check_confermato_at']),
          operatore: genBy.isEmpty ? '' : (namesByUuid[genBy] ?? genBy),
        ),
      );

      for (final d in logisticaMdoDotazioni) {
        final key = d['key']!;
        final presente = (row[key] ?? false) == true;
        final baseKey = key.replaceAll('_check', '');
        final byUuid =
            (row['${baseKey}_checked_by_user_uuid'] ?? '').toString().trim();
        items.add(
          MdoCheckExportItem(
            tipo: d['label'] ?? key,
            isCheckGenerale: false,
            presente: presente,
            checkedAt:
                parseSupabaseTimestampToItaly(row['${baseKey}_checked_at']),
            operatore: byUuid.isEmpty ? '' : (namesByUuid[byUuid] ?? byUuid),
          ),
        );
      }

      out.add(
        MdoCheckExportMezzo(
          mdoIdUuid: base.mdoIdUuid,
          mezzoLabel: mezzoLabel.isEmpty ? '—' : mezzoLabel,
          descrizioneMezzo: base.descrizioneMezzo,
          commessa: base.commessa,
          dtNome: base.dtNome,
          cantiere: base.cantiere,
          items: items,
        ),
      );
    }

    out.sort((a, b) => a.mezzoLabel.toLowerCase().compareTo(b.mezzoLabel.toLowerCase()));
    return out;
  }
}

class MdoCheckExportMezzo {
  const MdoCheckExportMezzo({
    required this.mdoIdUuid,
    required this.mezzoLabel,
    required this.descrizioneMezzo,
    required this.commessa,
    required this.dtNome,
    required this.cantiere,
    required this.items,
  });

  final String mdoIdUuid;
  final String mezzoLabel;
  final String descrizioneMezzo;
  final String commessa;
  final String dtNome;
  final String cantiere;
  final List<MdoCheckExportItem> items;
}

class MdoCheckExportItem {
  const MdoCheckExportItem({
    required this.tipo,
    required this.isCheckGenerale,
    required this.presente,
    this.checkedAt,
    this.operatore = '',
  });

  final String tipo;
  final bool isCheckGenerale;
  final bool presente;
  final DateTime? checkedAt;
  final String operatore;

  String get statoLabel => presente ? 'Presente' : 'Non presente';

  String get checkedAtLabel {
    if (checkedAt == null) return '';
    return formatDateTimeItFromSupabase(checkedAt!.toUtc().toIso8601String());
  }
}
