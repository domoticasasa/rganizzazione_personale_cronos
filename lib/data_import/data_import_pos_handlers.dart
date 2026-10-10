import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pos_commessa_dipendente_service.dart';
import '../services/pos_commessa_mdo_proprieta_service.dart';
import '../services/pos_commessa_mdo_service.dart';
import '../services/pos_commessa_mezzi_stradali_service.dart';
import '../services/pos_maestranze_import_parser.dart';
import '../services/pos_mdo_ferroviari_import_parser.dart';
import '../services/pos_mdo_proprieta_import_parser.dart';
import '../services/pos_mezzi_stradali_import_parser.dart';
import '../services/supabase_service.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportPosHandlers {
  DataImportPosHandlers._();

  static Uint8List templateBytes(String id) {
    switch (id) {
      case 'pos_dipendenti_lista':
        return PosMaestranzeImportParser.buildTemplateExcelBytes();
      case 'pos_mdo_ferroviari_lista':
        return PosMdoFerroviariImportParser.buildTemplateExcelBytes();
      case 'pos_mezzi_stradali_lista':
        return PosMezziStradaliImportParser.buildTemplateExcelBytes();
      case 'pos_mdo_proprieta_lista':
        return PosMdoProprietaImportParser.buildTemplateExcelBytes();
      default:
        throw ArgumentError('Modulo POS sconosciuto: $id');
    }
  }

  static Future<DataImportResult> runImport({
    required BuildContext context,
    required String id,
    required Uint8List bytes,
    required String fileName,
    int? userId,
  }) async {
    final commessaId = await pickCommessaForImport(context);
    if (commessaId == null || !context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }

    final userUuid = await _resolveUserUuid(userId);
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }

    switch (id) {
      case 'pos_dipendenti_lista':
        return _importDipendenti(
          context: context,
          bytes: bytes,
          fileName: fileName,
          commessaId: commessaId,
          userUuid: userUuid,
        );
      case 'pos_mdo_ferroviari_lista':
        return _importMdoFerroviari(
          context: context,
          bytes: bytes,
          fileName: fileName,
          commessaId: commessaId,
          userUuid: userUuid,
        );
      case 'pos_mezzi_stradali_lista':
        return _importMezziStradali(
          context: context,
          bytes: bytes,
          fileName: fileName,
          commessaId: commessaId,
          userUuid: userUuid,
        );
      case 'pos_mdo_proprieta_lista':
        return _importMdoProprieta(
          context: context,
          bytes: bytes,
          fileName: fileName,
          commessaId: commessaId,
          userUuid: userUuid,
        );
      default:
        throw ArgumentError('Modulo POS sconosciuto: $id');
    }
  }

  static Future<String?> _resolveUserUuid(int? userId) async {
    final auth = SupabaseService.client.auth.currentUser;
    if (auth != null) {
      final row = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('auth_id', auth.id)
          .maybeSingle();
      final u = row?['id_uuid']?.toString();
      if (u != null && u.isNotEmpty) return u;
    }
    if (userId == null) return null;
    final row = await SupabaseService.client
        .from('users')
        .select('id_uuid')
        .eq('id', userId)
        .maybeSingle();
    return row?['id_uuid']?.toString();
  }

  static Future<DataImportResult> _importDipendenti({
    required BuildContext context,
    required Uint8List bytes,
    required String fileName,
    required String commessaId,
    required String? userUuid,
  }) async {
    final parsed = await PosMaestranzeImportParser.parseFile(
      fileName: fileName,
      bytes: bytes,
    );
    if (parsed.righe.isEmpty) {
      return DataImportResult(
        message: parsed.avviso ?? 'File senza righe utili.',
        errors: 1,
      );
    }
    final personale = await PosCommessaDipendenteService.loadPersonaleAttivo();
    final previews = PosCommessaDipendenteService.previewImportMatches(
      righe: parsed.righe,
      personaleById: personale,
    );
    final matched = previews.where((p) => p.matched).toList();
    final skipped = previews.length - matched.length;
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import POS dipendenti',
      body: 'Righe nel file: ${parsed.righe.length}\n'
          'Abbinati: ${matched.length}\n'
          'Non abbinati (saltati): $skipped\n\n'
          'Procedere con l\'import degli abbinati?',
    );
    if (!ok || !context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final result = await PosCommessaDipendenteService.applyImport(
      commessaId: commessaId,
      previews: matched,
      dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
      userUuid: userUuid,
      listaMldKey: '',
    );
    return DataImportResult(
      message: 'Import completato.',
      added: result.added,
      updated: result.updated,
      skipped: result.skipped + skipped,
    );
  }

  static Future<DataImportResult> _importMdoFerroviari({
    required BuildContext context,
    required Uint8List bytes,
    required String fileName,
    required String commessaId,
    required String? userUuid,
  }) async {
    final parsed = await PosMdoFerroviariImportParser.parseFile(
      fileName: fileName,
      bytes: bytes,
    );
    if (parsed.righe.isEmpty) {
      return DataImportResult(
        message: parsed.avviso ?? 'File senza righe utili.',
        errors: 1,
      );
    }
    final mdoById = await PosCommessaMdoService.loadMdoAttivi();
    final previews = PosCommessaMdoService.previewImportMatches(
      righe: parsed.righe,
      mdoById: mdoById,
    );
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import MdO ferroviari POS',
      body: 'Righe: ${parsed.righe.length} · Abbinati automaticamente: '
          '${previews.where((p) => p.matched).length}\n\n'
          'Le righe senza abbinamento (es. noleggio) verranno importate con i dati del file.\n\n'
          'Procedere?',
    );
    if (!ok || !context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final result = await PosCommessaMdoService.applyImport(
      commessaId: commessaId,
      previews: previews,
      dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
      userUuid: userUuid,
    );
    return DataImportResult(
      message: 'Import completato.',
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
    );
  }

  static Future<DataImportResult> _importMezziStradali({
    required BuildContext context,
    required Uint8List bytes,
    required String fileName,
    required String commessaId,
    required String? userUuid,
  }) async {
    final parsed = await PosMezziStradaliImportParser.parseFile(
      fileName: fileName,
      bytes: bytes,
    );
    if (parsed.righe.isEmpty) {
      return DataImportResult(
        message: parsed.avviso ?? 'File senza righe utili.',
        errors: 1,
      );
    }
    final mezziById = await PosCommessaMezziStradaliService.loadMezziAttivi();
    final previews = PosCommessaMezziStradaliService.previewImportMatches(
      righe: parsed.righe,
      mezziById: mezziById,
    );
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import mezzi stradali POS',
      body: 'Righe: ${parsed.righe.length} · Abbinati automaticamente: '
          '${previews.where((p) => p.matched).length}\n\n'
          'Le righe senza abbinamento verranno importate con i dati del file.\n\n'
          'Procedere?',
    );
    if (!ok || !context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final result = await PosCommessaMezziStradaliService.applyImport(
      commessaId: commessaId,
      previews: previews,
      dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
      userUuid: userUuid,
    );
    return DataImportResult(
      message: 'Import completato.',
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
    );
  }

  static Future<DataImportResult> _importMdoProprieta({
    required BuildContext context,
    required Uint8List bytes,
    required String fileName,
    required String commessaId,
    required String? userUuid,
  }) async {
    final parsed = await PosMdoProprietaImportParser.parseFile(
      fileName: fileName,
      bytes: bytes,
    );
    if (parsed.righe.isEmpty) {
      return DataImportResult(
        message: parsed.avviso ?? 'File senza righe utili.',
        errors: 1,
      );
    }
    final mdoById = await PosCommessaMdoProprietaService.loadMdoAttiviPerImport();
    final previews = PosCommessaMdoProprietaService.previewImportMatches(
      righe: parsed.righe,
      mdoById: mdoById,
    );
    if (!context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final ok = await confirmImportSummary(
      context,
      title: 'Conferma import MdO proprietà POS',
      body: 'Righe: ${parsed.righe.length} · Abbinati automaticamente: '
          '${previews.where((p) => p.matched).length}\n\n'
          'Le righe senza abbinamento (es. noleggio) verranno importate con i dati del file.\n\n'
          'Procedere?',
    );
    if (!ok || !context.mounted) {
      return const DataImportResult(message: 'Import annullato.');
    }
    final result = await PosCommessaMdoProprietaService.applyImport(
      commessaId: commessaId,
      previews: previews,
      dataUltimoAggiornamento: parsed.dataUltimoAggiornamento,
      userUuid: userUuid,
    );
    return DataImportResult(
      message: 'Import completato.',
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
    );
  }
}
