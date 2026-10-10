import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/buoni_pasto_qr_payload.dart';
import '../utils/personale_name_matcher.dart';

class BuoniPastoRistoranteRow {
  const BuoniPastoRistoranteRow({
    required this.structureIdUuid,
    required this.nome,
    this.indirizzo,
    this.email,
    this.qrConfigId,
    this.qrToken,
    this.qrAttivo = false,
    this.strutturaAttiva = true,
    this.operatori = const [],
  });

  final String structureIdUuid;
  final String nome;
  final String? indirizzo;
  final String? email;
  final String? qrConfigId;
  final String? qrToken;
  final bool qrAttivo;
  final bool strutturaAttiva;
  final List<BuoniPastoOperatoreRow> operatori;

  bool get hasQr => (qrToken ?? '').trim().isNotEmpty;
}

class BuoniPastoOperatoreRow {
  const BuoniPastoOperatoreRow({
    required this.idUuid,
    required this.userIdUuid,
    required this.username,
    required this.email,
    required this.fullName,
    this.attivo = true,
  });

  final String idUuid;
  final String userIdUuid;
  final String username;
  final String email;
  final String fullName;
  final bool attivo;
}

class BuoniPastoRegistrazioneResult {
  const BuoniPastoRegistrazioneResult({
    required this.structureName,
    required this.dipendenteNome,
    required this.dataPasto,
    required this.tipoPasto,
    required this.registratoAt,
  });

  final String structureName;
  final String dipendenteNome;
  final DateTime dataPasto;
  final String tipoPasto;
  final DateTime registratoAt;

  factory BuoniPastoRegistrazioneResult.fromMap(Map<String, dynamic> m) {
    final dataRaw = (m['data_pasto'] ?? '').toString();
    final registratoRaw = (m['registrato_at'] ?? '').toString();
    return BuoniPastoRegistrazioneResult(
      structureName: (m['structure_name'] ?? '').toString(),
      dipendenteNome: (m['dipendente_nome'] ?? '').toString(),
      dataPasto: DateTime.tryParse(dataRaw) ??
          DateTime.tryParse('${dataRaw}T00:00:00') ??
          DateTime.now(),
      tipoPasto: (m['tipo_pasto'] ?? '').toString(),
      registratoAt: DateTime.tryParse(registratoRaw) ?? DateTime.now(),
    );
  }
}

class BuoniPastoStatoOggi {
  const BuoniPastoStatoOggi({
    required this.dataPasto,
    required this.tipoCorrente,
    required this.pranzoRegistrato,
    required this.cenaRegistrata,
  });

  final DateTime dataPasto;
  final String tipoCorrente;
  final bool pranzoRegistrato;
  final bool cenaRegistrata;

  bool get giaRegistratoTipoCorrente =>
      tipoCorrente == 'cena' ? cenaRegistrata : pranzoRegistrato;

  bool registratoPerTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'cena':
        return cenaRegistrata;
      case 'pranzo':
      default:
        return pranzoRegistrato;
    }
  }

  factory BuoniPastoStatoOggi.fromMap(Map<String, dynamic> m) {
    final dataRaw = (m['data_pasto'] ?? '').toString();
    return BuoniPastoStatoOggi(
      dataPasto: DateTime.tryParse(dataRaw) ??
          DateTime.tryParse('${dataRaw}T00:00:00') ??
          DateTime.now(),
      tipoCorrente: (m['tipo_corrente'] ?? 'pranzo').toString(),
      pranzoRegistrato: m['pranzo_registrato'] == true,
      cenaRegistrata: m['cena_registrata'] == true,
    );
  }
}

abstract final class BuoniPastoService {
  BuoniPastoService._();

  static Future<void> syncRistorantiDaStructures(SupabaseClient supa) async {
    try {
      await supa.rpc('sync_buoni_pasto_ristoranti_da_structures');
    } catch (_) {}
  }

  static Future<List<BuoniPastoRistoranteRow>> loadRistoranti(
    SupabaseClient supa,
  ) async {
    await syncRistorantiDaStructures(supa);

    final structuresRes = await supa
        .from('structures')
        .select('id_uuid, name, address, email, active, is_ristorante')
        .eq('is_ristorante', true)
        .order('name');

    final qrRes = await supa
        .from('buoni_pasto_ristoranti')
        .select('id_uuid, structure_id_uuid, qr_token, attivo');

    final opRes = await supa
        .from('buoni_pasto_operatori')
        .select('id_uuid, structure_id_uuid, user_id_uuid, attivo');

    final usersRes = await supa.from('users').select('id_uuid, username, email, full_name');
    final usersByUuid = <String, Map<String, dynamic>>{};
    for (final raw in usersRes as List) {
      final u = Map<String, dynamic>.from(raw as Map);
      final id = (u['id_uuid'] ?? '').toString();
      if (id.isNotEmpty) usersByUuid[id] = u;
    }

    final qrByStructure = <String, Map<String, dynamic>>{};
    for (final raw in qrRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final sid = (m['structure_id_uuid'] ?? '').toString();
      if (sid.isNotEmpty) qrByStructure[sid] = m;
    }

    final opsByStructure = <String, List<BuoniPastoOperatoreRow>>{};
    for (final raw in opRes as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final sid = (m['structure_id_uuid'] ?? '').toString();
      if (sid.isEmpty) continue;
      final userId = (m['user_id_uuid'] ?? '').toString();
      final u = usersByUuid[userId] ?? const <String, dynamic>{};
      opsByStructure.putIfAbsent(sid, () => []).add(
            BuoniPastoOperatoreRow(
              idUuid: (m['id_uuid'] ?? '').toString(),
              userIdUuid: (m['user_id_uuid'] ?? '').toString(),
              username: (u['username'] ?? '').toString(),
              email: (u['email'] ?? '').toString(),
              fullName: (u['full_name'] ?? '').toString(),
              attivo: m['attivo'] == true,
            ),
          );
    }

    return (structuresRes as List).map((raw) {
      final s = Map<String, dynamic>.from(raw as Map);
      final sid = (s['id_uuid'] ?? '').toString();
      final qr = qrByStructure[sid];
      return BuoniPastoRistoranteRow(
        structureIdUuid: sid,
        nome: (s['name'] ?? '').toString(),
        indirizzo: (s['address'] ?? '').toString(),
        email: (s['email'] ?? '').toString(),
        qrConfigId: qr == null ? null : (qr['id_uuid'] ?? '').toString(),
        qrToken: qr == null ? null : (qr['qr_token'] ?? '').toString(),
        qrAttivo: qr?['attivo'] == true,
        strutturaAttiva: (s['active'] ?? true) == true,
        operatori: opsByStructure[sid] ?? const [],
      );
    }).toList(growable: false);
  }

  static Future<String> ensureQrToken(
    SupabaseClient supa,
    String structureIdUuid,
  ) async {
    final existing = await supa
        .from('buoni_pasto_ristoranti')
        .select('id_uuid, qr_token')
        .eq('structure_id_uuid', structureIdUuid)
        .maybeSingle();
    if (existing != null) {
      return (existing['qr_token'] ?? '').toString();
    }
    final inserted = await supa
        .from('buoni_pasto_ristoranti')
        .insert({'structure_id_uuid': structureIdUuid, 'attivo': true})
        .select('qr_token')
        .single();
    return (inserted['qr_token'] ?? '').toString();
  }

  static Future<String> regenerateQrToken(
    SupabaseClient supa,
    String structureIdUuid,
  ) async {
    await ensureQrToken(supa, structureIdUuid);
    final token = _randomToken();
    await supa
        .from('buoni_pasto_ristoranti')
        .update({'qr_token': token, 'attivo': true})
        .eq('structure_id_uuid', structureIdUuid);
    return token;
  }

  static String _randomToken() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${now}_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
  }

  static Future<void> setQrAttivo(
    SupabaseClient supa,
    String structureIdUuid,
    bool attivo,
  ) async {
    await ensureQrToken(supa, structureIdUuid);
    await supa
        .from('buoni_pasto_ristoranti')
        .update({'attivo': attivo})
        .eq('structure_id_uuid', structureIdUuid);
  }

  static Future<Map<String, dynamic>> createOperatore({
    required SupabaseClient supa,
    required String structureIdUuid,
    required String email,
    required String password,
    String? username,
    String? fullName,
  }) async {
    final jwt = supa.auth.currentSession?.accessToken;
    if (jwt == null) throw Exception('Sessione scaduta');

    final res = await supa.functions.invoke(
      'admin-create-ristoratore',
      body: {
        'email': email.trim(),
        'password': password.trim(),
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
        'structure_id_uuid': structureIdUuid,
      },
      headers: {'Authorization': 'Bearer $jwt'},
    );

    final data = res.data;
    if (data is Map) {
      if (data['ok'] == true) return Map<String, dynamic>.from(data);
      final err = (data['error'] ?? data['details'] ?? '').toString().trim();
      if (err.isNotEmpty) throw Exception(err);
    }
    if (res.status >= 400) {
      throw Exception('admin-create-ristoratore HTTP ${res.status}');
    }
    throw Exception('Creazione operatore non riuscita');
  }

  static Future<BuoniPastoRegistrazioneResult> registraScansione(
    SupabaseClient supa,
    String rawQr, {
    double? latitudine,
    double? longitudine,
  }) async {
    final token = parseBuoniPastoQrToken(rawQr);
    if (token == null || token.isEmpty) {
      throw Exception('QR code non valido.');
    }
    try {
      final res = await supa.rpc(
        'registra_buono_pasto',
        params: {
          'p_qr_token': encodeBuoniPastoQrPayload(token),
          'p_latitudine': latitudine,
          'p_longitudine': longitudine,
        },
      );
      if (res is! Map) {
        throw Exception('Risposta registrazione non valida.');
      }
      return BuoniPastoRegistrazioneResult.fromMap(
        Map<String, dynamic>.from(res),
      );
    } on PostgrestException catch (e) {
      throw Exception(_friendlyRegistrazioneError(e.message));
    }
  }

  static Future<BuoniPastoStatoOggi> loadStatoOggi(SupabaseClient supa) async {
    try {
      final res = await supa.rpc('stato_buoni_pasto_oggi');
      if (res is Map) {
        return BuoniPastoStatoOggi.fromMap(Map<String, dynamic>.from(res));
      }
    } catch (_) {}
    final now = DateTime.now();
    return BuoniPastoStatoOggi(
      dataPasto: DateTime(now.year, now.month, now.day),
      tipoCorrente: tipoPastoFromHour(now.hour),
      pranzoRegistrato: false,
      cenaRegistrata: false,
    );
  }

  static String _friendlyRegistrazioneError(String raw) {
    final msg = raw.trim();
    if (msg.isEmpty) return 'Registrazione non riuscita.';
    if (msg.contains('già registrato')) return msg;
    if (msg.contains('unique_violation') ||
        msg.contains('buoni_pasto_registrazioni_unique_giorno')) {
      return 'Hai già registrato questo pasto per oggi.';
    }
    return msg;
  }

  static Future<List<Map<String, dynamic>>> loadRegistrazioni({
    required SupabaseClient supa,
    String? structureIdUuid,
    String? personaleIdUuid,
    DateTime? dal,
    DateTime? al,
  }) async {
    var q = supa.from('buoni_pasto_registrazioni').select(
          'id_uuid, structure_id_uuid, personale_id_uuid, dipendente_nome, '
          'registrato_at, data_pasto, tipo_pasto, latitudine, longitudine, '
          'structures(name)',
        );
    if (structureIdUuid != null && structureIdUuid.isNotEmpty) {
      q = q.eq('structure_id_uuid', structureIdUuid);
    }
    if (personaleIdUuid != null && personaleIdUuid.isNotEmpty) {
      q = q.eq('personale_id_uuid', personaleIdUuid);
    }
    if (dal != null) {
      q = q.gte('data_pasto', _dateStr(dal));
    }
    if (al != null) {
      q = q.lte('data_pasto', _dateStr(al));
    }
    final res = await q.order('registrato_at', ascending: false);
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  static Future<String?> loadRistoratoreStructureId(SupabaseClient supa) async {
    final res = await supa.rpc('current_ristoratore_structure_uuid');
    if (res == null) return null;
    final s = res.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime startOfWeek(DateTime d) {
    final local = dateOnly(d);
    return local.subtract(Duration(days: local.weekday - 1));
  }

  static DateTime endOfWeek(DateTime d) =>
      startOfWeek(d).add(const Duration(days: 6));

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  static DateTime endOfMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 0);

  static List<DateTime> daysInRange(DateTime dal, DateTime al) {
    final days = <DateTime>[];
    var cur = dateOnly(dal);
    final end = dateOnly(al);
    while (!cur.isAfter(end)) {
      days.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return days;
  }

  static Future<BuoniPastoPresenzeReport> loadPresenzeReport({
    required SupabaseClient supa,
    required DateTime dal,
    required DateTime al,
    bool soloAttivi = true,
  }) async {
    final dalNorm = dateOnly(dal);
    final alNorm = dateOnly(al);
    final giorni = daysInRange(dalNorm, alNorm);

    final personaleRes = soloAttivi
        ? await supa
            .from('personale')
            .select('id_uuid, full_name, matricola, active')
            .eq('active', true)
            .order('full_name', ascending: true)
        : await supa
            .from('personale')
            .select('id_uuid, full_name, matricola, active')
            .order('full_name', ascending: true);
    final registrazioni = await loadRegistrazioni(
      supa: supa,
      dal: dalNorm,
      al: alNorm,
    );

    final pastiByPersonale = <String, Map<String, BuoniPastoGiornoPasti>>{};
    for (final raw in registrazioni) {
      final r = Map<String, dynamic>.from(raw);
      final pid = (r['personale_id_uuid'] ?? '').toString();
      if (pid.isEmpty) continue;
      final dataStr = (r['data_pasto'] ?? '').toString();
      if (dataStr.length < 10) continue;
      final tipo = (r['tipo_pasto'] ?? '').toString().toLowerCase();
      final structure = r['structures'];
      final ristorante = structure is Map
          ? (structure['name'] ?? '').toString()
          : '';
      final byDay = pastiByPersonale.putIfAbsent(pid, () => {});
      final cell = byDay.putIfAbsent(
        dataStr.substring(0, 10),
        () => const BuoniPastoGiornoPasti(),
      );
      byDay[dataStr.substring(0, 10)] = cell.copyWith(
        pranzo: cell.pranzo || tipo == 'pranzo',
        cena: cell.cena || tipo == 'cena',
        pranzoRistorante: tipo == 'pranzo' && ristorante.isNotEmpty
            ? ristorante
            : cell.pranzoRistorante,
        cenaRistorante: tipo == 'cena' && ristorante.isNotEmpty
            ? ristorante
            : cell.cenaRistorante,
      );
    }

    final dipendenti = (personaleRes as List).map((raw) {
      final p = Map<String, dynamic>.from(raw as Map);
      final pid = (p['id_uuid'] ?? '').toString();
      return BuoniPastoDipendentePresenza(
        personaleIdUuid: pid,
        nome: (p['full_name'] ?? '').toString().trim(),
        matricola: (p['matricola'] ?? '').toString().trim(),
        pastiPerGiorno: pastiByPersonale[pid] ?? const {},
      );
    }).toList();
    dipendenti.sort((a, b) {
      final an = PersonaleNameMatcher.normalize(a.nome);
      final bn = PersonaleNameMatcher.normalize(b.nome);
      final byName = an.compareTo(bn);
      if (byName != 0) return byName;
      final am = (a.matricola ?? '').trim();
      final bm = (b.matricola ?? '').trim();
      return am.compareTo(bm);
    });

    return BuoniPastoPresenzeReport(
      dal: dalNorm,
      al: alNorm,
      giorni: giorni,
      dipendenti: dipendenti,
    );
  }
}

class BuoniPastoGiornoPasti {
  const BuoniPastoGiornoPasti({
    this.pranzo = false,
    this.cena = false,
    this.pranzoRistorante,
    this.cenaRistorante,
  });

  final bool pranzo;
  final bool cena;
  final String? pranzoRistorante;
  final String? cenaRistorante;

  bool get haPasto => pranzo || cena;

  String get riepilogo {
    if (pranzo && cena) return 'P+C';
    if (pranzo) return 'P';
    if (cena) return 'C';
    return '—';
  }

  BuoniPastoGiornoPasti copyWith({
    bool? pranzo,
    bool? cena,
    String? pranzoRistorante,
    String? cenaRistorante,
  }) {
    return BuoniPastoGiornoPasti(
      pranzo: pranzo ?? this.pranzo,
      cena: cena ?? this.cena,
      pranzoRistorante: pranzoRistorante ?? this.pranzoRistorante,
      cenaRistorante: cenaRistorante ?? this.cenaRistorante,
    );
  }
}

class BuoniPastoDipendentePresenza {
  const BuoniPastoDipendentePresenza({
    required this.personaleIdUuid,
    required this.nome,
    this.matricola,
    this.pastiPerGiorno = const {},
  });

  final String personaleIdUuid;
  final String nome;
  final String? matricola;
  final Map<String, BuoniPastoGiornoPasti> pastiPerGiorno;

  int countPastiIn(List<DateTime> giorni) {
    var n = 0;
    for (final g in giorni) {
      final key = BuoniPastoService._dateStr(g);
      final cell = pastiPerGiorno[key];
      if (cell == null) continue;
      if (cell.pranzo) n++;
      if (cell.cena) n++;
    }
    return n;
  }
}

class BuoniPastoPresenzeReport {
  const BuoniPastoPresenzeReport({
    required this.dal,
    required this.al,
    required this.giorni,
    required this.dipendenti,
  });

  final DateTime dal;
  final DateTime al;
  final List<DateTime> giorni;
  final List<BuoniPastoDipendentePresenza> dipendenti;
}
