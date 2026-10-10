import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_export.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminBuoniPastoPresenzePage extends StatefulWidget {
  const AdminBuoniPastoPresenzePage({super.key});

  @override
  State<AdminBuoniPastoPresenzePage> createState() =>
      _AdminBuoniPastoPresenzePageState();
}

class _AdminBuoniPastoPresenzePageState
    extends State<AdminBuoniPastoPresenzePage> {
  final _supa = SupabaseService.client;
  final _verticalScroll = ScrollController();
  static final _weekdayFmt = DateFormat('E', 'it_IT');

  bool _loading = true;
  String _modalita = 'settimana';
  DateTime _anchor = DateTime.now();
  String _search = '';
  BuoniPastoPresenzeReport? _report;

  DateTime get _dal => _modalita == 'mese'
      ? BuoniPastoService.startOfMonth(_anchor)
      : BuoniPastoService.startOfWeek(_anchor);

  DateTime get _al => _modalita == 'mese'
      ? BuoniPastoService.endOfMonth(_anchor)
      : BuoniPastoService.endOfWeek(_anchor);

  @override
  void dispose() {
    _verticalScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _report = await BuoniPastoService.loadPresenzeReport(
        supa: _supa,
        dal: _dal,
        al: _al,
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore caricamento: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftPeriod(int delta) {
    setState(() {
      if (_modalita == 'mese') {
        _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
      } else {
        _anchor = _anchor.add(Duration(days: 7 * delta));
      }
    });
    _load();
  }

  void _setModalita(String m) {
    if (_modalita == m) return;
    setState(() => _modalita = m);
    _load();
  }

  List<BuoniPastoDipendentePresenza> get _filtered {
    final report = _report;
    if (report == null) return const [];
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return report.dipendenti;
    return report.dipendenti
        .where(
          (d) =>
              d.nome.toLowerCase().contains(q) ||
              (d.matricola ?? '').toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  BuoniPastoPresenzeReport get _exportReport => BuoniPastoPresenzeReport(
        dal: _report!.dal,
        al: _report!.al,
        giorni: _report!.giorni,
        dipendenti: _filtered,
      );

  void _exportExcel() {
    exportBuoniPastoPresenzeExcel(
      context,
      report: _exportReport,
      pageName: 'Buoni_pasto_presenze_$_modalita',
    );
  }

  String get _periodLabel {
    final dal = _dal;
    final al = _al;
    final fmt = '${dal.day.toString().padLeft(2, '0')}/'
        '${dal.month.toString().padLeft(2, '0')}/${dal.year}';
    final fmtAl = '${al.day.toString().padLeft(2, '0')}/'
        '${al.month.toString().padLeft(2, '0')}/${al.year}';
    if (_modalita == 'mese') {
      return '${_monthName(dal.month)} ${dal.year}';
    }
    return '$fmt — $fmtAl';
  }

  String _monthName(int month) {
    const names = [
      '',
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ];
    return names[month];
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Presenze dipendenti';
    final actions = [
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      PopupMenuButton<String>(
        tooltip: 'Esporta',
        enabled: _report != null && _filtered.isNotEmpty,
        onSelected: (value) {
          if (value == 'excel') {
            _exportExcel();
          } else {
            exportBuoniPastoPresenzeCsv(
              context,
              report: _exportReport,
              pageName: 'Buoni_pasto_presenze_$_modalita',
            );
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(
            value: 'excel',
            child: ListTile(
              leading: Icon(Icons.table_chart_outlined),
              title: Text('Export Excel'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'csv',
            child: ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('Export CSV'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
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
      body: _loading && _report == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildControls(),
                const Divider(height: 1),
                _buildLegend(),
                Expanded(child: _buildGrid()),
              ],
            ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Settimana'),
                selected: _modalita == 'settimana',
                onSelected: (_) => _setModalita('settimana'),
              ),
              ChoiceChip(
                label: const Text('Mese'),
                selected: _modalita == 'mese',
                onSelected: (_) => _setModalita('mese'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Periodo precedente',
                onPressed: _loading ? null : () => _shiftPeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _periodLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IconButton(
                tooltip: 'Periodo successivo',
                onPressed: _loading ? null : () => _shiftPeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              FilledButton.icon(
                onPressed: _report == null || _filtered.isEmpty ? null : _exportExcel,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Export Excel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Cerca dipendente',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 4),
          Text(
            'Tutti i dipendenti attivi: per ogni giorno P = pranzo, C = cena, '
            '— = nessun pasto registrato.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 16,
        children: [
          _legendItem('P', 'Pranzo', Colors.orange.shade700),
          _legendItem('C', 'Cena', Colors.indigo.shade700),
          _legendItem('—', 'Assente', Colors.grey.shade500),
        ],
      ),
    );
  }

  Widget _legendItem(String symbol, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(symbol, style: TextStyle(color: color, fontSize: 11)),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildGrid() {
    final report = _report;
    final rows = _filtered;
    if (report == null) {
      return const Center(child: Text('Nessun dato.'));
    }
    if (rows.isEmpty) {
      return const Center(child: Text('Nessun dipendente trovato.'));
    }

    const nameWidth = 280.0;
    const cellWidth = 44.0;
    const rowHeight = 52.0;
    const headerHeight = 52.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: nameWidth,
              child: Column(
                children: [
                  const SizedBox(height: headerHeight),
                  Expanded(
                    child: ListView.builder(
                      controller: _verticalScroll,
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) => _nameCell(rows[i], rowHeight),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: report.giorni.length * cellWidth,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final g in report.giorni)
                            _dayHeader(g, cellWidth, headerHeight),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _verticalScroll,
                          itemCount: rows.length,
                          itemBuilder: (ctx, i) => Row(
                            children: [
                              for (final g in report.giorni)
                                _mealCell(
                                  rows[i],
                                  g,
                                  cellWidth,
                                  rowHeight,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _nameCell(BuoniPastoDipendentePresenza dip, double height) {
    final report = _report!;
    final tot = dip.countPastiIn(report.giorni);
    final matricola = (dip.matricola ?? '').trim();
    final subtitle = matricola.isNotEmpty
        ? 'Mat. $matricola · Pasti: $tot'
        : 'Pasti: $tot';
    return Tooltip(
      message: matricola.isNotEmpty ? '${dip.nome}\nMatricola: $matricola' : dip.nome,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dip.nome,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayHeader(DateTime g, double width, double height) {
    final weekday = _weekdayFmt.format(g).substring(0, 2).toUpperCase();
    final isWeekend = g.weekday >= 6;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWeekend ? Colors.grey.shade100 : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(weekday, style: const TextStyle(fontSize: 10)),
          Text(
            '${g.day}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _mealCell(
    BuoniPastoDipendentePresenza dip,
    DateTime g,
    double width,
    double height,
  ) {
    final key =
        '${g.year.toString().padLeft(4, '0')}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';
    final cell = dip.pastiPerGiorno[key] ?? const BuoniPastoGiornoPasti();
    final isWeekend = g.weekday >= 6;

    String tooltip = 'Nessun pasto';
    if (cell.pranzo && cell.cena) {
      tooltip = 'Pranzo: ${cell.pranzoRistorante ?? '—'}\n'
          'Cena: ${cell.cenaRistorante ?? '—'}';
    } else if (cell.pranzo) {
      tooltip = 'Pranzo: ${cell.pranzoRistorante ?? '—'}';
    } else if (cell.cena) {
      tooltip = 'Cena: ${cell.cenaRistorante ?? '—'}';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isWeekend ? Colors.grey.shade50 : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300),
            right: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: _mealSymbols(cell),
      ),
    );
  }

  Widget _mealSymbols(BuoniPastoGiornoPasti cell) {
    if (!cell.haPasto) {
      return Text(
        '—',
        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
      );
    }
    if (cell.pranzo && cell.cena) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('P', style: TextStyle(color: Colors.orange.shade700, fontSize: 10)),
          Text('C', style: TextStyle(color: Colors.indigo.shade700, fontSize: 10)),
        ],
      );
    }
    if (cell.pranzo) {
      return Text('P', style: TextStyle(color: Colors.orange.shade700, fontSize: 12));
    }
    return Text('C', style: TextStyle(color: Colors.indigo.shade700, fontSize: 12));
  }
}
