import 'dart:io';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/date_formatters.dart';
import 'package:path/path.dart' as p;

import '../services/supabase_service.dart';
import '../services/confirm_sound_service.dart';
import '../services/vestiario_dpie_excel.dart';
import '../services/vestiario_articoli_service.dart';
import '../services/vestiario_magazzino_service.dart';
import '../utils/employee_taglie_export.dart';
import '../utils/vestiario_catalog.dart';
import '../utils/responsive.dart';
import '../utils/gestopro_page_chrome.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminVestiarioPage extends StatefulWidget {
  const AdminVestiarioPage({super.key});

  @override
  State<AdminVestiarioPage> createState() => _AdminVestiarioPageState();
}

class _AdminVestiarioPageState extends State<AdminVestiarioPage> {
  bool _loading = true;
  bool _busy = false;
  final List<_DipTaglie> _dipendenti = <_DipTaglie>[];
  final Map<String, int> _multiplier = <String, int>{
    'tshirt': 1,
    'pantalone': 1,
    'felpa': 1,
    'giacca': 1,
    'giacca_leggera': 1,
    'gilet': 1,
    'scarpe': 1,
    'guanti_pelle': 1,
    'guanti_tessuto': 1,
  };
  final Set<String> _selectedPersonaleIds = <String>{};
  String _stagione = 'estivo';
  bool _salvaDotazioni = true;
  final Map<String, Set<String>> _enabledItemsBySeason = <String, Set<String>>{};

  List<_DpiCatalogItem> get _assignmentCatalog =>
      VestiarioArticoliService.activeArticoli
          .where((a) => a.inAssegnazione)
          .map(
            (a) => _DpiCatalogItem(
              key: a.key,
              label: a.label,
              rows: a.excelRows,
              sizeLabel: a.sizeLabel,
            ),
          )
          .toList(growable: false);

  List<String> get _allItemsOrder => VestiarioArticoliService.activeArticoli
      .where((a) => a.inAssegnazione)
      .map((a) => a.key)
      .toList(growable: false);

  Map<String, List<String>> get _seasonItems => <String, List<String>>{
        'estivo': VestiarioCatalog.estivoDefaultAssegnazione,
        'invernale': VestiarioCatalog.invernaleDefaultAssegnazione,
      };

  static String _normalizeAssignmentItemKey(String key) {
    if (key == 'giubbino_estivo') return 'giacca_leggera';
    return key;
  }

  Set<String> _normalizedActiveForSeason(String season) {
    final active = _enabledItemsBySeason[season] ?? <String>{};
    return active.map(_normalizeAssignmentItemKey).toSet();
  }

  bool _isItemForSeason(String key, String season) {
    final normalized = _normalizeAssignmentItemKey(key);
    final def = VestiarioArticoliService.byKey(normalized);
    if (def == null) {
      if (season == 'estivo') return normalized != 'giacca';
      if (season == 'invernale') return normalized != 'giacca_leggera';
      return true;
    }
    if (season == 'estivo') return def.stagioneEstivo;
    if (season == 'invernale') return def.stagioneInvernale;
    return true;
  }

  void _ensureDefaultSummerItems() {
    if (_stagione != 'estivo') return;
    final active = _enabledItemsBySeason.putIfAbsent('estivo', () => <String>{});
    for (final key in _seasonItems['estivo'] ?? const <String>[]) {
      active.add(_normalizeAssignmentItemKey(key));
    }
    active.remove('giubbino_estivo');
    active.remove('giacca');
  }

  void _migrateLegacySeasonItems() {
    for (final items in _enabledItemsBySeason.values) {
      if (items.remove('giubbino_estivo')) {
        items.add('giacca_leggera');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _enabledItemsBySeason['estivo'] = {...?_seasonItems['estivo']};
    _enabledItemsBySeason['invernale'] = {...?_seasonItems['invernale']};
    _migrateLegacySeasonItems();
    _load();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await VestiarioArticoliService.refresh();
      for (final a
          in VestiarioArticoliService.activeArticoli.where((e) => e.inMagazzino)) {
        _multiplier.putIfAbsent(a.key, () => 1);
      }

      final personaleRes = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, email, active')
          .eq('active', true)
          .order('full_name');
      final taglieRes = await SupabaseService.client.from('personale_taglie').select(
          'personale_id, taglia_tshirt, taglia_pantalone, taglia_felpa, taglia_giacca, taglia_gilet, taglia_scarpe, taglia_guanti');

      try {
        final cfg = await SupabaseService.client
            .from('vestiario_fabbisogno_annuo_config')
            .select()
            .eq('id', 1)
            .maybeSingle();
        if (cfg != null) {
          for (final k in _multiplier.keys) {
            dynamic raw = cfg[k];
            if (k == 'guanti_pelle') {
              raw = cfg['guanti_pelle_invernale'] ?? cfg['guanti_invernale'] ?? cfg['guanti'] ?? raw;
            } else if (k == 'guanti_tessuto') {
              raw = cfg['guanti_tessuto_invernale'] ?? cfg['guanti_invernale'] ?? cfg['guanti'] ?? raw;
            } else if (k == 'giacca_leggera') {
              raw = cfg['giacca_leggera_estivo'] ?? cfg['giacca_estivo'] ?? raw;
            }
            final n = int.tryParse((raw ?? '1').toString()) ?? 1;
            _multiplier[k] = n < 1 ? 1 : n;
          }
        }
      } catch (_) {}

      final taglieByPid = <String, Map<String, String>>{};
      for (final row in (taglieRes as List)) {
        final r = Map<String, dynamic>.from(row as Map);
        final pid = (r['personale_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        taglieByPid[pid] = EmployeeTaglieExport.mapFromRow(r);
      }

      final out = <_DipTaglie>[];
      for (final row in (personaleRes as List)) {
        final r = Map<String, dynamic>.from(row as Map);
        final id = (r['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final taglie = taglieByPid[id] ?? const <String, String>{};
        out.add(
          _DipTaglie(
            id: id,
            fullName: (r['full_name'] ?? '').toString().trim(),
            email: (r['email'] ?? '').toString().trim(),
            taglie: taglie,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _dipendenti
          ..clear()
          ..addAll(out);
        if (_selectedPersonaleIds.isEmpty && _dipendenti.isNotEmpty) {
          _selectedPersonaleIds.add(_dipendenti.first.id);
        }
      });
    } catch (e) {
      _snack('Errore caricamento dati vestiario: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_DipTaglie> get _selectedList {
    if (_selectedPersonaleIds.isEmpty) return const <_DipTaglie>[];
    return _dipendenti
        .where((d) => _selectedPersonaleIds.contains(d.id))
        .toList(growable: false);
  }

  String _dipLabel(_DipTaglie d) =>
      d.fullName.isEmpty ? d.id : d.fullName;

  bool _dipMatchesFilter(_DipTaglie d, String filter) {
    final q = filter.trim().toLowerCase();
    if (q.isEmpty) return true;
    return d.fullName.toLowerCase().contains(q) || d.email.toLowerCase().contains(q);
  }

  Widget _dipendenteHybridFilter() {
    final selected = _selectedList;
    return DropdownSearch<_DipTaglie>.multiSelection(
      enabled: !_busy && _dipendenti.isNotEmpty,
      items: _dipendenti,
      selectedItems: selected,
      compareFn: (a, b) => a.id == b.id,
      itemAsString: _dipLabel,
      filterFn: _dipMatchesFilter,
      popupProps: PopupPropsMultiSelection.menu(
        showSearchBox: true,
        searchFieldProps: const TextFieldProps(
          decoration: InputDecoration(
            hintText: 'Cerca nome o email...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        showSelectedItems: true,
        constraints: BoxConstraints(maxHeight: kIsWeb ? 360 : 420),
      ),
      dropdownDecoratorProps: const DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(
          labelText: 'Dipendente',
          hintText: 'Cerca o seleziona...',
          border: OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(Icons.person_search_outlined),
        ),
      ),
      onChanged: (list) {
        setState(() {
          _selectedPersonaleIds
            ..clear()
            ..addAll(list.map((d) => d.id));
        });
      },
    );
  }

  List<_ItemPreview> _buildPreview(_DipTaglie d) {
    final items = _activeItemsForSeason(_stagione);
    return items.map((k) {
      final meta = _catalogByKey(k);
      final label = meta?.label ?? _itemLabel(k);
      final sizeLabel = meta?.sizeLabel ?? label;
      final size = (d.taglie[sizeLabel] ?? '').trim();
      final qty = _multiplier[k] ?? 1;
      return _ItemPreview(itemKey: k, label: label, size: size, qty: qty);
    }).toList();
  }

  _DpiCatalogItem? _catalogByKey(String key) {
    for (final item in _assignmentCatalog) {
      if (item.key == key) return item;
    }
    final def = VestiarioArticoliService.byKey(key);
    if (def == null || !def.inAssegnazione) return null;
    return _DpiCatalogItem(
      key: def.key,
      label: def.label,
      rows: def.excelRows,
      sizeLabel: def.sizeLabel,
    );
  }

  List<String> _activeItemsForSeason(String season) {
    final normalized = _normalizedActiveForSeason(season);
    return _allItemsOrder
        .where((k) => normalized.contains(_normalizeAssignmentItemKey(k)))
        .toList(growable: false);
  }

  List<String> _availableToAddForCurrentSeason() {
    final normalizedActive = _normalizedActiveForSeason(_stagione);
    return _allItemsOrder
        .where((k) {
          final normalized = _normalizeAssignmentItemKey(k);
          return !normalizedActive.contains(normalized) &&
              _isItemForSeason(k, _stagione);
        })
        .toList(growable: false);
  }

  void _incQty(String key) {
    final cur = _multiplier[key] ?? 1;
    setState(() => _multiplier[key] = cur + 1);
  }

  void _decQty(String key) {
    final cur = _multiplier[key] ?? 1;
    if (cur <= 1) return;
    setState(() => _multiplier[key] = cur - 1);
  }

  void _removeItemFromSeason(String key) {
    final normalized = _normalizeAssignmentItemKey(key);
    setState(() {
      final items =
          _enabledItemsBySeason.putIfAbsent(_stagione, () => <String>{});
      items.remove(key);
      items.remove(normalized);
      if (normalized == 'giacca_leggera') {
        items.remove('giubbino_estivo');
      }
    });
  }

  void _addItemToSeason(String key) {
    final normalized = _normalizeAssignmentItemKey(key);
    setState(() {
      final items =
          _enabledItemsBySeason.putIfAbsent(_stagione, () => <String>{});
      items.remove('giubbino_estivo');
      items.add(normalized);
      _multiplier[normalized] =
          (_multiplier[normalized] ?? 1) < 1 ? 1 : (_multiplier[normalized] ?? 1);
    });
  }

  Future<void> _generaModulo() async {
    final selected = _selectedList;
    if (selected.isEmpty) {
      _snack('Seleziona almeno un dipendente', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      int generatedCount = 0;
      int skippedNoSizeCount = 0;
      final scarichiInsufficienti = <String>[];

      final righeMagazzino = <({String articolo, String taglia, int quantita})>[];
      final dipendentiDaGenerare = <_DipTaglie>[];
      for (final dip in selected) {
        final preview = _buildPreview(dip);
        if (preview.every((p) => p.size.isEmpty)) {
          skippedNoSizeCount++;
          continue;
        }
        dipendentiDaGenerare.add(dip);
        for (final p in preview) {
          if (p.size.isEmpty || p.qty < 1) continue;
          if (VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione(p.itemKey) ==
              null) {
            continue;
          }
          righeMagazzino.add(
            (articolo: p.itemKey, taglia: p.size, quantita: p.qty),
          );
        }
      }

      if (dipendentiDaGenerare.isEmpty) {
        _snack(
          'Nessun modulo generato: nessun dipendente selezionato ha taglie compilate.',
          error: true,
        );
        return;
      }

      final verifica =
          await VestiarioMagazzinoService.verificaDisponibilita(righe: righeMagazzino);
      for (final s in verifica) {
        if (!s.insufficiente) continue;
        scarichiInsufficienti.add(
          '${VestiarioCatalog.label(s.articolo)} ${s.taglia} (richiesti ${s.richiesto}, residui ${s.residuo})',
        );
      }
      if (scarichiInsufficienti.isNotEmpty) {
        final previewMsg = scarichiInsufficienti.take(4).join('; ');
        final extra = scarichiInsufficienti.length > 4
            ? ' (+${scarichiInsufficienti.length - 4} altri)'
            : '';
        _snack(
          'Magazzino insufficiente. Aggiorna inventario vestiario prima di assegnare.\n'
          '$previewMsg$extra',
          error: true,
        );
        return;
      }

      for (final dip in dipendentiDaGenerare) {
        final preview = _buildPreview(dip);

        final payload = <String, String>{
          // Campi corretti nel template (no area logo/header).
          'I12': dip.fullName,
          'E53': italyTodayIsoDate(),
        };

        final rowByItem = <String, List<int>>{
          for (final c in _assignmentCatalog) c.key: c.rows,
        };
        // Pulizia completa blocco DPI nel template (righe 15–30).
        for (var row = 15; row <= 30; row++) {
          payload['Q$row'] = '';
          payload['R$row'] = '';
        }
        final selectedKeys = _activeItemsForSeason(_stagione).toSet();
        for (final e in rowByItem.entries) {
          final include = selectedKeys.contains(e.key);
          final qty = _multiplier[e.key] ?? 1;
          final meta = _catalogByKey(e.key);
          final sizeLabel = meta?.sizeLabel;
          final size = (sizeLabel == null || sizeLabel.isEmpty)
              ? ''
              : (dip.taglie[sizeLabel] ?? '').trim();
          for (final row in e.value) {
            payload['Q$row'] = include ? '$qty' : '';
            payload['R$row'] = include ? size : '';
          }
        }

        final bytes = await VestiarioDpieExcel.fill(payload);
        final stamp = DateTime.now();
        final stampStr =
            '${stamp.year.toString().padLeft(4, '0')}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}';
        final fileName =
            'modulo_vestiario_${_stagione}_${EmployeeTaglieExport.safeFilePart(dip.fullName)}_$stampStr.xlsx';

        if (!kIsWeb && Platform.isWindows) {
          final downloads = p.join(
            Platform.environment['USERPROFILE'] ?? Directory.current.path,
            'Downloads',
          );
          final outFile = File(p.join(downloads, fileName));
          await outFile.writeAsBytes(bytes, flush: true);
        } else {
          await FileSaver.instance.saveFile(
            name: fileName.replaceAll('.xlsx', ''),
            bytes: bytes,
            ext: 'xlsx',
            mimeType: MimeType.other,
          );
        }

        if (_salvaDotazioni) {
          final today = italyTodayIsoDate();
          for (final p in preview) {
            if (p.size.isEmpty || p.qty < 1) continue;
            await SupabaseService.client.from('vestiario_dotazioni').insert({
              'personale_id': dip.id,
              'categoria': p.label,
              'quantita_assegnata': p.qty,
              'taglia': p.size,
              'data_consegna': today,
            });
          }
        }

        // Scarico magazzino ad ogni assegnazione (modulo generato).
        await VestiarioMagazzinoService.scaricaAssegnazione(
          stagione: _stagione,
          righe: preview
              .where((p) => p.size.isNotEmpty && p.qty > 0)
              .where(
                (p) =>
                    VestiarioCatalog.magazzinoArticoloDaChiaveAssegnazione(
                      p.itemKey,
                    ) !=
                    null,
              )
              .map(
                (p) => (
                  articolo: p.itemKey,
                  taglia: p.size,
                  quantita: p.qty,
                ),
              ),
        );

        generatedCount++;
      }

      if (generatedCount == 0) {
        _snack(
          'Nessun modulo generato: nessun dipendente selezionato ha taglie compilate.',
          error: true,
        );
      } else if (skippedNoSizeCount > 0) {
        _snack(
          'Generati $generatedCount moduli (${_stagione.toUpperCase()}). '
          'Saltati $skippedNoSizeCount senza taglie.',
        );
      } else {
        _snack('Generati $generatedCount moduli (${_stagione.toUpperCase()}) con successo');
      }
    } catch (e) {
      _snack('Errore generazione modulo vestiario: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedList = _selectedList;
    final dip = selectedList.isEmpty ? null : selectedList.first;
    final preview = dip == null ? const <_ItemPreview>[] : _buildPreview(dip);
    final isMobileLayout = useMobileUi(context) || useCompactPageLayout(context);
    const pageTitle = 'Assegnazione Vestiario';
    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      classicUseTrainBackground: false,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(title: const Text(pageTitle))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isMobileLayout)
                    Column(
                      children: [
                        _dipendenteHybridFilter(),
                        const SizedBox(height: 10),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Stagione',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: SegmentedButton<String>(
                            segments: const <ButtonSegment<String>>[
                              ButtonSegment<String>(
                                value: 'estivo',
                                label: Text('Estivo'),
                                icon: Icon(Icons.wb_sunny_outlined),
                              ),
                              ButtonSegment<String>(
                                value: 'invernale',
                                label: Text('Invernale'),
                                icon: Icon(Icons.ac_unit),
                              ),
                            ],
                            selected: <String>{_stagione},
                            showSelectedIcon: false,
                            onSelectionChanged: _busy
                                ? null
                                : (values) {
                                    if (values.isEmpty) return;
                                    setState(() => _stagione = values.first);
                                  },
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _dipendenteHybridFilter(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Stagione',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: SegmentedButton<String>(
                              segments: const <ButtonSegment<String>>[
                                ButtonSegment<String>(
                                  value: 'estivo',
                                  label: Text('Estivo'),
                                  icon: Icon(Icons.wb_sunny_outlined),
                                ),
                                ButtonSegment<String>(
                                  value: 'invernale',
                                  label: Text('Invernale'),
                                  icon: Icon(Icons.ac_unit),
                                ),
                              ],
                              selected: <String>{_stagione},
                              showSelectedIcon: false,
                              onSelectionChanged: _busy
                                  ? null
                                  : (values) {
                                      if (values.isEmpty) return;
                                      setState(() => _stagione = values.first);
                                    },
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (dip != null)
                    Text(
                      selectedList.length == 1
                          ? 'Dipendente: ${dip.fullName} ${dip.email.isEmpty ? '' : '· ${dip.email}'}'
                          : 'Anteprima su: ${dip.fullName} · Totale selezionati: ${selectedList.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DPI selezionati (${_stagione.toUpperCase()})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final canAdd = _availableToAddForCurrentSeason();
                                    if (canAdd.isEmpty) {
                                      _snack(
                                        'Tutti i DPI previsti per questa stagione sono già in lista',
                                      );
                                      return;
                                    }
                                    final picked = await showModalBottomSheet<String>(
                                      context: context,
                                      builder: (ctx) => SafeArea(
                                        child: ListView(
                                          shrinkWrap: true,
                                          children: canAdd
                                              .map(
                                                (k) => ListTile(
                                                  leading: const Icon(
                                                    Icons.add_box_outlined,
                                                  ),
                                                  title: Text(_itemLabel(k)),
                                                  onTap: () => Navigator.pop(ctx, k),
                                                ),
                                              )
                                              .toList(growable: false),
                                        ),
                                      ),
                                    );
                                    if (picked == null || !mounted) return;
                                    _addItemToSeason(picked);
                                  },
                            icon: const Icon(Icons.add),
                            label: const Text('Aggiungi DPI'),
                          ),
                          if (_stagione == 'estivo' &&
                              !_normalizedActiveForSeason('estivo')
                                  .contains('giacca_leggera'))
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(_ensureDefaultSummerItems);
                                      _snack(
                                        'Ripristinata Giacca leggera nella lista estiva',
                                      );
                                    },
                              icon: const Icon(Icons.restore_outlined, size: 18),
                              label: const Text('Giacca leggera'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Card(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: preview.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final pItem = preview[i];
                          return ListTile(
                            dense: true,
                            title: Text(pItem.label),
                            subtitle: Text('Taglia: ${pItem.size.isEmpty ? '—' : pItem.size}'),
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                IconButton(
                                  tooltip: 'Diminuisci quantita',
                                  onPressed: _busy ? null : () => _decQty(pItem.itemKey),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Text('Q.ta: ${pItem.qty}'),
                                IconButton(
                                  tooltip: 'Aumenta quantita',
                                  onPressed: _busy ? null : () => _incQty(pItem.itemKey),
                                  icon: const Icon(Icons.add_circle_outline),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  tooltip: 'Rimuovi DPI',
                                  onPressed:
                                      _busy ? null : () => _removeItemFromSeason(pItem.itemKey),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    value: _salvaDotazioni,
                    onChanged: _busy ? null : (v) => setState(() => _salvaDotazioni = v),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Salva anche in storico assegnazioni'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _generaModulo,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.description_outlined),
                    label: Text(
                      _busy
                          ? 'Generazione...'
                          : 'Compilazione automatica modulo (${_stagione.toUpperCase()})',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DipTaglie {
  final String id;
  final String fullName;
  final String email;
  final Map<String, String> taglie;
  const _DipTaglie({
    required this.id,
    required this.fullName,
    required this.email,
    required this.taglie,
  });
}

class _ItemPreview {
  final String itemKey;
  final String label;
  final String size;
  final int qty;
  const _ItemPreview({
    required this.itemKey,
    required this.label,
    required this.size,
    required this.qty,
  });
}

class _DpiCatalogItem {
  final String key;
  final String label;
  final List<int> rows;
  final String? sizeLabel;
  const _DpiCatalogItem({
    required this.key,
    required this.label,
    required this.rows,
    this.sizeLabel,
  });
}

String _itemLabel(String key) {
  switch (key) {
    case 'tshirt':
      return 'T-shirt';
    case 'pantalone':
      return 'Pantalone';
    case 'felpa':
      return 'Felpa';
    case 'giacca_leggera':
      return 'Giacca leggera';
    case 'giacca':
      return 'Giacca';
    case 'gilet':
      return 'Gilet';
    case 'scarpe':
      return 'Scarpe';
    case 'guanti':
    case 'guanti_tessuto':
      return 'Guanti tessuto (nylon/poliuretano)';
    case 'occhiali':
      return 'Occhiale Paraschegge';
    case 'archetti':
      return 'Archetti Antirumore';
    case 'cuffie':
      return 'Cuffie Antirumore';
    case 'guanti_pelle':
      return 'Guanti pelle';
    case 'giubbino_estivo':
      return 'Giacca leggera';
    case 'borsa_dpi':
      return 'Borsa Porta DPI 48x50x35';
    case 'lampada_frontale':
      return 'Lampada Frontale';
    case 'completo_antipioggia':
      return 'Completo Antipioggia';
    case 'berretto_lana':
      return 'Berretto in Lana';
    default:
      return key;
  }
}

