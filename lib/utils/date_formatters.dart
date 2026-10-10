import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Fuso orario ufficiale dell'app (Italia, con ora legale).
const String kAppTimezone = 'Europe/Rome';

bool _italyTzReady = false;
tz.Location? _italyLocation;

/// Inizializza il database IANA (chiamare una volta all'avvio, es. da [main]).
void ensureItalyTimezoneInitialized() {
  if (_italyTzReady) return;
  tz_data.initializeTimeZones();
  _italyLocation = tz.getLocation(kAppTimezone);
  _italyTzReady = true;
}

tz.Location get _rome {
  ensureItalyTimezoneInitialized();
  return _italyLocation!;
}

/// Ora corrente in Italia (wall clock).
DateTime italyNow() {
  final z = tz.TZDateTime.now(_rome);
  return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second, z.millisecond);
}

/// Per colonne Supabase `timestamptz`: istante UTC in ISO 8601.
String supabaseNowIsoUtc() => DateTime.now().toUtc().toIso8601String();

/// Data odierna in Italia `yyyy-MM-dd` (colonne `date`).
String italyTodayIsoDate() {
  final n = italyNow();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

final RegExp _hasTimezoneSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// `dd/MM/yyyy` all'inizio di testi liberi (es. `17/01/2025 - IN ATTESA …`).
String? extractLeadingDdMmYyyy(String raw) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(raw.trim());
  if (m == null) return null;
  return '${m.group(1)}/${m.group(2)}/${m.group(3)}';
}

/// `yyyy-MM-dd` all'inizio di testi liberi.
String? extractLeadingIsoDate(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (m == null) return null;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}

/// Interpreta valori da Supabase/Postgres `timestamptz` come istante UTC.
DateTime? parseSupabaseTimestampToUtc(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.isUtc ? v : v.toUtc();

  final raw = v.toString().trim();
  if (raw.isEmpty) return null;

  // Suffisso Z/offset solo su ISO con separatore data-ora (evita falsi positivi
  // su testi che terminano con «Z», es. «… SICILIAZ» in nolo_al).
  if (raw.contains('T') && _hasTimezoneSuffix.hasMatch(raw)) {
    return DateTime.tryParse(raw)?.toUtc();
  }

  if (raw.contains('T')) {
    // PostgREST spesso omette offset: il valore è UTC nel DB.
    final normalized = raw.endsWith('Z') ? raw : '${raw}Z';
    return DateTime.tryParse(normalized)?.toUtc() ?? DateTime.tryParse(raw)?.toUtc();
  }

  final d = DateTime.tryParse(raw);
  return d?.toUtc();
}

/// Istante → data/ora da mostrare in Italia (wall clock, senza tz nel DateTime).
DateTime? parseSupabaseTimestampToItaly(dynamic v) {
  final utc = parseSupabaseTimestampToUtc(v);
  if (utc == null) return null;
  final rome = tz.TZDateTime.from(utc, _rome);
  return DateTime(
    rome.year,
    rome.month,
    rome.day,
    rome.hour,
    rome.minute,
    rome.second,
    rome.millisecond,
  );
}

/// Inizio giorno calendario Italia → ISO UTC per filtri Supabase `timestamptz`.
String supabaseFilterItalyDayStartUtcIso(int year, int month, int day) {
  ensureItalyTimezoneInitialized();
  return tz.TZDateTime(_rome, year, month, day).toUtc().toIso8601String();
}

/// Fine giorno calendario Italia → ISO UTC per filtri Supabase `timestamptz`.
String supabaseFilterItalyDayEndUtcIso(int year, int month, int day) {
  ensureItalyTimezoneInitialized();
  return tz.TZDateTime(_rome, year, month, day, 23, 59, 59, 999)
      .toUtc()
      .toIso8601String();
}

/// Format date in Italian style: `dd/MM/yyyy`.
///
/// Accepts:
/// - `DateTime`
/// - `String` in `yyyy-MM-dd` or ISO datetime (`yyyy-MM-ddTHH:mm...`)
/// - `String` already in `dd/MM/yyyy`
String formatDateDdMmYyyy(dynamic iso) {
  if (iso == null) return '';
  final raw = iso.toString().trim();
  if (raw.isEmpty) return '';

  final leading = extractLeadingDdMmYyyy(raw);
  if (leading != null) return leading;

  // If already dd/MM/yyyy keep it.
  final ddMmYyyy = RegExp(r'^\d{2}/\d{2}/\d{4}$');
  if (ddMmYyyy.hasMatch(raw)) return raw;

  // yyyy-MM-dd
  final yyyyMmDd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  final m1 = yyyyMmDd.firstMatch(raw);
  if (m1 != null) {
    final yyyy = m1.group(1)!;
    final mm = m1.group(2)!;
    final dd = m1.group(3)!;
    return '$dd/$mm/$yyyy';
  }

  // ISO datetime: take first 10 chars.
  final prefix = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final m2 = yyyyMmDd.firstMatch(prefix);
  if (m2 != null) {
    final yyyy = m2.group(1)!;
    final mm = m2.group(2)!;
    final dd = m2.group(3)!;
    return '$dd/$mm/$yyyy';
  }

  final italy = parseSupabaseTimestampToItaly(raw);
  if (italy != null) {
    return formatDateDdMmYyyyFromDate(italy);
  }

  // Last resort: return raw.
  return raw;
}

/// Format `DateTime` -> `dd/MM/yyyy`.
String formatDateDdMmYyyyFromDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

/// Format date+time in Italian style: `dd/MM/yyyy HH:mm` (valore già in ora italiana).
String formatDateTimeIt(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${formatDateDdMmYyyyFromDate(d)} $hh:$mm';
}

/// Da timestamp Supabase → `dd/MM/yyyy HH:mm` in fuso Italia.
String formatDateTimeItFromSupabase(dynamic v) {
  final dt = parseSupabaseTimestampToItaly(v);
  if (dt == null) {
    final raw = v?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    return formatDateDdMmYyyy(raw);
  }
  return formatDateTimeIt(dt);
}

/// Parses flexible date strings and returns ISO date `yyyy-MM-dd`.
/// Returns `null` if it cannot parse.
String? parseFlexibleDateToIsoDate(String? input) {
  if (input == null) return null;
  final raw = input.trim();
  if (raw.isEmpty) return null;

  final leadingDd = extractLeadingDdMmYyyy(raw);
  if (leadingDd != null) {
    final mLead = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(leadingDd);
    if (mLead != null) {
      return '${mLead.group(3)}-${mLead.group(2)}-${mLead.group(1)}';
    }
  }
  final leadingIso = extractLeadingIsoDate(raw);
  if (leadingIso != null) {
    return leadingIso;
  }

  // yyyy-MM-dd
  final yyyyMmDd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  final m1 = yyyyMmDd.firstMatch(raw);
  if (m1 != null) {
    return raw;
  }

  // dd/MM/yyyy
  final ddMmYyyy = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  final m2 = ddMmYyyy.firstMatch(raw);
  if (m2 != null) {
    final dd = m2.group(1)!;
    final mm = m2.group(2)!;
    final yyyy = m2.group(3)!;
    return '$yyyy-$mm-$dd';
  }

  // dd-MM-yyyy
  final ddMmYyyyDash = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$');
  final m3 = ddMmYyyyDash.firstMatch(raw);
  if (m3 != null) {
    final dd = m3.group(1)!;
    final mm = m3.group(2)!;
    final yyyy = m3.group(3)!;
    return '$yyyy-$mm-$dd';
  }

  final italy = parseSupabaseTimestampToItaly(raw);
  if (italy != null) {
    return '${italy.year.toString().padLeft(4, '0')}-'
        '${italy.month.toString().padLeft(2, '0')}-'
        '${italy.day.toString().padLeft(2, '0')}';
  }

  // Unknown format.
  return null;
}

/// Campi DPI produzione/revisione: vuoto → [fallbackIso]; data riconosciuta → ISO; altrimenti testo libero.
String? normalizeDpiOptionalDateField(String? raw, String? fallbackIso) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return fallbackIso;
  return parseFlexibleDateToIsoDate(t) ?? t;
}

/// Parses flexible date strings to local date (no time).
DateTime? parseFlexibleDateToDateTime(dynamic input) {
  final iso = parseFlexibleDateToIsoDate(input?.toString());
  if (iso == null) return null;
  final parts = iso.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// Combina data `dd/MM/yyyy` (o ISO) e ora `HH:mm`
/// e restituisce un ISO UTC (`timestamptz`) coerente con il fuso Italia.
String? parseDateAndTimeToIso(String dateInput, String timeInput) {
  final localDate = parseFlexibleDateToDateTime(dateInput);
  if (localDate == null) return null;
  final t = timeInput.trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  final rome = tz.TZDateTime(
    _rome,
    localDate.year,
    localDate.month,
    localDate.day,
    h,
    min,
  );
  return rome.toUtc().toIso8601String();
}

/// Da ISO datetime → `HH:mm` per modifica form (ora italiana).
String formatTimeHhMmFromIso(dynamic iso) {
  final raw = (iso ?? '').toString().trim();
  if (raw.isEmpty) return '';
  final dt = parseSupabaseTimestampToItaly(iso);
  if (dt == null) return '';
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

/// Giorno dell'anno (1-based), senza effetti DST.
int dayOfYearForDate(DateTime date) {
  const monthLengths = <int>[0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final y = date.year;
  final isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
  var dayOfYear = date.day;
  for (var month = 1; month < date.month; month++) {
    dayOfYear += monthLengths[month];
    if (month == 2 && isLeap) dayOfYear += 1;
  }
  return dayOfYear;
}

/// Numero settimana ISO 8601 (lunedì = inizio settimana).
int isoWeekNumber(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  final dayOfYear = dayOfYearForDate(local);
  var week = ((dayOfYear - local.weekday + 10) / 7).floor();
  if (week < 1) {
    return isoWeekNumber(DateTime(local.year - 1, 12, 31));
  }
  if (week > 52) {
    if (isoWeekNumber(DateTime(local.year, 12, 28)) >= 52) return week;
    return 1;
  }
  return week;
}
