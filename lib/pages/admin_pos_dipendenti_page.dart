import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/confirm_sound_service.dart';
import '../services/pos_commessa_dipendente_service.dart';
import '../services/pos_maestranze_import_parser.dart';
import '../services/supabase_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/personale_name_matcher.dart';
import '../utils/roles.dart';
import '../utils/responsive.dart';
import '../utils/gestopro_page_chrome.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminPosDipendentiPage extends StatefulWidget {
  const AdminPosDipendentiPage({
    super.key,
    this.userId,
    this.role,
    this.readOnly = false,
  });

  final int? userId;
  final String? role;
  final bool readOnly;

  @override
  State<AdminPosDipendentiPage> createState() => _AdminPosDipendentiPageState();
}

class _AdminPosDipendentiPageState extends State<AdminPosDipendentiPage> {
  bool _loading = true;
  String? _commessaId;
  Map<String, String> _commesse = {};
  List<PosCommessaRiepilogo> _riepilogoCommesse = [];
  Map<String, String> _personale = {};
  List<PosCommessaDipendenteRow> _righe = [];
  DateTime? _ultimoAggiornamentoApp;
  String? _userUuid;
  final TextEditingController _searchCtrl = TextEditingController();
  String _commessaListaFiltro = 'ALL';
  String _mldListaSelezionata = 'TE';

  static const double _commesseListaMaxWidth = 520;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  bool _matchesSearch(PosCommessaDipendenteRow r, String q) {
    if (r.personaleFullName.toLowerCase().contains(q)) return true;
    final imp = '${r.cognomeImport ?? ''} ${r.nomeImport ?? ''}'.trim().toLowerCase();
    if (imp.isNotEmpty && imp.contains(q)) return true;
    for (final c in r.formazioni81) {
      if (c.toLowerCase().contains(q)) return true;
    }
    for (final c in r.formazioniRfi) {
      if (c.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  bool get _effectiveReadOnly =>
      widget.readOnly ||
      (widget.role != null &&
          widget.role!.trim().isNotEmpty &&
          !canManagePosDipendentiLista(widget.role!));

  List<PosCommessaDipendenteRow> get _righeFiltrate {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _righe;
    return _righe.where((r) => _matchesSearch(r, q)).toList();
  }

  bool get _isComessaMld {
    final cid = _commessaId;
    if (cid == null || cid.isEmpty) return false;
    final nome = (_commesse[cid] ?? '').trim().toUpperCase();
    return nome.startsWith('MLD-') || nome.startsWith('MLD ');
  }

  String get _listaMldKey => _isComessaMld ? _mldListaSelezionata : '';

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _resolveUserUuid();
      _commesse = await PosCommessaDipendenteService.loadCommesseAttive();
      _riepilogoCommesse =
          await PosCommessaDipendenteService.loadCommesseRiepilogo(_commesse);
      _personale = await PosCommessaDipendenteService.loadPersonaleAttivo();
      if (_commessaId != null && _commesse.containsKey(_commessaId)) {
        await _reloadLista();
      }
    } catch (e) {
      _snack('Errore caricamento: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveUserUuid() async {
    final auth = SupabaseService.client.auth.currentUser;
    if (auth != null) {
      final row = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('auth_id', auth.id)
          .maybeSingle();
      final u = (row?['id_uuid'] ?? '').toString().trim();
      if (u.isNotEmpty) {
        _userUuid = u;
        return;
      }
    }
    final uid = widget.userId;
    if (uid != null) {
      final row = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('id', uid)
          .maybeSingle();
      _userUuid = (row?['id_uuid'] ?? '').toString().trim();
    }
  }

  Future<void> _reloadLista() async {
    final cid = _commessaId;
    if (cid == null || cid.isEmpty) return;
    _ultimoAggiornamentoApp =
        await PosCommessaDipendenteService.loadUltimoAggiornamentoApp(
      cid,
      listaMldKey: _listaMldKey,
    );
    _righe = await PosCommessaDipendenteService.loadDipendentiPos(
      cid,
      listaMldKey: _listaMldKey,
    );
    await _refreshRiepilogoCommesse();
    if (mounted) setState(() {});
  }

  Future<void> _refreshRiepilogoCommesse() async {
    if (_commesse.isEmpty) return;
    _riepilogoCommesse =
        await PosCommessaDipendenteService.loadCommesseRiepilogo(_commesse);
    if (mounted) setState(() {});
  }

  static const List<String> _commessaFiltri = <String>[
    'ALL',
    'TE',
    'TLC',
    'IS',
    'LFM',
  ];

  String _commessaCategoria(String nomeCommessa) {
    final up = nomeCommessa.trim().toUpperCase();
    for (final code in _commessaFiltri.where((c) => c != 'ALL')) {
      if (up.startsWith('$code-') || up.startsWith('$code ')) {
        return code;
      }
    }
    return 'ALTRE';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _onCommessaChanged(String? id) async {
    setState(() {
      _commessaId = id;
      _righe = [];
      _ultimoAggiornamentoApp = null;
      _searchCtrl.clear();
      _mldListaSelezionata = 'TE';
    });
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _reloadLista();
    } catch (e) {
      _snack('Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final bytes = PosMaestranzeImportParser.buildTemplateExcelBytes();
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Modello_Elenco_Maestranze_POS',
        bytes: bytes,
      );
      if (!mounted) return;
      if (!saved) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      _snack(
        path.isEmpty
            ? 'Modello Excel scaricato. Compilalo e reimportalo con «Import Excel».'
            : 'Modello Excel scaricato:\n$path',
      );
    } catch (e) {
      _snack('Errore download modello: $e', error: true);
    }
  }

  Future<void> _importFile() async {
    final cid = _commessaId;
    if (cid == null || cid.isEmpty) {
      _snack('Seleziona prima la commessa', error: true);
      return;
    }
    const types = <XTypeGroup>[
      XTypeGroup(
        label: 'Excel o Word',
        extensions: <String>['xlsx', 'xls', 'docx'],
      ),
    ];
    final file = await openFile(acceptedTypeGroups: types);
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final parsed = await PosMaestranzeImportParser.parseFile(
        fileName: file.name,
        bytes: bytes,
      );
      if (parsed.righe.isEmpty) {
        _snack(parsed.avviso ?? 'File senza righe utili', error: true);
        return;
      }
      final previews = PosCommessaDipendenteService.previewImportMatches(
        righe: parsed.righe,
        personaleById: _personale,
      );
      if (!mounted) return;
      final confirmed = await showDialog<List<PosImportMatchPreview>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ImportPreviewDialog(
          fileName: file.name,
          dataLista: parsed.dataUltimoAggiornamento,
          previews: previews,
          personaleById: _personale,
        ),
      );
      if (confirmed == null) return;

      final result = await PosCommessaDipendenteService.applyImport(
        commessaId: cid,
        previews: confirmed,
        dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
        userUuid: _userUuid,
        listaMldKey: _listaMldKey,
      );
      await _reloadLista();
      final parts = <String>[
        if (result.added > 0) '${result.added} nuovi',
        if (result.updated > 0) '${result.updated} aggiornati',
        if (result.skipped > 0) '${result.skipped} non abbinati',
      ];
      _snack(
        parts.isEmpty
            ? 'Import completato (nessuna modifica)'
            : 'Import completato: ${parts.join(', ')}',
      );
    } catch (e) {
      _snack('Import non riuscito: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDipendenteManuale() async {
    final cid = _commessaId;
    if (cid == null) return;
    final existing = _righe.map((r) => r.personaleId).toSet();
    final available = _personale.entries
        .where((e) => !existing.contains(e.key))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (available.isEmpty) {
      _snack('Tutti i dipendenti attivi sono già in lista', error: true);
      return;
    }

    String? selected = available.first.key;
    TextEditingController? queryCtrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Iterable<MapEntry<String, String>> filterOptions(String query) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return available.take(50);
            return available
                .where((e) => e.value.toLowerCase().contains(q))
                .take(50);
          }

          String? resolveFromQuery(String query) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return selected;
            for (final e in available) {
              if (e.value.toLowerCase() == q) return e.key;
            }
            return null;
          }

          return AlertDialog(
            title: const Text('Aggiungi dipendente al POS'),
            content: SizedBox(
              width: 480,
              child: _PersonaleImportAutocomplete(
                hint: 'Dipendente (scrivi e seleziona)',
                initialQuery: available.first.value,
                optionsBuilder: filterOptions,
                onSelected: (id) => setDialogState(() => selected = id),
                onFieldReady: (ctrl) => queryCtrl = ctrl,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () {
                  final resolved =
                      resolveFromQuery(queryCtrl?.text ?? '') ?? selected;
                  if (resolved == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Seleziona un dipendente dalla lista o scrivi il nome completo.',
                        ),
                      ),
                    );
                    return;
                  }
                  selected = resolved;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Aggiungi'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || selected == null) return;

    try {
      final full = _personale[selected!] ?? '';
      final parts = PersonaleNameMatcher.tokens(full);
      final cognome = parts.isNotEmpty ? parts.last : '';
      final nome = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '';
      await PosCommessaDipendenteService.addDipendente(
        commessaId: cid,
        personaleId: selected!,
        cognomeImport: cognome,
        nomeImport: nome,
        createdByUserUuid: _userUuid,
        listaMldKey: _listaMldKey,
      );
      await _reloadLista();
      _snack('Dipendente aggiunto');
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  Future<void> _removeRow(PosCommessaDipendenteRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi dal POS'),
        content: Text('Rimuovere ${row.personaleFullName} da questa commessa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PosCommessaDipendenteService.removeDipendente(row.id);
      await _reloadLista();
      _snack('Rimosso');
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  Future<void> _onMldListaChanged(String key) async {
    if (_mldListaSelezionata == key) return;
    setState(() {
      _mldListaSelezionata = key;
      _righe = [];
      _ultimoAggiornamentoApp = null;
      _searchCtrl.clear();
      _loading = true;
    });
    try {
      await _reloadLista();
    } catch (e) {
      _snack('Errore cambio lista MLD: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
    final canEdit = !_effectiveReadOnly;
    final narrow = useMobileUi(context);
    final pad = narrow ? 12.0 : 16.0;
    final filtrate = _righeFiltrate;
    final searchActive = _searchCtrl.text.trim().isNotEmpty;

    final pageTitle = _effectiveReadOnly
        ? (narrow ? 'Lista POS (lettura)' : 'Lista dipendenti POS (sola lettura)')
        : (narrow ? 'Lista POS' : 'Lista dipendenti POS');
    final refreshAction = IconButton(
      tooltip: 'Ricarica',
      onPressed: _loading ? null : _bootstrap,
      icon: const Icon(Icons.refresh),
    );

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: [refreshAction],
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text(pageTitle),
        actions: [refreshAction],
      )),
      body: _loading && _commesse.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 16),
                    children: [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(narrow ? 12 : 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                narrow
                                    ? '1. Seleziona commessa'
                                    : '1. Seleziona commessa (cantiere)',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              CommessaUuidAutocompleteField(
                                commesseByUuid: _commesse,
                                selectedUuid: _commessaId,
                                labelText: narrow
                                    ? 'Commessa'
                                    : 'Commessa (scrivi e seleziona)',
                                onSelected: _onCommessaChanged,
                              ),
                              if (_commessaId != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _ultimoAggiornamentoApp != null
                                      ? 'Ultimo aggiornamento in app: ${dateTimeFmt.format(_ultimoAggiornamentoApp!)}'
                                      : 'Ultimo aggiornamento in app: da inserire',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: narrow ? 13 : 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  searchActive
                                      ? '${filtrate.length} di ${_righe.length} dipendenti'
                                      : _isComessaMld
                                          ? '${_righe.length} dipendenti nella lista $_mldListaSelezionata'
                                          : '${_righe.length} dipendenti nel POS di questa commessa',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_commessaId == null) ...[
                        const SizedBox(height: 12),
                        _buildTemplateHelpCard(narrow),
                        const SizedBox(height: 12),
                        _buildCommesseListaCompleta(
                          dateTimeFmt: dateTimeFmt,
                          narrow: narrow,
                        ),
                      ],
                      if (_commessaId != null) ...[
                        const SizedBox(height: 12),
                        if (_isComessaMld) ...[
                          _buildMldListeSelector(narrow),
                          const SizedBox(height: 12),
                        ],
                        if (canEdit) _buildActionButtons(narrow),
                        if (!canEdit) ...[
                          const SizedBox(height: 12),
                          _buildTemplateHelpCard(narrow, compact: true),
                        ],
                        if (_righe.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              labelText: 'Cerca dipendente o corso',
                              hintText: 'Nome, cognome, formazione 81, RFI…',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: searchActive
                                  ? IconButton(
                                      tooltip: 'Azzera ricerca',
                                      icon: const Icon(Icons.clear),
                                      onPressed: _searchCtrl.clear,
                                    )
                                  : null,
                            ),
                            textInputAction: TextInputAction.search,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_loading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_righe.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                _isComessaMld
                                    ? 'Nessun dipendente nella lista $_mldListaSelezionata di questa commessa. Usa Import o Aggiungi dipendente.'
                                    : 'Nessun dipendente in POS per questa commessa. Usa Import o Aggiungi dipendente.',
                              ),
                            ),
                          )
                        else if (filtrate.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Nessun risultato per «${_searchCtrl.text.trim()}».',
                              ),
                            ),
                          )
                        else
                          ...filtrate.map((r) => _buildDipendenteCard(
                                r,
                                canEdit: canEdit,
                                compact: narrow,
                              )),
                      ],
                    ],
                  ),
    );
  }

  Widget _buildCommesseListaCompleta({
    required DateFormat dateTimeFmt,
    required bool narrow,
  }) {
    final theme = Theme.of(context);
    final listaFiltrata = _commessaListaFiltro == 'ALL'
        ? _riepilogoCommesse
        : _riepilogoCommesse
            .where((r) => _commessaCategoria(r.nome) == _commessaListaFiltro)
            .toList(growable: false);
    final totali = listaFiltrata.length;
    final conData = _riepilogoCommesse
        .where((r) =>
            (_commessaListaFiltro == 'ALL' ||
                _commessaCategoria(r.nome) == _commessaListaFiltro) &&
            r.ultimoAggiornamentoApp != null)
        .length;
    final pctData =
        totali == 0 ? 0 : ((conData * 100) / totali).round();

    final lista = Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Elenco commesse',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commessaFiltri
                  .map(
                    (f) => ChoiceChip(
                      label: Text(f == 'ALL' ? 'Tutte' : f),
                      selected: _commessaListaFiltro == f,
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _commessaListaFiltro = f);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            Text(
              '$conData su $totali con aggiornamento in app ($pctData%)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (_loading && _riepilogoCommesse.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_riepilogoCommesse.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nessuna commessa attiva.'),
              )
            else if (listaFiltrata.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nessuna commessa per filtro ${_commessaListaFiltro == 'ALL' ? 'Tutte' : _commessaListaFiltro}.',
                ),
              )
            else
              for (var i = 0; i < listaFiltrata.length; i++) ...[
                _buildCommessaRiepilogoRow(
                  r: listaFiltrata[i],
                  dateTimeFmt: dateTimeFmt,
                  narrow: narrow,
                  theme: theme,
                ),
                if (i < listaFiltrata.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
              ],
          ],
        ),
      ),
    );

    if (narrow) return lista;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _commesseListaMaxWidth),
        child: lista,
      ),
    );
  }

  Widget _buildMldListeSelector(bool narrow) {
    const keys = <String>['TE', 'IS', 'TLC', 'FLM'];
    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Lista MLD multifunzionali',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keys
                  .map(
                    (k) => ChoiceChip(
                      label: Text(k),
                      selected: _mldListaSelezionata == k,
                      onSelected: (sel) {
                        if (!sel) return;
                        _onMldListaChanged(k);
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommessaRiepilogoRow({
    required PosCommessaRiepilogo r,
    required DateFormat dateTimeFmt,
    required bool narrow,
    required ThemeData theme,
  }) {
    final data = r.ultimoAggiornamentoApp;
    final dataLabel =
        data != null ? dateTimeFmt.format(data) : 'da inserire';
    return InkWell(
      onTap: () => _onCommessaChanged(r.commessaId),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: narrow ? 10 : 12,
          horizontal: 4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                r.nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: narrow ? 104 : 112,
              child: Text(
                dataLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: narrow ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: data != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontStyle:
                      data == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateHelpCard(bool narrow, {bool compact = false}) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              compact ? 'Modello import Excel' : 'Import elenco maestranze da Excel',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!compact) ...[
              const SizedBox(height: 6),
              const Text(
                'Scarica il modello per vedere il formato corretto (cognome, nome, '
                'idoneità sanitaria, mansione). Puoi anche importare file .xlsx come '
                'l\'allegato «Elenco Maestranze».',
                style: TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text(narrow ? 'Modello Excel' : 'Scarica modello Excel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool narrow) {
    final templateBtn = OutlinedButton.icon(
      onPressed: _downloadTemplate,
      icon: const Icon(Icons.download_outlined),
      label: Text(narrow ? 'Modello' : 'Scarica modello Excel'),
    );
    final importBtn = FilledButton.icon(
      onPressed: _importFile,
      icon: const Icon(Icons.upload_file),
      label: Text(narrow ? 'Import Excel' : 'Import Excel / Word'),
    );
    final addBtn = OutlinedButton.icon(
      onPressed: _addDipendenteManuale,
      icon: const Icon(Icons.person_add_outlined),
      label: Text(narrow ? 'Aggiungi' : 'Aggiungi dipendente'),
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: double.infinity, child: importBtn),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: templateBtn),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: addBtn),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [importBtn, templateBtn, addBtn],
    );
  }

  Widget _buildDipendenteCard(
    PosCommessaDipendenteRow r, {
    required bool canEdit,
    required bool compact,
  }) {
    return _PosDipendenteCard(
      row: r,
      canEdit: canEdit,
      compact: compact,
      onRemove: () => _removeRow(r),
    );
  }
}

/// Card dipendente POS: solo nome; dettagli formazioni con freccia.
class _PosDipendenteCard extends StatefulWidget {
  const _PosDipendenteCard({
    required this.row,
    required this.canEdit,
    required this.compact,
    required this.onRemove,
  });

  final PosCommessaDipendenteRow row;
  final bool canEdit;
  final bool compact;
  final VoidCallback onRemove;

  @override
  State<_PosDipendenteCard> createState() => _PosDipendenteCardState();
}

class _PosDipendenteCardState extends State<_PosDipendenteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final compact = widget.compact;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                10,
                compact ? 4 : 8,
                10,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.personaleFullName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 15 : 16,
                      ),
                    ),
                  ),
                  if (widget.canEdit)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      tooltip: 'Rimuovi dal POS',
                      onPressed: widget.onRemove,
                      icon: Icon(
                        Icons.person_remove_outlined,
                        color: Colors.red.shade700,
                        size: compact ? 22 : 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                8,
                compact ? 10 : 12,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PosFormazioniSection(
                    label: compact
                        ? 'Formazione 81/08'
                        : 'Formazione D.Lgs. 81/08',
                    corsi: r.formazioni81,
                    compact: compact,
                  ),
                  const SizedBox(height: 6),
                  _PosFormazioniSection(
                    label: 'Formazione RFI',
                    corsi: r.formazioniRfi,
                    compact: compact,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.fileName,
    required this.previews,
    required this.personaleById,
    this.dataLista,
  });

  final String fileName;
  final DateTime? dataLista;
  final List<PosImportMatchPreview> previews;
  final Map<String, String> personaleById;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late List<PosImportMatchPreview> _items;

  List<MapEntry<String, String>> get _personaleSorted {
    final list = widget.personaleById.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return list;
  }

  Set<String> get _usedPersonaleIds => _items
      .where((p) => p.matched)
      .map((p) => p.personaleId!)
      .toSet();

  int get _importCount => _items.where((p) => p.matched).length;

  int get _stillUnmatched =>
      _items.length - _importCount;

  @override
  void initState() {
    super.initState();
    _items = List<PosImportMatchPreview>.from(widget.previews);
  }

  Iterable<MapEntry<String, String>> _personaleOptionsForRow(
    int index,
    String query,
  ) {
    final currentId = _items[index].personaleId;
    final q = query.trim().toLowerCase();
    Iterable<MapEntry<String, String>> base = _personaleSorted.where(
      (e) => !_usedPersonaleIds.contains(e.key) || e.key == currentId,
    );
    if (q.isEmpty) return base.take(40);
    return base
        .where((e) => e.value.toLowerCase().contains(q))
        .take(40);
  }

  void _setMatch(int index, String personaleId) {
    setState(() {
      _items[index] = _items[index].copyWith(
        personaleId: personaleId,
        personaleFullName: widget.personaleById[personaleId],
      );
    });
  }

  void _clearMatch(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(clearMatch: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    var manualPicks = 0;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].matched && !widget.previews[i].matched) manualPicks++;
    }

    final mq = MediaQuery.of(context);
    final narrow = useMobileUi(context);
    final dialogW = cronosFormDialogWidth(context, desktop: 560);
    final dialogH = (mq.size.height - (narrow ? 100 : 140)).clamp(320.0, 520.0);

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 24,
        vertical: narrow ? 16 : 24,
      ),
      title: const Text('Anteprima import'),
      content: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${widget.fileName}'),
            if (widget.dataLista != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Data ultimo aggiornamento lista: ${dateFmt.format(widget.dataLista!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Righe lette: ${_items.length} · '
              'Da importare: $_importCount · '
              'Senza abbinamento: $_stillUnmatched'
              '${manualPicks > 0 ? ' ($manualPicks scelti a mano)' : ''}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Se il nome del file non coincide con l\'anagrafica, seleziona il dipendente corretto.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'I dipendenti già in lista vengono aggiornati; quelli non nel file restano invariati.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) => _buildRow(context, i),
              ),
            ),
            if (_stillUnmatched > 0)
              Text(
                'Restano $_stillUnmatched senza abbinamento: non verranno importati.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
          ],
        ),
      ),
      actions: narrow
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed:
                    _importCount > 0 ? () => Navigator.pop(context, _items) : null,
                child: Text('Importa $_importCount'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed:
                    _importCount > 0 ? () => Navigator.pop(context, _items) : null,
                child: Text('Importa $_importCount dipendenti (aggiunge/aggiorna)'),
              ),
            ],
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final p = _items[index];
    final imp = p.importRow;
    final fileLabel = '${imp.cognome} ${imp.nome}'.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  p.matched ? Icons.check_circle : Icons.warning_amber,
                  color: p.matched ? Colors.green : Colors.orange,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (p.matched && widget.previews[index].matched)
                        Text(
                          '→ ${p.personaleFullName}',
                          style: const TextStyle(fontSize: 13),
                        )
                      else if (p.matched)
                        Text(
                          '→ ${p.personaleFullName} (selezionato manualmente)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.green,
                          ),
                        )
                      else
                        const Text(
                          'Nessun abbinamento automatico',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (!p.matched) ...[
              const SizedBox(height: 6),
              _PersonaleImportAutocomplete(
                key: ValueKey('import-pick-$index-$fileLabel'),
                hint: 'Cerca in anagrafica (nome e cognome)',
                initialQuery: fileLabel,
                optionsBuilder: (q) => _personaleOptionsForRow(index, q),
                onSelected: (id) => _setMatch(index, id),
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _clearMatch(index),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Correggi abbinamento'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PersonaleImportAutocomplete extends StatelessWidget {
  const _PersonaleImportAutocomplete({
    super.key,
    required this.hint,
    required this.initialQuery,
    required this.optionsBuilder,
    required this.onSelected,
    this.onFieldReady,
  });

  final String hint;
  final String initialQuery;
  final Iterable<MapEntry<String, String>> Function(String query) optionsBuilder;
  final ValueChanged<String> onSelected;
  final void Function(TextEditingController ctrl)? onFieldReady;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<MapEntry<String, String>>(
      initialValue: TextEditingValue(text: initialQuery),
      displayStringForOption: (e) => e.value,
      optionsBuilder: (tev) => optionsBuilder(tev.text),
      onSelected: (e) => onSelected(e.key),
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 480),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(opt.value),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, ctrl, focusNode, onSubmitted) {
        onFieldReady?.call(ctrl);
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: ctrl,
              builder: (_, value, _) {
                if (value.text.trim().isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => ctrl.clear(),
                );
              },
            ),
          ),
          onSubmitted: (_) => onSubmitted(),
        );
      },
    );
  }
}

class _PosFormazioniSection extends StatelessWidget {
  const _PosFormazioniSection({
    required this.label,
    required this.corsi,
    this.compact = false,
  });

  final String label;
  final List<String> corsi;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
            fontSize: compact ? 12 : null,
          ),
        ),
        const SizedBox(height: 4),
        if (corsi.isEmpty)
          Text(
            'Nessun corso registrato in anagrafica',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          )
        else if (compact)
          ...corsi.map(
            (c) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                '• $c',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: corsi
                .map(
                  (c) => Chip(
                    label: Text(c),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
