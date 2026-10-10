import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Mobile/cronos_mobile_pages.dart';
import '../services/qt_carburante_dipendente_mancanti_service.dart';
import '../services/supabase_service.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/classic_app_bar_chrome.dart';
import 'logistica_rcc_carburante_page.dart';
import 'logistica_rcc_mdo_carburante_page.dart';

/// Elenco rifornimenti QT da giustificare per il dipendente (tutti i mesi).
class DipendenteRifornimentiMancantiPage extends StatefulWidget {
  const DipendenteRifornimentiMancantiPage({
    super.key,
    this.anno,
    this.mese,
    this.forceMobileLayout = false,
  });

  /// Se valorizzati, seleziona quel mese all’apertura.
  final int? anno;
  final int? mese;
  final bool forceMobileLayout;

  @override
  State<DipendenteRifornimentiMancantiPage> createState() =>
      _DipendenteRifornimentiMancantiPageState();
}

class _DipendenteRifornimentiMancantiPageState
    extends State<DipendenteRifornimentiMancantiPage> {
  bool _loading = true;
  String? _error;
  List<QtMancantiMeseResult> _mesi = const [];
  int? _selectedAnno;
  int? _selectedMese;

  final _monthKeys = <String, GlobalKey>{};

  static final _df = DateFormat('dd/MM/yyyy');
  static final _euro = NumberFormat.currency(locale: 'it_IT', symbol: '€');

  bool get _isMobile =>
      widget.forceMobileLayout || useMobileUi(context);

  String _keyFor(int anno, int mese) => '$anno-$mese';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await QtCarburanteDipendenteMancantiService.loadMancantiUltimiMesi(
        client: SupabaseService.client,
        monthsBack: 24,
        onlyWithImport: true,
      );
      if (!mounted) return;

      var selAnno = widget.anno ?? _selectedAnno;
      var selMese = widget.mese ?? _selectedMese;
      if (selAnno == null || selMese == null) {
        final prev =
            QtCarburanteDipendenteMancantiService.previousCalendarMonth();
        final hasPrev = list.any((r) => r.anno == prev.anno && r.mese == prev.mese);
        if (hasPrev) {
          selAnno = prev.anno;
          selMese = prev.mese;
        } else {
          final withMancanti = list.where((r) => !r.isEmpty).toList();
          final pick = withMancanti.isNotEmpty ? withMancanti.first : (list.isEmpty ? null : list.first);
          selAnno = pick?.anno;
          selMese = pick?.mese;
        }
      } else if (!list.any((r) => r.anno == selAnno && r.mese == selMese)) {
        selAnno = list.isEmpty ? null : list.first.anno;
        selMese = list.isEmpty ? null : list.first.mese;
      }

      setState(() {
        _mesi = list;
        _selectedAnno = selAnno;
        _selectedMese = selMese;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToSelected();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectMonth(QtMancantiMeseResult r) {
    setState(() {
      _selectedAnno = r.anno;
      _selectedMese = r.mese;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSelected();
    });
  }

  void _scrollToSelected() {
    final a = _selectedAnno;
    final m = _selectedMese;
    if (a == null || m == null) return;
    final key = _monthKeys[_keyFor(a, m)];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Future<void> _openRccStradali() async {
    final page = _isMobile
        ? const LogisticaRccCarburanteMobilePage(dipendenteMode: true)
        : LogisticaRccCarburantePage(
            dipendenteMode: true,
            forceMobileLayout: widget.forceMobileLayout,
          );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _reload();
  }

  Future<void> _openRccMdo() async {
    final page = _isMobile
        ? const LogisticaRccMdoCarburanteMobilePage(dipendenteMode: true)
        : LogisticaRccMdoCarburantePage(
            dipendenteMode: true,
            forceMobileLayout: widget.forceMobileLayout,
          );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _reload();
  }

  Widget _monthChip(QtMancantiMeseResult r) {
    final selected = r.anno == _selectedAnno && r.mese == _selectedMese;
    final label = QtCarburanteDipendenteMancantiService.monthLabelIt(
      r.mese,
      r.anno,
    );
    final hasMancanti = !r.isEmpty;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: hasMancanti
          ? Icon(
              Icons.error_outline,
              size: 18,
              color: selected ? Colors.white : Colors.red.shade700,
            )
          : Icon(
              Icons.check_circle_outline,
              size: 18,
              color: selected ? Colors.white : Colors.green.shade700,
            ),
      label: Text(
        hasMancanti ? '$label (${r.totale})' : label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : null,
        ),
      ),
      selectedColor: hasMancanti
          ? Colors.red.shade700
          : Theme.of(context).colorScheme.primary,
      onSelected: (_) => _selectMonth(r),
    );
  }

  Widget _monthSection(QtMancantiMeseResult res) {
    final meseTxt = QtCarburanteDipendenteMancantiService.monthLabelIt(
      res.mese,
      res.anno,
    );
    final selected =
        res.anno == _selectedAnno && res.mese == _selectedMese;
    final key = _monthKeys.putIfAbsent(
      _keyFor(res.anno, res.mese),
      GlobalKey.new,
    );

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer.withValues(
                      alpha: 0.45,
                    )
                : Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: ListTile(
              title: Text(
                'Fattura QT · $meseTxt',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                res.isEmpty
                    ? 'Tutto giustificato'
                    : '${res.totale} da giustificare',
              ),
              trailing: Icon(
                res.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.receipt_long_outlined,
                color: res.isEmpty ? Colors.green.shade700 : Colors.red.shade700,
              ),
              onTap: () => _selectMonth(res),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: res.isEmpty
                ? Card(
                    color: Colors.green.shade50,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade800,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Nessun rifornimento mancante in questo mese.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final d in res.dettagli)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              child: Icon(
                                Icons.local_gas_station_outlined,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            title: Text(
                              '${_df.format(d.data)} · ${d.prodotto}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Carta ${d.numeroCarta}\n'
                              '${d.volume.toStringAsFixed(2)} L · '
                              '${_euro.format(d.importo)}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Rifornimenti da giustificare';
    final totaleMancanti =
        _mesi.fold<int>(0, (sum, r) => sum + r.totale);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Errore caricamento: $_error',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'Tutti i mesi con fattura QT importata',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Transazioni presenti in fattura sulla tua scheda '
                      'senza giustificativo RCC. Inserisci il rifornimento '
                      'dal registro Stradali o MDO.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _openRccStradali,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Giustifica · Stradali'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openRccMdo,
                          icon: const Icon(Icons.train_outlined),
                          label: const Text('Giustifica · MDO'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_mesi.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Nessuna fattura QT importata negli ultimi mesi.',
                          ),
                        ),
                      )
                    else ...[
                      Text(
                        totaleMancanti == 0
                            ? 'Tutti i mesi risultano giustificati'
                            : '$totaleMancanti da giustificare in totale',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: totaleMancanti == 0
                                  ? Colors.green.shade800
                                  : Theme.of(context).colorScheme.error,
                            ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final r in _mesi) ...[
                              _monthChip(r),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final r in _mesi) _monthSection(r),
                    ],
                  ],
                ),
              );

    final actions = <Widget>[
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: _loading ? null : _reload,
        icon: const Icon(Icons.refresh),
      ),
    ];

    return buildGestoproAwarePage(
      context: context,
      title: title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(title: const Text(title), actions: actions),
      ),
      body: body,
    );
  }
}
