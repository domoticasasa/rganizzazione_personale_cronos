import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/supabase_service.dart';
import '../services/viaggi_mezzi_stradali_service.dart';
import '../utils/date_formatters.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/modify_feedback.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum ViaggiMezziReportMode {
  admin,
  conducente,
  assegnatario,
}

class ViaggiMezziReportPage extends StatefulWidget {
  const ViaggiMezziReportPage({
    super.key,
    required this.mode,
  });

  final ViaggiMezziReportMode mode;

  @override
  State<ViaggiMezziReportPage> createState() => _ViaggiMezziReportPageState();
}

class _ViaggiMezziReportPageState extends State<ViaggiMezziReportPage> {
  final _supa = SupabaseService.client;
  static final _monthFmt = DateFormat('MMMM yyyy', 'it_IT');

  bool _loading = true;
  late DateTime _month;
  List<Map<String, dynamic>> _rows = const [];
  String _search = '';

  DateTime get _monthStart => DateTime(_month.year, _month.month, 1);
  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);

  String get _title {
    switch (widget.mode) {
      case ViaggiMezziReportMode.admin:
        return 'Report viaggi mezzi';
      case ViaggiMezziReportMode.conducente:
        return 'I miei viaggi';
      case ViaggiMezziReportMode.assegnatario:
        return 'Viaggi sui miei mezzi';
    }
  }

  @override
  void initState() {
    super.initState();
    final now = italyNow();
    _month = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await ViaggiMezziStradaliService.loadViaggi(
        supa: _supa,
        dal: _monthStart,
        al: _monthEnd,
        soloMieiViaggi: widget.mode == ViaggiMezziReportMode.conducente,
        soloMieiMezziAssegnatario:
            widget.mode == ViaggiMezziReportMode.assegnatario,
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
    _load();
  }

  String _formatMonth(DateTime month) {
    final raw = _monthFmt.format(month);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final mezzo = r['logistica_mezzi_stradali'];
      final targa = mezzo is Map ? (mezzo['targa'] ?? '').toString() : '';
      final nome = (r['conducente_nome'] ?? '').toString();
      final assegn = mezzo is Map
          ? (mezzo['assegnatario_attuale'] ?? '').toString()
          : '';
      return targa.toLowerCase().contains(q) ||
          nome.toLowerCase().contains(q) ||
          assegn.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  int get _totaleKm =>
      _filtered.fold<int>(0, (sum, r) => sum + ((r['km_percorsi'] as num?)?.toInt() ?? 0));

  int get _viaggiChiusi =>
      _filtered.where((r) => (r['stato'] ?? '') == 'chiuso').length;

  @override
  Widget build(BuildContext context) {
    final actions = [
      IconButton(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
    ];

    return buildGestoproAwarePage(
      context: context,
      title: _title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(title: Text(_title), actions: actions)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _loading ? null : () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    _formatMonth(_monthStart),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Chip(label: Text('Viaggi chiusi: $_viaggiChiusi')),
                const SizedBox(width: 8),
                Chip(label: Text('Km totali: $_totaleKm')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Cerca targa o conducente',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(child: Text('Nessun viaggio nel mese.')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _tripCard(_filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tripCard(Map<String, dynamic> row) {
    final mezzoRaw = row['logistica_mezzi_stradali'];
    final mezzo = mezzoRaw is Map
        ? Map<String, dynamic>.from(mezzoRaw)
        : const <String, dynamic>{};
    final label = mezzoLabelFromParts(
      targa: (mezzo['targa'] ?? '').toString(),
      marca: (mezzo['marca'] ?? '').toString(),
      modello: (mezzo['modello'] ?? '').toString(),
    );
    final inizioRaw = row['iniziato_at'];
    final fineRaw = row['chiuso_at'];
    final inizioLabel = formatDateTimeItFromSupabase(inizioRaw);
    final fineLabel = formatDateTimeItFromSupabase(fineRaw);
    final chiuso = (row['stato'] ?? '') == 'chiuso';
    final gpsInizio = mdoGpsCoordsFromRow({
      'latitudine': row['lat_inizio'],
      'longitudine': row['lon_inizio'],
    });
    final gpsFine = mdoGpsCoordsFromRow({
      'latitudine': row['lat_fine'],
      'longitudine': row['lon_fine'],
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(chiuso ? 'Chiuso' : 'Aperto'),
                  backgroundColor: chiuso
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Conducente: ${row['conducente_nome'] ?? '—'}'),
            if (widget.mode != ViaggiMezziReportMode.assegnatario &&
                (mezzo['assegnatario_attuale'] ?? '').toString().isNotEmpty)
              Text('Assegnatario: ${mezzo['assegnatario_attuale']}'),
            if (inizioLabel.isNotEmpty)
              Text('Inizio: $inizioLabel · ${row['km_partenza']} km'),
            if (fineLabel.isNotEmpty)
              Text('Fine: $fineLabel · ${row['km_arrivo'] ?? '—'} km'),
            if (row['km_percorsi'] != null)
              Text(
                'Percorsi: ${row['km_percorsi']} km',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (gpsInizio != null)
              Text(
                'GPS inizio: ${formatGpsCoordsText(gpsInizio.$1, gpsInizio.$2)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (gpsFine != null)
              Text(
                'GPS fine: ${formatGpsCoordsText(gpsFine.$1, gpsFine.$2)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}
