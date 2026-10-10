import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../utils/excel_export_helper.dart';
import 'data_import_dpi_handlers.dart';
import 'data_import_formazione_handlers.dart';
import 'data_import_hub_entry.dart';
import 'data_import_logistica_handlers.dart';
import 'data_import_master_handlers.dart';
import 'data_import_pos_handlers.dart';
import 'data_import_tesserini_handler.dart';

/// Scarica modello Excel ed esegue import per ogni modulo del catalogo.
abstract final class DataImportHubService {
  DataImportHubService._();

  static Uint8List templateBytesFor(String entryId) {
    if (_masterIds.contains(entryId)) {
      return DataImportMasterHandlers.templateBytes(entryId);
    }
    if (_posIds.contains(entryId)) {
      return DataImportPosHandlers.templateBytes(entryId);
    }
    if (entryId == 'tesserini') {
      return DataImportTesseriniHandler.buildTemplate();
    }
    if (_logisticaIds.contains(entryId)) {
      return DataImportLogisticaHandlers.templateBytes(entryId);
    }
    if (_dpiIds.contains(entryId)) {
      return DataImportDpiHandlers.templateBytes(entryId);
    }
    if (_formazioneIds.contains(entryId)) {
      return DataImportFormazioneHandlers.templateBytes(entryId);
    }
    throw ArgumentError('Modulo import non configurato: $entryId');
  }

  static Future<bool> downloadTemplate({
    required String entryId,
    required String pageName,
  }) async {
    final bytes = templateBytesFor(entryId);
    return ExcelExportHelper.saveAndReveal(
      pageName: pageName,
      bytes: bytes,
    );
  }

  static Future<DataImportResult> runImport({
    required BuildContext context,
    required DataImportHubEntry entry,
    required Uint8List bytes,
    required String fileName,
    int? userId,
  }) async {
    final id = entry.id;
    if (_masterIds.contains(id)) {
      return DataImportMasterHandlers.runImport(
        context: context,
        id: id,
        bytes: bytes,
      );
    }
    if (_posIds.contains(id)) {
      return DataImportPosHandlers.runImport(
        context: context,
        id: id,
        bytes: bytes,
        fileName: fileName,
        userId: userId,
      );
    }
    if (id == 'tesserini') {
      return DataImportTesseriniHandler.runImport(context: context, bytes: bytes);
    }
    if (_logisticaIds.contains(id)) {
      return DataImportLogisticaHandlers.runImport(
        context: context,
        id: id,
        bytes: bytes,
      );
    }
    if (_dpiIds.contains(id)) {
      return DataImportDpiHandlers.runImport(
        context: context,
        id: id,
        bytes: bytes,
      );
    }
    if (_formazioneIds.contains(id)) {
      return DataImportFormazioneHandlers.runImport(
        context: context,
        id: id,
        bytes: bytes,
      );
    }
    return const DataImportResult(
      message: 'Import non disponibile per questo modulo.',
      errors: 1,
    );
  }

  static Future<DataImportResult?> pickFileAndImport({
    required BuildContext context,
    required DataImportHubEntry entry,
    int? userId,
  }) async {
    final extensions = entry.id == 'pos_dipendenti_lista'
        ? <String>['xlsx', 'xls', 'docx']
        : <String>['xlsx', 'xls'];
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'Excel', extensions: extensions),
      ],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;
    return runImport(
      context: context,
      entry: entry,
      bytes: bytes,
      fileName: file.name,
      userId: userId,
    );
  }

  static const _masterIds = {
    'master_commesse',
    'master_stazioni',
    'master_aeroporti',
    'master_strutture',
    'master_strutture_dlgs',
    'personale',
  };

  static const _posIds = {
    'pos_dipendenti_lista',
    'pos_mdo_ferroviari_lista',
    'pos_mezzi_stradali_lista',
    'pos_mdo_proprieta_lista',
  };

  static const _logisticaIds = {
    'estintori',
    'box',
    'mdo_ferroviari',
    'mdo_proprieta',
    'mezzi_stradali',
    'attrezzature',
    'casette_ps',
    'multicard',
    'noleggio',
  };

  static const _formazioneIds = {
    'formazione_dlgs',
    'formazione_rfi',
    'formazione_rfi_strutture',
  };

  static const _dpiIds = {
    'dpi_report',
    'dpi_categorie',
    'dpi_terza_categoria',
    'vestiario_assegnazione',
    'vestiario_riepilogo',
    'vestiario_fabbisogno',
    'vestiario_inventario',
  };

  static String formatResultMessage(DataImportResult result) {
    final parts = <String>[result.message];
    if (result.added > 0) parts.add('${result.added} inseriti');
    if (result.updated > 0) parts.add('${result.updated} aggiornati');
    if (result.skipped > 0) parts.add('${result.skipped} saltati');
    if (result.errors > 0) parts.add('${result.errors} errori');
    return parts.join(' · ');
  }
}
