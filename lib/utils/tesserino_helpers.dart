/// Unisce etichetta + testo legacy in un’unica riga da mostrare sul tesserino.
String mergeTesserinoRigaExtra(String? etichetta, String? testo) {
  var e = (etichetta ?? '').trim();
  final t = (testo ?? '').trim();
  if (e.endsWith(':')) e = e.substring(0, e.length - 1).trimRight();
  if (t.isEmpty) return e;
  if (e.isEmpty) return t;
  return '$e: $t';
}

/// Righe aggiuntive dal JSON personale o dalla riga legacy singola.
List<String> tesserinoRigheExtraFromPersonale(Map<String, dynamic> row) {
  final fromJson = parseTesserinoRigheExtraJson(row['tesserino_righe_extra']);
  if (fromJson.isNotEmpty) return fromJson;

  final legacy = mergeTesserinoRigaExtra(
    row['tesserino_extra_etichetta']?.toString(),
    row['tesserino_extra_testo']?.toString(),
  );
  if (legacy.isNotEmpty) return [legacy];
  return const [];
}

List<String> parseTesserinoRigheExtraJson(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

List<String> normalizeTesserinoRigheExtra(Iterable<String> lines) {
  return lines
      .map((e) => e.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// Conversione seriale Excel (1900) → data calendario.
DateTime? excelSerialToDateTime(num? serial) {
  if (serial == null || serial.isNaN) return null;
  final whole = serial.floor();
  // Base usata da Excel Windows: 30/12/1899; i seriali interi sono giorni.
  return DateTime(1899, 12, 30).add(Duration(days: whole));
}

({String nome, String cognome}) splitPersonaleFullName(String full) {
  final parts = full.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || (parts.length == 1 && parts.first.isEmpty)) {
    return (nome: '', cognome: '');
  }
  if (parts.length == 1) return (nome: '', cognome: parts.first);
  final cognome = parts.first;
  final nome = parts.sublist(1).join(' ');
  return (nome: nome, cognome: cognome);
}

bool namesMatchPersonale({
  required String excelNome,
  required String excelCognome,
  required String personaleFullName,
}) {
  final p = splitPersonaleFullName(personaleFullName);
  bool eq(String a, String b) =>
      a.trim().toUpperCase() == b.trim().toUpperCase();
  return eq(excelNome, p.nome) && eq(excelCognome, p.cognome);
}

/// Nome file sicuro per export foto tesserino (numero + cognome_nome).
String tesserinoFotoExportBaseName(Map<String, dynamic> personale) {
  final tess = (personale['numero_tesserino'] ?? '').toString().trim();
  final name = (personale['full_name'] ?? 'dipendente')
      .toString()
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  if (tess.isNotEmpty) return '${tess}_$name';
  return name;
}
