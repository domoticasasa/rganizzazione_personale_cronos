
import 'package:data_table_2/data_table_2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/qt_carburante_fattura_storage_service.dart';
import '../services/qt_carburante_fatturazione_parser.dart';
import '../services/qt_carburante_verifica_export.dart';
import '../services/qt_carburante_verifica_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

enum _QtFiltroStato { tutti, giustificati, mancanti }

enum _QtImportMode { oneFile, twoFiles, addSecond, replaceAll }

class LogisticaQtCarburanteVerificaPage extends StatefulWidget {
  final bool forceMobileLayout;

  const LogisticaQtCarburanteVerificaPage({
    super.key,
    this.forceMobileLayout = false,
  });

  @override
  State<LogisticaQtCarburanteVerificaPage> createState() =>
      _LogisticaQtCarburanteVerificaPageState();
}

class _LogisticaQtCarburanteVerificaPageState
    extends State<LogisticaQtCarburanteVerificaPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _df = DateFormat('dd/MM/yyyy');
  final _nf = NumberFormat('#,##0.00', 'it_IT');

  late final TabController _tabController;

  bool _loading = false;
  bool _monthsLoading = true;
  bool _exporting = false;
  int _selectedYear = 0;
  int _selectedMonth = 0;
  List<QtFatturaMeseIndex> _mesiSalvati = const [];
  final List<String> _fileNames = [];
  final List<QtCarburanteParseResult> _parsedParts = [];
  QtCarburanteVerificaResult? _result;
  _QtFiltroStato _filtro = _QtFiltroStato.tutti;
  String? _filtroScheda;

  static const _monthNames = <String>[
    'Gen',
    'Feb',
    'Mar',
    'Apr',
    'Mag',
    'Giu',
    'Lug',
    'Ago',
    'Set',
    'Ott',
    'Nov',
    'Dic',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final now = italyNow();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _monthsLoading = true);
    await _refreshMonthsIndex();
    if (!mounted) return;
    await _loadSelectedMonth(showSpinner: true);
  }

  Future<void> _refreshMonthsIndex() async {
    try {
      final mesi = await QtCarburanteFatturaStorageService.listMesi(_supa);
      if (!mounted) return;
      setState(() {
        _mesiSalvati = mesi;
        _monthsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _monthsLoading = false);
    }
  }

  bool _monthHasData(int anno, int mese) =>
      _mesiSalvati.any((e) => e.anno == anno && e.mese == mese);

  String _monthLabel(int mese) =>
      mese >= 1 && mese <= 12 ? _monthNames[mese - 1] : '$mese';

  Future<void> _selectMonth(int mese) async {
    if (mese == _selectedMonth) return;
    setState(() => _selectedMonth = mese);
    await _loadSelectedMonth();
  }

  Future<void> _shiftYear(int delta) async {
    setState(() => _selectedYear += delta);
    await _loadSelectedMonth();
  }

  Future<void> _loadSelectedMonth({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final stored = await QtCarburanteFatturaStorageService.loadMese(
        _supa,
        anno: _selectedYear,
        mese: _selectedMonth,
      );
      if (!mounted) return;
      if (stored == null || stored.transazioni.isEmpty) {
        setState(() {
          _parsedParts.clear();
          _fileNames.clear();
          _result = null;
          _filtro = _QtFiltroStato.tutti;
          _filtroScheda = null;
          _searchCtrl.clear();
        });
        return;
      }

      final verifica = await QtCarburanteVerificaService.verifica(
        supa: _supa,
        transazioni: stored.transazioni,
        riferimentoAnno: _selectedYear,
        riferimentoMese: _selectedMonth,
      );
      if (!mounted) return;
      setState(() {
        _fileNames
          ..clear()
          ..addAll(stored.fileNames);
        _parsedParts.clear();
        _result = verifica;
        _filtro = _QtFiltroStato.tutti;
        _filtroScheda = null;
        _searchCtrl.clear();
      });
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Caricamento mese: $e');
    } finally {
      if (mounted && showSpinner) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _narrow(BuildContext context) =>
      isLogisticaCompactLayout(context, force: widget.forceMobileLayout);

  static const _qtExcelGroup = XTypeGroup(
    label: 'Excel fatturazione QT',
    extensions: ['xlsx', 'xls'],
  );

  Future<QtCarburanteParseResult?> _parsePickedFile(XFile file) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(
          context,
          'Lettura file "${file.name}" fallita: $e',
        );
      }
      return null;
    }

    try {
      return await QtCarburanteFatturazioneParser.parseFile(
        fileName: file.name,
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(
          context,
          'Excel non valido (${file.name}): $e',
        );
      }
      return null;
    }
  }

  bool _isFileAlreadyImported(String fileName) {
    final n = fileName.trim().toLowerCase();
    if (_fileNames.any((f) => f.trim().toLowerCase() == n)) return true;
    return _parsedParts.any(
      (p) => (p.fileName ?? '').trim().toLowerCase() == n,
    );
  }

  Future<void> _verificaParsedParts({
    required List<QtCarburanteParseResult> parts,
    bool clearFilters = true,
  }) async {
    QtCarburanteMergedParseResult merged;
    try {
      merged = QtCarburanteFatturazioneParser.mergeParsed(parts);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
      return;
    }

    final meseRif =
        QtCarburanteFatturazioneParser.detectMeseRiferimento(merged.righe);
    if (meseRif == null) {
      final mesi =
          QtCarburanteFatturazioneParser.mesiDistintiLabel(merged.righe);
      if (mounted) {
        ModifyFeedback.error(
          context,
          'Le transazioni coprono più mesi (${mesi.join(', ')}). '
          'Carica file dello stesso mese oppure importali separatamente.',
        );
      }
      return;
    }

    final autoSwitched =
        meseRif.anno != _selectedYear || meseRif.mese != _selectedMonth;
    if (autoSwitched) {
      setState(() {
        _selectedYear = meseRif.anno;
        _selectedMonth = meseRif.mese;
      });
    }

    setState(() {
      _loading = true;
      _parsedParts
        ..clear()
        ..addAll(parts);
      _fileNames
        ..clear()
        ..addAll(merged.fileNames);
      if (clearFilters) {
        _filtro = _QtFiltroStato.tutti;
        _filtroScheda = null;
        _searchCtrl.clear();
      }
    });

    try {
      final verifica = await QtCarburanteVerificaService.verifica(
        supa: _supa,
        transazioni: merged.righe,
        riferimentoAnno: _selectedYear,
        riferimentoMese: _selectedMonth,
      );
      await QtCarburanteFatturaStorageService.saveMese(
        _supa,
        anno: _selectedYear,
        mese: _selectedMonth,
        merged: merged,
      );
      await _refreshMonthsIndex();
      if (!mounted) return;
      setState(() => _result = verifica);
      _tabController.index = 0;
      final msg = StringBuffer(
        'Importate ${merged.righe.length} transazioni'
        '${merged.fileNames.length > 1 ? ' da ${merged.fileNames.length} file' : ''} '
        'per ${_monthLabel(_selectedMonth)} $_selectedYear. '
        'Giustificate: ${verifica.giustificati}, '
        'mancanti: ${verifica.mancanti}, '
        'giustificativi senza fattura: ${verifica.senzaFattura}.',
      );
      if (autoSwitched) {
        msg.write(
          '\nMese impostato automaticamente dalle date nel file.',
        );
      }
      if (merged.avviso != null) msg.write('\n${merged.avviso}');
      ModifyFeedback.success(context, msg.toString());
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Verifica fallita: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importExcel({required int expectedFiles}) async {
    final picked = <XFile>[];
    for (var i = 0; i < expectedFiles; i++) {
      if (!mounted) return;
      final file = await openFile(acceptedTypeGroups: [_qtExcelGroup]);
      if (file == null) {
        if (picked.isEmpty) return;
        if (expectedFiles == 2 && picked.length == 1) {
          if (!mounted) return;
          final solo = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Seconda fattura mancante'),
              content: const Text(
                'Hai selezionato solo la prima fattura.\n'
                'Continuare la verifica con un solo file?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sì, solo 1 file'),
                ),
              ],
            ),
          );
          if (solo != true) return;
        }
        break;
      }
      picked.add(file);
    }

    if (picked.isEmpty) return;

    final parsedParts = <QtCarburanteParseResult>[];
    for (final file in picked) {
      if (_isFileAlreadyImported(file.name)) {
        if (mounted) {
          ModifyFeedback.error(
            context,
            'Il file "${file.name}" è già stato importato.',
          );
        }
        return;
      }
      final parsed = await _parsePickedFile(file);
      if (parsed == null) return;
      parsedParts.add(parsed);
    }

    await _verificaParsedParts(parts: parsedParts);
  }

  Future<void> _addSecondInvoice() async {
    if (_fileNames.length >= 2) {
      if (!mounted) return;
      ModifyFeedback.hint(
        context,
        'Sono già caricate 2 fatture. Usa «Reimporta» per sostituirle.',
      );
      return;
    }
    if (!mounted) return;
    final file = await openFile(acceptedTypeGroups: [_qtExcelGroup]);
    if (file == null || !mounted) return;
    if (_isFileAlreadyImported(file.name)) {
      ModifyFeedback.error(
        context,
        'Il file "${file.name}" è già stato importato.',
      );
      return;
    }
    final parsed = await _parsePickedFile(file);
    if (parsed == null) return;

    final parts = <QtCarburanteParseResult>[..._parsedParts];
    if (parts.isEmpty && _result != null) {
      for (final name in _fileNames) {
        final righe = _result!.righe
            .map((r) => r.transazione)
            .where((t) => (t.fileSorgente ?? name) == name)
            .toList();
        if (righe.isNotEmpty) {
          parts.add(QtCarburanteParseResult(righe: righe, fileName: name));
        }
      }
      if (parts.isEmpty && _result!.righe.isNotEmpty) {
        parts.add(
          QtCarburanteParseResult(
            righe: _result!.righe.map((r) => r.transazione).toList(),
            fileName: _fileNames.isNotEmpty ? _fileNames.first : 'fattura_1',
          ),
        );
      }
    }
    parts.add(parsed);

    await _verificaParsedParts(parts: parts, clearFilters: false);
  }

  Future<void> _showImportMenu() async {
    final hasOneFile = _fileNames.length == 1;
    final hasData = _result != null;

    final choice = await showModalBottomSheet<_QtImportMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hasData ? 'Fatture QT' : 'Importa fatture QT',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                hasOneFile
                    ? 'È caricata 1 fattura su 2. Aggiungi la seconda per '
                        'vedere il mese intero, oppure reimporta da zero.'
                    : 'Il mese può essere suddiviso in due fatture: puoi '
                        'caricarne una sola o entrambe per la verifica completa.',
              ),
              const SizedBox(height: 16),
              if (hasOneFile) ...[
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, _QtImportMode.addSecond),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Aggiungi 2ª fattura del mese'),
                ),
                const SizedBox(height: 8),
              ],
              if (!hasData || hasOneFile) ...[
                if (!hasOneFile)
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, _QtImportMode.oneFile),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('1 fattura'),
                  ),
                if (!hasOneFile) const SizedBox(height: 8),
                if (!hasOneFile)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, _QtImportMode.twoFiles),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('2 fatture dello stesso mese'),
                  ),
                if (hasOneFile)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, _QtImportMode.replaceAll),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reimporta da zero'),
                  ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, _QtImportMode.replaceAll),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reimporta da zero'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _QtImportMode.oneFile:
        await _importExcel(expectedFiles: 1);
      case _QtImportMode.twoFiles:
        await _importExcel(expectedFiles: 2);
      case _QtImportMode.addSecond:
        await _addSecondInvoice();
      case _QtImportMode.replaceAll:
        await _showReplaceImportMenu();
    }
  }

  Future<void> _showReplaceImportMenu() async {
    final choice = await showModalBottomSheet<_QtImportMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reimporta fatture',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sostituisce i file attuali. Scegli quante fatture caricare.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, _QtImportMode.oneFile),
                icon: const Icon(Icons.upload_file),
                label: const Text('1 fattura'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, _QtImportMode.twoFiles),
                icon: const Icon(Icons.upload_file),
                label: const Text('2 fatture dello stesso mese'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _QtImportMode.oneFile) {
      await _importExcel(expectedFiles: 1);
    } else if (choice == _QtImportMode.twoFiles) {
      await _importExcel(expectedFiles: 2);
    }
  }

  List<QtCarburanteRccSenzaFatturaRow> get _senzaFatturaVisibili {
    final res = _result;
    if (res == null) return const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    return res.giustificativiSenzaFattura.where((r) {
      if (q.isEmpty) return true;
      return r.numeroCarta.toLowerCase().contains(q) ||
          (r.nomeCognome ?? '').toLowerCase().contains(q) ||
          (r.cantiere ?? '').toLowerCase().contains(q) ||
          (r.tipoCarburante ?? '').toLowerCase().contains(q) ||
          _df.format(r.dataRifornimento).contains(q);
    }).toList();
  }

  List<QtCarburantePossibileErroreBattitura> get _possibiliErroriVisibili {
    final res = _result;
    if (res == null) return const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    return res.possibiliErroriBattitura.where((s) {
      if (q.isEmpty) return true;
      final rcc = s.rcc;
      final qt = s.transazione;
      return rcc.numeroCarta.toLowerCase().contains(q) ||
          (rcc.nomeCognome ?? '').toLowerCase().contains(q) ||
          (rcc.cantiere ?? '').toLowerCase().contains(q) ||
          qt.numeroCarta.toLowerCase().contains(q) ||
          qt.prodotto.toLowerCase().contains(q) ||
          _df.format(rcc.dataRifornimento).contains(q) ||
          _df.format(qt.dataTransazione).contains(q) ||
          s.differenze.any((d) => d.toLowerCase().contains(q));
    }).toList();
  }

  Widget _buildMonthBar(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Anno precedente',
                  onPressed: _loading || _monthsLoading
                      ? null
                      : () => _shiftYear(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Anno $_selectedYear',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Anno successivo',
                  onPressed: _loading || _monthsLoading
                      ? null
                      : () => _shiftYear(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_monthsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var m = 1; m <= 12; m++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 6),
                        child: FilterChip(
                          label: Text(_monthNames[m - 1]),
                          selected: m == _selectedMonth,
                          onSelected: _loading
                              ? null
                              : (_) => _selectMonth(m),
                          avatar: _monthHasData(_selectedYear, m)
                              ? Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<QtCarburanteSchedaRiepilogo> get _schedeVisibili {
    final res = _result;
    if (res == null) return const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    return res.perScheda.where((s) {
      if (q.isEmpty) return true;
      return s.numeroCarta.toLowerCase().contains(q) ||
          (s.assegnatario ?? '').toLowerCase().contains(q) ||
          (s.assegnatarioAttuale ?? '').toLowerCase().contains(q) ||
          (s.commessa ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<QtCarburanteVerificaRow> get _righeVisibili {
    final res = _result;
    if (res == null) return const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    return res.righe.where((r) {
      if (_filtro == _QtFiltroStato.giustificati &&
          r.stato != QtCarburanteStatoVerifica.giustificato) {
        return false;
      }
      if (_filtro == _QtFiltroStato.mancanti &&
          r.stato != QtCarburanteStatoVerifica.mancante) {
        return false;
      }
      if (_filtroScheda != null &&
          r.transazione.numeroCarta.trim() != _filtroScheda) {
        return false;
      }
      if (q.isEmpty) return true;
      final t = r.transazione;
      return t.numeroCarta.toLowerCase().contains(q) ||
          t.prodotto.toLowerCase().contains(q) ||
          _df.format(t.dataTransazione).contains(q) ||
          (r.assegnatario ?? '').toLowerCase().contains(q) ||
          (r.assegnatarioAttuale ?? '').toLowerCase().contains(q) ||
          (r.rccCommessa ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _apriScheda(QtCarburanteSchedaRiepilogo s) {
    setState(() {
      _filtroScheda = s.numeroCarta.trim();
      _filtro = _QtFiltroStato.tutti;
    });
    _tabController.animateTo(1);
  }

  Future<void> _exportExcel() async {
    final res = _result;
    if (res == null) return;

    setState(() => _exporting = true);
    try {
      final bytes = QtCarburanteVerificaExport.buildExcelBytes(
        result: res,
        fileNames: _fileNames,
        dateFmt: _df,
        numFmt: _nf,
      );
      final baseName = (_fileNames.isEmpty ? 'QT_verifica' : _fileNames.first)
          .replaceAll(RegExp(r'\.xlsx?$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: _fileNames.length > 1
            ? '${baseName}_e_altro_verifica'
            : '${baseName}_verifica',
        bytes: bytes,
        openFile: true,
      );
      if (!saved || !mounted) {
        if (mounted && !saved) {
          ModifyFeedback.error(
            context,
            'Download non avviato. Controlla i permessi del browser o riprova.',
          );
        }
        return;
      }
      final p = ExcelExportHelper.lastSavedPath ?? '';
      ModifyFeedback.success(
        context,
        kIsWeb
            ? 'Export avviato: controlla la cartella Download del browser ($p).'
            : p.isEmpty
                ? 'Export completato: ${res.totale} transazioni e '
                    '${res.perScheda.length} schede (2 fogli Excel).'
                : 'Export completato.\n$p',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore export: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fonteLabel(QtCarburanteFonteGiustificativo? fonte) {
    return switch (fonte) {
      QtCarburanteFonteGiustificativo.rccMdo => 'MDO',
      QtCarburanteFonteGiustificativo.rccStradali => 'Stradali',
      null => '—',
    };
  }

  String _rccLabel(QtCarburanteVerificaRow r) {
    if (r.stato != QtCarburanteStatoVerifica.giustificato) {
      return r.nota ?? '—';
    }
    final parts = <String>['Registro ${_fonteLabel(r.fonte)}'];
    final compilatore = r.rccNomeCognome?.trim();
    if (compilatore != null && compilatore.isNotEmpty) {
      parts.add('compilato da $compilatore');
    }
    return parts.join(' · ');
  }

  Widget _summaryChip({
    required String label,
    required String value,
    Color? color,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return FilterChip(
      label: Text('$label: $value'),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap(),
      selectedColor: color?.withValues(alpha: 0.2),
      checkmarkColor: color,
    );
  }

  Widget _buildViewTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedColor = scheme.primary;
    final unselectedColor = isDark
        ? scheme.onSurface.withValues(alpha: 0.78)
        : const Color(0xFF4A4A4A);

    return TabBar(
      controller: _tabController,
      labelColor: selectedColor,
      unselectedLabelColor: unselectedColor,
      indicatorColor: selectedColor,
      dividerColor: scheme.outline.withValues(alpha: isDark ? 0.28 : 0.22),
      labelStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      tabs: [
        Tab(text: 'Per scheda (${_schedeVisibili.length})'),
        Tab(text: 'Transazioni (${_righeVisibili.length})'),
        Tab(text: 'Senza fattura (${_senzaFatturaVisibili.length})'),
        Tab(text: 'Possibili errori (${_possibiliErroriVisibili.length})'),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final res = _result!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      elevation: 1,
      color: isDark
          ? theme.colorScheme.surface
          : Colors.white.withValues(alpha: 0.97),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_fileNames.isNotEmpty) ...[
              for (var i = 0; i < _fileNames.length; i++)
                Text(
                  _fileNames.length == 1
                      ? 'File: ${_fileNames[i]}'
                      : 'File ${i + 1}: ${_fileNames[i]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            Text(
              'Periodo: ${_df.format(res.dataMin)} – ${_df.format(res.dataMax)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_fileNames.length == 1) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(
                      alpha: 0.35,
                    ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Caricata 1 fattura su 2: aggiungi la seconda per '
                          'il mese intero.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _loading ? null : _addSecondInvoice,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('2ª fattura'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_fileNames.length >= 2) ...[
              const SizedBox(height: 4),
              Text(
                'Mese completo (${_fileNames.length} fatture unite)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryChip(
                  label: 'Totale',
                  value: '${res.totale}',
                  selected:
                      _filtro == _QtFiltroStato.tutti && _filtroScheda == null,
                  onTap: () => setState(() {
                    _filtro = _QtFiltroStato.tutti;
                    _filtroScheda = null;
                  }),
                ),
                _summaryChip(
                  label: 'Giustificati',
                  value: '${res.giustificati}',
                  color: Colors.green.shade700,
                  selected: _filtro == _QtFiltroStato.giustificati,
                  onTap: () {
                    setState(() {
                      _filtro = _QtFiltroStato.giustificati;
                      _filtroScheda = null;
                    });
                    _tabController.animateTo(1);
                  },
                ),
                _summaryChip(
                  label: 'Mancanti',
                  value: '${res.mancanti}',
                  color: Colors.red.shade700,
                  selected: _filtro == _QtFiltroStato.mancanti,
                  onTap: () {
                    setState(() {
                      _filtro = _QtFiltroStato.mancanti;
                      _filtroScheda = null;
                    });
                    _tabController.animateTo(1);
                  },
                ),
                _summaryChip(
                  label: 'Giust. senza fattura',
                  value: '${res.senzaFattura}',
                  color: Colors.orange.shade800,
                  selected: _tabController.index == 2,
                  onTap: () => _tabController.animateTo(2),
                ),
                if (res.possibiliErrori > 0)
                  _summaryChip(
                    label: 'Possibili errori',
                    value: '${res.possibiliErrori}',
                    color: Colors.deepPurple.shade700,
                    selected: _tabController.index == 3,
                    onTap: () => _tabController.animateTo(3),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                            labelText: 'Cerca nome, scheda, commessa o data',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_filtroScheda != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text('Carta $_filtroScheda'),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _filtroScheda = null),
                ),
              ),
            ],
            _buildViewTabBar(context),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (_fileNames.length == 1)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _addSecondInvoice,
                    icon: const Icon(Icons.add),
                    label: const Text('Aggiungi 2ª fattura'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _exporting ? null : _exportExcel,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Esporta tutti i dati'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsabileCell({
    required String? responsabile,
    required String? attuale,
    required bool daStorico,
  }) {
    final nome = responsabile?.trim();
    if (nome == null || nome.isEmpty) {
      return const Text('—');
    }
    final oggi = attuale?.trim();
    if (!daStorico || oggi == null || oggi.isEmpty) {
      return Text(nome);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          'Multicard oggi: $oggi',
          style: TextStyle(
            fontSize: 11,
            color: Colors.amber.shade900,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _statoBadge(QtCarburanteStatoVerifica stato) {
    final ok = stato == QtCarburanteStatoVerifica.giustificato;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.blueGrey).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        ok ? 'OK' : 'Da registro',
        style: TextStyle(
          color: ok ? Colors.green.shade800 : Colors.blueGrey.shade800,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSchedaTab(BuildContext context) {
    final schede = _schedeVisibili;
    if (schede.isEmpty) {
      return const Center(child: Text('Nessuna scheda per i filtri selezionati.'));
    }

    if (_narrow(context)) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: schede.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final s = schede[i];
          final completa = s.giustificati == s.totale;
          return Card(
            child: ListTile(
              isThreeLine: true,
              title: Text(
                s.assegnatario?.trim().isNotEmpty == true
                    ? s.assegnatario!.trim()
                    : s.numeroCarta.trim(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (s.responsabileDaStorico &&
                      s.assegnatarioAttuale?.trim().isNotEmpty == true)
                    'Multicard oggi: ${s.assegnatarioAttuale!.trim()}',
                  'Carta ${s.numeroCarta.trim()}',
                  if (s.commessa?.trim().isNotEmpty == true)
                    'Commessa ${s.commessa!.trim()}',
                  '${s.giustificati}/${s.totale} giustificati · '
                  '€ ${_nf.format(s.importoMancante)} da giustificare',
                ].join('\n'),
              ),
              trailing: Icon(
                completa ? Icons.check_circle : Icons.chevron_right,
                color: completa
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.primary,
              ),
              onTap: () => _apriScheda(s),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: 960,
        headingRowHeight: 40,
        dataRowHeight: 56,
        columns: const [
          DataColumn2(
            label: Text('Responsabile alla data'),
            size: ColumnSize.L,
          ),
          DataColumn2(label: Text('Numero carta'), size: ColumnSize.M),
          DataColumn2(label: Text('Commessa'), size: ColumnSize.L),
          DataColumn2(label: Text('Giustificati'), numeric: true, size: ColumnSize.S),
          DataColumn2(
            label: Text('Da giustificare'),
            numeric: true,
            size: ColumnSize.S,
          ),
          DataColumn2(label: Text('Stato'), size: ColumnSize.S),
        ],
        rows: [
          for (final s in schede)
            DataRow2(
              onTap: () => _apriScheda(s),
              cells: [
                DataCell(_buildResponsabileCell(
                  responsabile: s.assegnatario,
                  attuale: s.assegnatarioAttuale,
                  daStorico: s.responsabileDaStorico,
                )),
                DataCell(Text(s.numeroCarta.trim())),
                DataCell(Text(
                  s.commessa?.trim().isNotEmpty == true
                      ? s.commessa!.trim()
                      : '—',
                )),
                DataCell(Text('${s.giustificati}/${s.totale}')),
                DataCell(Text('€ ${_nf.format(s.importoMancante)}')),
                DataCell(_statoBadge(
                  s.giustificati == s.totale
                      ? QtCarburanteStatoVerifica.giustificato
                      : QtCarburanteStatoVerifica.mancante,
                )),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTransazioniTab(BuildContext context) {
    final rows = _righeVisibili;
    if (rows.isEmpty) {
      return const Center(child: Text('Nessuna riga per i filtri selezionati.'));
    }

    if (_narrow(context)) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final r = rows[i];
          final t = r.transazione;
          final ok = r.stato == QtCarburanteStatoVerifica.giustificato;
          return Card(
            child: ListTile(
              isThreeLine: true,
              leading: Icon(
                ok ? Icons.check_circle_outline : Icons.pending_outlined,
                color: ok ? Colors.green.shade700 : Colors.blueGrey.shade600,
              ),
              title: Text(
                r.assegnatario?.trim().isNotEmpty == true
                    ? r.assegnatario!.trim()
                    : t.numeroCarta.trim(),
              ),
              subtitle: Text(
                [
                  if (r.responsabileDaStorico &&
                      r.assegnatarioAttuale?.trim().isNotEmpty == true)
                    'Multicard oggi: ${r.assegnatarioAttuale!.trim()}',
                  if (r.assegnatario?.trim().isNotEmpty == true)
                    'Carta ${t.numeroCarta.trim()}',
                  if (r.rccCommessa?.trim().isNotEmpty == true)
                    'Commessa ${r.rccCommessa!.trim()}',
                  '${_df.format(t.dataTransazione)} · ${t.prodotto}',
                  '${_nf.format(t.volume)} L · € ${_nf.format(t.importo)}',
                ].join('\n'),
              ),
              trailing: Text(
                ok ? _rccLabel(r) : 'Da registro',
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? Colors.green.shade800 : Colors.blueGrey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: 1240,
        headingRowHeight: 40,
        dataRowHeight: 56,
        columns: const [
          DataColumn2(label: Text('Stato'), size: ColumnSize.S),
          DataColumn2(
            label: Text('Responsabile alla data'),
            size: ColumnSize.M,
          ),
          DataColumn2(label: Text('Numero Carta'), size: ColumnSize.M),
          DataColumn2(label: Text('Data'), size: ColumnSize.S),
          DataColumn2(label: Text('Prodotto'), size: ColumnSize.M),
          DataColumn2(label: Text('Commessa'), size: ColumnSize.L),
          DataColumn2(label: Text('Volume'), numeric: true, size: ColumnSize.S),
          DataColumn2(label: Text('Importo'), numeric: true, size: ColumnSize.S),
          DataColumn2(label: Text('Registro'), size: ColumnSize.S),
        ],
        rows: [
          for (final r in rows)
            DataRow2(
              cells: [
                DataCell(_statoBadge(r.stato)),
                DataCell(_buildResponsabileCell(
                  responsabile: r.assegnatario,
                  attuale: r.assegnatarioAttuale,
                  daStorico: r.responsabileDaStorico,
                )),
                DataCell(Text(r.transazione.numeroCarta.trim())),
                DataCell(Text(_df.format(r.transazione.dataTransazione))),
                DataCell(Text(r.transazione.prodotto)),
                DataCell(Text(
                  r.rccCommessa?.trim().isNotEmpty == true
                      ? r.rccCommessa!.trim()
                      : '—',
                )),
                DataCell(Text(_nf.format(r.transazione.volume))),
                DataCell(Text('€ ${_nf.format(r.transazione.importo)}')),
                DataCell(Text(_rccLabel(r))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPossibiliErroriTab(BuildContext context) {
    final rows = _possibiliErroriVisibili;
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nessun abbinamento sospetto tra giustificativi RCC e '
            'transazioni QT.\n\n'
            'Qui compaiono le coppie con stessa scheda e valori '
            'simili su data, litri o importo che potrebbero non '
            'corrispondere per un errore di battitura.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = rows[i];
        final rcc = s.rcc;
        final qt = s.transazione;
        final theme = Theme.of(context);
        return Card(
          color: Colors.deepPurple.shade50.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.12 : 1,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.compare_arrows,
                      color: Colors.deepPurple.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Potrebbe essere lo stesso rifornimento',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.deepPurple.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildConfrontoColonna(
                        context,
                        titolo: 'Giustificativo RCC (${_fonteLabel(rcc.fonte)})',
                        righe: [
                          rcc.nomeCognome?.trim().isNotEmpty == true
                              ? rcc.nomeCognome!.trim()
                              : '—',
                          'Carta ${rcc.numeroCarta}',
                          _df.format(rcc.dataRifornimento),
                          rcc.tipoCarburante?.trim().isNotEmpty == true
                              ? rcc.tipoCarburante!.trim()
                              : '—',
                          rcc.cantiere?.trim().isNotEmpty == true
                              ? rcc.cantiere!.trim()
                              : '—',
                          '${rcc.litri == null ? '—' : '${_nf.format(rcc.litri)} L'} · '
                              '${rcc.euro == null ? '—' : '€ ${_nf.format(rcc.euro)}'}',
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                      child: Icon(
                        Icons.sync_alt,
                        color: Colors.deepPurple.shade400,
                      ),
                    ),
                    Expanded(
                      child: _buildConfrontoColonna(
                        context,
                        titolo: 'Transazione in fattura QT',
                        righe: [
                          qt.numeroCarta,
                          _df.format(qt.dataTransazione),
                          qt.prodotto,
                          '${_nf.format(qt.volume)} L · € ${_nf.format(qt.importo)}',
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in s.differenze)
                      Chip(
                        avatar: Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Colors.deepOrange.shade800,
                        ),
                        label: Text(d),
                        backgroundColor: Colors.deepOrange.shade50,
                        labelStyle: TextStyle(
                          color: Colors.deepOrange.shade900,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfrontoColonna(
    BuildContext context, {
    required String titolo,
    required List<String> righe,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titolo,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final r in righe)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(r, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _buildSenzaFatturaTab(BuildContext context) {
    final rows = _senzaFatturaVisibili;
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nessun giustificativo RCC nel mese senza corrispondenza '
            'in fattura QT.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_narrow(context)) {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final r = rows[i];
          return Card(
            child: ListTile(
              isThreeLine: true,
              leading: Icon(
                Icons.receipt_long_outlined,
                color: Colors.orange.shade800,
              ),
              title: Text(
                r.nomeCognome?.trim().isNotEmpty == true
                    ? r.nomeCognome!.trim()
                    : r.numeroCarta,
              ),
              subtitle: Text(
                [
                  _fonteLabel(r.fonte),
                  'Carta ${r.numeroCarta}',
                  if (r.cantiere?.trim().isNotEmpty == true)
                    'Commessa ${r.cantiere!.trim()}',
                  '${_df.format(r.dataRifornimento)} · '
                      '${r.tipoCarburante?.trim().isNotEmpty == true ? r.tipoCarburante!.trim() : '—'}',
                  '${r.litri == null ? '—' : '${_nf.format(r.litri)} L'} · '
                      '${r.euro == null ? '—' : '€ ${_nf.format(r.euro)}'}',
                ].join('\n'),
              ),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: 1100,
        headingRowHeight: 40,
        dataRowHeight: 56,
        columns: const [
          DataColumn2(label: Text('Registro'), size: ColumnSize.S),
          DataColumn2(label: Text('Dipendente'), size: ColumnSize.M),
          DataColumn2(label: Text('Numero Carta'), size: ColumnSize.M),
          DataColumn2(label: Text('Data'), size: ColumnSize.S),
          DataColumn2(label: Text('Prodotto'), size: ColumnSize.M),
          DataColumn2(label: Text('Commessa'), size: ColumnSize.L),
          DataColumn2(label: Text('Litri'), numeric: true, size: ColumnSize.S),
          DataColumn2(label: Text('Euro'), numeric: true, size: ColumnSize.S),
        ],
        rows: [
          for (final r in rows)
            DataRow2(
              cells: [
                DataCell(Text(_fonteLabel(r.fonte))),
                DataCell(Text(r.nomeCognome?.trim().isNotEmpty == true
                    ? r.nomeCognome!.trim()
                    : '—')),
                DataCell(Text(r.numeroCarta)),
                DataCell(Text(_df.format(r.dataRifornimento))),
                DataCell(Text(r.tipoCarburante?.trim().isNotEmpty == true
                    ? r.tipoCarburante!.trim()
                    : '—')),
                DataCell(Text(r.cantiere?.trim().isNotEmpty == true
                    ? r.cantiere!.trim()
                    : '—')),
                DataCell(Text(
                  r.litri == null ? '—' : _nf.format(r.litri),
                )),
                DataCell(Text(
                  r.euro == null ? '—' : '€ ${_nf.format(r.euro)}',
                )),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildResultBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSchedaTab(context),
              _buildTransazioniTab(context),
              _buildSenzaFatturaTab(context),
              _buildPossibiliErroriTab(context),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Verifica fatturazione carburante QT',
        ),
        actions: [
          if (_result != null)
            IconButton(
              tooltip: 'Esporta tutti i dati',
              icon: _exporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              onPressed: _loading || _exporting ? null : _exportExcel,
            ),
          IconButton(
            tooltip: 'Importa fatture QT',
            icon: const Icon(Icons.upload_file),
            onPressed: _loading ? null : _showImportMenu,
          ),
        ],
      )),
      floatingActionButton: _result == null
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _showImportMenu,
              icon: const Icon(Icons.upload_file),
              label: const Text('Importa fatture'),
            )
          : null,
      body: PageWithTopLogo(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMonthBar(context),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _result == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_gas_station_outlined,
                                  size: 56,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Importa una o due fatture Excel QT '
                                  '(es. QT_15052026.xlsx e QT_31052026.xlsx).\n\n'
                                  'Il mese viene rilevato automaticamente dalle '
                                  'date transazione e salvato nel mese corretto.\n\n'
                                  'Le fatture vengono confrontate con i registri RCC '
                                  '(MDO e Stradali) per evidenziare cosa manca '
                                  'in fattura e cosa è giustificato dal '
                                  'dipendente ma non compare in fattura.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _showImportMenu,
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text('Scegli 1 o 2 fatture'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildResultBody(context),
            ),
          ],
        ),
      ),
    );
  }
}
