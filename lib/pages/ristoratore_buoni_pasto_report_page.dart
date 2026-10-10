import 'package:flutter/material.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_export.dart';
import '../utils/buoni_pasto_qr_payload.dart';
import '../widgets/classic_app_bar_chrome.dart';

class RistoratoreBuoniPastoReportPage extends StatefulWidget {
  const RistoratoreBuoniPastoReportPage({
    super.key,
    required this.structureIdUuid,
    required this.structureName,
  });

  final String structureIdUuid;
  final String structureName;

  @override
  State<RistoratoreBuoniPastoReportPage> createState() =>
      _RistoratoreBuoniPastoReportPageState();
}

class _RistoratoreBuoniPastoReportPageState
    extends State<RistoratoreBuoniPastoReportPage> {
  final _supa = SupabaseService.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];
  DateTime _dal = DateTime.now().subtract(const Duration(days: 30));
  DateTime _al = DateTime.now();
  String _filtro = 'mese';

  @override
  void initState() {
    super.initState();
    _applyPreset('mese');
    _load();
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    switch (preset) {
      case 'oggi':
        _dal = DateTime(now.year, now.month, now.day);
        _al = _dal;
        break;
      case 'settimana':
        _dal = now.subtract(Duration(days: now.weekday - 1));
        _al = now;
        break;
      case 'mese':
      default:
        _dal = DateTime(now.year, now.month, 1);
        _al = now;
    }
    _filtro = preset;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await BuoniPastoService.loadRegistrazioni(
        supa: _supa,
        structureIdUuid: widget.structureIdUuid,
        dal: _dal,
        al: _al,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _pranzo => _rows.where((r) => r['tipo_pasto'] == 'pranzo').length;
  int get _cena => _rows.where((r) => r['tipo_pasto'] == 'cena').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text('Report — ${widget.structureName}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _rows.isEmpty
                ? null
                : () => exportBuoniPastoCsv(
                      context,
                      rows: _rows,
                      pageName: 'Report_${widget.structureName}',
                    ),
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV',
          ),
        ],
      )),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Oggi'),
                  selected: _filtro == 'oggi',
                  onSelected: (_) {
                    setState(() => _applyPreset('oggi'));
                    _load();
                  },
                ),
                ChoiceChip(
                  label: const Text('Settimana'),
                  selected: _filtro == 'settimana',
                  onSelected: (_) {
                    setState(() => _applyPreset('settimana'));
                    _load();
                  },
                ),
                ChoiceChip(
                  label: const Text('Mese'),
                  selected: _filtro == 'mese',
                  onSelected: (_) {
                    setState(() => _applyPreset('mese'));
                    _load();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _statChip('Pranzo', _pranzo, Colors.orange),
                const SizedBox(width: 12),
                _statChip('Cena', _cena, Colors.indigo),
                const Spacer(),
                Text('Totale: ${_rows.length}'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('Nessuna registrazione nel periodo.'))
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) {
                          final row = _rows[i];
                          final registrato = DateTime.tryParse(
                            (row['registrato_at'] ?? '').toString(),
                          );
                          final ora = registrato != null
                              ? '${registrato.hour.toString().padLeft(2, '0')}:${registrato.minute.toString().padLeft(2, '0')}'
                              : '';
                          final data = (row['data_pasto'] ?? '').toString();
                          return ListTile(
                            leading: Icon(
                              row['tipo_pasto'] == 'cena'
                                  ? Icons.nightlife_outlined
                                  : Icons.wb_sunny_outlined,
                            ),
                            title: Text((row['dipendente_nome'] ?? '').toString()),
                            subtitle: Text(
                              '$data · $ora · ${tipoPastoLabel((row['tipo_pasto'] ?? '').toString())}',
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Text('$count', style: TextStyle(color: color, fontSize: 12)),
      ),
      label: Text(label),
    );
  }
}
