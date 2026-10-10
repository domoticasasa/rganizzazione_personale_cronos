// ======================= BLOCONE 1/4 =======================
// File: caposquadra_prenotazioni_page.dart (parte 1 di 4)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../utils/app_copyright.dart';
import '../utils/app_logout.dart';
import '../utils/date_formatters.dart';
import '../utils/users_directory.dart';
import '../utils/buono_pasto_scan_deep_link.dart';
import '../utils/viaggio_mezzo_scan_deep_link.dart';
import '../Mobile/employee_mobile_pages.dart';
import '../utils/mobile_navigation.dart';
import '../utils/responsive.dart';
import 'dipendente_prenotazione_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Caposquadra – Prenotazioni (lettura + filtri richiedente)
class CaposquadraPrenotazioniPage extends StatefulWidget {
  final int userId; // main ti passa solo questo

  // opzionali: se in futuro vorrai passarli da main
  final String? username;
  final String? fullName;

  const CaposquadraPrenotazioniPage({
    super.key,
    required this.userId,
    this.username,
    this.fullName,
  });

  @override
  State<CaposquadraPrenotazioniPage> createState() =>
      _CaposquadraPrenotazioniPageState();
}

class _CaposquadraPrenotazioniPageState
    extends State<CaposquadraPrenotazioniPage> {
  bool _busy = false;

  /// UUID della riga `personale` del caposquadra (per Formazioni in fallback)
  String? _myPersonaleUuid;

  /// Dati visualizzati in header (li risolvo da `users` se non forniti)
  String _uiUsername = '';
  String _uiFullName = '';

  bool get _isMobile => useMobileUi(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        await AppCopyright.ensureAccepted(context, userId: widget.userId);
        if (!mounted) return;
        await ViaggioMezzoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
        if (!mounted) return;
        await BuonoPastoScanDeepLink.openPendingScanIfAny(
          context,
          userId: widget.userId,
        );
      }());
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _resolveMyPersonaleUuid(),
      _resolveMyUserLabels(),
    ]);
  }

  // =========================================================================================
  // 0) Risoluzione nome/username da `users` se non passati dal main
  // =========================================================================================
  Future<void> _resolveMyUserLabels() async {
    // Se main li ha passati, li uso
    if ((widget.username ?? '').trim().isNotEmpty ||
        (widget.fullName ?? '').trim().isNotEmpty) {
      setState(() {
        _uiUsername = widget.username?.trim() ?? '';
        _uiFullName = widget.fullName?.trim() ?? '';
      });
      return;
    }

    try {
      final auth = Supabase.instance.client.auth.currentUser;
      if (auth == null) return;
      final row = await SupabaseService.client
          .from('users')
          .select() // * => no 42703
          .eq('auth_id', auth.id)
          .maybeSingle();

      if (!mounted) return;
      final username = (row?['username'] ?? row?['email'] ?? '').toString();
      final fullName = (row?['full_name'] ?? row?['email'] ?? '').toString();

      setState(() {
        _uiUsername = username;
        _uiFullName = fullName;
      });
    } catch (_) {
      // fallback minimo se qualcosa fallisce
      final auth = Supabase.instance.client.auth.currentUser;
      setState(() {
        _uiUsername = auth?.email ?? '';
        _uiFullName = auth?.email ?? '';
      });
    }
  }

  // =========================================================================================
  // 1) Risoluzione personale.id_uuid del caposquadra
  // =========================================================================================
  Future<void> _resolveMyPersonaleUuid() async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser == null) return;
      final authId = authUser.id;

      // 1) personale.user_id == authId
      final p1 = await SupabaseService.client
          .from('personale')
          .select('id_uuid, user_id')
          .eq('user_id', authId)
          .maybeSingle();
      if (p1 != null && (p1['id_uuid'] ?? '').toString().isNotEmpty) {
        setState(() => _myPersonaleUuid = (p1['id_uuid'] as String).trim());
        return;
      }

      // 2) users da auth_id
      final u = await SupabaseService.client
          .from('users')
          .select('id, id_uuid')
          .eq('auth_id', authId)
          .maybeSingle();
      final uid = (u?['id'] ?? '').toString();
      final uuid = (u?['id_uuid'] ?? '').toString();

      if (uid.isNotEmpty) {
        final p2 = await SupabaseService.client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', uid)
            .maybeSingle();
        if (p2 != null && (p2['id_uuid'] ?? '').toString().isNotEmpty) {
          setState(() => _myPersonaleUuid = (p2['id_uuid'] as String).trim());
          return;
        }
      }
      if (uuid.isNotEmpty) {
        final p3 = await SupabaseService.client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', uuid)
            .maybeSingle();
        if (p3 != null && (p3['id_uuid'] ?? '').toString().isNotEmpty) {
          setState(() => _myPersonaleUuid = (p3['id_uuid'] as String).trim());
          return;
        }
      }
    } catch (_) {
      // non blocchiamo
    }
  }

  // =========================================================================================
  // 2) Estrattori dinamici
  // =========================================================================================

  String _getPersonaleId(Map<String, dynamic> r) {
    // Solo chiavi della "persona beneficiaria" (non richiedente/DT).
    const keys = [
      'personale_id', // bookings table (uuid)
      'personale_id_uuid',
      'personale_id_text',
      'person_id',
      'person_id_uuid',
      'person_id_text',
      'personale_uuid',
      'id_personale',
    ];

    for (final k in keys) {
      final v = (r[k] ?? '').toString().trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  String _getCommessaId(Map<String, dynamic> r) {
    for (final k in const ['commessa_id_uuid', 'commessa_id']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getStrutturaId(Map<String, dynamic> r) {
    for (final k in const [
      'struttura_id_uuid',
      'structure_id_uuid',
      'struttura_id',
      'structure_id',
    ]) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getDtKey(Map<String, dynamic> r) {
    for (final k in const ['dt_user_uuid', 'dt_uuid', 'dt_id']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _getMapLink(Map<String, dynamic> r) {
    for (final k in const ['map_link_txt', 'maps_link_txt', 'map_link']) {
      final v = (r[k] ?? '').toString();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // =========================================================================================
  // 3) Dizionari (commesse / strutture / utenti)
  // =========================================================================================

  String _orEq(String col, Iterable<String> values) =>
      values.map((e) => '$col.eq.$e').join(',');

  Future<Map<String, String>> _loadCommesseLabels(Set<String> ids) async {
    final out = <String, String>{};
    final wanted = ids.where((e) => e.trim().isNotEmpty).toSet();
    if (wanted.isEmpty) return out;
    final orExpr = _orEq('id_uuid', wanted);
    final cr = await SupabaseService.client
        .from('commesse')
        .select('id_uuid, nome')
        .or(orExpr);
    for (final c in (cr as List)) {
      final idu = (c['id_uuid'] ?? '').toString();
      final nm = (c['nome'] ?? '').toString();
      if (idu.isNotEmpty) out[idu] = nm;
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _loadStrutture(
      Set<String> ids) async {
    final out = <String, Map<String, dynamic>>{};
    final wanted = ids.where((e) => e.trim().isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    try {
      final orExpr = _orEq('id_uuid', wanted);
      final sr = await SupabaseService.client
          .from('structures')
          .select('id_uuid, name, lat, lng')
          .or(orExpr);
      for (final s in (sr as List)) {
        final idu = (s['id_uuid'] ?? '').toString();
        out[idu] = {
          'name': (s['name'] ?? '').toString(),
          'lat': (s['lat'] is num) ? (s['lat'] as num).toDouble() : null,
          'lng': (s['lng'] is num) ? (s['lng'] as num).toDouble() : null,
        };
      }
      return out;
    } catch (_) {}

    try {
      final orExpr = _orEq('id_uuid', wanted);
      final sr = await SupabaseService.client
          .from('structures')
          .select('id_uuid, name, latitudine, longitudine')
          .or(orExpr);
      for (final s in (sr as List)) {
        final idu = (s['id_uuid'] ?? '').toString();
        out[idu] = {
          'name': (s['name'] ?? '').toString(),
          'lat': (s['latitudine'] is num)
              ? (s['latitudine'] as num).toDouble()
              : null,
          'lng': (s['longitudine'] is num)
              ? (s['longitudine'] as num).toDouble()
              : null,
        };
      }
      return out;
    } catch (_) {}

    final orExpr = _orEq('id_uuid', wanted);
    final sr = await SupabaseService.client
        .from('structures')
        .select('id_uuid, name')
        .or(orExpr);
    for (final s in (sr as List)) {
      final idu = (s['id_uuid'] ?? '').toString();
      out[idu] = {'name': (s['name'] ?? '').toString(), 'lat': null, 'lng': null};
    }
    return out;
  }

  /// utenti → { qualsiasiChiave (id/id_uuid/auth_id/email/username) : full_name/email/username }
  Future<Map<String, String>> _loadRequesterNames(Set<String> keys) async {
    final out = <String, String>{};
    final wanted =
        keys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    Future<void> doMerge(String col) async {
      final orExpr = _orEq(col, wanted);
      try {
        final ur = await SupabaseService.client
            .from('users')
            .select('id, id_uuid, auth_id, full_name, username, email')
            .or(orExpr);
        for (final u in (ur as List)) {
          final id = (u['id'] ?? '').toString();
          final uuid = (u['id_uuid'] ?? '').toString();
          final aid = (u['auth_id'] ?? '').toString();
          final uname = (u['username'] ?? '').toString();
          final mail = (u['email'] ?? '').toString();
          final label = ((u['full_name'] ?? '') as String).trim().isNotEmpty
              ? (u['full_name'] as String)
              : (mail.isNotEmpty
                  ? mail
                  : (uname.isNotEmpty
                      ? uname
                      : (id.isNotEmpty ? id : uuid)));
          if (id.isNotEmpty) out[id] = label;
          if (uuid.isNotEmpty) out[uuid] = label;
          if (aid.isNotEmpty) out[aid] = label;
          if (uname.isNotEmpty) out[uname] = label;
          if (mail.isNotEmpty) out[mail] = label;
        }
      } catch (_) {}
    }

    await doMerge('id_uuid');
    await doMerge('auth_id');
    await doMerge('id');
    await doMerge('email'); // supporto email
    await doMerge('username'); // supporto username
    return out;
  }

  /// Carica tutti gli utenti che hanno uno dei ruoli passati (es. ['admin','dt'])
  Future<Map<String, String>> _loadUsersByRoles(List<String> roles) async {
    final out = <String, String>{};
    if (roles.isEmpty) return out;
    try {
      final orExpr = roles.map((r) => 'role.eq.$r').join(',');
      List res;
      try {
        res = await SupabaseService.client
            .from('users')
            .select(
              'id, id_uuid, auth_id, full_name, username, email, hidden_from_directory',
            )
            .or(orExpr) as List;
      } catch (_) {
        res = await SupabaseService.client
            .from('users')
            .select('id, id_uuid, auth_id, full_name, username, email')
            .or(orExpr) as List;
      }
      for (final u in res) {
        final row = Map<String, dynamic>.from(u as Map);
        if (!UsersDirectory.isVisibleInDirectory(row)) continue;
        final id = (row['id'] ?? '').toString();
        final uuid = (row['id_uuid'] ?? '').toString();
        final aid = (row['auth_id'] ?? '').toString();
        final uname = (row['username'] ?? '').toString();
        final mail = (row['email'] ?? '').toString();
        final label = ((row['full_name'] ?? '') as String).trim().isNotEmpty
            ? (row['full_name'] as String)
            : (mail.isNotEmpty
                ? mail
                : (uname.isNotEmpty ? uname : (id.isNotEmpty ? id : uuid)));
        if (id.isNotEmpty) out[id] = label;
        if (uuid.isNotEmpty) out[uuid] = label;
        if (aid.isNotEmpty) out[aid] = label;
        if (uname.isNotEmpty) out[uname] = label;
        if (mail.isNotEmpty) out[mail] = label;
      }
    } catch (_) {}
    return out;
  }

  // ----------------- Persona (beneficiario) -----------------

String _composePersonaName(Map<String, dynamic> p) {
  // Normalizza tutte le chiavi in minuscolo senza spazi e underscore
  final normalized = <String, dynamic>{};
  p.forEach((key, value) {
    final nk = key.toString().toLowerCase().replaceAll(RegExp(r'[\s_]'), '');
    normalized[nk] = value;
  });

  // 1) full_name/fullname
  final fullName = (normalized['fullname'] ?? '').toString().trim();
  if (fullName.isNotEmpty && fullName.toUpperCase() != 'EMPTY') {
    return fullName;
  }

  // 2) name, displayname
  for (final key in ['name', 'displayname']) {
    final v = (normalized[key] ?? '').toString().trim();
    if (v.isNotEmpty && v.toUpperCase() != 'EMPTY') return v;
  }

  // 3) nome + cognome
  final nome = (normalized['nome'] ?? '').toString().trim();
  final cognome = (normalized['cognome'] ?? '').toString().trim();
  if (nome.isNotEmpty || cognome.isNotEmpty) {
    final full = '$nome $cognome'.trim();
    if (full.isNotEmpty && full.toUpperCase() != 'EMPTY') return full;
  }

  // 4) cognome_nome, nome_cognome
  for (final key in ['cognomenome', 'nomecognome']) {
    final v = (normalized[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }

  return '';
}
  /// personale → { qualsiasiId (id_uuid / id) : "Nome Cognome" }
  Future<Map<String, String>> _loadPersonaleLabels(Set<String> ids) async {
    final out = <String, String>{};
    final wanted = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    Future<void> mergeByCol(String col) async {
      try {
        final orExpr = _orEq(col, wanted);
        final res = await SupabaseService.client
            .from('personale')
            .select('id, id_uuid, full_name')
            .or(orExpr);
        for (final p in (res as List)) {
          final id = (p['id'] ?? '').toString();
          final uuid = (p['id_uuid'] ?? '').toString();
          final label = _composePersonaName(Map<String, dynamic>.from(p));
          if (label.isEmpty) continue;
          if (uuid.isNotEmpty) out[uuid] = label;
          if (id.isNotEmpty) out[id] = label;
        }
      } catch (_) {}
    }

    await mergeByCol('id_uuid');
    await mergeByCol('id');

    return out;
  }

  /// Se per qualche motivo non abbiamo risolto tutte le persone via
  /// `_loadPersonaleLabels`, proviamo una richiesta diretta per gli id mancanti
  /// e integriamo la mappa `out`.
  Future<void> _fetchMissingPersonale(Set<String> ids, Map<String, String> out) async {
    final wanted = ids.map((e) => e.trim()).where((e) => e.isNotEmpty && !out.containsKey(e)).toSet();
    debugPrint('[_fetchMissingPersonale] IDs da risolvere: $wanted');
    if (wanted.isEmpty) {
      debugPrint('[_fetchMissingPersonale] Nessun ID mancante');
      return;
    }
    
    // Prova un fetch diretto per ciascun UUID mancante
    for (final uuid in wanted) {
      try {
        debugPrint('[_fetchMissingPersonale] Cercando id_uuid=$uuid');
        final res = await SupabaseService.client
            .from('personale')
          .select('id, id_uuid, full_name')
            .eq('id_uuid', uuid)
            .maybeSingle();
        debugPrint('[_fetchMissingPersonale] Risultato per $uuid: $res');
        if (res != null) {
          final mp = Map<String, dynamic>.from(res);
          final label = _composePersonaName(mp);
          debugPrint('[_fetchMissingPersonale] Composto label per $uuid: "$label"');
          if (label.isNotEmpty) {
            out[uuid] = label;
          }
        } else {
          debugPrint('[_fetchMissingPersonale] Nessun risultato per $uuid');
        }
      } catch (e) {
        debugPrint('[_fetchMissingPersonale] Errore per $uuid: $e');
      }
    }
    final resolved = out.entries.where((e) => wanted.contains(e.key)).map((e) => '${e.key}: ${e.value}').toList();
    debugPrint('[_fetchMissingPersonale] Risolti: $resolved');
  }

// ----------------- Email del richiedente (inserito da) -----------------

  /// users → { qualsiasiChiave (id/id_uuid/auth_id/email/username) : email }
  Future<Map<String, String>> _loadRequesterEmails(Set<String> keys) async {
    final out = <String, String>{};
    final wanted =
        keys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (wanted.isEmpty) return out;

    Future<void> doMerge(String col) async {
      final orExpr = _orEq(col, wanted);
      try {
        final ur = await SupabaseService.client
            .from('users')
            .select('id, id_uuid, auth_id, email, username')
            .or(orExpr);
        for (final u in (ur as List)) {
          final id = (u['id'] ?? '').toString();
          final uuid = (u['id_uuid'] ?? '').toString();
          final aid = (u['auth_id'] ?? '').toString();
          final uname = (u['username'] ?? '').toString();
          final mail = (u['email'] ?? '').toString();
          if (mail.isEmpty) continue;
          if (id.isNotEmpty) out[id] = mail;
          if (uuid.isNotEmpty) out[uuid] = mail;
          if (aid.isNotEmpty) out[aid] = mail;
          if (uname.isNotEmpty) out[uname] = mail;
          out[mail] = mail; // se chiave è già l'email stessa, mappala a se stessa
        }
      } catch (_) {}
    }

    await doMerge('id_uuid');
    await doMerge('auth_id');
    await doMerge('id');
    await doMerge('email');
    await doMerge('username');

    // fallback: se la chiave "sembra" già una mail e non risolta, usala così com'è
    for (final k in wanted) {
      if (!out.containsKey(k) && k.contains('@')) out[k] = k;
    }
    return out;
  }

  // =========================================================================================
  // 4) Apri TUTTE le liste + filtro Richiedente (+ Persona)
  // =========================================================================================

  Future<void> _openTreniAll() async {
    setState(() => _busy = true);
    try {
      final rs = await SupabaseService.client
          .from('bookings_treno')
          .select()
          .order('data', ascending: false)
          .range(0, 999);

      final rows = (rs as List).cast<Map<String, dynamic>>();

      final commIds = <String>{};
      final dtIds = <String>{};
      final perIds = <String>{};

      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        dtIds.addAll(_collectRequesterKeys(r)); // id/uuid/email/username richiedente
        final pid = _getPersonaleId(r);
        perIds.add(pid);
        debugPrint('[TRENI] Estratto personale_id: "$pid" da record: ${r.keys.toList()}');
      }

      debugPrint('[TRENI] Totale personale_id estratti: ${perIds.where((e) => e.isNotEmpty).length}');
      debugPrint('[TRENI] personale_id set: $perIds');

      final commesse = await _loadCommesseLabels(commIds);
      final dtMap = await _loadRequesterNames(dtIds);
      final admins = await _loadUsersByRoles(['admin', 'dt']);
      admins.forEach((k, v) { if (!dtMap.containsKey(k)) dtMap[k] = v; });
      final dtEmails = await _loadRequesterEmails(dtIds);
      final personale = await _loadPersonaleLabels(perIds);
      debugPrint('[TRENI] Dopo _loadPersonaleLabels, personale map: $personale');
      await _fetchMissingPersonale(perIds, personale);
      debugPrint('[TRENI] Dopo _fetchMissingPersonale, personale map: $personale');

      if (!mounted) return;
      await _showAdaptiveList(
        title: 'Tutti i treni',
        child: _TreniAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: _headerWithLogo,
          getPersonaleId: _getPersonaleId,
        ),
        desktopDialog: _TreniAllDialog(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: _headerWithLogo,
          getPersonaleId: _getPersonaleId,
        ),
      );
    } catch (e) {
      _toast('Errore nel caricamento treni: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAereiAll() async {
    setState(() => _busy = true);
    try {
      final rs = await SupabaseService.client
          .from('bookings_aereo')
          .select()
          .order('data', ascending: false)
          .range(0, 999);

      final rows = (rs as List).cast<Map<String, dynamic>>();

      final commIds = <String>{};
      final dtIds = <String>{};
      final perIds = <String>{};

      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        dtIds.addAll(_collectRequesterKeys(r));
        perIds.add(_getPersonaleId(r));
      }
      final commesse = await _loadCommesseLabels(commIds);
      final dtMap = await _loadRequesterNames(dtIds);
      // Unisci admin/dt al dtMap per la selezione
      final admins = await _loadUsersByRoles(['admin', 'dt']);
      admins.forEach((k, v) { if (!dtMap.containsKey(k)) dtMap[k] = v; });
      final dtEmails = await _loadRequesterEmails(dtIds);
      final personale = await _loadPersonaleLabels(perIds);
      await _fetchMissingPersonale(perIds, personale);

      if (!mounted) return;
      await _showAdaptiveList(
        title: 'Tutti gli aerei',
        child: _AereiAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: _headerWithLogo,
          getPersonaleId: _getPersonaleId,
        ),
        desktopDialog: _AereiAllDialog(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: _headerWithLogo,
          getPersonaleId: _getPersonaleId,
        ),
      );
    } catch (e) {
      _toast('Errore nel caricamento aerei: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPernottiAll() async {
    setState(() => _busy = true);
    try {
      final rs = await SupabaseService.client
          .from('bookings')
          .select()
          .order('start_date', ascending: false)
          .range(0, 999);

      final rows = (rs as List).cast<Map<String, dynamic>>();

      final commIds = <String>{};
      final structIds = <String>{};
      final dtIds = <String>{};
      final perIds = <String>{};

      for (final r in rows) {
        commIds.add(_getCommessaId(r));
        structIds.add(_getStrutturaId(r));
        dtIds.addAll(_collectRequesterKeys(r));
        perIds.add(_getPersonaleId(r));
      }

      final commesse = await _loadCommesseLabels(commIds);
      final structures = await _loadStrutture(structIds);
      final dtMap = await _loadRequesterNames(dtIds);
      // Unisco anche gli admin/dt per permettere il filtro per questi ruoli
      final admins = await _loadUsersByRoles(['admin', 'dt']);
      admins.forEach((k, v) { if (!dtMap.containsKey(k)) dtMap[k] = v; });
      final dtEmails = await _loadRequesterEmails(dtIds);
      final personale = await _loadPersonaleLabels(perIds);
      await _fetchMissingPersonale(perIds, personale);

      if (!mounted) return;
      await _showAdaptiveList(
        title: 'Tutti i pernottamenti',
        child: _PernottiAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          structures: structures,
          buildHeader: _headerWithLogo,
          getCommessaId: _getCommessaId,
          getStrutturaId: _getStrutturaId,
          getDtKey: _getDtKey,
          getMapLink: _getMapLink,
          getPersonaleId: _getPersonaleId,
          onNavigate: _openMaps,
        ),
        desktopDialog: _PernottiAllDialog(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          structures: structures,
          buildHeader: _headerWithLogo,
          getCommessaId: _getCommessaId,
          getStrutturaId: _getStrutturaId,
          getDtKey: _getDtKey,
          getMapLink: _getMapLink,
          getPersonaleId: _getPersonaleId,
          onNavigate: _openMaps,
        ),
      );
    } catch (e) {
      _toast('Errore nel caricamento pernottamenti: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =========================================================================================
  // 5) FORMAZIONI – link del caposquadra (robusto)
  // =========================================================================================

  String? _pickUrlFromRow(Map<String, dynamic> r) {
    for (final k in const [
      'url',
      'link',
      'formazione_url',
      'formazioni_url',
      'url_formazione',
      'courses_url'
    ]) {
      final v = (r[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadCurrentUserRow() async {
    final auth = Supabase.instance.client.auth.currentUser;
    if (auth == null) return null;
    final tries = <MapEntry<String, String?>>[
      MapEntry('auth_id', auth.id),
      MapEntry('id_uuid', auth.id),
      MapEntry('email', auth.email),
    ];
    for (final t in tries) {
      final col = t.key;
      final val = (t.value ?? '').toString();
      if (val.isEmpty) continue;
      try {
        final row = await SupabaseService.client
            .from('users')
            .select()
            .eq(col, val)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row);
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _tryFindUrlSequential(
    String table, {
    required List<MapEntry<String, String>> attempts,
    List<String> urlKeys = const [],
  }) async {
    for (final att in attempts) {
      final col = att.key;
      final val = att.value.trim();
      if (val.isEmpty) continue;
      try {
        final res = await SupabaseService.client
            .from(table)
            .select()
            .eq(col, val)
            .limit(1);
        final list = (res as List);
        if (list.isNotEmpty) {
          final r = Map<String, dynamic>.from(list.first);
          final candidate = _pickUrlFromRow(r);
          if (candidate != null && candidate.isNotEmpty) return candidate;
          for (final k in urlKeys) {
            final v = (r[k] ?? '').toString().trim();
            if (v.isNotEmpty) return v;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> _openFormazioni() async {
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth.currentUser;
      if (auth == null) {
        _toast('Sessione scaduta. Accedi di nuovo.', error: true);
        return;
      }

      final u = await _loadCurrentUserRow();
      final userId = (u?['id'] ?? '').toString();
      final userUuid = (u?['id_uuid'] ?? '').toString();
      final userEmail = (u?['email'] ?? '').toString();
      final authId = auth.id;
      final pid = _myPersonaleUuid ?? '';

      String? url;

      // 1) public.formazioni (utente_id + url_formazione)
      url ??= await _tryFindUrlSequential(
        'formazioni',
        attempts: [
          MapEntry('utente_id', userUuid),
          MapEntry('utente_id', userId),
          MapEntry('utente_id', authId),
          if (pid.isNotEmpty) MapEntry('personale_id_uuid', pid),
          MapEntry('auth_id', authId),
          MapEntry('email', userEmail),
        ],
        urlKeys: const ['url_formazione'],
      );

      // 2) formazioni_links (se presente)
      url ??= await _tryFindUrlSequential(
        'formazioni_links',
        attempts: [
          if (pid.isNotEmpty) MapEntry('personale_id_uuid', pid),
          MapEntry('user_id', userUuid),
          MapEntry('user_id', userId),
          MapEntry('auth_id', authId),
          MapEntry('email', userEmail),
        ],
      );

      // 3) formationi (eventuale refuso)
      url ??= await _tryFindUrlSequential(
        'formationi',
        attempts: [
          MapEntry('utente_id', userUuid),
          MapEntry('utente_id', userId),
          MapEntry('utente_id_txt', userUuid),
          MapEntry('utente_id_txt', userId),
          if (pid.isNotEmpty) MapEntry('personale_id_uuid', pid),
          MapEntry('auth_id', authId),
          MapEntry('email', userEmail),
        ],
        urlKeys: const ['url_formazione'],
      );

      // 4) Campo su PERSONALE
      if (url == null && pid.isNotEmpty) {
        try {
          final p = await SupabaseService.client
              .from('personale')
              .select()
              .eq('id_uuid', pid)
              .maybeSingle();
          if (p != null) {
            url = _pickUrlFromRow(Map<String, dynamic>.from(p));
          }
        } catch (_) {}
      }

      // 5) Campo su USERS
      if (url == null && u != null) {
        url = _pickUrlFromRow(Map<String, dynamic>.from(u));
      }

      if (url == null || url.trim().isEmpty) {
        _toast('Nessun link formazione trovato per il tuo profilo.', error: true);
        return;
      }

      // Normalizza e apri
      Uri? uri = Uri.tryParse(url.trim());
      if (uri == null) {
        _toast('URL formazione non valido.', error: true);
        return;
      }
      if (!uri.hasScheme) {
        uri = Uri.parse('https://${url.trim()}');
      }

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _toast('Impossibile aprire il link formazione.', error: true);
      }
    } catch (e) {
      _toast('Errore apertura formazione: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =========================================================================================
  // 6) Helpers UI / nav
  // =========================================================================================

  Future<void> _openMaps(
      {String? mapLink, double? lat, double? lng, String? name}) async {
    Uri? uri;
    if ((mapLink ?? '').trim().isNotEmpty) {
      final raw = mapLink!.trim();
      uri = Uri.tryParse(raw);
      if (uri == null) {
        _toast('Link mappa non valido', error: true);
        return;
      }
      if (!uri.hasScheme) uri = Uri.parse('https://$raw');
    } else if (lat != null && lng != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if ((name ?? '').trim().isNotEmpty) {
      final q = Uri.encodeComponent(name!);
      uri =
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    } else {
      _toast('Posizione non disponibile', error: true);
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Impossibile aprire Maps', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  // --- Logo & header ---
  Widget _logo([double size = 22]) => Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.apartment, size: 20),
      );

  /// Header con logo senza Expanded (sicuro anche in Wrap)
  Widget _headerWithLogo(String title) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logo(20),
          const SizedBox(width: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      );

  // =========================================================================================
  // 7) UI principale
  // =========================================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerUsername = (widget.username ?? '').trim().isNotEmpty
        ? widget.username!.trim()
        : _uiUsername;
    final headerFullName = (widget.fullName ?? '').trim().isNotEmpty
        ? widget.fullName!.trim()
        : _uiFullName;
    void openDipPage() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => useMobileUi(context)
              ? DipendentePrenotazioniMobilePage(
                  userId: widget.userId,
                  username: headerUsername,
                  fullName: headerFullName,
                )
              : DipendentePrenotazioniPage(
                  userId: widget.userId,
                  username: headerUsername,
                  fullName: headerFullName,
                ),
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: wrapClassicAppBarChrome(context, AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                _logo(),
                const SizedBox(width: 8),
                const Text('Le mie prenotazioni (Caposquadra)'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: () => performAppLogout(context),
              ),
            ],
          )),
          body: PageWithTopLogo(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: Text(
                        (headerFullName.isNotEmpty
                                ? headerFullName[0]
                                : (headerUsername.isNotEmpty
                                    ? headerUsername[0]
                                    : '?'))
                            .toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$headerUsername • $headerFullName • person_id: ${widget.userId}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_isMobile)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.bed_outlined),
                              label: const Text('Pernottamenti'),
                              onPressed: _busy ? null : _openPernottiAll,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.train_outlined),
                              label: const Text('Treni'),
                              onPressed: _busy ? null : _openTreniAll,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.flight_takeoff_outlined),
                              label: const Text('Aerei'),
                              onPressed: _busy ? null : _openAereiAll,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.school_outlined),
                              label: const Text('Formazioni'),
                              onPressed: _busy ? null : _openFormazioni,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Vai a pagina dipendente'),
                          onPressed: _busy ? null : openDipPage,
                        ),
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.bed_outlined),
                        label: const Text('Pernottamenti (tutti)'),
                        onPressed: _busy ? null : _openPernottiAll,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.train_outlined),
                        label: const Text('Treni (tutti)'),
                        onPressed: _busy ? null : _openTreniAll,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.flight_takeoff_outlined),
                        label: const Text('Aerei (tutti)'),
                        onPressed: _busy ? null : _openAereiAll,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('Formazioni'),
                        onPressed: _busy ? null : _openFormazioni,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Pagina Dipendente'),
                        onPressed: _busy ? null : openDipPage,
                      ),
                    ],
                  ),

                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      'Apri una categoria e filtra per richiedente.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),

        if (_busy)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.10)),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
      ],
    );
  }

  // =========================================================================================
  // 8) Adaptive open: Bottom‑Sheet su Mobile; Pagina full‑screen su Desktop
  // =========================================================================================

  Future<void> _showAdaptiveList({
    required String title,
    required Widget child,
    required Widget desktopDialog, // mantenuta per firma
  }) async {
    if (_isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (ctx) {
            final h = MediaQuery.of(ctx).size.height;
            return SizedBox(
              height: h * 0.92,
              child: Column(
                children: [
                  Container(
                    height: 56,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: _headerWithLogo(title),
                  ),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            );
          },
        );
      });
    } else {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _ListPage(title: title, headerBuilder: _headerWithLogo, body: child),
          fullscreenDialog: false,
        ),
      );
    }
  }
}
// ===================== FINE BLOCONE 1/4 =====================
// ======================= BLOCONE 2/4 =======================
// File: caposquadra_prenotazioni_page.dart (parte 2 di 4)

/* --------------------------- Util UI ------------------------------------ */

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  Color _color() {
    switch (status.toUpperCase()) {
      case 'CONFERMATA':
        return Colors.green;
      case 'IN_ATTESA':
        return Colors.orange;
      case 'ANNULLATA':
        return Colors.redAccent;
      case 'RIFIUTATA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ChipInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }
}

/* --------------------------- Filtro Richiedente ------------------------- */

class _RequesterFilterBar extends StatelessWidget {
  final Map<String, String> dtMap;
  final String? selectedKey;
  final ValueChanged<String?> onChanged;

  const _RequesterFilterBar({
    required this.dtMap,
    required this.selectedKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Deduplica le voci per label: se più chiavi hanno la stessa label
    // mostriamo una sola voce nel dropdown (usando la prima chiave trovata)
    final sorted = dtMap.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    final labelToKey = <String, String>{};
    for (final e in sorted) {
      if (!labelToKey.containsKey(e.value)) labelToKey[e.value] = e.key;
    }

    // Se la label selezionata non è presente tra le voci (es. è una selezione
    // precedente), assicurati di includerla così da non perdere la selezione.
    if (selectedKey != null && selectedKey!.isNotEmpty) {
      if (!labelToKey.containsKey(selectedKey)) {
        // prova a trovare una key corrispondente nella dtMap; altrimenti
        // aggiungi la label come chiave con valore identico per mantenerla visibile
        final found = dtMap.entries.firstWhere(
            (e) => e.value.toString().trim() == selectedKey!.toString().trim(),
            orElse: () => MapEntry(selectedKey!, selectedKey!));
        labelToKey[selectedKey!] = found.value;
      }
    }

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Tutti i richiedenti'),
      ),
      ...labelToKey.entries.map((e) => DropdownMenuItem<String?>(
        // use the label itself as the dropdown value so users filter by full_name
        value: e.key,
        child: Text(e.key),
          )),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_alt_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: selectedKey,
                        items: items,
                        onChanged: onChanged,
                        decoration: const InputDecoration(
                          labelText: 'Richiedente',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.clear),
                    label: const Text('Azzera'),
                    onPressed: () => onChanged(null),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              const Icon(Icons.filter_alt_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedKey,
                  items: items,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    labelText: 'Richiedente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Azzera'),
                onPressed: () => onChanged(null),
              ),
            ],
          );
        },
      ),
    );
  }
}

/* --------------------------- Helper top-level ---------------------------- */

const List<String> _reqCols = [
  'dt_user_uuid',
  'dt_uuid',
  'dt_id',
  'requested_by',
  'created_by',
  'dt_username',
  'username',
  'dt_email',
  'email',
  'requester_email',
  'richiedente_email',
  'richiedente',
];

List<String> _collectRequesterKeys(Map<String, dynamic> r) {
  final out = <String>[];
  for (final k in _reqCols) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) out.add(v);
  }
  return out.toSet().toList();
}

String _fallbackRequesterLabel(Map<String, dynamic> r) {
  for (final k in const [
    'richiedente',
    'dt_email',
    'requester_email',
    'richiedente_email',
    'email',
    'dt_username',
    'username'
  ]) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  for (final k in const [
    'dt_user_uuid',
    'dt_uuid',
    'dt_id',
    'requested_by',
    'created_by'
  ]) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '—';
}

/* --------------------------- LIST PAGE (desktop) ------------------------- */

class _ListPage extends StatelessWidget {
  final String title;
  final Widget Function(String) headerBuilder;
  final Widget body;

  const _ListPage({
    required this.title,
    required this.headerBuilder,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(title: headerBuilder(title))),
      body: SafeArea(child: body),
    );
  }
}

/* ------------------------------ TRENI ----------------------------------- */

class _TreniAllList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Map<String, String> dtEmails;
  final Map<String, String> personale;

  final Widget Function(String) buildHeader;
  final String Function(Map<String, dynamic>) getPersonaleId;

  const _TreniAllList({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.buildHeader,
    required this.getPersonaleId,
  });

  @override
  State<_TreniAllList> createState() => _TreniAllListState();
}

class _TreniAllListState extends State<_TreniAllList> {
  String? _selectedDtKey;

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();

  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = (_selectedDtKey == null)
      ? widget.rows
      : widget.rows.where((r) {
        final keys = _collectRequesterKeys(r).map((e) => e.toString().trim().toLowerCase()).toSet();
        final selLabel = _selectedDtKey!.toString().trim().toLowerCase();
        if (keys.contains(selLabel)) return true;
        // trova tutte le key in dtMap che hanno questa label e verifica se
        // uno di quei key compare tra i valori della riga
        final matchingKeys = widget.dtMap.entries
            .where((e) => e.value.toString().trim().toLowerCase() == selLabel)
            .map((e) => e.key.toString().trim().toLowerCase())
            .toSet();
        if (matchingKeys.any((k) => keys.contains(k))) return true;
        return false;
        }).toList();

    return Column(
      children: [
        _RequesterFilterBar(
          dtMap: widget.dtMap,
          selectedKey: _selectedDtKey,
          onChanged: (v) => setState(() => _selectedDtKey = v),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),

            itemBuilder: (_, i) {
              final r = filtered[i];

              final date = _fmtDate(_get(r, 'data'));
              final time = _get(r, 'orario');
              final from = _get(r, 'stazione_partenza');
              final to = _get(r, 'stazione_arrivo');

              final commId =
                  (r['commessa_id_uuid'] ?? r['commessa_id'] ?? '').toString();
              final comm = widget.commesse[commId] ?? commId;

              final stato = _get(r, 'status');
              final note = _get(r, 'master_note');

              // Persona (prefer inline booking fullname if present)
              final inlineName = ((r['personale_fullname'] ?? r['personale_full_name'] ?? r['personalefullname'] ?? r['personalefullname']) ?? '').toString().trim();
              final pid = widget.getPersonaleId(r);
              final persRaw = inlineName.isNotEmpty ? inlineName : (widget.personale[pid]?.trim() ?? '—');

              // Richiedente
              final keys = _collectRequesterKeys(r);
              String rich = _fallbackRequesterLabel(r);
              for (final k in keys) {
                if (widget.dtMap.containsKey(k)) {
                  rich = widget.dtMap[k]!;
                  break;
                }
              }
              final pers = (persRaw.isNotEmpty && persRaw != '—') ? persRaw : '—';

              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                widget.buildHeader('$from → $to'),
                                const SizedBox(height: 6),
                                _StatusBadge(stato),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                  child: widget.buildHeader('$from → $to')),
                              const SizedBox(width: 8),
                              _StatusBadge(stato),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _ChipInfo(
                              icon: Icons.person_outline,
                              text: 'Persona: $pers'),
                          _ChipInfo(
                              icon: Icons.event,
                              text:
                                  '$date ${time.isEmpty ? '' : time}'),
                          _ChipInfo(
                              icon: Icons.work_outline,
                              text: 'Commessa: $comm'),
                          _ChipInfo(
                              icon: Icons.assignment_ind_outlined,
                              text: 'Richiedente: $rich'),
                          // *** RIMOSSO INSERITO DA ***
                        ],
                      ),

                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TreniAllDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Map<String, String> dtEmails;
  final Map<String, String> personale;
  final Widget Function(String title) buildHeader;
  final String Function(Map<String, dynamic>) getPersonaleId;

  const _TreniAllDialog({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.buildHeader,
    required this.getPersonaleId,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('Tutti i treni'),
      content: SizedBox(
        width: 800,
        child: _TreniAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: buildHeader,
          getPersonaleId: getPersonaleId,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

// ======================= BLOCONE 3/4 =======================
// File: caposquadra_prenotazioni_page.dart (parte 3 di 4)

/* ------------------------------ AEREI ----------------------------------- */

class _AereiAllList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;      // label richiedente (nome/email/username)
  final Map<String, String> dtEmails;   // email "inserito da"
  final Map<String, String> personale;  // persona (beneficiario)

  final Widget Function(String title) buildHeader;
  final String Function(Map<String, dynamic>) getPersonaleId;

  const _AereiAllList({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.buildHeader,
    required this.getPersonaleId,
  });

  @override
  State<_AereiAllList> createState() => _AereiAllListState();
}

class _AereiAllListState extends State<_AereiAllList> {
  String? _selectedDtKey;

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();

  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = (_selectedDtKey == null)
      ? widget.rows
      : widget.rows.where((r) {
        final keys = _collectRequesterKeys(r).map((e) => e.toString().trim().toLowerCase()).toSet();
        final selLabel = _selectedDtKey!.toString().trim().toLowerCase();
        if (keys.contains(selLabel)) return true;
        final matchingKeys = widget.dtMap.entries
            .where((e) => e.value.toString().trim().toLowerCase() == selLabel)
            .map((e) => e.key.toString().trim().toLowerCase())
            .toSet();
        if (matchingKeys.any((k) => keys.contains(k))) return true;
        return false;
        }).toList();

    if (widget.rows.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata.'));
    }

    return Column(
      children: [
        _RequesterFilterBar(
          dtMap: widget.dtMap,
          selectedKey: _selectedDtKey,
          onChanged: (v) => setState(() => _selectedDtKey = v),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),

            itemBuilder: (_, i) {
              final r = filtered[i];

              final date = _fmtDate(_get(r, 'data'));
              final time = _get(r, 'orario');
              final from = _get(r, 'aeroporto_partenza');
              final to   = _get(r, 'aeroporto_arrivo');

              final commId = (r['commessa_id_uuid'] ?? r['commessa_id'] ?? '').toString();
              final comm   = widget.commesse[commId] ?? commId;

              final bag   = _get(r, 'bagaglio');
              final park  = (r['parcheggio'] == true) ? 'Sì' : 'No';
              final targa = _get(r, 'targa_veicolo');

              final stato = _get(r, 'status');
              final note  = _get(r, 'master_note');

              // -------- Persona (beneficiario) ----------
              final inlineName = ((r['personale_fullname'] ?? r['personale_full_name'] ?? r['personalefullname'] ?? r['personalefullname']) ?? '').toString().trim();
              final pid  = widget.getPersonaleId(r);
              final persRaw = inlineName.isNotEmpty ? inlineName : (widget.personale[pid]?.trim() ?? '—');

              // -------- Richiedente ----------
              final keys = _collectRequesterKeys(r);
              String rich = _fallbackRequesterLabel(r);
              for (final k in keys) {
                if (widget.dtMap.containsKey(k)) {
                  rich = widget.dtMap[k]!;
                  break;
                }
              }
              final pers = (persRaw.isNotEmpty && persRaw != '—') ? persRaw : '—';

              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                widget.buildHeader('$from → $to'),
                                const SizedBox(height: 6),
                                _StatusBadge(stato),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: widget.buildHeader('$from → $to')),
                              const SizedBox(width: 8),
                              _StatusBadge(stato),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      // Info principali
                        Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _ChipInfo(icon: Icons.person_outline,  text: 'Persona: $pers'),
                          _ChipInfo(icon: Icons.event,          text: '$date ${time.isEmpty ? '' : time}'),
                          _ChipInfo(icon: Icons.work_outline,   text: 'Commessa: $comm'),
                          _ChipInfo(icon: Icons.assignment_ind_outlined, text: 'Richiedente: $rich'),

                          // *** INSERITO DA RIMOSSO ***

                          _ChipInfo(icon: Icons.luggage_outlined,
                              text: 'Bagaglio: ${bag == 'stiva' ? 'In stiva' : 'A mano'}'),
                          _ChipInfo(icon: Icons.local_parking_outlined,
                              text: 'Parcheggio: $park'),
                          if (targa.isNotEmpty)
                            _ChipInfo(icon: Icons.directions_car_outlined,
                                text: 'Targa: $targa'),
                        ],
                      ),

                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AereiAllDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Map<String, String> dtEmails;
  final Map<String, String> personale;

  final Widget Function(String title) buildHeader;
  final String Function(Map<String, dynamic>) getPersonaleId;

  const _AereiAllDialog({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.buildHeader,
    required this.getPersonaleId,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('Tutti gli aerei'),
      content: SizedBox(
        width: 800,
        child: _AereiAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          buildHeader: buildHeader,
          getPersonaleId: getPersonaleId,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

// ======================= BLOCONE 4/4 =======================
// File: caposquadra_prenotazioni_page.dart (parte 4 di 4)

/* --------------------------- PERNOTTAMENTI ------------------------------- */

class _PernottiAllList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;          // label richiedente
  final Map<String, String> dtEmails;       // email "inserito da"
  final Map<String, String> personale;      // persona (beneficiario)
  final Map<String, Map<String, dynamic>> structures;

  final Widget Function(String title) buildHeader;

  final String Function(Map<String, dynamic>) getCommessaId;
  final String Function(Map<String, dynamic>) getStrutturaId;
  final String Function(Map<String, dynamic>) getDtKey;
  final String Function(Map<String, dynamic>) getMapLink;
  final String Function(Map<String, dynamic>) getPersonaleId;

  final Future<void> Function({
    String? mapLink,
    double? lat,
    double? lng,
    String? name,
  }) onNavigate;

  const _PernottiAllList({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.structures,
    required this.buildHeader,
    required this.getCommessaId,
    required this.getStrutturaId,
    required this.getDtKey,
    required this.getMapLink,
    required this.getPersonaleId,
    required this.onNavigate,
  });

  @override
  State<_PernottiAllList> createState() => _PernottiAllListState();
}

class _PernottiAllListState extends State<_PernottiAllList> {
  String? _selectedDtKey;

  String _get(Map<String, dynamic> r, String k) => (r[k] ?? '').toString();

  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
      (_selectedDtKey == null)
        ? widget.rows
        : widget.rows.where((r) {
                final keys = _collectRequesterKeys(r).map((e) => e.toString().trim().toLowerCase()).toSet();
                final selLabel = _selectedDtKey!.toString().trim().toLowerCase();
                if (keys.contains(selLabel)) return true;
                final matchingKeys = widget.dtMap.entries
                    .where((e) => e.value.toString().trim().toLowerCase() == selLabel)
                    .map((e) => e.key.toString().trim().toLowerCase())
                    .toSet();
                if (matchingKeys.any((k) => keys.contains(k))) return true;
                return false;
          }).toList();

    if (widget.rows.isEmpty) {
      return const Center(child: Text('Nessun pernottamento trovato.'));
    }

    return Column(
      children: [
        _RequesterFilterBar(
          dtMap: widget.dtMap,
          selectedKey: _selectedDtKey,
          onChanged: (v) => setState(() => _selectedDtKey = v),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),

            itemBuilder: (_, i) {
              final r = filtered[i];

              final dal = _fmtDate(_get(r, 'start_date'));
              final al  = _fmtDate(_get(r, 'end_date'));
              final cam = _get(r, 'camera_tipo');

              final sid = widget.getStrutturaId(r);
              final cid = widget.getCommessaId(r);

              final structInfo = widget.structures[sid] ?? {};
              final struttura  = (structInfo['name'] ?? '').toString();

              final double? lat =
                  structInfo['lat'] is num ? (structInfo['lat'] as num).toDouble() : null;
              final double? lng =
                  structInfo['lng'] is num ? (structInfo['lng'] as num).toDouble() : null;

              final commessa = widget.commesse[cid] ?? cid;
              final stato    = _get(r, 'status');
              final note     = _get(r, 'master_note');

              final mapLink  = widget.getMapLink(r);

              // -------- Persona ----------
              final inlineName = ((r['personale_fullname'] ?? r['personale_full_name'] ?? r['personalefullname'] ?? r['personalefullname']) ?? '').toString().trim();
              final pid  = widget.getPersonaleId(r);
              final persRaw = inlineName.isNotEmpty ? inlineName : (widget.personale[pid]?.trim() ?? '—');

              // -------- Richiedente ----------
              final keys  = _collectRequesterKeys(r);
              String rich = _fallbackRequesterLabel(r);
              for (final k in keys) {
                if (widget.dtMap.containsKey(k)) {
                  rich = widget.dtMap[k]!;
                  break;
                }
              }
              final pers = (persRaw.isNotEmpty && persRaw != '—') ? persRaw : '—';

              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ---- HEADER ----
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = useUltraCompactAppBarWidth(constraints.maxWidth);
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _ChipInfo(
                                      icon: Icons.person_outline,
                                      text: 'Persona: $pers',
                                    ),
                                    widget.buildHeader('$dal → $al'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _ChipInfo(
                                      icon: Icons.bed_outlined,
                                      text: 'Camera: ${cam.isEmpty ? '—' : cam}',
                                    ),
                                    _ChipInfo(
                                      icon: Icons.apartment_outlined,
                                      text: 'Struttura: ${struttura.isEmpty ? '—' : struttura}',
                                    ),
                                    _StatusBadge(stato),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.directions),
                                  label: const Text('Raggiungi'),
                                  onPressed: () => widget.onNavigate(
                                    mapLink: mapLink,
                                    lat: lat,
                                    lng: lng,
                                    name: struttura,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _ChipInfo(
                                icon: Icons.person_outline,
                                text: 'Persona: $pers',
                              ),
                              widget.buildHeader('$dal → $al'),
                              _ChipInfo(
                                icon: Icons.bed_outlined,
                                text: 'Camera: ${cam.isEmpty ? '—' : cam}',
                              ),
                              _ChipInfo(
                                icon: Icons.apartment_outlined,
                                text: 'Struttura: ${struttura.isEmpty ? '—' : struttura}',
                              ),
                              _StatusBadge(stato),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.directions),
                                label: const Text('Raggiungi'),
                                onPressed: () => widget.onNavigate(
                                  mapLink: mapLink,
                                  lat: lat,
                                  lng: lng,
                                  name: struttura,
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 6),

                      // ---- INFO DETTAGLIO ----
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _ChipInfo(
                              icon: Icons.work_outline,
                              text: 'Commessa: $commessa'),
                          _ChipInfo(
                              icon: Icons.assignment_ind_outlined,
                              text: 'Richiedente: $rich'),
                          // *** INSERITO DA RIMOSSO ***
                        ],
                      ),

                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        NotePreviewText(note: note, prefix: 'Note: ', maxChars: 10),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PernottiAllDialog extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> commesse;
  final Map<String, String> dtMap;
  final Map<String, String> dtEmails;
  final Map<String, String> personale;
  final Map<String, Map<String, dynamic>> structures;

  final Widget Function(String title) buildHeader;

  final String Function(Map<String, dynamic>) getCommessaId;
  final String Function(Map<String, dynamic>) getStrutturaId;
  final String Function(Map<String, dynamic>) getDtKey;
  final String Function(Map<String, dynamic>) getMapLink;
  final String Function(Map<String, dynamic>) getPersonaleId;

  final Future<void> Function({
    String? mapLink,
    double? lat,
    double? lng,
    String? name,
  }) onNavigate;

  const _PernottiAllDialog({
    required this.rows,
    required this.commesse,
    required this.dtMap,
    required this.dtEmails,
    required this.personale,
    required this.structures,
    required this.buildHeader,
    required this.getCommessaId,
    required this.getStrutturaId,
    required this.getDtKey,
    required this.getMapLink,
    required this.getPersonaleId,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: buildHeader('Tutti i pernottamenti'),
      content: SizedBox(
        width: 920,
        child: _PernottiAllList(
          rows: rows,
          commesse: commesse,
          dtMap: dtMap,
          dtEmails: dtEmails,
          personale: personale,
          structures: structures,
          buildHeader: buildHeader,
          getCommessaId: getCommessaId,
          getStrutturaId: getStrutturaId,
          getDtKey: getDtKey,
          getMapLink: getMapLink,
          getPersonaleId: getPersonaleId,
          onNavigate: onNavigate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

// ===================== FINE BLOCONE 4/4 =====================