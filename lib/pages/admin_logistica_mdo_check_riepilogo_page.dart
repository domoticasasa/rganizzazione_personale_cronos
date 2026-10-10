import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';

import '../services/logistica_mdo_check_riepilogo_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_web_safe.dart';
import '../utils/logistica_layout.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum _MdoCheckFilter { tutti, soloGenerale, soloDotazioni }

class AdminLogisticaMdoCheckRiepilogoPage extends StatefulWidget {
  const AdminLogisticaMdoCheckRiepilogoPage({super.key});

  @override
  State<AdminLogisticaMdoCheckRiepilogoPage> createState() =>
      _AdminLogisticaMdoCheckRiepilogoPageState();
}

class _AdminLogisticaMdoCheckRiepilogoPageState
    extends State<AdminLogisticaMdoCheckRiepilogoPage> {
  final _service = LogisticaMdoCheckRiepilogoService();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _search = '';
  _MdoCheckFilter _filter = _MdoCheckFilter.tutti;
  List<MdoCheckRiepilogoEntry> _entries = [];
  final Set<String> _expandedMdoIds = <String>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() => _search = _searchCtrl.text);
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchEntries();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<MdoCheckRiepilogoEntry> _filterEntries(List<MdoCheckRiepilogoEntry> source) {
    return source.where((e) {
      if (_filter == _MdoCheckFilter.soloGenerale && !e.isCheckGenerale) {
        return false;
      }
      if (_filter == _MdoCheckFilter.soloDotazioni && e.isCheckGenerale) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<MdoCheckRiepilogoGruppo> get _gruppi {
    final filteredEntries = _filterEntries(_entries);
    final groups = MdoCheckRiepilogoGruppo.raggruppaPerMezzo(filteredEntries);

    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return groups;

    return groups.where((g) {
      final header = [
        g.mezzoLabel,
        g.descrizioneMezzo,
        g.commessa,
        g.dtNome,
        g.cantiere,
        g.operatorePrincipale,
        g.ultimoCheckLabel,
      ];
      if (header.any((t) => t.toLowerCase().contains(q))) return true;
      return g.checks.any((c) {
        return [
          c.tipoCheck,
          c.operatoreDisplay,
          c.checkedAtLabel,
        ].any((t) => t.toLowerCase().contains(q));
      });
    }).toList(growable: false);
  }

  List<MdoCheckRiepilogoEntry> _checksVisibiliNelGruppo(MdoCheckRiepilogoGruppo g) {
    return _filterEntries(g.checks);
  }

  void _toggleExpanded(String mdoId) {
    setState(() {
      if (_expandedMdoIds.contains(mdoId)) {
        _expandedMdoIds.remove(mdoId);
      } else {
        _expandedMdoIds.add(mdoId);
      }
    });
  }

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final matrix = await _service.fetchExportMatrix();
      final visibleIds = _gruppi.map((g) => g.mdoIdUuid).toSet();
      final mezzi = matrix
          .where((m) => visibleIds.contains(m.mdoIdUuid))
          .toList(growable: false);

      final excel = Excel.createExcel();
      // Su web rename/delete fogli crashano (liste XML read-only).
      final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
      excelRenameIfPossible(excel, defaultName, 'Matrice_dotazioni');
      for (final name in excel.tables.keys.toList()) {
        if (name != 'Matrice_dotazioni' && name != defaultName) {
          excelDeleteSheetIfPossible(excel, name);
        }
      }
      final wide = excelUseDefaultSheet(excel);

      final tipDotazioni = mezzi.isEmpty
          ? const <String>[]
          : mezzi.first.items
              .where((i) => !i.isCheckGenerale)
              .map((i) => i.tipo)
              .toList(growable: false);

      final includeGenerale = _filter != _MdoCheckFilter.soloDotazioni;
      final includeDotazioni = _filter != _MdoCheckFilter.soloGenerale;

      String cellCheck(MdoCheckExportItem? item) {
        if (item == null || !item.presente) return 'Non presente';
        final data = item.checkedAtLabel.trim();
        final op = item.operatore.trim();
        final parts = <String>['Presente'];
        if (data.isNotEmpty) parts.add(data);
        if (op.isNotEmpty) parts.add(op);
        return parts.join(' | ');
      }

      final headers = <String>[
        'Mezzo',
        'Descrizione',
        'Commessa',
        'DT / Assegnatario',
        'Cantiere',
        if (includeGenerale) 'Check generale (stato | data | operatore)',
        if (includeDotazioni)
          ...tipDotazioni.map((t) => '$t (stato | data | operatore)'),
      ];
      wide.appendRow(headers);

      for (final m in mezzi) {
        final byTipo = {for (final i in m.items) i.tipo: i};
        wide.appendRow([
          m.mezzoLabel,
          m.descrizioneMezzo,
          m.commessa,
          m.dtNome,
          m.cantiere,
          if (includeGenerale) cellCheck(byTipo['Check generale']),
          if (includeDotazioni)
            ...tipDotazioni.map((t) => cellCheck(byTipo[t])),
        ]);
      }

      // Impaginazione: colonne leggibili senza allargarle a mano.
      final widths = <double>[
        12, // Mezzo
        42, // Descrizione
        36, // Commessa
        28, // DT
        28, // Cantiere
        if (includeGenerale) 42,
        if (includeDotazioni) ...List<double>.filled(tipDotazioni.length, 38),
      ];
      for (var i = 0; i < widths.length; i++) {
        wide.setColWidth(i, widths[i]);
      }

      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Riepilogo_check_MDO',
        bytes: bytes,
      );
      if (!mounted) return;
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? (p.isEmpty
                    ? 'Export Excel completato'
                    : 'Export Excel completato: $p')
                : 'Export non salvato',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore export Excel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gruppi = _gruppi;
    final narrow = isLogisticaCompactLayout(context);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                narrow ? 'Check MDO' : 'Riepilogo check MDO',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: (_loading || _exporting) ? null : _exportExcel,
            icon: _exporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: Column(
        children: [
          _buildToolbar(gruppi.length),
          Expanded(child: _buildBody(gruppi)),
        ],
      ),
    );
  }

  Widget _buildToolbar(int mezziCount) {
    final compact = isLogisticaCompactLayout(context);
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Cerca mezzo (es. A67), DT, operatore...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchCtrl.clear(),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.train_outlined, size: 18),
                      label: Text('$mezziCount mezzi'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Cerca mezzo (es. A67), DT, operatore...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _searchCtrl.clear(),
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Chip(
                    avatar: const Icon(Icons.train_outlined, size: 18),
                    label: Text('$mezziCount mezzi'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_MdoCheckFilter>(
                segments: const [
                  ButtonSegment(
                    value: _MdoCheckFilter.tutti,
                    label: Text('Tutti i check'),
                  ),
                  ButtonSegment(
                    value: _MdoCheckFilter.soloGenerale,
                    label: Text('Solo generale'),
                  ),
                  ButtonSegment(
                    value: _MdoCheckFilter.soloDotazioni,
                    label: Text('Solo dotazioni'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _filter = s.first);
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tocca un mezzo per aprire l’elenco dei check inseriti.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<MdoCheckRiepilogoGruppo> gruppi) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Errore: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Riprova')),
            ],
          ),
        ),
      );
    }
    if (gruppi.isEmpty) {
      return const Center(
        child: Text(
          'Nessun check MDO registrato.\n'
          'I check inseriti da MDO Ferroviari compariranno qui.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: gruppi.length,
        itemBuilder: (context, i) => _buildGruppoCard(gruppi[i]),
      ),
    );
  }

  Widget _buildGruppoCard(MdoCheckRiepilogoGruppo g) {
    final expanded = _expandedMdoIds.contains(g.mdoIdUuid);
    final checks = _checksVisibiliNelGruppo(g);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleExpanded(g.mdoIdUuid),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      g.mezzoLabel.length > 5
                          ? g.mezzoLabel.substring(0, 5)
                          : g.mezzoLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.mezzoLabel,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          g.descrizioneMezzo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          g.riepilogoCheckLabel,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _miniInfo(Icons.schedule, g.ultimoCheckLabel),
                            _miniInfo(Icons.person_outline, g.assegnatarioDisplay),
                            if (g.commessa.isNotEmpty)
                              _miniInfo(Icons.work_outline, g.commessa),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            _buildDettaglioMezzo(g),
            if (checks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nessun check con il filtro selezionato.'),
              )
            else
              ...checks.map(_buildRigaCheck),
          ],
        ],
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.black54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }

  Widget _buildDettaglioMezzo(MdoCheckRiepilogoGruppo g) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dati mezzo',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          _dettaglioRiga('DT / Assegnatario', g.assegnatarioDisplay),
          _dettaglioRiga('Operatore (check generale)', g.operatorePrincipale),
          _dettaglioRiga('Commessa', g.commessa.isEmpty ? '—' : g.commessa),
          _dettaglioRiga('Cantiere', g.cantiere.isEmpty ? '—' : g.cantiere),
          _dettaglioRiga('Ultimo check', g.ultimoCheckLabel),
          const SizedBox(height: 4),
          Text(
            'Elenco check (${g.checks.length})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _dettaglioRiga(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 168,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRigaCheck(MdoCheckRiepilogoEntry e) {
    return ListTile(
      dense: true,
      leading: Icon(
        e.isCheckGenerale ? Icons.verified : Icons.check_circle_outline,
        color: e.isCheckGenerale ? Colors.green.shade700 : Colors.blue.shade700,
      ),
      title: Text(
        e.tipoCheck,
        style: TextStyle(
          fontWeight: e.isCheckGenerale ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${e.checkedAtLabel} · Operatore: ${e.operatoreDisplay}',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
