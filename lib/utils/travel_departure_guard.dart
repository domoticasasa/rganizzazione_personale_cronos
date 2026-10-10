import 'package:flutter/material.dart';

import 'date_formatters.dart';

/// Combina data calendario + orario `HH:mm` come wall-clock Italia.
DateTime? combineItalyDateAndTime(DateTime date, String orarioHHmm) {
  final parts = orarioHHmm.trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return DateTime(date.year, date.month, date.day, h, m);
}

String _fmtDt(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString().padLeft(4, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy $hh:$min';
}

/// Messaggio errore se partenza (e opz. ritorno) è già trascorsa; altrimenti `null`.
String? pastTravelDepartureMessage({
  required DateTime dataPartenza,
  required String orarioPartenzaHHmm,
  DateTime? dataRitorno,
  String? orarioRitornoHHmm,
  bool andataRitorno = false,
  required String tipoViaggioLabel,
}) {
  final now = italyNow();
  final partenza = combineItalyDateAndTime(dataPartenza, orarioPartenzaHHmm);
  if (partenza == null) {
    return 'Orario di partenza non valido.';
  }
  if (!partenza.isAfter(now)) {
    return 'Non è più possibile richiedere questo $tipoViaggioLabel:\n\n'
        'la partenza del ${_fmtDt(partenza)} è già trascorsa '
        '(ora attuale: ${_fmtDt(now)}).\n\n'
        'Scegli una data/orario futura e riprova.';
  }

  if (andataRitorno) {
    final orarioR = (orarioRitornoHHmm ?? '').trim();
    if (dataRitorno == null || orarioR.isEmpty) return null;
    final ritorno = combineItalyDateAndTime(dataRitorno, orarioR);
    if (ritorno == null) {
      return 'Orario di ritorno non valido.';
    }
    if (!ritorno.isAfter(now)) {
      return 'Non è più possibile richiedere questo $tipoViaggioLabel:\n\n'
          'il ritorno del ${_fmtDt(ritorno)} è già trascorso '
          '(ora attuale: ${_fmtDt(now)}).\n\n'
          'Scegli una data/orario futura e riprova.';
    }
    if (!ritorno.isAfter(partenza)) {
      return 'La data/orario di ritorno deve essere successiva alla partenza '
          '(partenza ${_fmtDt(partenza)}, ritorno ${_fmtDt(ritorno)}).';
    }
  }
  return null;
}

/// Popup bloccante: restituisce dopo chiusura. Non proseguire con l'invio.
Future<void> showPastTravelDepartureDialog(
  BuildContext context,
  String message,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Richiesta non inviabile'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
