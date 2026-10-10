/// Testo per file taglie da `personale_taglie` (inserite dal dipendente).
abstract final class EmployeeTaglieExport {
  static const List<MapEntry<String, String>> _dbFields = [
    MapEntry('T-shirt', 'taglia_tshirt'),
    MapEntry('Pantalone', 'taglia_pantalone'),
    MapEntry('Felpa', 'taglia_felpa'),
    MapEntry('Giacca', 'taglia_giacca'),
    MapEntry('Gilet', 'taglia_gilet'),
    MapEntry('Scarpe', 'taglia_scarpe'),
    MapEntry('Guanti', 'taglia_guanti'),
  ];

  static Map<String, String> mapFromRow(Map<String, dynamic>? row) {
    final out = <String, String>{};
    if (row == null) return out;
    for (final e in _dbFields) {
      out[e.key] = (row[e.value] ?? '').toString().trim();
    }
    return out;
  }

  static Map<String, String> mapFromDialogValues({
    required String tshirt,
    required String pantalone,
    required String felpa,
    required String giacca,
    required String gilet,
    required String scarpe,
    required String guanti,
  }) {
    return {
      'T-shirt': tshirt.trim(),
      'Pantalone': pantalone.trim(),
      'Felpa': felpa.trim(),
      'Giacca': giacca.trim(),
      'Gilet': gilet.trim(),
      'Scarpe': scarpe.trim(),
      'Guanti': guanti.trim(),
    };
  }

  static String buildText({
    required String employeeName,
    required Map<String, String> taglieByLabel,
  }) {
    final b = StringBuffer()
      ..writeln('CRONOS — Taglie vestiario (inserite dal dipendente)')
      ..writeln('Dipendente: $employeeName')
      ..writeln('Generato: ${_nowIt()}')
      ..writeln('');
    var any = false;
    for (final e in _dbFields) {
      final v = (taglieByLabel[e.key] ?? '').trim();
      if (v.isEmpty) continue;
      any = true;
      b.writeln('${e.key}: $v');
    }
    if (!any) {
      b.writeln('(Nessuna taglia registrata.)');
    }
    return b.toString();
  }

  static String _nowIt() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String safeFilePart(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');

  /// Mappa le taglie anagrafiche sulle righe del modulo Mod.DPIE (colonna **R**),
  /// come in [AdminVestiarioPage] per Calzature r.15, T-shirt r.22, ecc.
  static void mergeIntoDpieColumnR(
    Map<String, String> payload,
    Map<String, String> taglieByLabel,
  ) {
    void rCell(int excelRow, String key) {
      payload['R$excelRow'] = (taglieByLabel[key] ?? '').trim();
    }

    rCell(15, 'Scarpe');
    final guanti = (taglieByLabel['Guanti'] ?? '').trim();
    payload['R19'] = guanti;
    payload['R20'] = guanti;
    rCell(21, 'Gilet');
    rCell(22, 'T-shirt');
    rCell(24, 'Pantalone');
    rCell(25, 'Felpa');
    rCell(26, 'Giacca');
  }
}
