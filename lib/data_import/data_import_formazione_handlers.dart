import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/tesserino_helpers.dart';
import '../utils/simple_excel_table_io.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportFormazioneHandlers {
  DataImportFormazioneHandlers._();

  static final _supa = SupabaseService.client;

  static Uint8List templateBytes(String id) {
    switch (id) {
      case 'formazione_dlgs':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Formazione_DLGS_81_08',
          headers: const [
            'Dipendente',
            'Corso',
            'Data attestato',
            'Scadenza attestato',
            'Data programmazione',
            'Orario',
            'Modalita',
            'Struttura/Link',
          ],
          exampleRows: const [
            [
              'Mario Rossi',
              'Formazione generale',
              '15/01/2025',
              '15/01/2028',
              '10/01/2025',
              '09:00',
              'Aula',
              'Sede Milano',
            ],
          ],
        );
      case 'formazione_rfi':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Formazione_RFI',
          titleRow: 'Una riga per dipendente e corso/colonna RFI.',
          headers: const [
            'Dipendente',
            'Corso / Attestato',
            'Data conseguimento',
            'Scadenza',
            'Note',
          ],
          exampleRows: const [
            ['Mario Rossi', 'Patente RFI base', '01/06/2025', '01/06/2028', ''],
          ],
        );
      case 'formazione_rfi_strutture':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Strutture_RFI',
          headers: const ['Codice DOIT', 'Nome struttura', 'Indirizzo', 'Note'],
          exampleRows: const [
            ['DOIT001', 'Centro RFI Roma', 'Via Roma 1', ''],
          ],
        );
      default:
        throw ArgumentError('Modulo formazione sconosciuto: $id');
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
      case 'formazione_dlgs':
        return _importFormazioneDlgs(rows);
      case 'formazione_rfi':
        return _importFormazioneRfi(rows);
      case 'formazione_rfi_strutture':
        return _importStruttureRfi(rows);
      default:
        throw ArgumentError('Modulo formazione sconosciuto: $id');
    }
  }

  static Future<Map<String, String>> _loadPersonaleByName() async {
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

  static String? _findPersonaleUuid(Map<String, String> byName, String? label) {
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

  static Future<DataImportResult> _importFormazioneDlgs(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final dipLabel = SimpleExcelTableIo.rowValue(row, const ['Dipendente']);
      final pid = _findPersonaleUuid(byName, dipLabel);
      if (pid == null) {
        skipped++;
        continue;
      }
      try {
        await _supa.from('formazione_corsi').insert({
          'personale_id': pid,
          'corso': SimpleExcelTableIo.rowValue(row, const ['Corso']),
          'data_attestato': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data attestato']),
          ),
          'scadenza_attestato': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Scadenza attestato']),
          ),
          'prima_data': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data programmazione']),
          ),
          'orario': SimpleExcelTableIo.rowValue(row, const ['Orario']),
          'modalita': SimpleExcelTableIo.rowValue(row, const ['Modalita']),
          'struttura_link': SimpleExcelTableIo.rowValue(row, const ['Struttura/Link']),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import formazione D.Lgs. completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importFormazioneRfi(
    List<Map<String, String>> rows,
  ) async {
    final byName = await _loadPersonaleByName();
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final dipLabel = SimpleExcelTableIo.rowValue(row, const ['Dipendente']);
      final pid = _findPersonaleUuid(byName, dipLabel);
      if (pid == null) {
        skipped++;
        continue;
      }
      final corso = SimpleExcelTableIo.rowValue(row, const ['Corso / Attestato', 'Corso']);
      if (corso == null || corso.isEmpty) {
        skipped++;
        continue;
      }
      try {
        final dataIso = parseFlexibleDateToIsoDate(
          SimpleExcelTableIo.rowValue(row, const ['Data conseguimento']),
        );
        final scadenza = SimpleExcelTableIo.rowValue(row, const ['Scadenza']);
        await _supa.from('formazione_rfi_records').upsert(
          <String, dynamic>{
            'personale_id': pid,
            'track_key': 'import_hub',
            'field_key': corso,
            'value_date': dataIso,
            'value_text': scadenza ?? '',
            'source_file': 'import_hub',
          },
          onConflict: 'personale_id,track_key,field_key',
        );
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import formazione RFI completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importStruttureRfi(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        await _supa.from('formazione_rfi_strutture').insert({
          'nome': SimpleExcelTableIo.rowValue(row, const ['Nome struttura', 'Nome']),
          'indirizzo': SimpleExcelTableIo.rowValue(row, const ['Indirizzo']),
          'maps_link': SimpleExcelTableIo.rowValue(row, const ['Note', 'Maps link']),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import strutture RFI completato.',
      added: added,
      errors: errors,
    );
  }
}
