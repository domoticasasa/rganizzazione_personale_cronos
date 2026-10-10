import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../utils/date_formatters.dart';

/// Nome fisso in Mod.RFP_03 sotto «Per accettazione» (firma datore).
const kRfp03DatoreLavoroNome = 'LUCA VIVIAN';

String rfp03SafeString(dynamic v) => (v ?? '').toString().trim();

String rfp03TipoLabel(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'FERIE':
      return 'Ferie';
    case 'PERMESSO':
      return 'Permesso';
    case 'MALATTIA':
      return 'Malattia';
    case 'INFORTUNIO':
      return 'Infortunio';
    default:
      return tipo;
  }
}

int rfp03GiorniInclusivi(String isoDal, String isoAl) {
  final dal = DateTime.tryParse(isoDal);
  final al = DateTime.tryParse(isoAl);
  if (dal == null || al == null) return 1;
  return al.difference(dal).inDays + 1;
}

String rfp03FormatTime(dynamic v) {
  final raw = rfp03SafeString(v);
  if (raw.isEmpty) return '';
  final parts = raw.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  return raw;
}

String rfp03FormatOre(dynamic v) {
  if (v == null) return '';
  if (v is num) {
    final d = v.toDouble();
    if (d <= 0) return '';
    if (d == d.roundToDouble()) return '${d.toInt()}';
    return d.toStringAsFixed(1);
  }
  final parsed = double.tryParse(v.toString().replaceAll(',', '.'));
  if (parsed == null || parsed <= 0) return '';
  if (parsed == parsed.roundToDouble()) return '${parsed.toInt()}';
  return parsed.toStringAsFixed(1);
}

Map<String, String> buildRfp03Payload({
  required Map<String, dynamic> row,
  required String approvatoreAdminLabel,
  required String dtLabel,
  String? adminComment,
}) {
  final dalIso = rfp03SafeString(row['data_dal']);
  final alIso = rfp03SafeString(row['prolungato_fino_al']).isNotEmpty
      ? rfp03SafeString(row['prolungato_fino_al'])
      : rfp03SafeString(row['data_al']);
  final dal = formatDateDdMmYyyy(dalIso);
  final al = formatDateDdMmYyyy(alIso);
  final richiestaData = formatDateDdMmYyyy(rfp03SafeString(row['created_at']));
  final nomeDip = rfp03SafeString(row['dipendente_nome']).isNotEmpty
      ? rfp03SafeString(row['dipendente_nome'])
      : 'Dipendente';
  final tipoRaw = rfp03SafeString(row['tipo_assenza']).toUpperCase();
  final tipo = rfp03TipoLabel(tipoRaw);
  final isPermesso = tipoRaw == 'PERMESSO';
  final isFerieOrPermesso = tipoRaw == 'FERIE' || isPermesso;
  final giorni = rfp03GiorniInclusivi(dalIso, alIso);

  final dalleOre = rfp03FormatTime(row['ora_inizio']);
  final alleOre = rfp03FormatTime(row['ora_fine']);
  var oreLabel = rfp03FormatOre(row['ore_permesso']);
  if (oreLabel.isEmpty && dalleOre.isNotEmpty && alleOre.isNotEmpty) {
    final a = _rfp03ParseMinutes(dalleOre);
    final b = _rfp03ParseMinutes(alleOre);
    if (a != null && b != null && b > a) {
      final h = (b - a) / 60.0;
      oreLabel = h == h.roundToDouble() ? '${h.toInt()}' : h.toStringAsFixed(1);
    }
  }

  final dataRiga = dal.isNotEmpty ? dal : richiestaData;

  final payload = <String, String>{
    'B13': 'Il Sottoscritto $nomeDip chiede autorizzazione a usufruire di:',
    // Riga riepilogo: DATA in F16, N° giorni in O16 (non sovrascrivere le etichette B16/K16).
    'F16': dataRiga,
    'O16': '$giorni',
    // Griglia valori (righe 18–19 del template).
    if (isPermesso && oreLabel.isNotEmpty) 'C18': oreLabel,
    if (isPermesso && dalleOre.isNotEmpty) 'F18': dalleOre,
    if (isPermesso && alleOre.isNotEmpty) 'I18': alleOre,
    'L18': '$giorni',
    'O18': dal,
    'R18': al,
    // Template ha ● rossi su D37–D40: lascia spunta solo sull'opzione scelta.
    'D37': isFerieOrPermesso ? '\u2713' : '',
    'D38': '',
    'D39': '',
    'D40': (!isFerieOrPermesso) ? '\u2713' : '',
    'E40': (!isFerieOrPermesso)
        ? 'Altro (specificare): $tipo'
        : 'Altro (specificare)',
    'C44': richiestaData.isEmpty
        ? 'Data richiesta: $dal'
        : 'Data richiesta: $richiestaData',
    // Template attuale: D49 = firma richiedente; N46 = «Per accettazione» (immagine firma).
    'D49': nomeDip,
    'N49': '',
  };
  final note = rfp03SafeString(adminComment).isNotEmpty
      ? rfp03SafeString(adminComment)
      : rfp03SafeString(row['note']);
  if (note.isNotEmpty) {
    // Area note template: merge D46:M46, wrap + altezza dedicata.
    payload['D46'] = 'Note:\n$note';
  }
  return payload;
}

int? _rfp03ParseMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

Future<Uint8List> buildAssenzaRfp03ExcelFallbackBytes({
  required Map<String, dynamic> row,
  required String approvatoreAdminLabel,
  required String dtLabel,
  String? adminComment,
}) async {
  final payload = buildRfp03Payload(
    row: row,
    approvatoreAdminLabel: approvatoreAdminLabel,
    dtLabel: dtLabel,
    adminComment: adminComment,
  );
  final excel = Excel.createExcel();
  // Non usare excel.rename()/delete(): su web falliscono con
  // "Cannot remove from an unmodifiable list" (liste archive/XML read-only).
  final sheet = excel[excel.tables.keys.first];

  sheet.appendRow(<String>['Campo', 'Valore']);
  sheet.appendRow(<String>[
    'Dipendente',
    rfp03SafeString(row['dipendente_nome']),
  ]);
  sheet.appendRow(<String>[
    'Tipo assenza',
    rfp03TipoLabel(rfp03SafeString(row['tipo_assenza'])),
  ]);
  sheet.appendRow(<String>[
    'Dal',
    formatDateDdMmYyyy(rfp03SafeString(row['data_dal'])),
  ]);
  sheet.appendRow(<String>[
    'Al',
    formatDateDdMmYyyy(
      rfp03SafeString(row['prolungato_fino_al']).isNotEmpty
          ? rfp03SafeString(row['prolungato_fino_al'])
          : rfp03SafeString(row['data_al']),
    ),
  ]);
  sheet.appendRow(<String>['Firma Datore Lavoro', kRfp03DatoreLavoroNome]);
  sheet.appendRow(<String>['Approvatore admin', '']);
  sheet.appendRow(<String>['Commento admin', rfp03SafeString(adminComment)]);
  sheet.appendRow(<String>['---', '---']);
  sheet.appendRow(<String>['Mappatura celle Mod.RFP_03', '']);
  for (final e in payload.entries) {
    sheet.appendRow(<String>[e.key, e.value]);
  }

  final out = excel.encode();
  if (out == null) {
    throw StateError('Impossibile generare il file Excel Mod.RFP_03.');
  }
  return Uint8List.fromList(out);
}
