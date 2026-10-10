import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../services/tesserino_excel_import.dart';
import '../utils/tesserino_helpers.dart';
import '../utils/simple_excel_table_io.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportTesseriniHandler {
  DataImportTesseriniHandler._();

  static Uint8List buildTemplate() {
    return SimpleExcelTableIo.buildTemplate(
      sheetName: 'Tesserini',
      titleRow: 'Aggiorna tesserini per dipendenti già in anagrafica.',
      headers: const [
        'nome',
        'Cognome',
        'Data nascita',
        'Data assunzione',
        'Numero tesserino',
      ],
      exampleRows: const [
        ['Mario', 'Rossi', '15/06/1985', '01/03/2020', '12345'],
      ],
    );
  }

  static Future<DataImportResult> runImport({
    required BuildContext context,
    required Uint8List bytes,
  }) async {
    List<TesserinoExcelRow> excelRows;
    try {
      excelRows = parseTesseriniExcelBytes(bytes);
    } catch (e) {
      return DataImportResult(message: 'Excel non valido: $e', errors: 1);
    }
    if (excelRows.isEmpty) {
      return const DataImportResult(
        message: 'Nessuna riga utile nel file.',
        errors: 1,
      );
    }
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import tesserini',
      body: 'Righe nel file: ${excelRows.length}\n\nProcedere?',
    );
    if (!ok) return const DataImportResult(message: 'Import annullato.');

    final supa = SupabaseService.client;
    final personale = await supa
        .from('personale')
        .select('id, full_name')
        .eq('active', true);
    var matched = 0;
    var skipped = 0;
    var errors = 0;
    for (final er in excelRows) {
      Map<String, dynamic>? hit;
      for (final p in personale as List) {
        if (namesMatchPersonale(
          excelNome: er.nome,
          excelCognome: er.cognome,
          personaleFullName: (p['full_name'] ?? '').toString(),
        )) {
          hit = p;
          break;
        }
      }
      if (hit == null) {
        skipped++;
        continue;
      }
      final upd = <String, dynamic>{};
      if (er.numeroTesserino.trim().isNotEmpty) {
        upd['numero_tesserino'] = er.numeroTesserino.trim();
      }
      if (er.dataNascita != null) {
        final d = er.dataNascita!;
        upd['data_nascita'] =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      if (er.dataAssunzione != null) {
        final d = er.dataAssunzione!;
        upd['data_assunzione'] =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      if (upd.isEmpty) continue;
      try {
        await supa.from('personale').update(upd).eq('id', hit['id']);
        matched++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import tesserini completato.',
      updated: matched,
      skipped: skipped,
      errors: errors,
    );
  }
}
