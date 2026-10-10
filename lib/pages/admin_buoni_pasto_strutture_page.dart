import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_export.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';
import 'admin_buoni_pasto_struttura_detail_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

class _StrutturaRiepilogo {
  const _StrutturaRiepilogo({
    required this.structureIdUuid,
    required this.nome,
    required this.pranzo,
    required this.cena,
    required this.registrazioni,
  });

  final String structureIdUuid;
  final String nome;
  final int pranzo;
  final int cena;
  final List<Map<String, dynamic>> registrazioni;

  int get totale => registrazioni.length;
}

class AdminBuoniPastoStrutturePage extends StatefulWidget {
  const AdminBuoniPastoStrutturePage({super.key});

  @override
  State<AdminBuoniPastoStrutturePage> createState() =>
      _AdminBuoniPastoStrutturePageState();
}

class _AdminBuoniPastoStrutturePageState extends State<AdminBuoniPastoStrutturePage> {
  final _supa = SupabaseService.client;
  static final _monthFmt = DateFormat('MMMM yyyy', 'it_IT');

  bool _loading = true;
  String _search = '';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<BuoniPastoRistoranteRow> _ristoranti = const [];
  List<Map<String, dynamic>> _registrazioni = const [];

  DateTime get _monthStart => DateTime(_month.year, _month.month, 1);

  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _ristoranti = await BuoniPastoService.loadRistoranti(_supa);
      _registrazioni = await BuoniPastoService.loadRegistrazioni(
        supa: _supa,
        dal: _monthStart,
        al: _monthEnd,
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore caricamento: $e');
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

  String _formatMonthTitle(DateTime month) {
    final raw = _monthFmt.format(month);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  List<_StrutturaRiepilogo> get _riepiloghi {
    final byStructure = <String, List<Map<String, dynamic>>>{};
    for (final row in _registrazioni) {
      final sid = (row['structure_id_uuid'] ?? '').toString();
      if (sid.isEmpty) continue;
      byStructure.putIfAbsent(sid, () => []).add(row);
    }

    final out = <_StrutturaRiepilogo>[];
    for (final r in _ristoranti) {
      final rows = byStructure[r.structureIdUuid] ?? const [];
      out.add(
        _StrutturaRiepilogo(
          structureIdUuid: r.structureIdUuid,
          nome: r.nome,
          pranzo: rows.where((x) => x['tipo_pasto'] == 'pranzo').length,
          cena: rows.where((x) => x['tipo_pasto'] == 'cena').length,
          registrazioni: rows,
        ),
      );
    }
    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  List<_StrutturaRiepilogo> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _riepiloghi;
    return _riepiloghi
        .where((r) => r.nome.toLowerCase().contains(q))
        .toList(growable: false);
  }

  int get _totalePranzo =>
      _registrazioni.where((r) => r['tipo_pasto'] == 'pranzo').length;

  int get _totaleCena =>
      _registrazioni.where((r) => r['tipo_pasto'] == 'cena').length;

  void _openDetail(_StrutturaRiepilogo item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminBuoniPastoStrutturaDetailPage(
          structureIdUuid: item.structureIdUuid,
          structureName: item.nome,
          initialMonth: _month,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Riepilogo per struttura';
    final actions = [
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      IconButton(
        tooltip: 'Export Excel mese',
        onPressed: _registrazioni.isEmpty
            ? null
            : () => exportBuoniPastoExcel(
                  context,
                  rows: _registrazioni,
                  pageName: 'Buoni_pasto_strutture_${_month.year}_${_month.month}',
                ),
        icon: const Icon(Icons.download_outlined),
      ),
    ];

    return buildGestoproAwarePage(
      context: context,
      title: title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Text(title),
        actions: actions,
      )),
      body: _loading && _ristoranti.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                          _formatMonthTitle(_monthStart),
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
                      _chip('Pranzo', _totalePranzo, Colors.orange.shade700),
                      const SizedBox(width: 8),
                      _chip('Cena', _totaleCena, Colors.indigo.shade700),
                      const Spacer(),
                      Text('Totale: ${_registrazioni.length}'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Cerca struttura',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'Nessuna struttura o nessuna registrazione nel mese.',
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard(_StrutturaRiepilogo item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.restaurant_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nome,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _miniStat('Pranzo', item.pranzo, Colors.orange.shade700),
                        _miniStat('Cena', item.cena, Colors.indigo.shade700),
                        Text(
                          'Totale: ${item.totale}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, int n, Color color) {
    return Chip(
      label: Text('$label: $n'),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }

  Widget _miniStat(String label, int n, Color color) {
    return Text(
      '$label: $n',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}
