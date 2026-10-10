import 'dart:io';
import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_dpi_report_page.dart';
import '../services/confirm_sound_service.dart';
import '../services/dpi3c_excel.dart';
import '../services/supabase_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/excel_template_assets.dart';
import '../utils/date_formatters.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminDpiTerzaCategoriaPage extends StatefulWidget {
  const AdminDpiTerzaCategoriaPage({super.key});

  @override
  State<AdminDpiTerzaCategoriaPage> createState() =>
      _AdminDpiTerzaCategoriaPageState();
}

class _AdminDpiTerzaCategoriaPageState extends State<AdminDpiTerzaCategoriaPage> {
  bool _loading = true;
  bool _saving = false;
  bool _loadingDpi = false;
  bool _exporting = false;
  List<Map<String, dynamic>> _personale = <Map<String, dynamic>>[];
  String? _personaleId;
  final _dipendenteSearchCtrl = TextEditingController();

  final _matricolaDipCtrl = TextEditingController();
  DateTime _dataConsegna = DateTime.now();

  final _elmQtyCtrl = TextEditingController();
  final _elmMarcaCtrl = TextEditingController();
  final _elmProdCtrl = TextEditingController();
  final _elmMatCtrl = TextEditingController();
  final _elmModCtrl = TextEditingController();
  final _elmFornCtrl = TextEditingController();
  final _elmRevCtrl = TextEditingController();

  final _imbQtyCtrl = TextEditingController();
  final _imbMarcaCtrl = TextEditingController();
  final _imbProdCtrl = TextEditingController();
  final _imbMatCtrl = TextEditingController();
  final _imbModCtrl = TextEditingController();
  final _imbFornCtrl = TextEditingController();
  final _imbRevCtrl = TextEditingController();

  final _cordSingQtyCtrl = TextEditingController();
  final _cordSingMarcaCtrl = TextEditingController();
  final _cordSingProdCtrl = TextEditingController();
  final _cordSingMatCtrl = TextEditingController();
  final _cordSingModCtrl = TextEditingController();
  final _cordSingFornCtrl = TextEditingController();
  final _cordSingRevCtrl = TextEditingController();

  final _cordPosQtyCtrl = TextEditingController();
  final _cordPosMarcaCtrl = TextEditingController();
  final _cordPosProdCtrl = TextEditingController();
  final _cordPosMatCtrl = TextEditingController();
  final _cordPosModCtrl = TextEditingController();
  final _cordPosFornCtrl = TextEditingController();
  final _cordPosRevCtrl = TextEditingController();

  final _cordYQtyCtrl = TextEditingController();
  final _cordYMarcaCtrl = TextEditingController();
  final _cordYProdCtrl = TextEditingController();
  final _cordYMatCtrl = TextEditingController();
  final _cordYModCtrl = TextEditingController();
  final _cordYFornCtrl = TextEditingController();
  final _cordYRevCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _dipendenteSearchCtrl.dispose();
    _matricolaDipCtrl.dispose();
    _elmQtyCtrl.dispose();
    _elmMarcaCtrl.dispose();
    _elmProdCtrl.dispose();
    _elmMatCtrl.dispose();
    _elmModCtrl.dispose();
    _elmFornCtrl.dispose();
    _elmRevCtrl.dispose();
    _imbQtyCtrl.dispose();
    _imbMarcaCtrl.dispose();
    _imbProdCtrl.dispose();
    _imbMatCtrl.dispose();
    _imbModCtrl.dispose();
    _imbFornCtrl.dispose();
    _imbRevCtrl.dispose();
    _cordSingQtyCtrl.dispose();
    _cordSingMarcaCtrl.dispose();
    _cordSingProdCtrl.dispose();
    _cordSingMatCtrl.dispose();
    _cordSingModCtrl.dispose();
    _cordSingFornCtrl.dispose();
    _cordSingRevCtrl.dispose();
    _cordPosQtyCtrl.dispose();
    _cordPosMarcaCtrl.dispose();
    _cordPosProdCtrl.dispose();
    _cordPosMatCtrl.dispose();
    _cordPosModCtrl.dispose();
    _cordPosFornCtrl.dispose();
    _cordPosRevCtrl.dispose();
    _cordYQtyCtrl.dispose();
    _cordYMarcaCtrl.dispose();
    _cordYProdCtrl.dispose();
    _cordYMatCtrl.dispose();
    _cordYModCtrl.dispose();
    _cordYFornCtrl.dispose();
    _cordYRevCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, active, matricola')
          .eq('active', true)
          .order('full_name');
      final rows = List<Map<String, dynamic>>.from(res as List)
        ..sort((a, b) => (a['full_name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['full_name'] ?? '').toString().toLowerCase()));
      if (!mounted) return;
      setState(() {
        _personale = rows;
        if (_personale.isNotEmpty) {
          _personaleId = (_personale.first['id_uuid'] ?? '').toString();
          _dipendenteSearchCtrl.text = _selectedName;
          _syncMatricolaDipendente();
        }
      });
    } catch (e) {
      _snack('Errore caricamento personale: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _selectedName {
    final row = _personale.firstWhere(
      (e) => (e['id_uuid'] ?? '').toString() == (_personaleId ?? ''),
      orElse: () => <String, dynamic>{},
    );
    return (row['full_name'] ?? '').toString();
  }

  Map<String, dynamic>? _personaleRowById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in _personale) {
      if ((p['id_uuid'] ?? '').toString() == id) return p;
    }
    return null;
  }

  void _syncMatricolaDipendente() {
    final row = _personaleRowById(_personaleId);
    _matricolaDipCtrl.text =
        row == null ? '' : (row['matricola'] ?? '').toString().trim();
  }

  Iterable<Map<String, dynamic>> _dipendentiFiltrati(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _personale;
    return _personale.where((p) {
      final name = (p['full_name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    });
  }

  void _selezionaDipendente(Map<String, dynamic> p) {
    setState(() {
      _personaleId = (p['id_uuid'] ?? '').toString();
      _dipendenteSearchCtrl.text = (p['full_name'] ?? '').toString();
      _syncMatricolaDipendente();
    });
  }

  void _azzeraDipendente(TextEditingController fieldCtrl) {
    setState(() {
      _personaleId = null;
      _dipendenteSearchCtrl.clear();
      fieldCtrl.clear();
      _matricolaDipCtrl.clear();
    });
  }

  Widget _dipendenteAutocompleteField() {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: _dipendenteSearchCtrl.text),
      optionsBuilder: (textEditingValue) => _dipendentiFiltrati(textEditingValue.text),
      displayStringForOption: (p) => (p['full_name'] ?? '').toString(),
      onSelected: _selezionaDipendente,
      fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
        if (textCtrl.text != _dipendenteSearchCtrl.text) {
          textCtrl.text = _dipendenteSearchCtrl.text;
        }
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Dipendente',
            hintText: 'Scrivi nome e cognome…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: textCtrl.text.trim().isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    tooltip: 'Azzera selezione',
                    icon: const Icon(Icons.clear),
                    onPressed: () => _azzeraDipendente(textCtrl),
                  ),
          ),
          onChanged: (value) {
            _dipendenteSearchCtrl.text = value;
            final exact = _personale
                .where(
                  (p) =>
                      (p['full_name'] ?? '').toString().trim().toLowerCase() ==
                      value.trim().toLowerCase(),
                )
                .toList(growable: false);
            setState(() {
              if (exact.isNotEmpty) {
                _personaleId = (exact.first['id_uuid'] ?? '').toString();
                _syncMatricolaDipendente();
              } else {
                _personaleId = null;
                _matricolaDipCtrl.clear();
              }
            });
          },
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<Uint8List> _buildExcel() async {
    final elmQty = _toQty(_elmQtyCtrl.text);
    final imbQty = _toQty(_imbQtyCtrl.text);
    final cordSingQty = _toQty(_cordSingQtyCtrl.text);
    final cordPosQty = _toQty(_cordPosQtyCtrl.text);
    final cordYQty = _toQty(_cordYQtyCtrl.text);

    final payload = <String, String>{
      'I12': _selectedName,
      'S12': _matricolaDipCtrl.text.trim(),
      'E56': formatDateDdMmYyyyFromDate(_dataConsegna),
      'P16': elmQty > 0 ? elmQty.toString() : '',
      'S16': elmQty > 0 ? 'X' : '',
      'U16': '',
      'G17': _elmMarcaCtrl.text.trim(),
      'G18': _elmProdCtrl.text.trim(),
      'G19': _elmMatCtrl.text.trim(),
      'G20': _elmModCtrl.text.trim(),
      'G21': _elmFornCtrl.text.trim(),
      'P23': imbQty > 0 ? imbQty.toString() : '',
      'S23': imbQty > 0 ? 'X' : '',
      'U23': '',
      'G24': _imbMarcaCtrl.text.trim(),
      'G25': _imbProdCtrl.text.trim(),
      'G26': _imbMatCtrl.text.trim(),
      'G27': _imbModCtrl.text.trim(),
      'G28': _imbFornCtrl.text.trim(),
      'P30': cordSingQty > 0 ? cordSingQty.toString() : '',
      'S30': cordSingQty > 0 ? 'X' : '',
      'U30': '',
      'G31': _cordSingMarcaCtrl.text.trim(),
      'G32': _cordSingProdCtrl.text.trim(),
      'G33': _cordSingMatCtrl.text.trim(),
      'G34': _cordSingModCtrl.text.trim(),
      'G35': _cordSingFornCtrl.text.trim(),
      'P37': cordPosQty > 0 ? cordPosQty.toString() : '',
      'S37': cordPosQty > 0 ? 'X' : '',
      'U37': '',
      'G38': _cordPosMarcaCtrl.text.trim(),
      'G39': _cordPosProdCtrl.text.trim(),
      'G40': _cordPosMatCtrl.text.trim(),
      'G41': _cordPosModCtrl.text.trim(),
      'G42': _cordPosFornCtrl.text.trim(),
      'P44': cordYQty > 0 ? cordYQty.toString() : '',
      'S44': cordYQty > 0 ? 'X' : '',
      'U44': '',
      'G45': _cordYMarcaCtrl.text.trim(),
      'G46': _cordYProdCtrl.text.trim(),
      'G47': _cordYMatCtrl.text.trim(),
      'G48': _cordYModCtrl.text.trim(),
      'G49': _cordYFornCtrl.text.trim(),
    };

    if (kIsWeb) {
      return Dpi3cExcel.fill(payload);
    }

    final tempDir = await Directory.systemTemp.createTemp('dpi3c_');
    late final String templatePath;
    late final String logoPath;
    try {
      templatePath = await ExcelTemplateAssets.materialize(
        tempDir,
        ExcelTemplateAssets.modDpi3c,
        'Mod.DPI3C_00.xlsx',
      );
      logoPath = await ExcelTemplateAssets.materializeLogoOrEmpty(tempDir);
    } catch (e) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      throw Exception(
        'Template Mod.DPI3C_00.xlsx non disponibile negli asset. '
        'Verifica assets/Mod.DPI3C_00.xlsx e pubspec.yaml. Dettaglio: $e',
      );
    }
    final scriptFile = File('${tempDir.path}\\fill_dpi3c_template.py');
    final jsonFile = File('${tempDir.path}\\payload.json');
    final outputFile = File('${tempDir.path}\\modulo_dpi_iii_categoria.xlsx');
    const pyScript = r'''
import json
import sys
from openpyxl import load_workbook

template_path = sys.argv[1]
payload_path = sys.argv[2]
output_path = sys.argv[3]
logo_path = sys.argv[4]

with open(payload_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

wb = load_workbook(template_path)
ws = wb["CONS DPI3"] if "CONS DPI3" in wb.sheetnames else wb[wb.sheetnames[0]]

for ref, value in payload.items():
    ws[ref] = value if value is not None else ""

try:
    from openpyxl.drawing.image import Image
    import os
    if logo_path and os.path.exists(logo_path):
        img = Image(logo_path)
        img.width = 180
        img.height = 55
        ws.add_image(img, "B2")
except Exception:
    pass

wb.save(output_path)
''';

    await scriptFile.writeAsString(pyScript);
    await jsonFile.writeAsString(jsonEncode(payload));

    Uint8List outBytes;
    try {
      final proc = await Process.run(
        'python',
        [scriptFile.path, templatePath, jsonFile.path, outputFile.path, logoPath],
      );
      if (proc.exitCode != 0 || !outputFile.existsSync()) {
        outBytes = await Dpi3cExcel.fill(payload);
      } else {
        final out = await outputFile.readAsBytes();
        outBytes = Uint8List.fromList(out);
      }
    } catch (_) {
      outBytes = await Dpi3cExcel.fill(payload);
    }

    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    return outBytes;
  }

  int _toQty(String value) => int.tryParse(value.trim()) ?? 0;

  /// Campo vuoto → data consegna; altrimenti data libera (DD-MM-YYYY, MM/YYYY, solo anno, testo).
  String? _dateOrConsegna(String raw, String? consegnaIso) =>
      normalizeDpiOptionalDateField(raw, consegnaIso);

  Future<bool> _saveInDpi({bool showSuccessSnack = true}) async {
    final personaleId = _personaleId ?? '';
    if (personaleId.isEmpty) {
      _snack('Seleziona un dipendente', isError: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      final consegnaIso =
          parseFlexibleDateToIsoDate(formatDateDdMmYyyyFromDate(_dataConsegna));
      final rows = <Map<String, dynamic>>[
        {
          'personale_id': personaleId,
          'categoria': 'Elmetto',
          'quantita_assegnata': _toQty(_elmQtyCtrl.text),
          'marca': _elmMarcaCtrl.text.trim(),
          'data_produzione': _dateOrConsegna(_elmProdCtrl.text, consegnaIso),
          'data_consegna': consegnaIso,
          'data_revisione': _dateOrConsegna(_elmRevCtrl.text, consegnaIso),
          'matricola': _elmMatCtrl.text.trim().isEmpty ? null : _elmMatCtrl.text.trim(),
          'modello': _elmModCtrl.text.trim(),
          'note': 'Inserito da modulo DPI III categoria (Elmetto)',
        },
        {
          'personale_id': personaleId,
          'categoria': 'Imbracatura',
          'quantita_assegnata': _toQty(_imbQtyCtrl.text),
          'marca': _imbMarcaCtrl.text.trim(),
          'data_produzione': _dateOrConsegna(_imbProdCtrl.text, consegnaIso),
          'data_consegna': consegnaIso,
          'data_revisione': _dateOrConsegna(_imbRevCtrl.text, consegnaIso),
          'matricola': _imbMatCtrl.text.trim().isEmpty ? null : _imbMatCtrl.text.trim(),
          'modello': _imbModCtrl.text.trim(),
          'note': 'Inserito da modulo DPI III categoria',
        },
        {
          'personale_id': personaleId,
          'categoria': 'Cordino Singolo con Dissipatore',
          'quantita_assegnata': _toQty(_cordSingQtyCtrl.text),
          'marca': _cordSingMarcaCtrl.text.trim(),
          'data_produzione': _dateOrConsegna(_cordSingProdCtrl.text, consegnaIso),
          'data_consegna': consegnaIso,
          'data_revisione': _dateOrConsegna(_cordSingRevCtrl.text, consegnaIso),
          'matricola': _cordSingMatCtrl.text.trim().isEmpty ? null : _cordSingMatCtrl.text.trim(),
          'modello': _cordSingModCtrl.text.trim(),
          'note': 'Inserito da modulo DPI III categoria (Cordino singolo)',
        },
        {
          'personale_id': personaleId,
          'categoria': 'Cordino di Posizionamento',
          'quantita_assegnata': _toQty(_cordPosQtyCtrl.text),
          'marca': _cordPosMarcaCtrl.text.trim(),
          'data_produzione': _dateOrConsegna(_cordPosProdCtrl.text, consegnaIso),
          'data_consegna': consegnaIso,
          'data_revisione': _dateOrConsegna(_cordPosRevCtrl.text, consegnaIso),
          'matricola': _cordPosMatCtrl.text.trim().isEmpty ? null : _cordPosMatCtrl.text.trim(),
          'modello': _cordPosModCtrl.text.trim(),
          'note': 'Inserito da modulo DPI III categoria',
        },
        {
          'personale_id': personaleId,
          'categoria': 'Cordino Shock Absorber Doppio',
          'quantita_assegnata': _toQty(_cordYQtyCtrl.text),
          'marca': _cordYMarcaCtrl.text.trim(),
          'data_produzione': _dateOrConsegna(_cordYProdCtrl.text, consegnaIso),
          'data_consegna': consegnaIso,
          'data_revisione': _dateOrConsegna(_cordYRevCtrl.text, consegnaIso),
          'matricola': _cordYMatCtrl.text.trim().isEmpty ? null : _cordYMatCtrl.text.trim(),
          'modello': _cordYModCtrl.text.trim(),
          'note': 'Inserito da modulo DPI III categoria',
        },
      ].where((e) => (e['quantita_assegnata'] as int) > 0).toList();

      if (rows.isEmpty) {
        _snack('Inserisci almeno una quantita > 0', isError: true);
        return false;
      }
      for (final row in rows) {
        final categoria = (row['categoria'] ?? '').toString().trim();
        final personale = (row['personale_id'] ?? '').toString().trim();

        // Unicità matricola: vincolo DB su (personale_id, categoria, matricola), non globale.

        // 1) Keep one current record per employee+category for DPI III flow:
        // update latest if exists, otherwise insert.
        final existingSameCategory = await SupabaseService.client
            .from('dpi_dotazioni')
            .select('id, created_at')
            .eq('personale_id', personale)
            .eq('categoria', categoria)
            .order('created_at', ascending: false)
            .limit(1);

        if ((existingSameCategory as List).isNotEmpty) {
          final id = (existingSameCategory.first['id'] ?? '').toString();
          if (id.isNotEmpty) {
            await SupabaseService.client.from('dpi_dotazioni').update(row).eq('id', id);
            continue;
          }
        }

        await SupabaseService.client.from('dpi_dotazioni').insert(row);
      }
      if (showSuccessSnack) {
        _snack('Dati DPI salvati con successo');
      }
      return true;
    } catch (e) {
      _snack('Errore salvataggio DPI: $e', isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _safeEmployeeFileStem() {
    final employee = _selectedName.isEmpty ? 'dipendente' : _selectedName;
    return employee
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  void _fillSectionFromRow(
    Map<String, dynamic>? row, {
    required TextEditingController qtyCtrl,
    required TextEditingController marcaCtrl,
    required TextEditingController prodCtrl,
    required TextEditingController revCtrl,
    required TextEditingController matCtrl,
    required TextEditingController modCtrl,
    required TextEditingController fornCtrl,
  }) {
    qtyCtrl.text = row == null ? '' : (row['quantita_assegnata'] ?? '').toString();
    marcaCtrl.text = row == null ? '' : (row['marca'] ?? '').toString().trim();
    prodCtrl.text =
        row == null ? '' : formatDateDdMmYyyy(row['data_produzione']);
    revCtrl.text =
        row == null ? '' : formatDateDdMmYyyy(row['data_revisione']);
    matCtrl.text = row == null ? '' : (row['matricola'] ?? '').toString().trim();
    modCtrl.text = row == null ? '' : (row['modello'] ?? '').toString().trim();
    fornCtrl.clear();
  }

  Map<String, dynamic>? _latestRowForCategory(
    Map<String, Map<String, dynamic>> byCategory,
    String category,
  ) {
    final direct = byCategory[category.trim().toLowerCase()];
    if (direct != null) return direct;
    if (category == 'Cordino Singolo con Dissipatore') {
      return byCategory['cordino'];
    }
    return null;
  }

  Future<void> _caricaDatiSalvati() async {
    final personaleId = _personaleId ?? '';
    if (personaleId.isEmpty) {
      _snack('Seleziona un dipendente', isError: true);
      return;
    }
    setState(() => _loadingDpi = true);
    try {
      final res = await SupabaseService.client
          .from('dpi_dotazioni')
          .select(
            'categoria, quantita_assegnata, marca, data_produzione, data_consegna, data_revisione, matricola, modello, created_at',
          )
          .eq('personale_id', personaleId)
          .order('created_at', ascending: false);
      final rows = List<Map<String, dynamic>>.from(res as List);
      final byCategory = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final key = (row['categoria'] ?? '').toString().trim().toLowerCase();
        if (key.isEmpty || byCategory.containsKey(key)) continue;
        byCategory[key] = row;
      }

      if (byCategory.isEmpty) {
        _snack('Nessuna assegnazione DPI salvata per questo dipendente', isError: true);
        return;
      }

      final consegnaRaw = rows
          .map((r) => (r['data_consegna'] ?? '').toString().trim())
          .firstWhere((v) => v.isNotEmpty, orElse: () => '');
      final consegnaIso = parseFlexibleDateToIsoDate(consegnaRaw);
      if (consegnaIso != null) {
        final parts = consegnaIso.split('-');
        if (parts.length == 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            _dataConsegna = DateTime(y, m, d);
          }
        }
      }

      _fillSectionFromRow(
        _latestRowForCategory(byCategory, 'Elmetto'),
        qtyCtrl: _elmQtyCtrl,
        marcaCtrl: _elmMarcaCtrl,
        prodCtrl: _elmProdCtrl,
        revCtrl: _elmRevCtrl,
        matCtrl: _elmMatCtrl,
        modCtrl: _elmModCtrl,
        fornCtrl: _elmFornCtrl,
      );
      _fillSectionFromRow(
        _latestRowForCategory(byCategory, 'Imbracatura'),
        qtyCtrl: _imbQtyCtrl,
        marcaCtrl: _imbMarcaCtrl,
        prodCtrl: _imbProdCtrl,
        revCtrl: _imbRevCtrl,
        matCtrl: _imbMatCtrl,
        modCtrl: _imbModCtrl,
        fornCtrl: _imbFornCtrl,
      );
      _fillSectionFromRow(
        _latestRowForCategory(byCategory, 'Cordino Singolo con Dissipatore'),
        qtyCtrl: _cordSingQtyCtrl,
        marcaCtrl: _cordSingMarcaCtrl,
        prodCtrl: _cordSingProdCtrl,
        revCtrl: _cordSingRevCtrl,
        matCtrl: _cordSingMatCtrl,
        modCtrl: _cordSingModCtrl,
        fornCtrl: _cordSingFornCtrl,
      );
      _fillSectionFromRow(
        _latestRowForCategory(byCategory, 'Cordino di Posizionamento'),
        qtyCtrl: _cordPosQtyCtrl,
        marcaCtrl: _cordPosMarcaCtrl,
        prodCtrl: _cordPosProdCtrl,
        revCtrl: _cordPosRevCtrl,
        matCtrl: _cordPosMatCtrl,
        modCtrl: _cordPosModCtrl,
        fornCtrl: _cordPosFornCtrl,
      );
      _fillSectionFromRow(
        _latestRowForCategory(byCategory, 'Cordino Shock Absorber Doppio'),
        qtyCtrl: _cordYQtyCtrl,
        marcaCtrl: _cordYMarcaCtrl,
        prodCtrl: _cordYProdCtrl,
        revCtrl: _cordYRevCtrl,
        matCtrl: _cordYMatCtrl,
        modCtrl: _cordYModCtrl,
        fornCtrl: _cordYFornCtrl,
      );

      if (!mounted) return;
      setState(() {});
      _snack('Dati DPI caricati: verifica i campi e usa Esporta Excel modulo');
    } catch (e) {
      _snack('Errore caricamento DPI: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loadingDpi = false);
    }
  }

  Future<void> _exportModuloExcel({
    bool openFile = true,
    String? successMessage,
  }) async {
    if ((_personaleId ?? '').isEmpty) {
      _snack('Seleziona un dipendente', isError: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final file = await _buildExcel();
      final pageName = 'modulo_dpi3c_${_safeEmployeeFileStem()}';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: pageName,
          bytes: file,
          ext: 'xlsx',
          mimeType: MimeType.other,
        );
        _snack(successMessage ?? 'Modulo Excel generato');
        return;
      }

      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: pageName,
        bytes: file,
        openFile: openFile,
      );
      if (!ok) {
        _snack('Errore salvataggio modulo Excel', isError: true);
        return;
      }
      final path = ExcelExportHelper.lastSavedPath;
      _snack(
        successMessage ??
            (path == null
                ? 'Modulo Excel generato'
                : 'Modulo Excel generato: $path'),
      );
    } catch (e) {
      _snack('Errore generazione modulo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAndSave() async {
    final ok = await _saveInDpi(showSuccessSnack: false);
    if (!ok) return;
    await _exportModuloExcel(
      openFile: true,
      successMessage: 'Dati DPI salvati e modulo Excel generato',
    );
  }

  Widget _section({
    required BuildContext context,
    required String title,
    required TextEditingController qtyCtrl,
    required TextEditingController marcaCtrl,
    required TextEditingController prodCtrl,
    required TextEditingController revCtrl,
    required TextEditingController matCtrl,
    required TextEditingController modCtrl,
    required TextEditingController fornCtrl,
  }) {
    final narrow = useMobileUi(context);
    final qtyW = narrow ? 100.0 : 120.0;
    final fieldW = narrow
        ? cronosFullFieldWidth(context, horizontalMargin: 44)
        : 220.0;
    final fornW = narrow
        ? cronosFullFieldWidth(context, horizontalMargin: 44)
        : 260.0;
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: qtyW,
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Quantita'),
                  ),
                ),
                SizedBox(
                  width: fieldW,
                  child: TextField(controller: marcaCtrl, decoration: deco('Marca')),
                ),
                SizedBox(
                  width: fieldW,
                  child: TextField(
                    controller: prodCtrl,
                    decoration: deco('Produzione').copyWith(
                      helperText: 'Libero: DD-MM-YYYY, MM/YYYY, anno… Vuoto = data consegna',
                    ),
                  ),
                ),
                SizedBox(
                  width: fieldW,
                  child: TextField(
                    controller: revCtrl,
                    decoration: deco('Revisione').copyWith(
                      helperText: 'Libero: DD-MM-YYYY, MM/YYYY, anno… Vuoto = data consegna',
                    ),
                  ),
                ),
                SizedBox(
                  width: fieldW,
                  child: TextField(controller: matCtrl, decoration: deco('N Serie/Matricola')),
                ),
                SizedBox(
                  width: fieldW,
                  child: TextField(controller: modCtrl, decoration: deco('Item/Modello')),
                ),
                SizedBox(
                  width: fornW,
                  child: TextField(controller: fornCtrl, decoration: deco('Estremi fornitore')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = useMobileUi(context);
    final fieldW = narrow
        ? cronosFullFieldWidth(context, horizontalMargin: 44)
        : 220.0;
    final dipW = narrow
        ? cronosFullFieldWidth(context, horizontalMargin: 44)
        : 340.0;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(
          title: narrow
              ? 'DPI III Categoria'
              : 'Impostazioni App — Assegnazione DPI III Categoria',
          desktopLogoSize: 40,
        ),
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(narrow ? 8 : 12),
              child: ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: dipW,
                            child: _dipendenteAutocompleteField(),
                          ),
                          SizedBox(
                            width: fieldW,
                            child: TextField(
                              controller: _matricolaDipCtrl,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Matricola dipendente',
                                hintText: 'Da Gestione Dipendenti',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: fieldW,
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _dataConsegna,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() => _dataConsegna = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Data consegna',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(formatDateDdMmYyyyFromDate(_dataConsegna)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _section(
                    context: context,
                    title: 'Elmetto',
                    qtyCtrl: _elmQtyCtrl,
                    marcaCtrl: _elmMarcaCtrl,
                    prodCtrl: _elmProdCtrl,
                    revCtrl: _elmRevCtrl,
                    matCtrl: _elmMatCtrl,
                    modCtrl: _elmModCtrl,
                    fornCtrl: _elmFornCtrl,
                  ),
                  _section(
                    context: context,
                    title: 'Imbracatura',
                    qtyCtrl: _imbQtyCtrl,
                    marcaCtrl: _imbMarcaCtrl,
                    prodCtrl: _imbProdCtrl,
                    revCtrl: _imbRevCtrl,
                    matCtrl: _imbMatCtrl,
                    modCtrl: _imbModCtrl,
                    fornCtrl: _imbFornCtrl,
                  ),
                  _section(
                    context: context,
                    title: 'Cordino singolo con dissipatore',
                    qtyCtrl: _cordSingQtyCtrl,
                    marcaCtrl: _cordSingMarcaCtrl,
                    prodCtrl: _cordSingProdCtrl,
                    revCtrl: _cordSingRevCtrl,
                    matCtrl: _cordSingMatCtrl,
                    modCtrl: _cordSingModCtrl,
                    fornCtrl: _cordSingFornCtrl,
                  ),
                  _section(
                    context: context,
                    title: 'Cordino di posizionamento',
                    qtyCtrl: _cordPosQtyCtrl,
                    marcaCtrl: _cordPosMarcaCtrl,
                    prodCtrl: _cordPosProdCtrl,
                    revCtrl: _cordPosRevCtrl,
                    matCtrl: _cordPosMatCtrl,
                    modCtrl: _cordPosModCtrl,
                    fornCtrl: _cordPosFornCtrl,
                  ),
                  _section(
                    context: context,
                    title: 'Cordino di connessione a Y con dissipatore',
                    qtyCtrl: _cordYQtyCtrl,
                    marcaCtrl: _cordYMarcaCtrl,
                    prodCtrl: _cordYProdCtrl,
                    revCtrl: _cordYRevCtrl,
                    matCtrl: _cordYMatCtrl,
                    modCtrl: _cordYModCtrl,
                    fornCtrl: _cordYFornCtrl,
                  ),
                  const SizedBox(height: 10),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveInDpi,
                          icon: const Icon(Icons.save),
                          label: const Text('Salva assegnazione DPI'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: (_loadingDpi || _exporting)
                              ? null
                              : _exportModuloExcel,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Esporta Excel modulo'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _loadingDpi ? null : _caricaDatiSalvati,
                          icon: _loadingDpi
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.history),
                          label: const Text('Carica da assegnazione salvata'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: (_saving || _exporting) ? null : _exportAndSave,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Salva + genera modulo'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminDpiReportPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.summarize_outlined),
                          label: const Text('Vai a riepilogo DPI'),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveInDpi,
                          icon: const Icon(Icons.save),
                          label: const Text('Salva assegnazione DPI'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: (_loadingDpi || _exporting)
                              ? null
                              : _exportModuloExcel,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Esporta Excel modulo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingDpi ? null : _caricaDatiSalvati,
                          icon: _loadingDpi
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.history),
                          label: const Text('Carica da assegnazione salvata'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: (_saving || _exporting) ? null : _exportAndSave,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Salva + genera modulo + apri percorso'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminDpiReportPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.summarize_outlined),
                          label: const Text('Vai a riepilogo DPI'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

