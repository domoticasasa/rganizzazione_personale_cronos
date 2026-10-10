import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';

import '../services/dpi3c_excel.dart';
import '../services/dpi_categories_service.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/mobile_navigation.dart';
import '../utils/field_timestamps.dart';
import '../widgets/app_logo.dart';
import '../widgets/data_cell_audit_hover.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminDpiReportPage extends StatefulWidget {
  const AdminDpiReportPage({super.key});

  @override
  State<AdminDpiReportPage> createState() => _AdminDpiReportPageState();
}

class _AdminDpiReportPageState extends State<AdminDpiReportPage> {
  bool _loading = true;
  bool _isNfcWriting = false;
  String? _exportingModuloFor;
  String _search = '';
  String? _categoriaFilter;
  String _matricolaFilter = '';
  String _modelloFilter = '';
  bool _onlyWithDpi = true;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _matricolaCtrl = TextEditingController();
  final TextEditingController _modelloCtrl = TextEditingController();
  final List<String> _categorie = <String>[];
  List<_EmployeeDpiSummary> _all = <_EmployeeDpiSummary>[];
  final Map<String, String> _auditUserNamesByUuid = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _matricolaCtrl.dispose();
    _modelloCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final personaleRes = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, email, active, matricola')
          .eq('active', true)
          .order('full_name');

      final dpiRes = await SupabaseService.client
          .from('dpi_dotazioni')
          .select(
              'id, personale_id, categoria, quantita_assegnata, marca, '
              'data_produzione, data_consegna, data_revisione, matricola, modello, '
              'created_at, field_timestamps, updated_at')
          .order('categoria');

      final personaleRows = List<Map<String, dynamic>>.from(personaleRes as List);
      final dpiRows = List<Map<String, dynamic>>.from(dpiRes as List);

      final byPersonale = <String, List<Map<String, dynamic>>>{};
      for (final d in dpiRows) {
        final pid = (d['personale_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        byPersonale.putIfAbsent(pid, () => <Map<String, dynamic>>[]).add(d);
      }

      final categoriaSet = <String>{};
      final categories = await DpiCategoriesService.listCategories();
      final summaries = <_EmployeeDpiSummary>[];

      for (final p in personaleRows) {
        final id = (p['id_uuid'] ?? '').toString().trim();
        final name = (p['full_name'] ?? '').toString().trim();
        final email = (p['email'] ?? '').toString().trim();
        final matricola = (p['matricola'] ?? '').toString().trim();
        final rawList = byPersonale[id] ?? const <Map<String, dynamic>>[];
        final items = _latestByCategory(rawList.map(_DpiEntry.fromRow).toList())
          ..sort((a, b) => a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase()));

        for (final it in items) {
          if (it.categoria.isNotEmpty) categoriaSet.add(it.categoria);
        }

        summaries.add(
          _EmployeeDpiSummary(
            personaleId: id,
            fullName: name,
            email: email,
            matricola: matricola,
            dpi: items,
          ),
        );
      }

      summaries.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      final auditIds = <String>{};
      for (final d in dpiRows) {
        mergeFieldTimestampActorUuids(d, auditIds);
      }
      final auditNames = await loadUserNamesByUuid(auditIds);

      if (!mounted) return;
      setState(() {
        _auditUserNamesByUuid
          ..clear()
          ..addAll(auditNames);
        _all = summaries;
        _categorie
          ..clear()
          ..addAll(
            DpiCategoriesService.mergeUniqueCategoryNames(
              [
                ...categories,
                ...categoriaSet,
              ],
              seedDefaults: false,
            ),
          );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore caricamento report DPI: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_DpiEntry> _latestByCategory(List<_DpiEntry> all) {
    final latest = <String, _DpiEntry>{};
    for (final d in all) {
      final key = d.categoria.trim().toLowerCase();
      if (key.isEmpty) continue;
      final curr = latest[key];
      if (curr == null || d.createdAt.isAfter(curr.createdAt)) {
        latest[key] = d;
      }
    }
    return latest.values.toList();
  }

  List<_EmployeeDpiSummary> get _filtered {
    final q = _search.trim().toLowerCase();
    final matricolaQ = _matricolaFilter.trim().toLowerCase();
    final modelloQ = _modelloFilter.trim().toLowerCase();
    return _all.where((e) {
      if (_onlyWithDpi && e.dpi.isEmpty) return false;

      final byCategory = _categoriaFilter == null ||
          e.dpi.any((d) => d.categoria.toLowerCase() == _categoriaFilter!.toLowerCase());
      if (!byCategory) return false;

      if (matricolaQ.isNotEmpty &&
          !e.dpi.any((d) => d.matricola.toLowerCase().contains(matricolaQ))) {
        return false;
      }
      if (modelloQ.isNotEmpty &&
          !e.dpi.any((d) => d.modello.toLowerCase().contains(modelloQ))) {
        return false;
      }

      if (q.isEmpty) return true;

      final inName = e.fullName.toLowerCase().contains(q);
      final inEmail = e.email.toLowerCase().contains(q);
      final inDpi = e.dpi.any((d) =>
          d.categoria.toLowerCase().contains(q) ||
          d.marca.toLowerCase().contains(q) ||
          d.matricola.toLowerCase().contains(q) ||
          d.modello.toLowerCase().contains(q));

      return inName || inEmail || inDpi;
    }).toList();
  }

  String _dpiLabel(_DpiEntry d) {
    final q = d.quantitaAssegnata > 0 ? ' x${d.quantitaAssegnata}' : '';
    final m = d.marca.isEmpty ? '' : ' (${d.marca})';
    return '${d.categoria}$q$m';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  String _safeText(String value) => value.trim().isEmpty ? 'N/D' : value.trim();

  String _friendlyNfcError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('not available') || s.contains('nfc') && s.contains('disable')) {
      return 'NFC disattivato o non disponibile sul dispositivo.';
    }
    if (s.contains('read only')) return 'Tag NFC in sola lettura.';
    if (s.contains('size') || s.contains('too large') || s.contains('capacity')) {
      return 'Dati troppo lunghi per questo tag NFC.';
    }
    if (s.contains('ndef')) return 'Tag non compatibile con scrittura NDEF.';
    return 'Errore durante la scrittura NFC.';
  }

  String _fit(String value, int max) {
    final v = _safeText(value);
    return v.length <= max ? v : '${v.substring(0, max)}...';
  }

  String _buildDpiNfcPayloadFull({
    required String fullName,
    required _DpiEntry d,
  }) {
    return [
      'CRONOS - DATI DPI',
      'Nome: ${_safeText(fullName)}',
      'Categoria: ${_safeText(d.categoria)}',
      'Quantita assegnata: ${_safeText('${d.quantitaAssegnata}')}',
      'Marca: ${_safeText(d.marca)}',
      'Data produzione: ${_safeText(_toDdMmYyyy(d.dataProduzione))}',
      'Data consegna: ${_safeText(_toDdMmYyyy(d.dataConsegna))}',
      'Data revisione: ${_safeText(_toDdMmYyyy(d.dataRevisione))}',
      'Matricola: ${_safeText(d.matricola)}',
      'Modello: ${_safeText(d.modello)}',
    ].join('\n');
  }

  String _buildDpiNfcPayloadCompact({
    required String fullName,
    required _DpiEntry d,
  }) {
    return [
      'CRONOS DPI',
      'N:${_fit(fullName, 22)}',
      'C:${_fit(d.categoria, 14)}',
      'Q:${_fit('${d.quantitaAssegnata}', 4)}',
      'Ma:${_fit(d.marca, 14)}',
      'Dt:${_fit(_toDdMmYyyy(d.dataProduzione), 10)}',
      'Dc:${_fit(_toDdMmYyyy(d.dataConsegna), 10)}',
      'Dr:${_fit(_toDdMmYyyy(d.dataRevisione), 10)}',
      'Mt:${_fit(d.matricola, 14)}',
      'Mo:${_fit(d.modello, 14)}',
    ].join('\n');
  }

  NdefRecord _createTextRecord(String text, {String languageCode = 'it'}) {
    final langBytes = utf8.encode(languageCode);
    final textBytes = utf8.encode(text);
    final payload = Uint8List(1 + langBytes.length + textBytes.length)
      ..[0] = langBytes.length
      ..setRange(1, 1 + langBytes.length, langBytes)
      ..setRange(1 + langBytes.length, 1 + langBytes.length + textBytes.length, textBytes);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList(utf8.encode('T')),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  Future<void> _writeDpiToNfc({
    required String fullName,
    required _DpiEntry d,
  }) async {
    if (_isNfcWriting) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _snack('Scrittura NFC disponibile solo su Android.', error: true);
      return;
    }
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      _snack('NFC non disponibile su questo dispositivo.', error: true);
      return;
    }

    setState(() => _isNfcWriting = true);
    _snack('Modalita scrittura attiva: avvicina il tag NFC...');
    var handled = false;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        noPlatformSoundsAndroid: true,
        onDiscovered: (NfcTag tag) async {
          if (handled) return;
          handled = true;
          try {
            var message = NdefMessage(
              records: [
                _createTextRecord(_buildDpiNfcPayloadFull(fullName: fullName, d: d)),
              ],
            );
            final ndef = NdefAndroid.from(tag);
            if (ndef != null) {
              if (!ndef.isWritable) throw Exception('Tag in sola lettura.');
              if (message.byteLength > ndef.maxSize) {
                message = NdefMessage(
                  records: [
                    _createTextRecord(_buildDpiNfcPayloadCompact(fullName: fullName, d: d)),
                  ],
                );
                if (message.byteLength > ndef.maxSize) {
                  throw Exception('Payload too large for this tag (${message.byteLength}/${ndef.maxSize}).');
                }
              }
              await ndef.writeNdefMessage(message);
            } else {
              final formatable = NdefFormatableAndroid.from(tag);
              if (formatable == null) {
                throw Exception('Tag non compatibile con scrittura NDEF.');
              }
              await formatable.format(message);
            }
            await NfcManager.instance.stopSession(alertMessageIos: 'Dati DPI scritti con successo.');
            _snack('Scrittura NFC completata.');
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessageIos: _friendlyNfcError(e));
            _snack(_friendlyNfcError(e), error: true);
          } finally {
            if (mounted) setState(() => _isNfcWriting = false);
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isNfcWriting = false);
      _snack(_friendlyNfcError(e), error: true);
    }
  }

  String _toDdMmYyyy(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    final iso = parseFlexibleDateToIsoDate(v);
    if (iso != null) {
      final p = iso.split('-');
      if (p.length == 3) {
        return '${p[2]}-${p[1]}-${p[0]}';
      }
    }
    return v;
  }

  String? _saveDpiFreeDate(String raw) => normalizeDpiOptionalDateField(raw, null);

  String? _saveDpiConsegnaDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return parseFlexibleDateToIsoDate(t);
  }

  Future<void> _openEditDpiDialog({
    required _EmployeeDpiSummary employee,
    _DpiEntry? current,
  }) async {
    final fromAdmin = await DpiCategoriesService.listCategories();
    if (!mounted) return;
    final categories = List<String>.from(fromAdmin);
    final curRaw = (current?.categoria ?? '').trim();
    if (curRaw.isNotEmpty &&
        !categories.any((c) => c.toLowerCase() == curRaw.toLowerCase())) {
      categories.add(curRaw);
      categories.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    }
    if (categories.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nessuna categoria attiva. Vai in Impostazioni → Categorie DPI e crea o abilita le categorie.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    String categoria = categories.first;
    if (curRaw.isNotEmpty) {
      for (final c in categories) {
        if (c.toLowerCase() == curRaw.toLowerCase()) {
          categoria = c;
          break;
        }
      }
    }
    final qCtrl = TextEditingController(
      text: (current?.quantitaAssegnata ?? 1).toString(),
    );
    final marcaCtrl = TextEditingController(text: current?.marca ?? '');
    final modelloCtrl = TextEditingController(text: current?.modello ?? '');
    final matricolaCtrl = TextEditingController(text: current?.matricola ?? '');
    final dataProdCtrl = TextEditingController(
      text: _toDdMmYyyy(current?.dataProduzione ?? ''),
    );
    final dataConsegnaCtrl = TextEditingController(
      text: _toDdMmYyyy(current?.dataConsegna ?? ''),
    );
    final dataRevisioneCtrl = TextEditingController(
      text: _toDdMmYyyy(current?.dataRevisione ?? ''),
    );

    Future<void> pickDateFor(TextEditingController ctrl) async {
      DateTime initialDate = DateTime.now();
      final currentIso = parseFlexibleDateToIsoDate(ctrl.text);
      if (currentIso != null) {
        final parsed = DateTime.tryParse(currentIso);
        if (parsed != null) initialDate = parsed;
      }
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      ctrl.text = formatDateDdMmYyyyFromDate(picked).replaceAll('/', '-');
    }

    Widget dpiDateField({
      required TextEditingController ctrl,
      required String label,
      required bool freeText,
    }) {
      return TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          helperText: freeText
              ? 'Libero: DD-MM-YYYY, MM/YYYY, anno…'
              : 'DD-MM-YYYY o calendario',
          suffixIcon: IconButton(
            tooltip: 'Seleziona data',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => pickDateFor(ctrl),
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(current == null ? 'Nuovo DPI' : 'Modifica DPI'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: categoria,
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setSt(() => categoria = v ?? categoria),
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final ctrl = TextEditingController();
                        final addOk = await showDialog<bool>(
                          context: ctx,
                          builder: (ctx2) => AlertDialog(
                            title: const Text('Nuova categoria DPI'),
                            content: TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome categoria',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx2, false),
                                child: const Text('Annulla'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx2, true),
                                child: const Text('Aggiungi'),
                              ),
                            ],
                          ),
                        );
                        if (addOk == true && ctrl.text.trim().isNotEmpty) {
                          try {
                            await DpiCategoriesService.addCategory(ctrl.text);
                            final newName = ctrl.text.trim();
                            if (!categories.any((c) => c.toLowerCase() == newName.toLowerCase())) {
                              categories.add(newName);
                              categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            }
                            setSt(() => categoria = newName);
                            await _load();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Errore creazione categoria: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Nuova categoria'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantita',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: marcaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Marca',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: modelloCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Modello',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: matricolaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Matricola',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  dpiDateField(
                    ctrl: dataProdCtrl,
                    label: 'Data produzione',
                    freeText: true,
                  ),
                  const SizedBox(height: 10),
                  dpiDateField(
                    ctrl: dataConsegnaCtrl,
                    label: 'Data consegna',
                    freeText: false,
                  ),
                  const SizedBox(height: 10),
                  dpiDateField(
                    ctrl: dataRevisioneCtrl,
                    label: 'Data revisione',
                    freeText: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final quantita = int.tryParse(qCtrl.text.trim());
    final dataProd = _saveDpiFreeDate(dataProdCtrl.text);
    final dataConsegna = _saveDpiConsegnaDate(dataConsegnaCtrl.text);
    final dataRevisione = _saveDpiFreeDate(dataRevisioneCtrl.text);
    if (quantita == null || quantita < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantita non valida'), backgroundColor: Colors.red),
      );
      return;
    }
    if (dataConsegnaCtrl.text.trim().isNotEmpty && dataConsegna == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data consegna non valida (usa DD-MM-YYYY o calendario)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final payload = {
        'personale_id': employee.personaleId,
        'categoria': categoria,
        'quantita_assegnata': quantita,
        'marca': marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
        'modello': modelloCtrl.text.trim().isEmpty ? null : modelloCtrl.text.trim(),
        'matricola': matricolaCtrl.text.trim().isEmpty ? null : matricolaCtrl.text.trim(),
        'data_produzione': dataProd,
        'data_consegna': dataConsegna,
        'data_revisione': dataRevisione,
      };
      if (current == null) {
        await SupabaseService.client.from('dpi_dotazioni').insert(payload);
      } else {
        await SupabaseService.client.from('dpi_dotazioni').update(payload).eq('id', current.id);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio DPI: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteDpi(_DpiEntry d) async {
    try {
      await SupabaseService.client.from('dpi_dotazioni').delete().eq('id', d.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore eliminazione DPI: $e'), backgroundColor: Colors.red),
      );
    }
  }

  _DpiTotals _computeTotals(List<_EmployeeDpiSummary> rows) {
    final byCategory = <String, int>{};
    int totalDotazioni = 0;
    int totalQuantita = 0;
    int dipConDpi = 0;
    for (final e in rows) {
      if (e.dpi.isNotEmpty) dipConDpi++;
      for (final d in e.dpi) {
        totalDotazioni++;
        totalQuantita += d.quantitaAssegnata;
        final key = d.categoria.trim().isEmpty ? 'Senza categoria' : d.categoria.trim();
        byCategory[key] = (byCategory[key] ?? 0) + d.quantitaAssegnata;
      }
    }
    final catSorted = byCategory.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return _DpiTotals(
      dipendentiTotali: rows.length,
      dipendentiConDpi: dipConDpi,
      dotazioniTotali: totalDotazioni,
      quantitaTotale: totalQuantita,
      quantitaPerCategoria: catSorted,
    );
  }

  List<_DpiEntry> _visibleDpiFor(_EmployeeDpiSummary e) {
    if (_categoriaFilter == null) return e.dpi;
    return e.dpi
        .where((d) =>
            d.categoria.toLowerCase() == _categoriaFilter!.toLowerCase())
        .toList();
  }

  Widget _summaryCard(_DpiTotals totals) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Riepilogo totale',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Dipendenti: ${totals.dipendentiTotali}')),
                Chip(label: Text('Con DPI: ${totals.dipendentiConDpi}')),
                Chip(label: Text('Dotazioni: ${totals.dotazioniTotali}')),
                Chip(label: Text('Quantità totale: ${totals.quantitaTotale}')),
              ],
            ),
            if (totals.quantitaPerCategoria.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: totals.quantitaPerCategoria
                    .map((e) => Chip(label: Text('${e.key}: ${e.value}')))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mobileDpiBlock(_EmployeeDpiSummary employee, _DpiEntry d) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            d.categoria,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Qtà ${d.quantitaAssegnata} · Marca ${d.marca.isEmpty ? '—' : d.marca}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Matricola ${d.matricola.isEmpty ? '—' : d.matricola} · Modello ${d.modello.isEmpty ? '—' : d.modello}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Prod. ${_toDdMmYyyy(d.dataProduzione).isEmpty ? '—' : _toDdMmYyyy(d.dataProduzione)} · Cons. ${_toDdMmYyyy(d.dataConsegna).isEmpty ? '—' : _toDdMmYyyy(d.dataConsegna)} · Rev. ${_toDdMmYyyy(d.dataRevisione).isEmpty ? '—' : _toDdMmYyyy(d.dataRevisione)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isNfcWriting
                ? null
                : () => _writeDpiToNfc(fullName: employee.fullName, d: d),
            icon: const Icon(Icons.nfc_rounded, size: 26),
            label: const Text('Scrivi su tag NFC'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openEditDpiDialog(employee: employee, current: d),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('Modifica'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => _deleteDpi(d),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Elimina',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBody(List<_EmployeeDpiSummary> rows, _DpiTotals totals) {
    final cs = Theme.of(context).colorScheme;
    final nfcHint = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Center(
                child: AppLogo(size: 56),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (nfcHint)
                    Material(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.touch_app_rounded, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Scegli la dotazione sotto e tocca «Scrivi su tag NFC», poi avvicina il telefono al tag.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Material(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'La scrittura NFC è disponibile solo su Android con NFC attivo.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Cerca dipendente o DPI…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoriaFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoria DPI',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tutte le categorie'),
                      ),
                      ..._categorie.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoriaFilter = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _matricolaCtrl,
                    onChanged: (v) => setState(() => _matricolaFilter = v),
                    decoration: InputDecoration(
                      hintText: 'Filtra per matricola…',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: _matricolaFilter.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _matricolaCtrl.clear();
                                setState(() => _matricolaFilter = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelloCtrl,
                    onChanged: (v) => setState(() => _modelloFilter = v),
                    decoration: InputDecoration(
                      hintText: 'Filtra per modello…',
                      prefixIcon: const Icon(Icons.category_outlined),
                      suffixIcon: _modelloFilter.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _modelloCtrl.clear();
                                setState(() => _modelloFilter = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo dipendenti con DPI'),
                    value: _onlyWithDpi,
                    onChanged: (v) => setState(() => _onlyWithDpi = v),
                  ),
                  const SizedBox(height: 8),
                  _summaryCard(totals),
                  const SizedBox(height: 12),
                  Text(
                    'Risultati: ${rows.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Nessun risultato')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final e = rows[i];
                    final visibleDpi = _visibleDpiFor(e);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                e.fullName.isEmpty ? '(senza nome)' : e.fullName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (e.email.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  e.email,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (visibleDpi.isEmpty)
                                const Text('Nessun DPI assegnato')
                              else
                                ...visibleDpi.map(
                                  (d) => _mobileDpiBlock(e, d),
                                ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openEditDpiDialog(employee: e),
                                icon: const Icon(Icons.add),
                                label: const Text('Aggiungi DPI'),
                              ),
                              if (visibleDpi.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _exportModuloButton(e, fullWidth: true),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: rows.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopBody(List<_EmployeeDpiSummary> rows, _DpiTotals totals) {
    return PageWithTopLogo(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Cerca dipendente o DPI...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _categoriaFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Filtro categoria DPI',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Tutte le categorie',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._categorie.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoriaFilter = v),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _matricolaCtrl,
                    onChanged: (v) => setState(() => _matricolaFilter = v),
                    decoration: InputDecoration(
                      hintText: 'Filtro matricola...',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: _matricolaFilter.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _matricolaCtrl.clear();
                                setState(() => _matricolaFilter = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _modelloCtrl,
                    onChanged: (v) => setState(() => _modelloFilter = v),
                    decoration: InputDecoration(
                      hintText: 'Filtro modello...',
                      prefixIcon: const Icon(Icons.category_outlined),
                      suffixIcon: _modelloFilter.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _modelloCtrl.clear();
                                setState(() => _modelloFilter = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo dipendenti con DPI'),
                    value: _onlyWithDpi,
                    onChanged: (v) => setState(() => _onlyWithDpi = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _summaryCard(totals),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Risultati: ${rows.length}'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Nessun risultato'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = rows[i];
                        final visibleDpi = _visibleDpiFor(e);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.fullName.isEmpty ? '(senza nome)' : e.fullName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (e.email.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(e.email),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: visibleDpi.isEmpty
                                      ? const [
                                          Chip(label: Text('Nessun DPI assegnato'))
                                        ]
                                      : visibleDpi
                                          .map((d) =>
                                              Chip(label: Text(_dpiLabel(d))))
                                          .toList(),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _openEditDpiDialog(employee: e),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Nuovo DPI'),
                                    ),
                                    _exportModuloButton(e),
                                  ],
                                ),
                                if (visibleDpi.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      columnSpacing: 16,
                                      headingRowHeight: 34,
                                      dataRowMinHeight: 32,
                                      dataRowMaxHeight: 38,
                                      columns: const [
                                        DataColumn(label: Text('Categoria')),
                                        DataColumn(label: Text('Qta')),
                                        DataColumn(label: Text('Marca')),
                                        DataColumn(label: Text('Modello')),
                                        DataColumn(label: Text('Matricola')),
                                        DataColumn(label: Text('Data prod.')),
                                        DataColumn(label: Text('Data consegna')),
                                        DataColumn(label: Text('Data revisione')),
                                        DataColumn(label: Text('Azioni')),
                                      ],
                                      rows: visibleDpi
                                          .map(
                                            (d) => DataRow(
                                              cells: [
                                                _dpiAuditCell(
                                                  Text(d.categoria),
                                                  d.sourceRow,
                                                  'categoria',
                                                ),
                                                _dpiAuditCell(
                                                  Text('${d.quantitaAssegnata}'),
                                                  d.sourceRow,
                                                  'quantita_assegnata',
                                                ),
                                                _dpiAuditCell(
                                                  Text(d.marca),
                                                  d.sourceRow,
                                                  'marca',
                                                ),
                                                _dpiAuditCell(
                                                  Text(d.modello),
                                                  d.sourceRow,
                                                  'modello',
                                                ),
                                                _dpiAuditCell(
                                                  Text(d.matricola),
                                                  d.sourceRow,
                                                  'matricola',
                                                ),
                                                _dpiAuditCell(
                                                  Text(_toDdMmYyyy(
                                                      d.dataProduzione)),
                                                  d.sourceRow,
                                                  'data_produzione',
                                                ),
                                                _dpiAuditCell(
                                                  Text(_toDdMmYyyy(
                                                      d.dataConsegna)),
                                                  d.sourceRow,
                                                  'data_consegna',
                                                ),
                                                _dpiAuditCell(
                                                  Text(_toDdMmYyyy(
                                                      d.dataRevisione)),
                                                  d.sourceRow,
                                                  'data_revisione',
                                                ),
                                                DataCell(
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        tooltip: 'Scrivi su NFC',
                                                        visualDensity:
                                                            VisualDensity.compact,
                                                        onPressed: () =>
                                                            _writeDpiToNfc(
                                                          fullName: e.fullName,
                                                          d: d,
                                                        ),
                                                        icon: const Icon(
                                                            Icons.nfc,
                                                            size: 18),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Modifica',
                                                        visualDensity:
                                                            VisualDensity.compact,
                                                        onPressed: () =>
                                                            _openEditDpiDialog(
                                                          employee: e,
                                                          current: d,
                                                        ),
                                                        icon: const Icon(
                                                            Icons.edit,
                                                            size: 18),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Elimina',
                                                        visualDensity:
                                                            VisualDensity.compact,
                                                        onPressed: () =>
                                                            _deleteDpi(d),
                                                        icon: const Icon(
                                                          Icons.delete,
                                                          size: 18,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _dataConsegnaModulo(List<_DpiEntry> dpi) {
    for (final d in dpi) {
      final fmt = _toDdMmYyyy(d.dataConsegna);
      if (fmt.isNotEmpty) return fmt;
    }
    return formatDateDdMmYyyyFromDate(DateTime.now());
  }

  String _safeFileStem(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> _exportModuloDpi3c(_EmployeeDpiSummary employee) async {
    final visibleDpi = _visibleDpiFor(employee);
    if (visibleDpi.isEmpty) {
      _snack('Nessun DPI da esportare per questo dipendente.', error: true);
      return;
    }

    setState(() => _exportingModuloFor = employee.personaleId);
    try {
      final dotazioni = visibleDpi.map(
        (d) => (
          categoria: d.categoria,
          riga: Dpi3cModuloRiga(
            quantita: d.quantitaAssegnata,
            marca: d.marca,
            produzione: _toDdMmYyyy(d.dataProduzione),
            matricola: d.matricola,
            modello: d.modello,
          ),
        ),
      );
      final payload = Dpi3cExcel.buildPayloadFromDpi(
        dipendente: employee.fullName,
        matricolaDipendente: employee.matricola,
        dataConsegna: _dataConsegnaModulo(visibleDpi),
        dotazioni: dotazioni,
      );
      final bytes = await Dpi3cExcel.fill(payload);
      final stem = _safeFileStem(
        employee.fullName.isEmpty ? 'dipendente' : employee.fullName,
      );
      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: 'modulo_dpi3c_$stem',
        bytes: bytes,
        openFile: true,
      );
      if (ok) {
        _snack('Modulo DPI III generato per ${employee.fullName}.');
      }
    } catch (e) {
      _snack('Errore export modulo: $e', error: true);
    } finally {
      if (mounted) setState(() => _exportingModuloFor = null);
    }
  }

  Widget _exportModuloButton(_EmployeeDpiSummary employee, {bool fullWidth = false}) {
    final visibleDpi = _visibleDpiFor(employee);
    if (visibleDpi.isEmpty) return const SizedBox.shrink();

    final exporting = _exportingModuloFor == employee.personaleId;
    final button = FilledButton.tonalIcon(
      onPressed: exporting ? null : () => _exportModuloDpi3c(employee),
      icon: exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      label: const Text('Esporta modulo Excel'),
    );
    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }

  Future<void> _exportReportExcel(List<_EmployeeDpiSummary> rows) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report DPI'];
    sheet.appendRow(const <String>[
      'Dipendente',
      'Email',
      'Categoria',
      'Qta',
      'Marca',
      'Modello',
      'Matricola',
      'Data produzione',
      'Data consegna',
      'Data revisione',
    ]);

    var count = 0;
    for (final e in rows) {
      final visibleDpi = _visibleDpiFor(e);
      if (visibleDpi.isEmpty) continue;
      for (final d in visibleDpi) {
        count++;
        sheet.appendRow(<Object?>[
          e.fullName,
          e.email,
          d.categoria,
          d.quantitaAssegnata,
          d.marca,
          d.modello,
          d.matricola,
          _toDdMmYyyy(d.dataProduzione),
          _toDdMmYyyy(d.dataConsegna),
          _toDdMmYyyy(d.dataRevisione),
        ]);
      }
    }

    if (count == 0) {
      _snack('Nessun dato da esportare.', error: true);
      return;
    }

    final bytes = excel.encode();
    if (bytes == null || bytes.isEmpty) {
      _snack('Impossibile generare il file Excel.', error: true);
      return;
    }

    final ok = await ExcelExportHelper.saveAndReveal(
      pageName: 'Report_DPI_III_categoria',
      bytes: Uint8List.fromList(bytes),
      extension: 'xlsx',
      openFile: true,
    );
    _snack(ok ? 'Export Excel completato.' : 'Export annullato.');
  }

  @override
  Widget build(BuildContext context) {
    final mobile = useMobileUi(context);
    final rows = _filtered;
    final totals = _computeTotals(rows);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: mobile
            ? const Text('Report DPI — III categoria')
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogo(size: 44),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Impostazioni App — Report DPI',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            icon: const Icon(Icons.download_outlined),
            onPressed: _loading ? null : () => _exportReportExcel(rows),
          ),
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : mobile
              ? _buildMobileBody(rows, totals)
              : _buildDesktopBody(rows, totals),
    );
  }

  DataCell _dpiAuditCell(
    Widget child,
    Map<String, dynamic> row,
    String fieldKey,
  ) {
    return decorateDataCellWithAuditHover(
      DataCell(child),
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: _auditUserNamesByUuid,
      rowAuditWhenFieldMissing: false,
    );
  }
}

class _EmployeeDpiSummary {
  final String personaleId;
  final String fullName;
  final String email;
  final String matricola;
  final List<_DpiEntry> dpi;

  const _EmployeeDpiSummary({
    required this.personaleId,
    required this.fullName,
    required this.email,
    required this.matricola,
    required this.dpi,
  });
}

class _DpiEntry {
  final String id;
  final String categoria;
  final int quantitaAssegnata;
  final String marca;
  final String dataProduzione;
  final String dataConsegna;
  final String dataRevisione;
  final String matricola;
  final String modello;
  final DateTime createdAt;
  final Map<String, dynamic> sourceRow;

  const _DpiEntry({
    required this.id,
    required this.categoria,
    required this.quantitaAssegnata,
    required this.marca,
    required this.dataProduzione,
    required this.dataConsegna,
    required this.dataRevisione,
    required this.matricola,
    required this.modello,
    required this.createdAt,
    required this.sourceRow,
  });

  factory _DpiEntry.fromRow(Map<String, dynamic> r) => _DpiEntry(
        id: (r['id'] ?? '').toString(),
        categoria: (r['categoria'] ?? '').toString(),
        quantitaAssegnata: (r['quantita_assegnata'] is int)
            ? (r['quantita_assegnata'] as int)
            : int.tryParse((r['quantita_assegnata'] ?? '0').toString()) ?? 0,
        marca: (r['marca'] ?? '').toString(),
        dataProduzione: (r['data_produzione'] ?? '').toString(),
        dataConsegna: (r['data_consegna'] ?? '').toString(),
        dataRevisione: (r['data_revisione'] ?? '').toString(),
        matricola: (r['matricola'] ?? '').toString(),
        modello: (r['modello'] ?? '').toString(),
        createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sourceRow: r,
      );
}

class _DpiTotals {
  final int dipendentiTotali;
  final int dipendentiConDpi;
  final int dotazioniTotali;
  final int quantitaTotale;
  final List<MapEntry<String, int>> quantitaPerCategoria;

  const _DpiTotals({
    required this.dipendentiTotali,
    required this.dipendentiConDpi,
    required this.dotazioniTotali,
    required this.quantitaTotale,
    required this.quantitaPerCategoria,
  });
}

