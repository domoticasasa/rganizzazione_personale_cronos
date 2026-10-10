import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/date_formatters.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import 'mezzi_km_service.dart';

class ViaggioMezzoScansioneStato {
  const ViaggioMezzoScansioneStato({
    required this.azioneAttesa,
    required this.mezzoIdUuid,
    required this.targa,
    this.marca,
    this.modello,
    this.kmAttuali,
    this.messaggio,
    this.viaggioIdUuid,
    this.kmPartenza,
    this.iniziatoAt,
  });

  final String azioneAttesa;
  final String mezzoIdUuid;
  final String targa;
  final String? marca;
  final String? modello;
  final int? kmAttuali;
  final String? messaggio;
  final String? viaggioIdUuid;
  final int? kmPartenza;
  final DateTime? iniziatoAt;

  bool get isBloccato => azioneAttesa == 'bloccato';
  bool get isApertura => azioneAttesa == 'apertura';
  bool get isChiusura => azioneAttesa == 'chiusura';

  String get mezzoLabel => mezzoLabelFromParts(
        targa: targa,
        marca: marca,
        modello: modello,
      );

  factory ViaggioMezzoScansioneStato.fromMap(Map<String, dynamic> m) {
    return ViaggioMezzoScansioneStato(
      azioneAttesa: (m['azione_attesa'] ?? '').toString(),
      mezzoIdUuid: (m['mezzo_id_uuid'] ?? '').toString(),
      targa: (m['targa'] ?? '').toString(),
      marca: (m['marca'] ?? '').toString(),
      modello: (m['modello'] ?? '').toString(),
      kmAttuali: MezziKmService.parseKmOreValue(m['km_attuali']),
      messaggio: (m['messaggio'] ?? '').toString().trim().isEmpty
          ? null
          : (m['messaggio'] ?? '').toString(),
      viaggioIdUuid: (m['viaggio_id_uuid'] ?? '').toString().trim().isEmpty
          ? null
          : (m['viaggio_id_uuid'] ?? '').toString(),
      kmPartenza: MezziKmService.parseKmOreValue(m['km_partenza']),
      iniziatoAt: parseSupabaseTimestampToItaly(m['iniziato_at']),
    );
  }
}

class ViaggioMezzoRegistrazioneResult {
  const ViaggioMezzoRegistrazioneResult({
    required this.azione,
    required this.mezzoLabel,
    required this.targa,
    required this.conducenteNome,
    required this.kmPartenza,
    this.kmArrivo,
    this.kmPercorsi,
    this.iniziatoAt,
    this.chiusoAt,
  });

  final String azione;
  final String mezzoLabel;
  final String targa;
  final String conducenteNome;
  final int kmPartenza;
  final int? kmArrivo;
  final int? kmPercorsi;
  final DateTime? iniziatoAt;
  final DateTime? chiusoAt;

  bool get isChiusura => azione == 'chiusura';

  factory ViaggioMezzoRegistrazioneResult.fromMap(Map<String, dynamic> m) {
    return ViaggioMezzoRegistrazioneResult(
      azione: (m['azione'] ?? '').toString(),
      mezzoLabel: mezzoLabelFromParts(
        targa: (m['targa'] ?? '').toString(),
        marca: (m['marca'] ?? '').toString(),
        modello: (m['modello'] ?? '').toString(),
      ),
      targa: (m['targa'] ?? '').toString(),
      conducenteNome: (m['conducente_nome'] ?? '').toString(),
      kmPartenza: MezziKmService.parseKmOreValue(m['km_partenza']) ?? 0,
      kmArrivo: MezziKmService.parseKmOreValue(m['km_arrivo']),
      kmPercorsi: MezziKmService.parseKmOreValue(m['km_percorsi']),
      iniziatoAt: parseSupabaseTimestampToItaly(m['iniziato_at']),
      chiusoAt: parseSupabaseTimestampToItaly(m['chiuso_at']),
    );
  }
}

abstract final class ViaggiMezziStradaliService {
  ViaggiMezziStradaliService._();

  static Future<ViaggioMezzoScansioneStato> loadStatoScansione(
    SupabaseClient supa,
    String rawQr,
  ) async {
    final token = parseViaggiMezziQrToken(rawQr);
    if (token == null || token.isEmpty) {
      throw Exception('QR code non valido.');
    }
    final res = await supa.rpc(
      'stato_viaggio_mezzo_scansione',
      params: {'p_qr_token': encodeViaggiMezziQrPayload(token)},
    );
    if (res is! Map) throw Exception('Risposta scansione non valida.');
    return ViaggioMezzoScansioneStato.fromMap(
      Map<String, dynamic>.from(res),
    );
  }

  static Future<ViaggioMezzoRegistrazioneResult> registraScansione(
    SupabaseClient supa,
    String rawQr,
    int km, {
    double? latitudine,
    double? longitudine,
  }) async {
    final token = parseViaggiMezziQrToken(rawQr);
    if (token == null || token.isEmpty) {
      throw Exception('QR code non valido.');
    }
    try {
      final res = await supa.rpc(
        'registra_scansione_viaggio_mezzo',
        params: {
          'p_qr_token': encodeViaggiMezziQrPayload(token),
          'p_km': km,
          'p_latitudine': latitudine,
          'p_longitudine': longitudine,
        },
      );
      if (res is! Map) throw Exception('Risposta registrazione non valida.');
      return ViaggioMezzoRegistrazioneResult.fromMap(
        Map<String, dynamic>.from(res),
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message.trim().isEmpty ? 'Registrazione non riuscita.' : e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> loadViaggi({
    required SupabaseClient supa,
    DateTime? dal,
    DateTime? al,
    String? mezzoIdUuid,
    String? conducenteUserUuid,
    bool soloMieiMezziAssegnatario = false,
    bool soloMieiViaggi = false,
  }) async {
    var q = supa.from('logistica_mezzi_stradali_viaggi').select(
          'id_uuid, mezzo_id_uuid, conducente_user_uuid, conducente_nome, stato, '
          'km_partenza, km_arrivo, km_percorsi, iniziato_at, chiuso_at, '
          'lat_inizio, lon_inizio, lat_fine, lon_fine, '
          'logistica_mezzi_stradali(targa,marca,modello,assegnatario_attuale,assegnatario_user_uuid)',
        );
    if (dal != null) {
      q = q.gte('iniziato_at', _dateStartIso(dal));
    }
    if (al != null) {
      q = q.lte('iniziato_at', _dateEndIso(al));
    }
    if (mezzoIdUuid != null && mezzoIdUuid.isNotEmpty) {
      q = q.eq('mezzo_id_uuid', mezzoIdUuid);
    }
    if (conducenteUserUuid != null && conducenteUserUuid.isNotEmpty) {
      q = q.eq('conducente_user_uuid', conducenteUserUuid);
    }
    final res = await q.order('iniziato_at', ascending: false);
    var rows = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    if (soloMieiViaggi) {
      final myUuid = await _currentUserUuid(supa);
      if (myUuid != null) {
        rows = rows
            .where((r) => (r['conducente_user_uuid'] ?? '').toString() == myUuid)
            .toList(growable: false);
      }
    }

    if (soloMieiMezziAssegnatario) {
      final myUuid = await _currentUserUuid(supa);
      if (myUuid != null) {
        rows = rows.where((r) {
          final mezzo = r['logistica_mezzi_stradali'];
          if (mezzo is! Map) return false;
          return (mezzo['assegnatario_user_uuid'] ?? '').toString() == myUuid;
        }).toList(growable: false);
      }
    }

    return rows;
  }

  static Future<String?> ensureQrToken(SupabaseClient supa, String mezzoIdUuid) async {
    try {
      final res = await supa.rpc(
        'ensure_mezzo_viaggio_qr_token',
        params: {'p_mezzo_id_uuid': mezzoIdUuid},
      );
      final token = res?.toString().trim() ?? '';
      return token.isEmpty ? null : token;
    } on PostgrestException catch (e) {
      throw Exception(e.message.trim().isEmpty ? 'QR non disponibile.' : e.message);
    }
  }

  static Future<String?> _currentUserUuid(SupabaseClient supa) async {
    final res = await supa.rpc('current_user_uuid');
    if (res == null) return null;
    final s = res.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String _dateStartIso(DateTime d) =>
      supabaseFilterItalyDayStartUtcIso(d.year, d.month, d.day);

  static String _dateEndIso(DateTime d) =>
      supabaseFilterItalyDayEndUtcIso(d.year, d.month, d.day);
}
