import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/admin_estintori_page.dart';
import '../pages/admin_logistica_box_page.dart';
import '../pages/admin_logistica_casette_ps_page.dart';
import '../pages/admin_logistica_mdo_ferroviari_page.dart';
import '../pages/admin_logistica_mezzi_stradali_page.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/logistica_box_linked_sync.dart';
import '../services/uqsa_sedi_sicurezza_excel_export.dart';
import '../theme/cronos_app_themes.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/logistica_layout.dart';
import '../utils/logistica_ubicazione_ref.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// UQSA — sedi sicurezza: ubicante → dove → estintori → casette P.S.
class AdminUqsaSediSicurezzaPage extends StatefulWidget {
  const AdminUqsaSediSicurezzaPage({
    super.key,
    this.forceMobileLayout = false,
  });

  final bool forceMobileLayout;

  @override
  State<AdminUqsaSediSicurezzaPage> createState() =>
      _AdminUqsaSediSicurezzaPageState();
}

enum _SicurezzaFilter { all, scaduti, inScadenza, noEstintore, noCasetta, ok }

enum _HostSeverity { ok, warn, critical, incomplete }

enum _HostScope { box, mdo, mezzo, altro }

class _HostSicurezzaRow {
  _HostSicurezzaRow({
    required this.kind,
    required this.hostId,
    required this.ubicante,
    required this.tipologia,
    required this.commessa,
    required this.posizione,
    required this.estintori,
    required this.casette,
  });

  final String kind;
  final String hostId;
  /// Nome BOX / CON / container / MDO.
  final String ubicante;
  final String tipologia;
  final String commessa;
  /// Dove si trova (campo ubicazione / descrizione).
  final String posizione;
  final List<Map<String, dynamic>> estintori;
  final List<Map<String, dynamic>> casette;

  bool get missingEstintore => estintori.isEmpty;
  bool get missingCasetta => casette.isEmpty;
}

class _AdminUqsaSediSicurezzaPageState extends State<AdminUqsaSediSicurezzaPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  String _search = '';
  _SicurezzaFilter _filter = _SicurezzaFilter.all;
  _HostScope _scope = _HostScope.box;
  final ScrollController _hScroll = ScrollController();
  bool _exporting = false;

  List<_HostSicurezzaRow> _boxRows = const [];
  List<_HostSicurezzaRow> _mdoRows = const [];
  List<_HostSicurezzaRow> _mezzoRows = const [];
  List<_HostSicurezzaRow> _altroRows = const [];

  static const _estAccent = Color(0xFFB71C1C);
  static const _casAccent = Color(0xFF0D47A1);
  static const _okAccent = Color(0xFF1B5E20);
  static const _warnAccent = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  bool get _isCompact =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  String _s(dynamic v) => (v ?? '').toString().trim();

  DateTime? _parseDay(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final raw = v.toString().trim();
    if (raw.isEmpty) return null;
    final iso = parseFlexibleDateToIsoDate(raw);
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  String _fmtScadenza(dynamic v) {
    final d = _parseDay(v);
    if (d == null) {
      final raw = _s(v);
      return raw.isEmpty ? '—' : raw;
    }
    return '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool _isScaduto(dynamic v) {
    final d = _parseDay(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return d.isBefore(today);
  }

  bool _isInScadenza30(dynamic v) {
    final d = _parseDay(v);
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = d.difference(today).inDays;
    return days >= 0 && days <= 30;
  }

  bool _rowHasScaduto(_HostSicurezzaRow r) {
    for (final e in r.estintori) {
      if (_isScaduto(e['prossimo_controllo'])) return true;
    }
    for (final c in r.casette) {
      if (_isScaduto(c['scadenze'])) return true;
    }
    return false;
  }

  bool _rowHasInScadenza(_HostSicurezzaRow r) {
    for (final e in r.estintori) {
      if (_isInScadenza30(e['prossimo_controllo'])) return true;
    }
    for (final c in r.casette) {
      if (_isInScadenza30(c['scadenze'])) return true;
    }
    return false;
  }

  _HostSeverity _severityOf(_HostSicurezzaRow r) {
    if (_rowHasScaduto(r)) return _HostSeverity.critical;
    if (r.missingEstintore || r.missingCasetta) return _HostSeverity.incomplete;
    if (_rowHasInScadenza(r)) return _HostSeverity.warn;
    return _HostSeverity.ok;
  }

  Color _severityColor(_HostSeverity s) {
    switch (s) {
      case _HostSeverity.critical:
        return _estAccent;
      case _HostSeverity.warn:
        return _warnAccent;
      case _HostSeverity.incomplete:
        return Colors.blueGrey.shade700;
      case _HostSeverity.ok:
        return _okAccent;
    }
  }

  String _severityLabel(_HostSeverity s) {
    switch (s) {
      case _HostSeverity.critical:
        return 'SCADUTO';
      case _HostSeverity.warn:
        return '≤30GG';
      case _HostSeverity.incomplete:
        return 'INCOMPLETO';
      case _HostSeverity.ok:
        return 'OK';
    }
  }

  Color _scadenzaColor(BuildContext context, dynamic v) {
    if (_isScaduto(v)) return _estAccent;
    if (_isInScadenza30(v)) return _warnAccent;
    return CronosAppThemes.onSurfaceOf(context);
  }

  DateTime? _earliestDay(_HostSicurezzaRow r) {
    DateTime? best;
    void consider(dynamic v) {
      final d = _parseDay(v);
      if (d == null) return;
      if (best == null || d.isBefore(best!)) best = d;
    }

    for (final e in r.estintori) {
      consider(e['prossimo_controllo']);
    }
    for (final c in r.casette) {
      consider(c['scadenze']);
    }
    return best;
  }

  Set<String> _expandMatchKeys(Set<String> refs) {
    final out = <String>{};
    for (final r in refs) {
      final u = r.trim().toUpperCase();
      if (u.isEmpty) continue;
      out.add(u);
      final compact = u.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (compact.isNotEmpty) out.add(compact);
      final m = RegExp(r'^(BOX|CON|UFF|A)(\d+)$').firstMatch(u);
      if (m == null) continue;
      final prefix = m.group(1)!;
      final rawDigits = m.group(2)!;
      final normalized = rawDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      out.add('$prefix$rawDigits');
      out.add('$prefix$normalized');
      if (normalized.length < 2) {
        out.add('$prefix${normalized.padLeft(2, '0')}');
      }
    }
    return out;
  }

  Map<String, List<Map<String, dynamic>>> _indexByUbicazione(
    List<Map<String, dynamic>> assets,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    void put(String key, Map<String, dynamic> row) {
      final k = key.trim().toUpperCase();
      if (k.isEmpty) return;
      final list = map.putIfAbsent(k, () => <Map<String, dynamic>>[]);
      final id = _s(row['id_uuid']);
      if (id.isNotEmpty && list.any((e) => _s(e['id_uuid']) == id)) return;
      list.add(row);
    }

    for (final row in assets) {
      final ref = extractLogisticaUbicazioneRef(_s(row['ubicazione']));
      if (ref.isEmpty) continue;
      for (final key in _expandMatchKeys({ref})) {
        put(key, row);
      }
    }
    return map;
  }

  String _assetFingerprint(Map<String, dynamic> row) {
    final code = _s(row['matricola']).isNotEmpty
        ? _s(row['matricola'])
        : _s(row['codice_interno']);
    final tipo = _s(row['tipo_cassetta']);
    final scad = _s(row['prossimo_controllo']).isNotEmpty
        ? _s(row['prossimo_controllo'])
        : _s(row['scadenze']);
    final ubi = extractLogisticaUbicazioneRef(_s(row['ubicazione']));
    return '${code.toUpperCase()}|$tipo|$scad|$ubi'.toLowerCase();
  }

  List<Map<String, dynamic>> _assetsForRefs(
    Set<String> hostRefs,
    Map<String, List<Map<String, dynamic>>> byRef,
  ) {
    final seenId = <String>{};
    final seenFp = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final key in _expandMatchKeys(hostRefs)) {
      for (final row in byRef[key] ?? const <Map<String, dynamic>>[]) {
        final id = _s(row['id_uuid']);
        if (id.isEmpty) continue;
        if (!seenId.add(id)) continue;
        if (!seenFp.add(_assetFingerprint(row))) continue;
        out.add(row);
      }
    }
    out.sort((a, b) {
      final am = _s(a['matricola']).isNotEmpty
          ? _s(a['matricola'])
          : _s(a['codice_interno']);
      final bm = _s(b['matricola']).isNotEmpty
          ? _s(b['matricola'])
          : _s(b['codice_interno']);
      return am.toLowerCase().compareTo(bm.toLowerCase());
    });
    return out;
  }

  /// Raggruppa «Altro» per sede reale, non solo per il prefisso
  /// (`SEDE` / `MAGAZZINO`). Es. «SEDE CAIRO, 1 PIANO» ≠ «SEDE-TORRE ANNUNZIATA».
  String _altroGroupKey(Map<String, dynamic> row) {
    return _altroNormalizeSite(_s(row['ubicazione']));
  }

  String _altroNormalizeSite(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.split(',').first.trim();
    s = s.replaceAll(RegExp(r'\s*[-–—]\s*'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.toUpperCase();
  }

  String _altroSiteDetails(String raw) {
    final t = raw.trim();
    final comma = t.indexOf(',');
    if (comma < 0 || comma >= t.length - 1) return '';
    return t.substring(comma + 1).trim();
  }

  List<_HostSicurezzaRow> _altroRowsFromUnmatched({
    required List<Map<String, dynamic>> estintori,
    required List<Map<String, dynamic>> casette,
    required List<_HostSicurezzaRow> assigned,
  }) {
    final taken = <String>{};
    for (final host in assigned) {
      for (final e in host.estintori) {
        final id = _s(e['id_uuid']);
        if (id.isNotEmpty) taken.add(id);
      }
      for (final c in host.casette) {
        final id = _s(c['id_uuid']);
        if (id.isNotEmpty) taken.add(id);
      }
    }

    final estByKey = <String, List<Map<String, dynamic>>>{};
    final casByKey = <String, List<Map<String, dynamic>>>{};
    final detailsByKey = <String, List<String>>{};

    void putDetail(String key, String raw) {
      final d = _altroSiteDetails(raw);
      if (d.isEmpty) return;
      final list = detailsByKey.putIfAbsent(key, () => <String>[]);
      if (!list.any((e) => e.toLowerCase() == d.toLowerCase())) {
        list.add(d);
      }
    }

    for (final e in estintori) {
      if (taken.contains(_s(e['id_uuid']))) continue;
      final key = _altroGroupKey(e);
      estByKey.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(e);
      putDetail(key, _s(e['ubicazione']));
    }
    for (final c in casette) {
      if (taken.contains(_s(c['id_uuid']))) continue;
      final key = _altroGroupKey(c);
      casByKey.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(c);
      putDetail(key, _s(c['ubicazione']));
    }

    final keys = <String>{...estByKey.keys, ...casByKey.keys};
    final out = <_HostSicurezzaRow>[];
    for (final key in keys) {
      final est = List<Map<String, dynamic>>.from(
        estByKey[key] ?? const <Map<String, dynamic>>[],
      );
      final cas = List<Map<String, dynamic>>.from(
        casByKey[key] ?? const <Map<String, dynamic>>[],
      );
      if (est.isEmpty && cas.isEmpty) continue;
      int byCode(Map<String, dynamic> a, Map<String, dynamic> b) {
        final am = _s(a['matricola']).isNotEmpty
            ? _s(a['matricola'])
            : _s(a['codice_interno']);
        final bm = _s(b['matricola']).isNotEmpty
            ? _s(b['matricola'])
            : _s(b['codice_interno']);
        return am.toLowerCase().compareTo(bm.toLowerCase());
      }

      est.sort(byCode);
      cas.sort(byCode);
      final details = detailsByKey[key] ?? const <String>[];
      out.add(
        _HostSicurezzaRow(
          kind: 'altro',
          hostId: key.isEmpty ? 'altro-senza-ubicazione' : key,
          ubicante: key.isEmpty ? 'Senza ubicazione' : key,
          tipologia: 'Altro',
          commessa: '',
          posizione: details.join(' · '),
          estintori: est,
          casette: cas,
        ),
      );
    }
    return out;
  }

  String _shortTipoCasetta(String tipo) {
    final t = tipo.toLowerCase();
    if (t.contains('allegato 1') || t.contains('all.1') || t.contains('all 1')) {
      return 'All.1';
    }
    if (t.contains('allegato 2') || t.contains('all.2') || t.contains('all 2')) {
      return 'All.2';
    }
    if (tipo.length <= 14) return tipo;
    return '${tipo.substring(0, 14)}…';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client
            .from('logistica_box')
            .select(
              'id_uuid,numero_interno,codice_box,nome_box,tipologia,ubicazione,commessa_id,active',
            )
            .order('numero_interno'),
        client
            .from('logistica_mdo_ferroviari')
            .select(
              'id_uuid,matricola_interna,descrizione_mezzo,commessa,posizione_gps,active',
            )
            .order('matricola_interna'),
        client
            .from('logistica_mezzi_stradali')
            .select(
              'id_uuid,numerazione,targa,marca,modello,tipologia_mezzo,'
              'assegnatario_attuale,deposito_gomme,noleggiatore,active',
            )
            .order('targa'),
        client.from('estintori').select(
              'id_uuid,matricola,numero_estintore,codice_interno,ubicazione,prossimo_controllo,active',
            ),
        client.from('logistica_casette_ps').select(
              'id_uuid,codice_interno,tipo_cassetta,ubicazione,scadenze,active',
            ),
        client.from('commesse').select('id_uuid,nome'),
      ]);

      final boxes = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['active'] != false)
          .toList();
      final mdos = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['active'] != false)
          .toList();
      final mezzi = (results[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['active'] != false)
          .toList();
      final estintori = (results[3] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['active'] != false)
          .toList();
      final casette = (results[4] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => r['active'] != false)
          .toList();

      final commesseById = <String, String>{};
      for (final raw in results[5] as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _s(m['id_uuid']);
        if (id.isEmpty) continue;
        commesseById[id] = _s(m['nome']);
      }

      final estByRef = _indexByUbicazione(estintori);
      final casByRef = _indexByUbicazione(casette);

      String boxCommessa(Map<String, dynamic> row) {
        final id = _s(row['commessa_id']);
        if (id.isEmpty) return '';
        return commesseById[id] ?? '';
      }

      final boxRows = <_HostSicurezzaRow>[];
      for (final box in boxes) {
        final refs = logisticaBoxRefsFromRow(box);
        final ubicante = _s(box['numero_interno']).isNotEmpty
            ? _s(box['numero_interno'])
            : (_s(box['codice_box']).isNotEmpty
                ? _s(box['codice_box'])
                : _s(box['nome_box']));
        if (ubicante.isEmpty) continue;
        boxRows.add(
          _HostSicurezzaRow(
            kind: 'box',
            hostId: _s(box['id_uuid']),
            ubicante: ubicante,
            tipologia: _s(box['tipologia']).isNotEmpty
                ? _s(box['tipologia'])
                : _s(box['nome_box']),
            commessa: boxCommessa(box),
            posizione: _s(box['ubicazione']),
            estintori: _assetsForRefs(refs, estByRef),
            casette: _assetsForRefs(refs, casByRef),
          ),
        );
      }

      final mdoOut = <_HostSicurezzaRow>[];
      for (final mdo in mdos) {
        final refs = mdoUbicazioneRefsFromRow(mdo);
        final ubicante = _s(mdo['matricola_interna']);
        if (ubicante.isEmpty) continue;
        mdoOut.add(
          _HostSicurezzaRow(
            kind: 'mdo',
            hostId: _s(mdo['id_uuid']),
            ubicante: ubicante,
            tipologia: _s(mdo['descrizione_mezzo']),
            commessa: _s(mdo['commessa']),
            posizione: _s(mdo['posizione_gps']).isNotEmpty
                ? _s(mdo['posizione_gps'])
                : _s(mdo['descrizione_mezzo']),
            estintori: _assetsForRefs(refs, estByRef),
            casette: _assetsForRefs(refs, casByRef),
          ),
        );
      }

      final mezzoOut = <_HostSicurezzaRow>[];
      for (final mezzo in mezzi) {
        final refs = mezziStradaliUbicazioneRefsFromRow(mezzo);
        final targa = _s(mezzo['targa']);
        final num = _s(mezzo['numerazione']);
        final ubicante = targa.isNotEmpty ? targa : num;
        if (ubicante.isEmpty) continue;
        final tipoParts = <String>[
          _s(mezzo['marca']),
          _s(mezzo['modello']),
          _s(mezzo['tipologia_mezzo']),
        ].where((v) => v.isNotEmpty).toList();
        final pos = _s(mezzo['assegnatario_attuale']).isNotEmpty
            ? _s(mezzo['assegnatario_attuale'])
            : (_s(mezzo['deposito_gomme']).isNotEmpty
                ? _s(mezzo['deposito_gomme'])
                : _s(mezzo['noleggiatore']));
        mezzoOut.add(
          _HostSicurezzaRow(
            kind: 'mezzo',
            hostId: _s(mezzo['id_uuid']),
            ubicante: ubicante,
            tipologia: tipoParts.join(' '),
            commessa: num.isEmpty ? '' : 'N. $num',
            posizione: pos,
            estintori: _assetsForRefs(refs, estByRef),
            casette: _assetsForRefs(refs, casByRef),
          ),
        );
      }

      int rank(_HostSeverity s) {
        switch (s) {
          case _HostSeverity.critical:
            return 0;
          case _HostSeverity.incomplete:
            return 1;
          case _HostSeverity.warn:
            return 2;
          case _HostSeverity.ok:
            return 3;
        }
      }

      int cmp(_HostSicurezzaRow a, _HostSicurezzaRow b) {
        final bySev = rank(_severityOf(a)).compareTo(rank(_severityOf(b)));
        if (bySev != 0) return bySev;
        final da = _earliestDay(a);
        final db = _earliestDay(b);
        if (da == null && db == null) {
          return a.ubicante.toLowerCase().compareTo(b.ubicante.toLowerCase());
        }
        if (da == null) return 1;
        if (db == null) return -1;
        final byDate = da.compareTo(db);
        if (byDate != 0) return byDate;
        return a.ubicante.toLowerCase().compareTo(b.ubicante.toLowerCase());
      }

      boxRows.sort(cmp);
      mdoOut.sort(cmp);
      mezzoOut.sort(cmp);
      final altroOut = _altroRowsFromUnmatched(
        estintori: estintori,
        casette: casette,
        assigned: [...boxRows, ...mdoOut, ...mezzoOut],
      );
      altroOut.sort(cmp);

      if (!mounted) return;
      setState(() {
        _boxRows = boxRows;
        _mdoRows = mdoOut;
        _mezzoRows = mezzoOut;
        _altroRows = altroOut;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<_HostSicurezzaRow> get _source {
    switch (_scope) {
      case _HostScope.box:
        return _boxRows;
      case _HostScope.mdo:
        return _mdoRows;
      case _HostScope.mezzo:
        return _mezzoRows;
      case _HostScope.altro:
        return _altroRows;
    }
  }

  String get _scopeNoun {
    switch (_scope) {
      case _HostScope.box:
        return 'ubicanti';
      case _HostScope.mdo:
        return 'MDO';
      case _HostScope.mezzo:
        return 'mezzi';
      case _HostScope.altro:
        return 'altre sedi';
    }
  }

  List<_HostSicurezzaRow> _filtered(List<_HostSicurezzaRow> source) {
    var list = source;
    switch (_filter) {
      case _SicurezzaFilter.scaduti:
        list = list.where(_rowHasScaduto).toList(growable: false);
        break;
      case _SicurezzaFilter.inScadenza:
        list = list
            .where((r) => _rowHasInScadenza(r) && !_rowHasScaduto(r))
            .toList(growable: false);
        break;
      case _SicurezzaFilter.noEstintore:
        list = list.where((r) => r.missingEstintore).toList(growable: false);
        break;
      case _SicurezzaFilter.noCasetta:
        list = list.where((r) => r.missingCasetta).toList(growable: false);
        break;
      case _SicurezzaFilter.ok:
        list = list
            .where((r) => _severityOf(r) == _HostSeverity.ok)
            .toList(growable: false);
        break;
      case _SicurezzaFilter.all:
        break;
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((r) {
      final tokens = <String>[
        r.ubicante,
        r.tipologia,
        r.commessa,
        r.posizione,
        for (final e in r.estintori) ...[
          _s(e['matricola']),
          _s(e['numero_estintore']),
          _s(e['codice_interno']),
        ],
        for (final c in r.casette) ...[
          _s(c['codice_interno']),
          _s(c['tipo_cassetta']),
        ],
      ];
      return tokens.any((t) => t.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  String _estintoreMatricola(Map<String, dynamic> e) {
    final m = _s(e['matricola']);
    if (m.isNotEmpty) return m;
    final n = _s(e['numero_estintore']);
    if (n.isNotEmpty) return n;
    final c = _s(e['codice_interno']);
    return c.isEmpty ? '—' : c;
  }

  String _casettaLabel(Map<String, dynamic> c) {
    final code = _s(c['codice_interno']);
    final tipo = _s(c['tipo_cassetta']);
    final codePart = code.isEmpty ? '—' : code;
    if (tipo.isEmpty) return codePart;
    return '$codePart · ${_shortTipoCasetta(tipo)}';
  }

  UqsaExportTone _toneOfScadenza(dynamic v) {
    if (_isScaduto(v)) return UqsaExportTone.critical;
    if (_isInScadenza30(v)) return UqsaExportTone.warn;
    return UqsaExportTone.ok;
  }

  UqsaExportTone _toneOfSeverity(_HostSeverity s) {
    switch (s) {
      case _HostSeverity.critical:
        return UqsaExportTone.critical;
      case _HostSeverity.warn:
        return UqsaExportTone.warn;
      case _HostSeverity.incomplete:
        return UqsaExportTone.empty;
      case _HostSeverity.ok:
        return UqsaExportTone.ok;
    }
  }

  List<UqsaSediSicurezzaAssetLine> _estExportLines(_HostSicurezzaRow r) {
    return [
      for (final e in r.estintori)
        UqsaSediSicurezzaAssetLine(
          label: _estintoreMatricola(e),
          scadenza: _fmtScadenza(e['prossimo_controllo']),
          tone: _toneOfScadenza(e['prossimo_controllo']),
        ),
    ];
  }

  List<UqsaSediSicurezzaAssetLine> _casExportLines(_HostSicurezzaRow r) {
    return [
      for (final c in r.casette)
        UqsaSediSicurezzaAssetLine(
          label: _casettaLabel(c),
          scadenza: _fmtScadenza(c['scadenze']),
          tone: _toneOfScadenza(c['scadenze']),
        ),
    ];
  }

  UqsaSediSicurezzaExportRow _toExportRow(_HostSicurezzaRow r, int index) {
    final sev = _severityOf(r);
    return UqsaSediSicurezzaExportRow(
      index: index,
      ubicante: r.ubicante,
      tipologia: r.tipologia,
      commessa: r.commessa,
      posizione: r.posizione,
      estintori: _estExportLines(r),
      casette: _casExportLines(r),
      stato: _severityLabel(sev),
      statoTone: _toneOfSeverity(sev),
    );
  }

  UqsaSediSicurezzaExportSheet _sheetFor({
    required String name,
    required String tabLabel,
    required String noun,
    required List<_HostSicurezzaRow> source,
  }) {
    final rows = _filtered(source);
    final scaduti = rows.where(_rowHasScaduto).length;
    final noEst = rows.where((r) => r.missingEstintore).length;
    final noCas = rows.where((r) => r.missingCasetta).length;
    return UqsaSediSicurezzaExportSheet(
      name: name,
      tabLabel: tabLabel,
      summary:
          '${rows.length} $noun · $scaduti scaduti · $noEst senza est. · $noCas senza cass.',
      rows: [
        for (var i = 0; i < rows.length; i++) _toExportRow(rows[i], i + 1),
      ],
    );
  }

  Future<void> _exportExcel() async {
    if (_exporting || _loading) return;
    setState(() => _exporting = true);
    try {
      final bytes = UqsaSediSicurezzaExcelExport.build(
        sheets: [
          _sheetFor(
            name: 'BOX-CON',
            tabLabel: 'BOX / CON',
            noun: 'ubicanti',
            source: _boxRows,
          ),
          _sheetFor(
            name: 'MDO',
            tabLabel: 'MDO',
            noun: 'MDO',
            source: _mdoRows,
          ),
          _sheetFor(
            name: 'Mezzi stradali',
            tabLabel: 'Mezzi stradali',
            noun: 'mezzi',
            source: _mezzoRows,
          ),
          _sheetFor(
            name: 'Altro',
            tabLabel: 'Altro',
            noun: 'altre sedi',
            source: _altroRows,
          ),
        ],
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'UQSA_Sedi_sicurezza',
        bytes: bytes,
      );
      if (!saved || !mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            p.isEmpty ? 'Export Excel completato' : 'Export Excel completato: $p',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore export Excel: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _statusBadge(_HostSeverity sev) {
    final c = _severityColor(sev);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        _severityLabel(sev),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: c,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Future<void> _openWithHighlight({
    required String idUuid,
    required Widget page,
    required String title,
    String? activeSubKey,
  }) async {
    final id = idUuid.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 10);
    if (!mounted) return;
    await FuturisticNavigation.pushPage<void>(
      context,
      page: page,
      title: title,
      activeSubKey: activeSubKey,
    );
  }

  Future<void> _openUbicante(_HostSicurezzaRow row) async {
    if (row.kind == 'altro') return;
    if (row.kind == 'mdo') {
      await _openWithHighlight(
        idUuid: row.hostId,
        title: 'MDO ferroviari',
        activeSubKey: 'mdo_ferroviari',
        page: AdminLogisticaMdoFerroviariPage(forceMobileLayout: _isCompact),
      );
      return;
    }
    if (row.kind == 'mezzo') {
      await _openWithHighlight(
        idUuid: row.hostId,
        title: 'Mezzi stradali',
        activeSubKey: 'mezzi_stradali',
        page: AdminLogisticaMezziStradaliPage(forceMobileLayout: _isCompact),
      );
      return;
    }
    await _openWithHighlight(
      idUuid: row.hostId,
      title: 'Logistica BOX',
      activeSubKey: 'logistica_box',
      page: const AdminLogisticaBoxPage(),
    );
  }

  Future<void> _openEstintore(Map<String, dynamic> e) async {
    final id = _s(e['id_uuid']).isNotEmpty ? _s(e['id_uuid']) : _s(e['id']);
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 10);
    if (!mounted) return;
    await FuturisticNavigation.pushPage<void>(
      context,
      page: AdminEstintoriPage(highlightUuid: id),
      title: 'Estintori',
    );
  }

  Future<void> _openCasetta(Map<String, dynamic> c) async {
    final id = _s(c['id_uuid']).isNotEmpty ? _s(c['id_uuid']) : _s(c['id']);
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 10);
    if (!mounted) return;
    await FuturisticNavigation.pushPage<void>(
      context,
      page: AdminLogisticaCasettePsPage(highlightUuid: id),
      title: 'Cassette P.S.',
    );
  }

  Widget _assetCell({
    required Color accent,
    required String emptyLabel,
    required List<
            ({
              String label,
              String scad,
              dynamic scadRaw,
              VoidCallback? onDoubleTap
            })>
        items,
  }) {
    final fg = CronosAppThemes.onSurfaceOf(context);
    final muted = CronosAppThemes.mutedOf(context);
    if (items.isEmpty) {
      return Text(
        emptyLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: accent.withValues(alpha: 0.8),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _SicurezzaDoubleClick(
              onDoubleClick: item.onDoubleTap,
              tooltip: 'Doppio clic: apri la scheda e lampeggia la riga',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: fg,
                            decoration: TextDecoration.underline,
                            decorationColor: accent.withValues(alpha: 0.55),
                          ),
                          children: [
                            TextSpan(text: item.label),
                            TextSpan(
                              text: '  ·  ',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                                color: muted,
                              ),
                            ),
                            TextSpan(
                              text: item.scad,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: TextDecoration.none,
                                color: _scadenzaColor(context, item.scadRaw),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: accent.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static const List<double> _colW = <double>[
    52, 220, 88, 196, 176, 236, 236, 108,
  ];

  double get _tableMinW =>
      _colW.fold<double>(0, (sum, w) => sum + w);

  Widget _headerCell(String text, double width, {Color? bg}) {
    final dark = CronosAppThemes.isDarkOf(context);
    return SizedBox(
      width: width,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: bg ??
            (dark ? const Color(0xFF243328) : const Color(0xFFD6E4C7)),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: dark ? CronosAppThemes.darkSidebarFg : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _textCell(
    double width,
    String text, {
    TextStyle? style,
    int maxLines = 2,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style ??
              TextStyle(
                fontSize: 12,
                color: CronosAppThemes.onSurfaceOf(context),
              ),
        ),
      ),
    );
  }

  Widget _tableHeader() {
    final dark = CronosAppThemes.isDarkOf(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _headerCell('#', _colW[0]),
          _headerCell('UBICANTE', _colW[1]),
          _headerCell('TIPO', _colW[2]),
          _headerCell('COMMESSA', _colW[3]),
          _headerCell('POSIZIONE', _colW[4]),
          _headerCell(
            'ESTINTORI',
            _colW[5],
            bg: dark ? const Color(0xFF3A1C1C) : const Color(0xFFF3C4C4),
          ),
          _headerCell(
            'CASSETTE P.S.',
            _colW[6],
            bg: dark ? const Color(0xFF1A2740) : const Color(0xFFC9D6F2),
          ),
          _headerCell('STATO', _colW[7]),
        ],
      ),
    );
  }

  Widget _tableRow(_HostSicurezzaRow row, int index) {
    final sev = _severityOf(row);
    final fg = CronosAppThemes.onSurfaceOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: index.isEven
            ? CronosAppThemes.cardOf(context)
            : CronosAppThemes.cardMutedOf(context),
        border: Border(
          bottom: BorderSide(color: CronosAppThemes.hairlineOf(context)),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _textCell(
              _colW[0],
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            SizedBox(
              width: _colW[1],
              child: row.kind == 'altro'
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Text(
                        row.ubicante,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: fg,
                        ),
                      ),
                    )
                  : _SicurezzaDoubleClick(
                      onDoubleClick: () => _openUbicante(row),
                      tooltip: 'Doppio clic per aprire BOX / MDO / mezzo',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Text(
                          row.ubicante,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: fg,
                          ),
                        ),
                      ),
                    ),
            ),
            _textCell(_colW[2], row.tipologia),
            _textCell(_colW[3], row.commessa),
            _textCell(_colW[4], row.posizione),
            SizedBox(
              width: _colW[5],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _assetCell(
                  accent: _estAccent,
                  emptyLabel: 'Nessun estintore',
                  items: [
                    for (final e in row.estintori)
                      (
                        label: _estintoreMatricola(e),
                        scad: _fmtScadenza(e['prossimo_controllo']),
                        scadRaw: e['prossimo_controllo'],
                        onDoubleTap: () => _openEstintore(e),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _colW[6],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: _assetCell(
                  accent: _casAccent,
                  emptyLabel: 'Nessuna cassetta',
                  items: [
                    for (final c in row.casette)
                      (
                        label: _casettaLabel(c),
                        scad: _fmtScadenza(c['scadenze']),
                        scadRaw: c['scadenze'],
                        onDoubleTap: () => _openCasetta(c),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _colW[7],
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _statusBadge(sev),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField({double? width}) {
    final field = TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: 'Cerca…',
        isDense: true,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      ),
      onChanged: (v) => setState(() => _search = v),
    );
    if (width == null) return SizedBox(height: 38, child: field);
    return SizedBox(width: width, height: 38, child: field);
  }

  Widget _filterDropdown({bool compact = false}) {
    return DropdownButton<_SicurezzaFilter>(
      value: _filter,
      isDense: true,
      isExpanded: compact,
      underline: compact ? const SizedBox.shrink() : null,
      items: [
        const DropdownMenuItem(
          value: _SicurezzaFilter.all,
          child: Text('Tutti'),
        ),
        const DropdownMenuItem(
          value: _SicurezzaFilter.scaduti,
          child: Text('Scaduti'),
        ),
        DropdownMenuItem(
          value: _SicurezzaFilter.inScadenza,
          child: Text(compact ? '≤30gg' : 'In scadenza ≤30gg'),
        ),
        DropdownMenuItem(
          value: _SicurezzaFilter.noEstintore,
          child: Text(compact ? 'Senza est.' : 'Senza estintore'),
        ),
        DropdownMenuItem(
          value: _SicurezzaFilter.noCasetta,
          child: Text(compact ? 'Senza cass.' : 'Senza cassetta'),
        ),
        const DropdownMenuItem(
          value: _SicurezzaFilter.ok,
          child: Text('Solo OK'),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filter = v);
      },
    );
  }

  Widget _scopeChips() {
    Widget chip(_HostScope scope, String label, int count) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label ($count)'),
          selected: _scope == scope,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => setState(() => _scope = scope),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_HostScope.box, 'BOX', _boxRows.length),
          chip(_HostScope.mdo, 'MDO', _mdoRows.length),
          chip(_HostScope.mezzo, 'Mezzi', _mezzoRows.length),
          chip(_HostScope.altro, 'Altro', _altroRows.length),
        ],
      ),
    );
  }

  Widget _mobileAssetSection({
    required String title,
    required Color accent,
    required IconData icon,
    required String emptyLabel,
    required List<
            ({
              String label,
              String scad,
              dynamic scadRaw,
              VoidCallback onOpen
            })>
        items,
  }) {
    final muted = CronosAppThemes.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: accent,
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                emptyLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.85),
                ),
              ),
            )
          else
            for (final item in items)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: item.onOpen,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: CronosAppThemes.onSurfaceOf(context),
                              ),
                              children: [
                                TextSpan(text: item.label),
                                TextSpan(
                                  text: '  ·  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: muted,
                                  ),
                                ),
                                TextSpan(
                                  text: item.scad,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _scadenzaColor(context, item.scadRaw),
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _mobileCard(_HostSicurezzaRow row, int index) {
    final sev = _severityOf(row);
    final fg = CronosAppThemes.onSurfaceOf(context);
    final muted = CronosAppThemes.mutedOf(context);
    final canOpenHost = row.kind != 'altro';
    final meta = [
      if (row.tipologia.isNotEmpty) row.tipologia,
      if (row.commessa.isNotEmpty) row.commessa,
    ].join('  ·  ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: CronosAppThemes.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _severityColor(sev).withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: muted,
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: canOpenHost ? () => _openUbicante(row) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.ubicante,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: fg,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: muted,
                                ),
                              ),
                            ),
                          if (row.posizione.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                row.posizione,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _statusBadge(sev),
                if (canOpenHost)
                  IconButton(
                    tooltip: 'Apri scheda',
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _openUbicante(row),
                  ),
              ],
            ),
            _mobileAssetSection(
              title: 'ESTINTORI',
              accent: _estAccent,
              icon: Icons.fire_extinguisher_outlined,
              emptyLabel: 'Nessun estintore',
              items: [
                for (final e in row.estintori)
                  (
                    label: _estintoreMatricola(e),
                    scad: _fmtScadenza(e['prossimo_controllo']),
                    scadRaw: e['prossimo_controllo'],
                    onOpen: () => _openEstintore(e),
                  ),
              ],
            ),
            _mobileAssetSection(
              title: 'CASSETTE P.S.',
              accent: _casAccent,
              icon: Icons.medical_services_outlined,
              emptyLabel: 'Nessuna cassetta',
              items: [
                for (final c in row.casette)
                  (
                    label: _casettaLabel(c),
                    scad: _fmtScadenza(c['scadenze']),
                    scadRaw: c['scadenze'],
                    onOpen: () => _openCasetta(c),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList(List<_HostSicurezzaRow> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _mobileCard(items[i], i),
    );
  }

  Widget _toolbar(List<_HostSicurezzaRow> source) {
    final scaduti = source.where(_rowHasScaduto).length;
    final noEst = source.where((r) => r.missingEstintore).length;
    final noCas = source.where((r) => r.missingCasetta).length;
    final compact = _isCompact;
    final stats = Text(
      '${source.length} $_scopeNoun'
      ' · $scaduti scaduti · $noEst senza est. · $noCas senza cass.',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _scopeChips(),
            const SizedBox(height: 8),
            _searchField(),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _filterDropdown(compact: true)),
                IconButton(
                  tooltip: 'Export Excel',
                  onPressed: _loading || _exporting
                      ? null
                      : () => unawaited(_exportExcel()),
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                ),
              ],
            ),
            stats,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_HostScope>(
                segments: [
                  ButtonSegment(
                    value: _HostScope.box,
                    label: Text('BOX / CON (${_boxRows.length})'),
                  ),
                  ButtonSegment(
                    value: _HostScope.mdo,
                    label: Text('MDO (${_mdoRows.length})'),
                  ),
                  ButtonSegment(
                    value: _HostScope.mezzo,
                    label: Text('Mezzi stradali (${_mezzoRows.length})'),
                  ),
                  ButtonSegment(
                    value: _HostScope.altro,
                    label: Text('Altro (${_altroRows.length})'),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              _searchField(width: 260),
              _filterDropdown(),
              OutlinedButton.icon(
                onPressed: _loading || _exporting
                    ? null
                    : () => unawaited(_exportExcel()),
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Excel'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          stats,
        ],
      ),
    );
  }

  Widget _buildList(List<_HostSicurezzaRow> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Nessun risultato.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (_isCompact) return _buildMobileList(items);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableW = constraints.maxWidth < _tableMinW
            ? _tableMinW
            : constraints.maxWidth;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableHeader(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _tableRow(items[i], i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final items = _filtered(_source);

    final compact = _isCompact;

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: ResponsiveAppBarTitle(
            title: compact ? 'Sedi sicurezza' : 'UQSA — Sedi sicurezza',
          ),
          actions: [
            if (!compact)
              IconButton(
                tooltip: 'Export Excel',
                onPressed: _loading || _exporting
                    ? null
                    : () => unawaited(_exportExcel()),
                icon: const Icon(Icons.download_outlined),
              ),
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: PageWithTopLogo(
        showLogo: !compact,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Errore: $_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _toolbar(_source),
                      const Divider(height: 1),
                      Expanded(child: _buildList(items)),
                    ],
                  ),
      ),
    );
  }
}

/// Doppio clic affidabile anche sul web (mouse), come sul titolo BOX/MDO.
class _SicurezzaDoubleClick extends StatefulWidget {
  const _SicurezzaDoubleClick({
    required this.child,
    this.onDoubleClick,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onDoubleClick;
  final String? tooltip;

  @override
  State<_SicurezzaDoubleClick> createState() => _SicurezzaDoubleClickState();
}

class _SicurezzaDoubleClickState extends State<_SicurezzaDoubleClick> {
  DateTime? _lastDown;
  Offset? _lastPos;
  DateTime? _firedAt;
  bool _hover = false;

  void _fire() {
    final cb = widget.onDoubleClick;
    if (cb == null) return;
    final now = DateTime.now();
    if (_firedAt != null &&
        now.difference(_firedAt!) < const Duration(milliseconds: 450)) {
      return;
    }
    _firedAt = now;
    cb();
  }

  void _onPointerDown(PointerDownEvent e) {
    if (widget.onDoubleClick == null) return;
    if (e.buttons != 0 && e.buttons != 1) return;
    final now = DateTime.now();
    final last = _lastDown;
    final lastPos = _lastPos;
    _lastDown = now;
    _lastPos = e.position;
    if (last == null || lastPos == null) return;
    if (now.difference(last) > const Duration(milliseconds: 550)) return;
    if ((e.position - lastPos).distance > 24) return;
    _lastDown = null;
    _lastPos = null;
    _fire();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onDoubleClick != null;
    Widget body = MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hover && enabled
              ? const Color(0xFF1565C0).withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: widget.child,
      ),
    );
    body = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: enabled ? _fire : null,
        child: body,
      ),
    );
    final tip = widget.tooltip;
    if (tip == null || !enabled) return body;
    return Tooltip(message: tip, waitDuration: const Duration(milliseconds: 600), child: body);
  }
}
