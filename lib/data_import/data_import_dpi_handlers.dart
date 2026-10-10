import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/dpi_categories_service.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/tesserino_helpers.dart';
import '../utils/simple_excel_table_io.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportDpiHandlers {
  DataImportDpiHandlers._();

  static final _supa = SupabaseService.client;

  static Uint8List templateBytes(String id) {
    switch (id) {
      case 'dpi_report':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Report_DPI',
          titleRow: 'Una riga per dipendente e categoria DPI.',
          headers: const [
            'Dipendente',
            'Categoria DPI',
            'Quantità',
            'Marca',
            'Modello',
            'Matricola',
            'Data produzione',
            'Data consegna',
            'Data revisione',
          ],
          exampleRows: const [
            ['Mario Rossi', 'Casco', '1', 'Brand X', 'Mod A', 'MAT001', '01/01/2024', '15/03/2024', '15/03/2027'],
          ],
        );
      case 'dpi_categorie':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Categorie_DPI',
          headers: const ['Nome categoria', 'Descrizione'],
          exampleRows: const [
            ['Casco', 'Protezione testa'],
          ],
        );
      case 'dpi_terza_categoria':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'DPI_III_Categoria',
          titleRow: 'Assegnazione DPI di terza categoria per dipendente.',
          headers: const [
            'Dipendente',
            'Descrizione DPI',
            'Data consegna',
            'Note',
          ],
          exampleRows: const [
            ['Mario Rossi', 'Imbracatura completa', '15/03/2024', ''],
          ],
        );
      case 'vestiario_assegnazione':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Assegnazione_Vestiario',
          titleRow: 'Stagione: estivo o invernale nella colonna dedicata.',
          headers: const [
            'Dipendente',
            'Stagione (estivo/invernale)',
            'Articolo/Categoria',
            'Taglia',
            'Quantità',
            'Data consegna',
          ],
          exampleRows: const [
            ['Mario Rossi', 'estivo', 'Polo', 'L', '2', '01/06/2025'],
          ],
        );
      case 'vestiario_riepilogo':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Taglie_Dipendenti',
          titleRow: 'Taglie vestiario per dipendente (riepilogo).',
          headers: const [
            'Dipendente',
            'T-shirt',
            'Pantalone',
            'Felpa',
            'Giacca',
            'Gilet',
            'Scarpe',
            'Guanti',
          ],
          exampleRows: const [
            ['Mario Rossi', 'L', '48', 'L', 'L', 'L', '42', '9'],
          ],
        );
      case 'vestiario_fabbisogno':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Fabbisogno_Taglie',
          headers: const [
            'Dipendente',
            'Stagione (estivo/invernale)',
            'Articolo',
            'Taglia',
            'Quantità fabbisogno',
          ],
          exampleRows: const [
            ['Mario Rossi', 'estivo', 'Polo', 'L', '2'],
          ],
        );
      case 'vestiario_inventario':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Inventario_Vestiario',
          headers: const [
            'Articolo',
            'Taglia',
            'Quantità',
            'Stagione (estivo/invernale)',
            'Note',
          ],
          exampleRows: const [
            ['Polo', 'L', '10', 'estivo', ''],
          ],
        );
      default:
        throw ArgumentError('Modulo DPI sconosciuto: $id');
    }
  }

  static Future<DataImportResult> runImport({
    required BuildContext context,
    required String id,
    required Uint8List bytes,
  }) async {
    final rows = SimpleExcelTableIo.parseTable(bytes);
    if (rows.isEmpty) {
      return const DataImportResult(
        message: 'File senza righe dati.',
        errors: 1,
      );
    }
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import',
      body: 'Righe da importare: ${rows.length}\n\nProcedere?',
    );
    if (!ok) return const DataImportResult(message: 'Import annullato.');

    switch (id) {
      case 'dpi_report':
        return _importDpiReport(rows);
      case 'dpi_categorie':
        return _importDpiCategorie(rows);
      case 'dpi_terza_categoria':
        return _importDpiTerzaCategoria(rows);
      case 'vestiario_assegnazione':
        return _importVestiarioAssegnazione(rows);
      case 'vestiario_riepilogo':
        return _importVestiarioRiepilogo(rows);
      case 'vestiario_fabbisogno':
        return _importVestiarioFabbisogno(rows);
      case 'vestiario_inventario':
        return _importVestiarioInventario(rows);
      default:
        throw ArgumentError('Modulo DPI sconosciuto: $id');
    }
  }

  static Future<Map<String, String>> _loadPersonaleUuidByName() async {
    final rows = await _supa
        .from('personale')
        .select('id_uuid, full_name')
        .eq('active', true);
    final map = <String, String>{};
    for (final p in rows as List) {
      final name = (p['full_name'] ?? '').toString().trim().toLowerCase();
      final uuid = (p['id_uuid'] ?? '').toString();
      if (name.isNotEmpty && uuid.isNotEmpty) map[name] = uuid;
    }
    return map;
  }

  static String? _findPersonaleUuid(
    Map<String, String> byName,
    String? label,
  ) {
    if (label == null || label.trim().isEmpty) return null;
    final direct = byName[label.trim().toLowerCase()];
    if (direct != null) return direct;
    for (final e in byName.entries) {
      final parts = label.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final cognome = parts.last;
        final nome = parts.sublist(0, parts.length - 1).join(' ');
        if (namesMatchPersonale(
          excelNome: nome,
          excelCognome: cognome,
          personaleFullName: e.key,
        )) {
          return e.value;
        }
      }
    }
    return null;
  }

  static Future<DataImportResult> _importDpiReport(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleUuidByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final pid = _findPersonaleUuid(
        byName,
        SimpleExcelTableIo.rowValue(row, const ['Dipendente']),
      );
      final categoria =
          SimpleExcelTableIo.rowValue(row, const ['Categoria DPI', 'Categoria']);
      if (pid == null || categoria == null || categoria.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await _supa.from('dpi_dotazioni').insert({
          'personale_id': pid,
          'categoria': categoria,
          'quantita_assegnata': int.tryParse(
                SimpleExcelTableIo.rowValue(row, const ['Quantità', 'Quantita']) ?? '1',
              ) ??
              1,
          'marca': SimpleExcelTableIo.rowValue(row, const ['Marca']),
          'modello': SimpleExcelTableIo.rowValue(row, const ['Modello']),
          'matricola': SimpleExcelTableIo.rowValue(row, const ['Matricola']),
          'data_produzione': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data produzione']),
          ),
          'data_consegna': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data consegna']),
          ),
          'data_revisione': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data revisione']),
          ),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import report DPI completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importDpiCategorie(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome categoria', 'Nome']);
      if (nome == null || nome.isEmpty) continue;
      try {
        await DpiCategoriesService.addCategory(nome);
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import categorie DPI completato.',
      added: added,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importDpiTerzaCategoria(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleUuidByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final pid = _findPersonaleUuid(
        byName,
        SimpleExcelTableIo.rowValue(row, const ['Dipendente']),
      );
      final descr = SimpleExcelTableIo.rowValue(row, const ['Descrizione DPI', 'Descrizione']);
      if (pid == null || descr == null || descr.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await _supa.from('dpi_dotazioni').insert({
          'personale_id': pid,
          'categoria': 'DPI III Categoria',
          'quantita_assegnata': 1,
          'modello': descr,
          'data_consegna': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data consegna']),
          ),
          'marca': SimpleExcelTableIo.rowValue(row, const ['Note']),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import DPI III categoria completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importVestiarioAssegnazione(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleUuidByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final pid = _findPersonaleUuid(
        byName,
        SimpleExcelTableIo.rowValue(row, const ['Dipendente']),
      );
      final categoria = SimpleExcelTableIo.rowValue(
        row,
        const ['Articolo/Categoria', 'Categoria', 'Articolo'],
      );
      final taglia = SimpleExcelTableIo.rowValue(row, const ['Taglia']);
      if (pid == null || categoria == null || taglia == null) {
        skipped++;
        continue;
      }
      try {
        await _supa.from('vestiario_dotazioni').insert({
          'personale_id': pid,
          'categoria': categoria,
          'taglia': taglia,
          'quantita_assegnata': int.tryParse(
                SimpleExcelTableIo.rowValue(row, const ['Quantità', 'Quantita']) ?? '1',
              ) ??
              1,
          'data_consegna': parseFlexibleDateToIsoDate(
                SimpleExcelTableIo.rowValue(row, const ['Data consegna']),
              ) ??
              italyTodayIsoDate(),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import assegnazione vestiario completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importVestiarioRiepilogo(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleUuidByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final pid = _findPersonaleUuid(
        byName,
        SimpleExcelTableIo.rowValue(row, const ['Dipendente']),
      );
      if (pid == null) {
        skipped++;
        continue;
      }
      try {
        await _supa.from('personale_taglie').upsert(
          {
            'personale_id': pid,
            'taglia_tshirt': SimpleExcelTableIo.rowValue(row, const ['T-shirt', 'Tshirt']),
            'taglia_pantalone': SimpleExcelTableIo.rowValue(row, const ['Pantalone']),
            'taglia_felpa': SimpleExcelTableIo.rowValue(row, const ['Felpa']),
            'taglia_giacca': SimpleExcelTableIo.rowValue(row, const ['Giacca']),
            'taglia_gilet': SimpleExcelTableIo.rowValue(row, const ['Gilet']),
            'taglia_scarpe': SimpleExcelTableIo.rowValue(row, const ['Scarpe']),
            'taglia_guanti': SimpleExcelTableIo.rowValue(row, const ['Guanti']),
          },
          onConflict: 'personale_id',
        );
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import taglie dipendenti completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importVestiarioFabbisogno(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleUuidByName();
    final pending = <String, Map<String, String>>{};
    var skipped = 0;
    for (final row in rows) {
      final pid = _findPersonaleUuid(
        byName,
        SimpleExcelTableIo.rowValue(row, const ['Dipendente']),
      );
      final articolo = SimpleExcelTableIo.rowValue(row, const ['Articolo']);
      final taglia = SimpleExcelTableIo.rowValue(row, const ['Taglia']);
      final field = _tagliaFieldForArticolo(articolo ?? '');
      if (pid == null || field == null || taglia == null || taglia.isEmpty) {
        skipped++;
        continue;
      }
      pending.putIfAbsent(pid, () => <String, String>{})[field] = taglia;
    }
    var added = 0;
    var errors = 0;
    for (final entry in pending.entries) {
      try {
        final existing = await _supa
            .from('personale_taglie')
            .select()
            .eq('personale_id', entry.key)
            .maybeSingle();
        final payload = <String, dynamic>{
          'personale_id': entry.key,
          if (existing != null) ...Map<String, dynamic>.from(existing as Map),
          ...entry.value,
        };
        await _supa.from('personale_taglie').upsert(
          payload,
          onConflict: 'personale_id',
        );
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import fabbisogno taglie completato (taglie dipendenti).',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static String? _tagliaFieldForArticolo(String articolo) {
    final a = articolo.toLowerCase();
    if (a.contains('t-shirt') || a.contains('tshirt') || a.contains('polo')) {
      return 'taglia_tshirt';
    }
    if (a.contains('pantal')) return 'taglia_pantalone';
    if (a.contains('felpa')) return 'taglia_felpa';
    if (a.contains('giacca')) return 'taglia_giacca';
    if (a.contains('gilet')) return 'taglia_gilet';
    if (a.contains('scarpe')) return 'taglia_scarpe';
    if (a.contains('guanti')) return 'taglia_guanti';
    return null;
  }

  static Future<DataImportResult> _importVestiarioInventario(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final stagione = SimpleExcelTableIo.rowValue(
              row,
              const ['Stagione (estivo/invernale)', 'Stagione'],
            ) ??
            'estivo';
        final articolo = SimpleExcelTableIo.rowValue(row, const ['Articolo']) ?? '';
        final taglia = SimpleExcelTableIo.rowValue(row, const ['Taglia']) ?? '';
        final qty = int.tryParse(
              SimpleExcelTableIo.rowValue(row, const ['Quantità', 'Quantita']) ?? '',
            ) ??
            0;
        await _supa.from('vestiario_magazzino').upsert(
          {
            'stagione': stagione,
            'articolo': articolo,
            'taglia': taglia,
            'quantita': qty < 0 ? 0 : qty,
          },
          onConflict: 'stagione,articolo,taglia',
        );
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import inventario vestiario completato.',
      added: added,
      errors: errors,
    );
  }
}
