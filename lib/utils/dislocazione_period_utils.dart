/// Utilità per espandere/comprimere periodi dislocazione (come nel file Excel).
library;

/// Risolve testo incollato/digitato in valore cella (commessa, stato catalogo o testo libero).
DislocazioneGiornoValore? parseDislocazioneTesto(
  String raw, {
  required List<String> statiCatalogo,
  required Map<String, String> commesse,
}) {
  final t = raw.replaceAll('\u00a0', ' ').trim();
  if (t.isEmpty) return null;
  var up = t.toUpperCase();
  const alias = <String, String>{
    'PERMESSI': 'PERMESSO',
    'FERIE': 'FERIE',
    'MALATTIE': 'MALATTIA',
    'INFORTUNI': 'INFORTUNIO',
  };
  up = alias[up] ?? up;
  if (statiCatalogo.contains(up)) {
    return DislocazioneGiornoValore(stato: up);
  }
  final cid = trovaCommessaIdDaTesto(t, commesse);
  if (cid != null) return DislocazioneGiornoValore(commessaId: cid);
  return DislocazioneGiornoValore(stato: up);
}

/// Cerca commessa per codice (prefisso prima dello spazio) o per contenuto nel nome.
String? trovaCommessaIdDaTesto(String testo, Map<String, String> commesse) {
  final t = testo.trim();
  if (t.isEmpty) return null;
  final up = t.toUpperCase();

  String codice(String nome) {
    final s = nome.trim();
    final sp = s.indexOf(' ');
    if (sp > 0) return s.substring(0, sp).toUpperCase();
    return s.toUpperCase();
  }

  for (final e in commesse.entries) {
    if (codice(e.value) == up) return e.key;
  }
  for (final e in commesse.entries) {
    if (e.value.toUpperCase().contains(up)) return e.key;
  }
  return null;
}

/// Valore giornaliero: commessa, stato catalogo (FERIE, MALATTIA, …) o testo libero in [stato].
class DislocazioneGiornoValore {
  const DislocazioneGiornoValore({this.commessaId, this.stato});

  final String? commessaId;
  final String? stato;

  bool get isEmpty =>
      (commessaId == null || commessaId!.isEmpty) &&
      (stato == null || stato!.isEmpty);

  String cacheKey() {
    if (commessaId != null && commessaId!.isNotEmpty) return 'c:$commessaId';
    final s = stato?.trim().toUpperCase();
    return s == null || s.isEmpty ? '' : 's:$s';
  }

  static DislocazioneGiornoValore fromRow(Map<String, dynamic> row) {
    final cid = (row['commessa_id'] ?? '').toString().trim();
    if (cid.isNotEmpty) {
      return DislocazioneGiornoValore(commessaId: cid);
    }
    final st = (row['stato'] ?? '').toString().trim();
    if (st.isNotEmpty) {
      return DislocazioneGiornoValore(stato: st.toUpperCase());
    }
    return const DislocazioneGiornoValore();
  }

  Map<String, dynamic> toPayload({
    required String nominativo,
    required String? abilitazioni,
    String? attivita,
    required DateTime dal,
    required DateTime al,
  }) {
    var at = attivita?.trim();
    if (at != null && at.isEmpty) at = null;
    return <String, dynamic>{
      'nominativo': nominativo,
      'abilitazioni': abilitazioni,
      'attivita': at,
      'commessa_id': (commessaId ?? '').isEmpty ? null : commessaId,
      'stato': (commessaId ?? '').isNotEmpty ? null : (stato?.trim().isEmpty ?? true ? null : stato!.trim().toUpperCase()),
      'data_inizio': _isoDate(dal),
      'data_fine': _isoDate(al),
      'active': true,
    };
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _isoDate(DateTime d) {
  final x = dateOnly(d);
  return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

DateTime? parseIsoDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return dateOnly(d);
}

/// Espande righe periodo in mappa giorno → valore.
Map<DateTime, DislocazioneGiornoValore> espandiPeriodi(
  Iterable<Map<String, dynamic>> rows,
) {
  final out = <DateTime, DislocazioneGiornoValore>{};
  for (final row in rows) {
    final dal = parseIsoDate(row['data_inizio']);
    final al = parseIsoDate(row['data_fine']) ?? dal;
    if (dal == null) continue;
    final end = al ?? dal;
    final val = DislocazioneGiornoValore.fromRow(row);
    if (val.isEmpty) continue;
    var cur = dal;
    while (!cur.isAfter(end)) {
      out[cur] = val;
      cur = cur.add(const Duration(days: 1));
    }
  }
  return out;
}

/// Comprime mappa giornaliera in periodi consecutivi con stesso valore.
List<Map<String, dynamic>> comprimiGiorni({
  required String nominativo,
  required String? abilitazioni,
  String? attivita,
  required Map<DateTime, DislocazioneGiornoValore> giorni,
}) {
  if (giorni.isEmpty) return <Map<String, dynamic>>[];

  final keys = giorni.keys.toList()..sort();
  final out = <Map<String, dynamic>>[];
  DislocazioneGiornoValore? curVal;
  DateTime? curStart;
  DateTime? curEnd;

  void flush() {
    if (curVal == null || curStart == null || curEnd == null) return;
    if (curVal!.isEmpty) return;
    out.add(curVal!.toPayload(
      nominativo: nominativo,
      abilitazioni: abilitazioni,
      attivita: attivita,
      dal: curStart!,
      al: curEnd!,
    ));
    curVal = null;
    curStart = null;
    curEnd = null;
  }

  for (final day in keys) {
    final v = giorni[day]!;
    if (v.isEmpty) {
      flush();
      continue;
    }
    if (curVal == null) {
      curVal = v;
      curStart = day;
      curEnd = day;
    } else if (v.cacheKey() == curVal!.cacheKey()) {
      curEnd = day;
    } else {
      flush();
      curVal = v;
      curStart = day;
      curEnd = day;
    }
  }
  flush();
  return out;
}

/// Applica modifica su un giorno e ricomprime tutti i periodi del nominativo.
List<Map<String, dynamic>> aggiornaGiornoERicomprimi({
  required String nominativo,
  required String? abilitazioni,
  String? attivita,
  required Iterable<Map<String, dynamic>> righeEsistenti,
  required DateTime giorno,
  required DislocazioneGiornoValore nuovoValore,
}) {
  final map = espandiPeriodi(righeEsistenti);
  final g = dateOnly(giorno);
  if (nuovoValore.isEmpty) {
    map.remove(g);
  } else {
    map[g] = nuovoValore;
  }
  return comprimiGiorni(
    nominativo: nominativo,
    abilitazioni: abilitazioni,
    attivita: attivita,
    giorni: map,
  );
}

String etichettaBreve({
  required DislocazioneGiornoValore valore,
  required Map<String, String> commesse,
  int maxLen = 14,
}) {
  if (valore.commessaId != null && valore.commessaId!.isNotEmpty) {
    final nome = commesse[valore.commessaId!] ?? '';
    return _tronca(_codiceCommessa(nome), maxLen);
  }
  final s = valore.stato ?? '';
  return _tronca(s, maxLen);
}

String _codiceCommessa(String nome) {
  final t = nome.trim();
  if (t.isEmpty) return '';
  final sp = t.indexOf(' ');
  if (sp > 0 && sp <= 12) return t.substring(0, sp);
  return t.length > 16 ? '${t.substring(0, 14)}…' : t;
}

String _tronca(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1)}…';
}
