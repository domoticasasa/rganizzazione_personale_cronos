import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/numero_tesserino_service.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/simple_excel_table_io.dart';
import 'data_import_commessa_picker.dart';
import 'data_import_hub_entry.dart';

abstract final class DataImportMasterHandlers {
  DataImportMasterHandlers._();

  static final _supa = SupabaseService.client;

  static Uint8List templateBytes(String id) {
    switch (id) {
      case 'master_commesse':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Commesse',
          titleRow: 'Compila e importa. Il codice commessa deve essere univoco.',
          headers: const [
            'Codice commessa',
            'Attiva (SI/NO)',
            'PM',
            'DT',
            'DT 2',
            'CIG',
            'CIG derivato',
            'CUP',
            'Cliente',
            'Latitudine',
            'Longitudine',
          ],
          exampleRows: const [
            [
              'MLD-001',
              'SI',
              'Mario Rossi',
              'Luigi Verdi',
              '',
              '1234567890',
              '',
              'ABCD1234',
              'Cliente SPA',
              '45.4642',
              '9.1900',
            ],
          ],
        );
      case 'master_stazioni':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Stazioni',
          headers: const ['Nome stazione', 'Attiva (SI/NO)'],
          exampleRows: const [
            ['Milano Centrale', 'SI'],
          ],
        );
      case 'master_aeroporti':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Aeroporti',
          headers: const ['Nome aeroporto', 'Attivo (SI/NO)'],
          exampleRows: const [
            ['Milano Malpensa', 'SI'],
          ],
        );
      case 'master_strutture':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Strutture',
          headers: const [
            'Nome',
            'Tipo (hotel/ristorante/altro)',
            'Indirizzo',
            'Telefono',
            'Latitudine',
            'Longitudine',
            'Attiva (SI/NO)',
          ],
          exampleRows: const [
            [
              'Hotel Roma',
              'hotel',
              'Via Roma 1, Roma',
              '0612345678',
              '41.9028',
              '12.4964',
              'SI',
            ],
          ],
        );
      case 'master_strutture_dlgs':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Strutture_DLGS',
          headers: const ['Nome struttura', 'Indirizzo', 'Note'],
          exampleRows: const [
            ['Sede formazione Milano', 'Via Formazione 10', ''],
          ],
        );
      case 'personale':
        return SimpleExcelTableIo.buildTemplate(
          sheetName: 'Dipendenti',
          titleRow:
              'Inserisce solo anagrafica (senza login). Cognome e Nome in colonne separate.',
          headers: const [
            'Cognome',
            'Nome',
            'Email',
            'Telefono',
            'Matricola',
            'Ruolo in azienda',
            'Data assunzione (gg/mm/aaaa)',
            'Data nascita (gg/mm/aaaa)',
            'Attivo (SI/NO)',
          ],
          exampleRows: const [
            [
              'Rossi',
              'Mario',
              'mario.rossi@azienda.it',
              '3331234567',
              'A001',
              'Operaio',
              '01/03/2020',
              '15/06/1985',
              'SI',
            ],
          ],
        );
      default:
        throw ArgumentError('Modulo master sconosciuto: $id');
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
        message: 'File senza righe dati dopo l\'intestazione.',
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
      case 'master_commesse':
        return _importCommesse(rows);
      case 'master_stazioni':
        return _importStazioni(rows);
      case 'master_aeroporti':
        return _importAeroporti(rows);
      case 'master_strutture':
        return _importStrutture(rows);
      case 'master_strutture_dlgs':
        return _importStruttureDlgs(rows);
      case 'personale':
        return _importPersonale(rows);
      default:
        throw ArgumentError('Modulo master sconosciuto: $id');
    }
  }

  static Future<DataImportResult> _importCommesse(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var updated = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final code = (SimpleExcelTableIo.rowValue(row, const [
                'Codice commessa',
                'Commessa',
                'Nome',
              ]) ??
              '')
          .trim()
          .toUpperCase();
      if (code.isEmpty) {
        skipped++;
        continue;
      }
      try {
        final active = SimpleExcelTableIo.parseBool(
          SimpleExcelTableIo.rowValue(row, const ['Attiva (SI/NO)', 'Attiva']),
        );
        final existing = await _supa
            .from('commesse')
            .select('id_uuid')
            .eq('nome', code)
            .maybeSingle();
        final gpsLat = SimpleExcelTableIo.rowValue(row, const ['Latitudine']);
        final gpsLng = SimpleExcelTableIo.rowValue(row, const ['Longitudine']);
        final payload = <String, dynamic>{
          'nome': code,
          'active': active,
          'pm': SimpleExcelTableIo.rowValue(row, const ['PM']),
          'dt': SimpleExcelTableIo.rowValue(row, const ['DT']),
          'dt2': SimpleExcelTableIo.rowValue(row, const ['DT 2', 'DT2']),
          if (gpsLat != null) 'latitudine': double.tryParse(gpsLat),
          if (gpsLng != null) 'longitudine': double.tryParse(gpsLng),
        };
        String idUuid;
        if (existing != null) {
          idUuid = existing['id_uuid'].toString();
          await _supa.from('commesse').update(payload).eq('id_uuid', idUuid);
          updated++;
        } else {
          final ins = await _supa
              .from('commesse')
              .insert(payload)
              .select('id_uuid')
              .single();
          idUuid = ins['id_uuid'].toString();
          added++;
        }
        final cig = SimpleExcelTableIo.rowValue(row, const ['CIG']) ?? '';
        final cigD = SimpleExcelTableIo.rowValue(row, const ['CIG derivato']) ?? '';
        final cup = SimpleExcelTableIo.rowValue(row, const ['CUP']) ?? '';
        final cliente = SimpleExcelTableIo.rowValue(row, const ['Cliente']) ?? '';
        if (cig.isNotEmpty || cup.isNotEmpty || cliente.isNotEmpty) {
          await _supa.from('commesse_cig_cup').upsert(
            <String, dynamic>{
              'commessa_id_uuid': idUuid,
              'commessa_code': code,
              'cig': cig.isEmpty ? null : cig,
              'cig_derivato': cigD.isEmpty ? null : cigD,
              'cup': cup.isEmpty ? null : cup,
              'cliente': cliente.isEmpty ? null : cliente,
              'active': active,
            },
            onConflict: 'commessa_id_uuid',
          );
        }
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import commesse completato.',
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importStazioni(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome stazione', 'Nome']);
      if (nome == null || nome.isEmpty) continue;
      try {
        final attiva = SimpleExcelTableIo.parseBool(
          SimpleExcelTableIo.rowValue(row, const ['Attiva (SI/NO)', 'Attiva']),
        );
        await _supa.from('stazioni').insert({'nome': nome, 'attiva': attiva});
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import stazioni completato.',
      added: added,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importAeroporti(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome aeroporto', 'Nome']);
      if (nome == null || nome.isEmpty) continue;
      try {
        final attiva = SimpleExcelTableIo.parseBool(
          SimpleExcelTableIo.rowValue(row, const ['Attivo (SI/NO)', 'Attiva']),
        );
        await _supa.from('aeroporti').insert({'nome': nome, 'attiva': attiva});
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import aeroporti completato.',
      added: added,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importStrutture(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome']);
      if (nome == null || nome.isEmpty) continue;
      try {
        final lat = SimpleExcelTableIo.rowValue(row, const ['Latitudine']);
        final lng = SimpleExcelTableIo.rowValue(row, const ['Longitudine']);
        await _supa.from('structures').insert({
          'name': nome,
          'type': SimpleExcelTableIo.rowValue(row, const ['Tipo']) ?? 'hotel',
          'address': SimpleExcelTableIo.rowValue(row, const ['Indirizzo']),
          'phone': SimpleExcelTableIo.rowValue(row, const ['Telefono']),
          'active': SimpleExcelTableIo.parseBool(
            SimpleExcelTableIo.rowValue(row, const ['Attiva (SI/NO)']),
          ),
          if (lat != null) 'latitudine': double.tryParse(lat),
          if (lng != null) 'longitudine': double.tryParse(lng),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import strutture completato.',
      added: added,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importStruttureDlgs(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var errors = 0;
    for (final row in rows) {
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome struttura', 'Nome']);
      if (nome == null || nome.isEmpty) continue;
      try {
        await _supa.from('formazione_dlgs_strutture').insert({
          'nome': nome,
          'indirizzo': SimpleExcelTableIo.rowValue(row, const ['Indirizzo']),
          'note': SimpleExcelTableIo.rowValue(row, const ['Note']),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import strutture D.Lgs. completato.',
      added: added,
      errors: errors,
    );
  }

  static Future<DataImportResult> _importPersonale(
    List<Map<String, String>> rows,
  ) async {
    var added = 0;
    var skipped = 0;
    var errors = 0;
    for (final row in rows) {
      final cognome = SimpleExcelTableIo.rowValue(row, const ['Cognome']) ?? '';
      final nome = SimpleExcelTableIo.rowValue(row, const ['Nome']) ?? '';
      if (cognome.isEmpty && nome.isEmpty) {
        skipped++;
        continue;
      }
      final fullName = '$nome $cognome'.trim();
      try {
        final numero = await NumeroTesserinoService.allocate(
          supa: _supa,
          cognome: cognome,
          nome: nome,
        );
        await _supa.from('personale').insert({
          'full_name': fullName,
          'numero_tesserino': numero,
          'email': SimpleExcelTableIo.rowValue(row, const ['Email']),
          'telefono': SimpleExcelTableIo.rowValue(row, const ['Telefono']),
          'matricola': SimpleExcelTableIo.rowValue(row, const ['Matricola']),
          'ruolo_aziendale': SimpleExcelTableIo.rowValue(
            row,
            const ['Ruolo in azienda', 'Ruolo aziendale', 'Incarico'],
          ),
          'data_assunzione': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const [
              'Data assunzione (gg/mm/aaaa)',
              'Data assunzione',
            ]),
          ),
          'data_nascita': parseFlexibleDateToIsoDate(
            SimpleExcelTableIo.rowValue(row, const [
              'Data nascita (gg/mm/aaaa)',
              'Data nascita',
            ]),
          ),
          'active': SimpleExcelTableIo.parseBool(
            SimpleExcelTableIo.rowValue(row, const ['Attivo (SI/NO)', 'Attivo']),
          ),
        });
        added++;
      } catch (_) {
        errors++;
      }
    }
    return DataImportResult(
      message: 'Import dipendenti completato.',
      added: added,
      skipped: skipped,
      errors: errors,
    );
  }
}
