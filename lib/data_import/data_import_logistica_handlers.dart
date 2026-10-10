import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pos_commessa_dipendente_service.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/simple_excel_table_io.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportLogisticaHandlers {
  DataImportLogisticaHandlers._();

  static final _supa = SupabaseService.client;

  static Uint8List templateBytes(String id) {
    switch (id) {
      case 'estintori':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Estintori',
          headers: const [
            'Cod. interno',
            'Tipologia',
            'Numero',
            'Matricola',
            'Luogo',
            'Posizione GPS',
            'Carica KG/L',
            'Anno produzione',
            'Potere estinguente',
            'Scadenza controllo semestrale',
            'Scadenza revisione',
            'Scadenza collaudo',
            'Scadenza omologazione',
            'Richiesta sostituzione',
            'Commessa',
            'Note',
          ],
          exampleRows: const [
            [
              'EST-001',
              'Polvere',
              '1',
              'MAT123',
              'BOX A1',
              '45.46, 9.19',
              '6',
              '2020',
              '34A',
              '06/2026',
              '06/2027',
              '06/2028',
              '06/2029',
              'NO',
              'MLD-001',
              '',
            ],
          ],
        );
      case 'box':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Logistica_BOX',
          headers: const [
            'Numero interno',
            'Tipologia',
            'Commessa',
            'Ubicazione',
            'Posizione GPS',
            'Latitudine',
            'Longitudine',
            'Stato',
            'Targa stato',
            'Check eseguito',
            'Note',
          ],
          exampleRows: const [
            [
              'BOX-01',
              'Standard',
              'MLD-001',
              'Cantiere A',
              '45.46, 9.19',
              '45.46',
              '9.19',
              'OK',
              'VERDE',
              'SI',
              '',
            ],
          ],
        );
      case 'mdo_ferroviari':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'MDO_Ferroviari',
          headers: const [
            'Matricola interna',
            'Targa RFI',
            'Descrizione',
            'Commessa',
            'Ubicazione',
            'Note',
          ],
          exampleRows: const [
            ['MDO-001', 'RFI123', 'Carrello elevatore', 'MLD-001', 'Deposito', ''],
          ],
        );
      case 'mdo_proprieta':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'MDO_Proprieta',
          headers: const [
            'Codifica',
            'Targa/Matricola',
            'Descrizione',
            'Proprietà/Noleggio',
            'Commessa',
            'Note',
          ],
          exampleRows: const [
            ['P-001', 'AB123CD', 'Escavatore', 'PROPRIETÀ', 'MLD-001', ''],
          ],
        );
      case 'mezzi_stradali':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Mezzi_Stradali',
          headers: const [
            'Targa',
            'Modello',
            'Definizione classe',
            'Proprietà/Noleggio',
            'Note',
          ],
          exampleRows: const [
            ['AB123CD', 'Fiat Ducato', 'N1', 'PROPRIETÀ', ''],
          ],
        );
      case 'attrezzature':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Attrezzature',
          headers: const [
            'Codice',
            'Descrizione',
            'Commessa',
            'Ubicazione',
            'Note',
          ],
          exampleRows: const [
            ['ATT-01', 'Trapano', 'MLD-001', 'BOX 1', ''],
          ],
        );
      case 'casette_ps':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Casette_PS',
          headers: const [
            'Codice',
            'Ubicazione',
            'Commessa',
            'Posizione GPS',
            'Note',
          ],
          exampleRows: const [
            ['PS-01', 'BOX A', 'MLD-001', '45.46, 9.19', ''],
          ],
        );
      case 'multicard':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Multicard',
          headers: const [
            'Numero carta',
            'Intestatario',
            'PIN',
            'Note',
          ],
          exampleRows: const [
            ['1234567890123456', 'Mario Rossi', '', ''],
          ],
        );
      case 'noleggio':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Noleggio',
          headers: const [
            'Descrizione',
            'Fornitore',
            'Commessa',
            'Targa',
            'Data inizio',
            'Data fine',
            'Note',
          ],
          exampleRows: const [
            ['Furgone 35q', 'Noleggio SPA', 'MLD-001', 'XY999ZZ', '01/01/2026', '31/12/2026', ''],
          ],
        );
      default:
        throw ArgumentError('Modulo logistica sconosciuto: $id');
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

    final commesse = await PosCommessaDipendenteService.loadCommesseAttive();
    final byName = <String, String>{
      for (final e in commesse.entries) e.value.trim().toUpperCase(): e.key,
    };

    switch (id) {
      case 'estintori':
        return _importEstintori(rows, byName);
      case 'box':
        return _importBox(rows, byName);
      case 'mdo_ferroviari':
        return _importMdoFerroviari(rows, byName);
      case 'mdo_proprieta':
        return _importMdoProprieta(rows, byName);
      case 'mezzi_stradali':
        return _importMezziStradali(rows);
      case 'attrezzature':
        return _importAttrezzature(rows, byName);
      case 'casette_ps':
        return _importCasettePs(rows, byName);
      case 'multicard':
        return _importMulticard(rows);
      case 'noleggio':
        return _importNoleggio(rows, byName);
      default:
        throw ArgumentError('Modulo logistica sconosciuto: $id');
    }
  }

  static String? _commessaId(
    Map<String, String> byName,
    String? code,
  ) {
    if (code == null || code.trim().isEmpty) return null;
    return byName[code.trim().toUpperCase()];
  }

  static Future<DataImportResult> _importEstintori(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('estintori').insert({
          'codice_interno': SimpleExcelTableIo.rowValue(row, const ['Cod. interno']),
          'tipo': SimpleExcelTableIo.rowValue(row, const ['Tipologia']),
          'numero_estintore': SimpleExcelTableIo.rowValue(row, const ['Numero']),
          'matricola': SimpleExcelTableIo.rowValue(row, const ['Matricola']),
          'ubicazione': SimpleExcelTableIo.rowValue(row, const ['Luogo', 'Ubicazione']),
          'posizione_gps': SimpleExcelTableIo.rowValue(row, const ['Posizione GPS']),
          'carica_kg_l': SimpleExcelTableIo.rowValue(row, const ['Carica KG/L']),
          'anno_produzione': SimpleExcelTableIo.rowValue(row, const ['Anno produzione']),
          'potere_estinguente': SimpleExcelTableIo.rowValue(row, const ['Potere estinguente']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'commessa_id': _commessaId(byName, commessaName),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import estintori completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importBox(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        final gpsText =
            SimpleExcelTableIo.rowValue(row, const ['Posizione GPS']) ?? '';
        final latRaw =
            SimpleExcelTableIo.rowValue(row, const ['Latitudine']);
        final lonRaw =
            SimpleExcelTableIo.rowValue(row, const ['Longitudine']);
        final fromCols = <String, dynamic>{
          'latitudine': latRaw,
          'longitudine': lonRaw,
          'posizione_gps': gpsText,
        };
        final coords = mdoGpsCoordsFromRow(fromCols);
        final posizione = (gpsText.trim().isNotEmpty)
            ? gpsText.trim()
            : (coords == null
                ? null
                : formatGpsCoordsText(coords.$1, coords.$2));
        await _supa.from('logistica_box').insert({
          'numero_interno':
              SimpleExcelTableIo.rowValue(row, const ['Numero interno']),
          'tipologia': SimpleExcelTableIo.rowValue(row, const ['Tipologia']),
          'commessa_id': _commessaId(byName, commessaName),
          'ubicazione': SimpleExcelTableIo.rowValue(row, const ['Ubicazione']),
          'posizione_gps': posizione,
          'latitudine': coords?.$1,
          'longitudine': coords?.$2,
          'stato': SimpleExcelTableIo.rowValue(row, const ['Stato']),
          'targa_stato': SimpleExcelTableIo.rowValue(row, const ['Targa stato']),
          'check_eseguito': SimpleExcelTableIo.parseBool(
            SimpleExcelTableIo.rowValue(row, const ['Check eseguito']),
          ),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import BOX completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importMdoFerroviari(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('logistica_mdo_ferroviari').insert({
          'matricola_interna': SimpleExcelTableIo.rowValue(row, const ['Matricola interna']),
          'targa_rfi': SimpleExcelTableIo.rowValue(row, const ['Targa RFI']),
          'descrizione_mezzo': SimpleExcelTableIo.rowValue(row, const ['Descrizione']),
          'ubicazione': SimpleExcelTableIo.rowValue(row, const ['Ubicazione']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'commessa_id': _commessaId(byName, commessaName),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import MDO ferroviari completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importMdoProprieta(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('logistica_mdo_proprieta').insert({
          'codifica': SimpleExcelTableIo.rowValue(row, const ['Codifica']),
          'targa_matricola': SimpleExcelTableIo.rowValue(row, const ['Targa/Matricola']),
          'descrizione': SimpleExcelTableIo.rowValue(row, const ['Descrizione']),
          'proprieta_noleggio': SimpleExcelTableIo.rowValue(row, const ['Proprietà/Noleggio']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'commessa_id': _commessaId(byName, commessaName),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import MDO proprietà completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importMezziStradali(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        await _supa.from('logistica_mezzi_stradali').insert({
          'targa': SimpleExcelTableIo.rowValue(row, const ['Targa']),
          'modello': SimpleExcelTableIo.rowValue(row, const ['Modello']),
          'definizione_classe': SimpleExcelTableIo.rowValue(row, const ['Definizione classe']),
          'proprieta_noleggio': SimpleExcelTableIo.rowValue(row, const ['Proprietà/Noleggio']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import mezzi stradali completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importAttrezzature(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('logistica_attrezzature').insert({
          'codice': SimpleExcelTableIo.rowValue(row, const ['Codice']),
          'descrizione': SimpleExcelTableIo.rowValue(row, const ['Descrizione']),
          'ubicazione': SimpleExcelTableIo.rowValue(row, const ['Ubicazione']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'commessa_id': _commessaId(byName, commessaName),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import attrezzature completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importCasettePs(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('logistica_casette_ps').insert({
          'codice': SimpleExcelTableIo.rowValue(row, const ['Codice']),
          'ubicazione': SimpleExcelTableIo.rowValue(row, const ['Ubicazione']),
          'posizione_gps': SimpleExcelTableIo.rowValue(row, const ['Posizione GPS']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'commessa_id': _commessaId(byName, commessaName),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import cassette P.S. completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importMulticard(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        await _supa.from('logistica_multicard').insert({
          'numero_carta': SimpleExcelTableIo.rowValue(row, const ['Numero carta']),
          'intestatario': SimpleExcelTableIo.rowValue(row, const ['Intestatario']),
          'pin': SimpleExcelTableIo.rowValue(row, const ['PIN']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import multicard completato.', added: added, errors: errors);
  }

  static Future<DataImportResult> _importNoleggio(
    List<Map<String, String>> rows,
    Map<String, String> byName,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      try {
        final commessaName = SimpleExcelTableIo.rowValue(row, const ['Commessa']);
        await _supa.from('logistica_noleggio').insert({
          'descrizione': SimpleExcelTableIo.rowValue(row, const ['Descrizione']),
          'fornitore': SimpleExcelTableIo.rowValue(row, const ['Fornitore']),
          'targa': SimpleExcelTableIo.rowValue(row, const ['Targa']),
          'commessa_testo': commessaName,
          'commessa_id': _commessaId(byName, commessaName),
          'data_inizio': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data inizio']),
          ),
          'data_fine': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const ['Data fine']),
          ),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
          'active': true,
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(message: 'Import noleggio completato.', added: added, errors: errors);
  }
}
