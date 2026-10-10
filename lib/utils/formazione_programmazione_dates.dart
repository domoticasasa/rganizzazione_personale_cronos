import 'date_formatters.dart';

/// Data fine programmazione: `seconda_data` se impostata, altrimenti `prima_data`.
DateTime? programmazioneEndDate(
  dynamic primaData,
  dynamic secondaData,
) {
  final fine = parseDateOnly(secondaData) ?? parseDateOnly(primaData);
  return fine;
}

DateTime? parseDateOnly(dynamic v) {
  final iso = parseFlexibleDateToIsoDate((v ?? '').toString());
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

/// Visualizza intervallo programmazione; un solo giorno → una data.
String formatProgrammazioneDalAl(dynamic primaData, dynamic secondaData) {
  final dal = formatDateDdMmYyyy(primaData);
  if (dal.isEmpty) return '';
  final al = formatDateDdMmYyyy(secondaData);
  if (al.isEmpty || al == dal) return dal;
  return '$dal – $al';
}

/// Colonne data su `formazione_corsi` che vanno inviate come `null` per azzerare il DB.
const formazioneCorsiDatePayloadKeys = <String>{
  'data_attestato',
  'scadenza_attestato',
  'prima_data',
  'seconda_data',
};

/// Rimuove stringhe vuote dal payload ma conserva `null` espliciti sulle date
/// (se omessi, Supabase non cancella il valore precedente).
void finalizeFormazioneCorsiPayload(Map<String, dynamic> payload) {
  for (final key in formazioneCorsiDatePayloadKeys) {
    if (!payload.containsKey(key)) continue;
    final v = payload[key];
    if (v == null || (v is String && v.trim().isEmpty)) {
      payload[key] = null;
    }
  }
  payload.removeWhere((key, v) {
    if (formazioneCorsiDatePayloadKeys.contains(key)) return false;
    return v == null || (v is String && v.trim().isEmpty);
  });
}

/// Normalizza salvataggio programmazione (dal/al).
({String? primaIso, String? secondaIso, String? error}) normalizeProgrammazioneIso({
  required String dalText,
  required String alText,
}) {
  final dal = dalText.trim();
  final al = alText.trim();
  if (dal.isEmpty && al.isEmpty) {
    return (primaIso: null, secondaIso: null, error: null);
  }
  if (dal.isEmpty && al.isNotEmpty) {
    final isoAl = parseFlexibleDateToIsoDate(al);
    if (isoAl == null) {
      return (primaIso: null, secondaIso: null, error: 'Data programmazione «al» non valida.');
    }
    return (primaIso: isoAl, secondaIso: isoAl, error: null);
  }
  final isoDal = parseFlexibleDateToIsoDate(dal);
  if (isoDal == null) {
    return (primaIso: null, secondaIso: null, error: 'Data programmazione «dal» non valida.');
  }
  if (al.isEmpty) {
    return (primaIso: isoDal, secondaIso: null, error: null);
  }
  final isoAl = parseFlexibleDateToIsoDate(al);
  if (isoAl == null) {
    return (primaIso: null, secondaIso: null, error: 'Data programmazione «al» non valida.');
  }
  final dDal = parseDateOnly(isoDal)!;
  final dAl = parseDateOnly(isoAl)!;
  if (dAl.isBefore(dDal)) {
    return (
      primaIso: null,
      secondaIso: null,
      error: 'La data «al» non può essere precedente alla data «dal».',
    );
  }
  if (isoDal == isoAl) {
    return (primaIso: isoDal, secondaIso: isoDal, error: null);
  }
  return (primaIso: isoDal, secondaIso: isoAl, error: null);
}

/// Giorni fino all'inizio programmazione (negativo = già iniziato).
int? daysUntilProgrammazioneStart(dynamic primaData) {
  final start = parseDateOnly(primaData);
  if (start == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return start.difference(today).inDays;
}

/// Oggi è dentro l'intervallo [dal, al] (incluso).
bool isTodayInProgrammazioneRange(
  dynamic primaData,
  dynamic secondaData,
) {
  final start = parseDateOnly(primaData);
  if (start == null) return false;
  final end = programmazioneEndDate(primaData, secondaData) ?? start;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return !today.isBefore(start) && !today.isAfter(end);
}

/// Lampeggio rosso: il corso è oggi (giorno singolo) o in corso nell'intervallo.
bool isProgrammazioneTodayOrInCorso(
  dynamic primaData,
  dynamic secondaData,
) =>
    isTodayInProgrammazioneRange(primaData, secondaData);
