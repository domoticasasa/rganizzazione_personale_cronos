import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_web_safe.dart';
import '../utils/logistica_layout.dart';
import '../utils/mdo_gps_coords.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class AdminLogisticaMdoProprietaPage extends StatefulWidget {
  const AdminLogisticaMdoProprietaPage({super.key});

  @override
  State<AdminLogisticaMdoProprietaPage> createState() =>
      _AdminLogisticaMdoProprietaPageState();
}

class _AdminLogisticaMdoProprietaPageState
    extends State<AdminLogisticaMdoProprietaPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  String _search = '';
  List<Map<String, dynamic>> _rows = [];
  String? _expandedMobileGroup;
  final Map<String, String> _commesse = {};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadCommesse();
    await _loadRows();
  }

  Future<void> _loadCommesse() async {
    try {
      final res = await _supa
          .from('commesse')
          .select('id_uuid,nome,active')
          .eq('active', true)
          .order('nome');
      _commesse
        ..clear()
        ..addEntries((res as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return MapEntry(
            (m['id_uuid'] ?? '').toString(),
            (m['nome'] ?? '').toString(),
          );
        }));
    } catch (_) {}
  }

  Future<void> _loadRows() async {
    setState(() => _loading = true);
    try {
      final res = await _supa
          .from('logistica_mdo_proprieta')
          .select()
          .eq('active', true)
          .order('codifica_gruppo')
          .order('ordine');
      var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (_search.trim().isNotEmpty) {
        final k = _search.toLowerCase().trim();
        list = list
            .where((r) => _rowTokens(r).any((t) => t.contains(k)))
            .toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e')),
      );
    }
  }

  List<String> _rowTokens(Map<String, dynamic> r) => [
        r['codifica_gruppo'],
        r['codifica'],
        r['tipologia'],
        r['matricola'],
        r['definizione_classe_mezzo'],
        r['numero_serie'],
        r['dichiarazione_conformita_ce'],
        r['ubicazione'],
        r['posizione_gps'],
        _commesse[(r['commessa_id'] ?? '').toString()],
      ].map((v) => (v ?? '').toString().toLowerCase()).toList();

  Future<void> _openCoordsOnMap(Map<String, dynamic> row) async {
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna coordinata GPS valida.')),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _fmtDate(dynamic v) => formatDateDdMmYyyy(v);

  Color? _scadenzaColor(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return null;
    DateTime? d;
    if (v is DateTime) {
      d = v;
    } else {
      d = DateTime.tryParse(v.toString());
    }
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    if (target.isBefore(today)) return Colors.red.shade700;
    if (!target.isAfter(today.add(const Duration(days: 60)))) {
      return Colors.orange.shade800;
    }
    return Colors.green.shade700;
  }

  Map<String, List<Map<String, dynamic>>> get _groupedRows {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final g = (r['codifica_gruppo'] ?? '').toString();
      out.putIfAbsent(g, () => <Map<String, dynamic>>[]).add(r);
    }
    return out;
  }

  Future<void> _deleteRow(String id) async {
    if (!await ensureCanPersist(context)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina riga'),
        content: const Text('Confermi l\'eliminazione di questa voce?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('logistica_mdo_proprieta').delete().eq('id_uuid', id);
    await _loadRows();
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MdoProprietaDialog(
        row: row,
        gruppiEsistenti: _groupedRows.keys.toList()..sort(),
        commesse: _commesse,
      ),
    );
    if (saved == true) await _loadRows();
  }

  Future<void> _exportExcel() async {
    final wb = Excel.createExcel();
    final sheet = excelUseDefaultSheet(wb);
    const headers = [
      'Codifica',
      'TIPOLOGIA',
      'MATRICOLA',
      'Definizione Classe Mezzo',
      'N. SERIE',
      'DICH. CONF. CE',
      'SCADENZA VERIFICA PERIODICA',
      'UBICAZIONE',
      'COMMESSA',
      'COORDINATE GPS',
    ];
    sheet.appendRow(headers);
    for (final g in _groupedRows.keys.toList()..sort()) {
      for (final r in _groupedRows[g]!) {
        sheet.appendRow([
          (r['is_mezzo_principale'] == true) ? r['codifica_gruppo'] : null,
          r['tipologia'],
          r['matricola'],
          r['definizione_classe_mezzo'],
          r['numero_serie'],
          r['dichiarazione_conformita_ce'],
          _fmtDate(r['scadenza_verifica_periodica']),
          r['ubicazione'],
          _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
          (r['posizione_gps'] ?? '').toString(),
        ]);
      }
    }
    final bytes = Uint8List.fromList(wb.encode()!);
    final saved = await ExcelExportHelper.saveAndReveal(
      pageName: 'MDO_Proprieta',
      bytes: bytes,
    );
    if (!mounted) return;
    if (saved) {
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(p.isEmpty ? 'Export completato' : 'Salvato: $p')),
      );
    }
  }

  Widget _header(String t) => Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      );

  Widget _mobileInfo(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ],
        ),
      );

  Widget _buildMobileList() {
    final groups = _groupedRows.keys.toList()..sort();
    if (groups.isEmpty) {
      return const Center(child: Text('Nessun MDO proprietà trovato'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final g = groups[index];
        final items = _groupedRows[g]!;
        final main = items.firstWhere(
          (r) => (r['is_mezzo_principale'] ?? false) == true,
          orElse: () => items.first,
        );
        final expanded = _expandedMobileGroup == g;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            key: PageStorageKey<String>('mdo_prop_$g'),
            initiallyExpanded: expanded,
            onExpansionChanged: (v) =>
                setState(() => _expandedMobileGroup = v ? g : null),
            title: Text(
              '$g — ${(main['tipologia'] ?? '').toString()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if ((main['matricola'] ?? '').toString().isNotEmpty)
                  'Matr. ${main['matricola']}',
                if ((main['ubicazione'] ?? '').toString().isNotEmpty)
                  main['ubicazione'].toString(),
              ].join(' · '),
            ),
            children: [
              for (final r in items) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((r['is_mezzo_principale'] ?? false) != true)
                        Text(
                          '↳ Accessorio',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      _mobileInfo('Tipologia', (r['tipologia'] ?? '').toString()),
                      _mobileInfo('Matricola', (r['matricola'] ?? '').toString()),
                      _mobileInfo(
                        'Definizione classe',
                        (r['definizione_classe_mezzo'] ?? '').toString(),
                      ),
                      _mobileInfo('N. serie', (r['numero_serie'] ?? '').toString()),
                      _mobileInfo(
                        'Dich. conf. CE',
                        (r['dichiarazione_conformita_ce'] ?? '').toString(),
                      ),
                      Row(
                        children: [
                          const SizedBox(
                            width: 150,
                            child: Text(
                              'Scad. verifica',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _fmtDate(r['scadenza_verifica_periodica']).isEmpty
                                  ? '—'
                                  : _fmtDate(r['scadenza_verifica_periodica']),
                              style: TextStyle(
                                color: _scadenzaColor(
                                    r['scadenza_verifica_periodica']),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _mobileInfo('Ubicazione', (r['ubicazione'] ?? '').toString()),
                      _mobileInfo(
                        'Commessa',
                        _commesse[(r['commessa_id'] ?? '').toString()] ?? '',
                      ),
                      _mobileInfo(
                        'Posizione GPS',
                        (r['posizione_gps'] ?? '').toString(),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Apri su Maps',
                            onPressed: mdoGpsCoordsFromRow(r) == null
                                ? null
                                : () => _openCoordsOnMap(r),
                            icon: const Icon(Icons.map_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Modifica',
                            onPressed: () => _openForm(row: r),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Elimina',
                            onPressed: () => _deleteRow(
                              (r['id_uuid'] ?? '').toString(),
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = isLogisticaCompactLayout(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Row(
          children: [
            AppLogo(size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('MDO Proprietà')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Aggiungi',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'Esporta Excel',
            onPressed: _rows.isEmpty ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading ? null : _loadRows,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cerca codifica, tipologia, matricola, ubicazione…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _search = '');
                          _loadRows();
                        },
                      ),
              ),
              onChanged: (v) {
                setState(() => _search = v);
                _loadRows();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : isMobile
                    ? _buildMobileList()
                    : logisticaScrollableTable(
                        context: context,
                        child: SingleChildScrollView(
                          child: DataTable(
                            showCheckboxColumn: false,
                            columnSpacing: 10,
                            headingRowHeight: 42,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 52,
                            columns: [
                              DataColumn(label: _header('Codifica')),
                              DataColumn(label: _header('Tipologia')),
                              DataColumn(label: _header('Matricola')),
                              DataColumn(label: _header('Def. classe mezzo')),
                              DataColumn(label: _header('N. serie')),
                              DataColumn(label: _header('Dich. conf. CE')),
                              DataColumn(label: _header('Scad. verifica')),
                              DataColumn(label: _header('Ubicazione')),
                              DataColumn(label: _header('Commessa')),
                              DataColumn(label: _header('Posizione GPS')),
                              const DataColumn(label: Text('Azioni')),
                            ],
                            rows: _rows.map((r) {
                              final id = (r['id_uuid'] ?? '').toString();
                              final isMain =
                                  (r['is_mezzo_principale'] ?? false) == true;
                              final scadColor =
                                  _scadenzaColor(r['scadenza_verifica_periodica']);
                              return DataRow(
                                color: WidgetStateProperty.resolveWith<Color?>(
                                  (_) => isMain
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.35)
                                      : null,
                                ),
                                cells: [
                                  DataCell(Text(
                                    isMain
                                        ? (r['codifica_gruppo'] ?? '').toString()
                                        : '↳ ${r['codifica_gruppo'] ?? ''}',
                                  )),
                                  DataCell(SizedBox(
                                    width: 220,
                                    child: Text(
                                      (r['tipologia'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                  DataCell(Text((r['matricola'] ?? '').toString())),
                                  DataCell(SizedBox(
                                    width: 180,
                                    child: Text(
                                      (r['definizione_classe_mezzo'] ?? '')
                                          .toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                  DataCell(Text((r['numero_serie'] ?? '').toString())),
                                  DataCell(SizedBox(
                                    width: 160,
                                    child: Text(
                                      (r['dichiarazione_conformita_ce'] ?? '')
                                          .toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                  DataCell(Text(
                                    _fmtDate(r['scadenza_verifica_periodica'])
                                            .isEmpty
                                        ? '—'
                                        : _fmtDate(
                                            r['scadenza_verifica_periodica']),
                                    style: TextStyle(
                                      color: scadColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )),
                                  DataCell(Text((r['ubicazione'] ?? '').toString())),
                                  DataCell(SizedBox(
                                    width: 140,
                                    child: Text(
                                      _commesse[
                                              (r['commessa_id'] ?? '').toString()] ??
                                          '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                  DataCell(SizedBox(
                                    width: 150,
                                    child: Text(
                                      (r['posizione_gps'] ?? '').toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Apri su Maps',
                                        onPressed: mdoGpsCoordsFromRow(r) == null
                                            ? null
                                            : () => _openCoordsOnMap(r),
                                        icon: const Icon(Icons.map_outlined,
                                            size: 20),
                                      ),
                                      IconButton(
                                        tooltip: 'Modifica',
                                        onPressed: () => _openForm(row: r),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 20),
                                      ),
                                      IconButton(
                                        tooltip: 'Elimina',
                                        onPressed: id.isEmpty
                                            ? null
                                            : () => _deleteRow(id),
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20, color: Colors.red),
                                      ),
                                    ],
                                  )),
                                ],
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _MdoProprietaDialog extends StatefulWidget {
  const _MdoProprietaDialog({
    this.row,
    required this.gruppiEsistenti,
    required this.commesse,
  });

  final Map<String, dynamic>? row;
  final List<String> gruppiEsistenti;
  final Map<String, String> commesse;

  @override
  State<_MdoProprietaDialog> createState() => _MdoProprietaDialogState();
}

class _MdoProprietaDialogState extends State<_MdoProprietaDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController _gruppoCtrl;
  late final TextEditingController _codificaCtrl;
  late final TextEditingController _tipologiaCtrl;
  late final TextEditingController _matricolaCtrl;
  late final TextEditingController _definizioneCtrl;
  late final TextEditingController _serieCtrl;
  late final TextEditingController _dichCtrl;
  late final TextEditingController _ubicazioneCtrl;
  late final TextEditingController _scadenzaCtrl;
  late final TextEditingController _posizioneGpsCtrl;
  late final TextEditingController _commessaSearchCtrl;
  String? _commessaSel;
  double? _latitudine;
  double? _longitudine;
  bool _gpsLoading = false;
  bool _isPrincipale = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _gruppoCtrl =
        TextEditingController(text: (r?['codifica_gruppo'] ?? '').toString());
    _codificaCtrl = TextEditingController(text: (r?['codifica'] ?? '').toString());
    _tipologiaCtrl = TextEditingController(text: (r?['tipologia'] ?? '').toString());
    _matricolaCtrl = TextEditingController(text: (r?['matricola'] ?? '').toString());
    _definizioneCtrl = TextEditingController(
      text: (r?['definizione_classe_mezzo'] ?? '').toString(),
    );
    _serieCtrl = TextEditingController(text: (r?['numero_serie'] ?? '').toString());
    _dichCtrl = TextEditingController(
      text: (r?['dichiarazione_conformita_ce'] ?? '').toString(),
    );
    _ubicazioneCtrl = TextEditingController(text: (r?['ubicazione'] ?? '').toString());
    _scadenzaCtrl = TextEditingController(
      text: formatDateDdMmYyyy(r?['scadenza_verifica_periodica']),
    );
    _posizioneGpsCtrl =
        TextEditingController(text: (r?['posizione_gps'] ?? '').toString());
    _commessaSel = (r?['commessa_id'] ?? '').toString().trim().isEmpty
        ? null
        : (r?['commessa_id'] ?? '').toString();
    _commessaSearchCtrl = TextEditingController(
      text: widget.commesse[_commessaSel ?? ''] ?? '',
    );
    _latitudine =
        (r?['latitudine'] is num) ? (r?['latitudine'] as num).toDouble() : null;
    _longitudine = (r?['longitudine'] is num)
        ? (r?['longitudine'] as num).toDouble()
        : null;
    _isPrincipale = (r?['is_mezzo_principale'] ?? false) == true;
  }

  @override
  void dispose() {
    _gruppoCtrl.dispose();
    _codificaCtrl.dispose();
    _tipologiaCtrl.dispose();
    _matricolaCtrl.dispose();
    _definizioneCtrl.dispose();
    _serieCtrl.dispose();
    _dichCtrl.dispose();
    _ubicazioneCtrl.dispose();
    _scadenzaCtrl.dispose();
    _posizioneGpsCtrl.dispose();
    _commessaSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fillFromGps() async {
    setState(() => _gpsLoading = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servizio GPS disattivato.')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso posizione negato.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final lat = pos.latitude.toStringAsFixed(6);
      final lon = pos.longitude.toStringAsFixed(6);
      setState(() {
        _posizioneGpsCtrl.text = 'GPS: $lat, $lon';
        _latitudine = pos.latitude;
        _longitudine = pos.longitude;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile leggere coordinate GPS.')),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openGpsOnMap() async {
    final coords = (_latitudine != null && _longitudine != null)
        ? (_latitudine!, _longitudine!)
        : mdoGpsCoordsFromText(_posizioneGpsCtrl.text);
    if (coords == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna coordinata GPS valida.')),
      );
      return;
    }
    final (lat, lon) = coords;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _syncCoordsFromGpsText(String text) {
    final coords = mdoGpsCoordsFromText(text);
    if (coords != null) {
      _latitudine = coords.$1;
      _longitudine = coords.$2;
    } else if (!text.trim().toUpperCase().startsWith('GPS:')) {
      _latitudine = null;
      _longitudine = null;
    }
  }

  DateTime? _parseDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final parts = t.split(RegExp(r'[./-]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }
    return DateTime.tryParse(t);
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    final gruppo = _gruppoCtrl.text.trim();
    if (gruppo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Codifica gruppo obbligatoria (es. MdO1)')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final scad = _parseDate(_scadenzaCtrl.text);
      _syncCoordsFromGpsText(_posizioneGpsCtrl.text);
      final payload = <String, dynamic>{
        'codifica_gruppo': gruppo,
        'codifica': _codificaCtrl.text.trim().isEmpty
            ? null
            : _codificaCtrl.text.trim(),
        'is_mezzo_principale': _isPrincipale,
        'tipologia': _tipologiaCtrl.text.trim(),
        'matricola': _matricolaCtrl.text.trim(),
        'definizione_classe_mezzo': _definizioneCtrl.text.trim(),
        'numero_serie': _serieCtrl.text.trim(),
        'dichiarazione_conformita_ce': _dichCtrl.text.trim(),
        'scadenza_verifica_periodica':
            scad?.toIso8601String().split('T').first,
        'ubicazione': _ubicazioneCtrl.text.trim(),
        'commessa_id': (_commessaSel ?? '').trim().isEmpty ? null : _commessaSel,
        'posizione_gps': _posizioneGpsCtrl.text.trim().isEmpty
            ? null
            : _posizioneGpsCtrl.text.trim(),
        'latitudine': _latitudine,
        'longitudine': _longitudine,
        'active': true,
      };

      final id = (widget.row?['id_uuid'] ?? '').toString().trim();
      if (id.isNotEmpty) {
        await _supa.from('logistica_mdo_proprieta').update(payload).eq('id_uuid', id);
      } else {
        final maxOrd = await _supa
            .from('logistica_mdo_proprieta')
            .select('ordine')
            .eq('codifica_gruppo', gruppo)
            .order('ordine', ascending: false)
            .limit(1);
        var nextOrd = 1;
        if ((maxOrd as List).isNotEmpty) {
          nextOrd =
              (((maxOrd.first as Map)['ordine'] as num?)?.toInt() ?? 0) + 1;
        }
        payload['ordine'] = nextOrd;
        if (_isPrincipale && (payload['codifica'] == null)) {
          payload['codifica'] = gruppo;
        }
        await _supa.from('logistica_mdo_proprieta').insert(payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commessaItems = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: Text(widget.row == null ? 'Nuovo MDO proprietà' : 'Modifica voce'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _gruppoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Codifica gruppo *',
                  hintText: 'MdO1, MdO2…',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mezzo principale'),
                subtitle: const Text('Escavatore, carrello, ecc.'),
                value: _isPrincipale,
                onChanged: (v) => setState(() => _isPrincipale = v),
              ),
              TextField(
                controller: _codificaCtrl,
                decoration: const InputDecoration(labelText: 'Codifica'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tipologiaCtrl,
                decoration: const InputDecoration(labelText: 'Tipologia'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _matricolaCtrl,
                decoration: const InputDecoration(labelText: 'Matricola'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _definizioneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Definizione classe mezzo',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serieCtrl,
                decoration: const InputDecoration(labelText: 'N. serie'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dichCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dichiarazione conformità CE',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _scadenzaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Scadenza verifica periodica (gg/mm/aaaa)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ubicazioneCtrl,
                decoration: const InputDecoration(labelText: 'Ubicazione'),
              ),
              const SizedBox(height: 8),
              Autocomplete<MapEntry<String, String>>(
                initialValue: TextEditingValue(text: _commessaSearchCtrl.text),
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return commessaItems;
                  return commessaItems
                      .where((e) => e.value.toLowerCase().contains(q));
                },
                displayStringForOption: (opt) => opt.value,
                onSelected: (opt) {
                  setState(() {
                    _commessaSel = opt.key;
                    _commessaSearchCtrl.text = opt.value;
                  });
                },
                fieldViewBuilder:
                    (context, textCtrl, focusNode, onFieldSubmitted) {
                  if (textCtrl.text != _commessaSearchCtrl.text) {
                    textCtrl.text = _commessaSearchCtrl.text;
                  }
                  return TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Commessa (scrivi e seleziona)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Azzera commessa',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          textCtrl.clear();
                          _commessaSearchCtrl.clear();
                          setState(() => _commessaSel = null);
                        },
                      ),
                    ),
                    onChanged: (v) {
                      _commessaSearchCtrl.text = v;
                      final match = commessaItems
                          .where((e) => e.value.toLowerCase() == v.toLowerCase())
                          .toList();
                      if (match.length == 1) {
                        _commessaSel = match.first.key;
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _posizioneGpsCtrl,
                decoration: InputDecoration(
                  labelText: 'Coordinate GPS (lat, lon o link Maps)',
                  border: const OutlineInputBorder(),
                  suffixIcon: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Prendi coordinate GPS',
                          onPressed: _gpsLoading ? null : _fillFromGps,
                          icon: _gpsLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                        ),
                        IconButton(
                          tooltip: 'Apri su mappa',
                          onPressed: _openGpsOnMap,
                          icon: const Icon(Icons.map_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                onChanged: (v) => setState(() => _syncCoordsFromGpsText(v)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}
