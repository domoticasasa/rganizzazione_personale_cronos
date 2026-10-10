import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'excel_export_helper.dart';

/// Voce rubrica da riga `personale`.
class PersonaleContactEntry {
  final String fullName;
  final String phoneE164;
  final String? email;
  final bool active;

  const PersonaleContactEntry({
    required this.fullName,
    required this.phoneE164,
    this.email,
    this.active = true,
  });
}

/// Export rubrica (vCard / CSV) per import su telefono e gruppi WhatsApp.
abstract final class PersonaleContactsExport {
  static const String contactBrand = 'Cronos';
  static final RegExp _digitsOnly = RegExp(r'\D');

  /// Nome visibile in rubrica/WhatsApp (sempre con «Cronos»).
  static String displayNameForExport(PersonaleContactEntry e) {
    var base = e.fullName.trim();
    if (!base.toLowerCase().contains(contactBrand.toLowerCase())) {
      base = '$contactBrand - $base';
    }
    if (!e.active) base = '$base (inattivo)';
    return base;
  }

  /// Normalizza per cellulare italiano (+39…).
  static String? normalizePhoneItaly(String? raw) {
    if (raw == null) return null;
    var d = raw.replaceAll(_digitsOnly, '');
    if (d.isEmpty) return null;
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 10 && d.startsWith('3')) {
      return '+39$d';
    }
    if (d.length == 11 && d.startsWith('39')) {
      return '+$d';
    }
    if (d.length == 12 && d.startsWith('39')) {
      return '+$d';
    }
    if (d.length >= 8 && d.length <= 15) {
      return '+$d';
    }
    return null;
  }

  static List<PersonaleContactEntry> fromPersonaleRows(
    List<Map<String, dynamic>> rows, {
    bool onlyActive = false,
    bool requirePhone = true,
  }) {
    final out = <PersonaleContactEntry>[];
    for (final r in rows) {
      if (onlyActive && (r['active'] ?? true) != true) continue;
      final name = (r['full_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final phone = normalizePhoneItaly((r['telefono'] ?? '').toString());
      if (requirePhone && (phone == null || phone.isEmpty)) continue;
      final email = (r['email'] ?? '').toString().trim();
      out.add(
        PersonaleContactEntry(
          fullName: name,
          phoneE164: phone ?? '',
          email: email.isEmpty ? null : email,
          active: (r['active'] ?? true) == true,
        ),
      );
    }
    out.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return out;
  }

  static String _escapeVCard(String s) =>
      s.replaceAll('\\', r'\\').replaceAll(';', r'\;').replaceAll('\n', r'\n');

  /// vCard 3.0 — importabile da Rubrica Android/iPhone.
  static String buildVCard(
    List<PersonaleContactEntry> entries, {
    String organization = 'Cronos',
  }) {
    final buf = StringBuffer();
    for (final e in entries) {
      if (e.phoneE164.isEmpty) continue;
      final fn = displayNameForExport(e);
      buf.writeln('BEGIN:VCARD');
      buf.writeln('VERSION:3.0');
      buf.writeln('FN:${_escapeVCard(fn)}');
      buf.writeln('N:${_escapeVCard(fn)};;;;');
      buf.writeln('ORG:${_escapeVCard(organization)}');
      buf.writeln('TEL;TYPE=CELL:${e.phoneE164}');
      if (e.email != null && e.email!.isNotEmpty) {
        buf.writeln('EMAIL;TYPE=INTERNET:${_escapeVCard(e.email!)}');
      }
      buf.writeln('END:VCARD');
    }
    return buf.toString();
  }

  /// CSV compatibile con Google Contatti / Excel.
  static String buildGoogleContactsCsv(List<PersonaleContactEntry> entries) {
    final buf = StringBuffer();
    buf.writeln('Name,Given Name,Phone 1 - Type,Phone 1 - Value,Notes');
    for (final e in entries) {
      if (e.phoneE164.isEmpty) continue;
      final name = displayNameForExport(e);
      final parts = e.fullName.split(RegExp(r'\s+'));
      final given = parts.isNotEmpty ? parts.first : e.fullName;
      buf.writeln(
        '"${_csv(name)}","${_csv(given)}","Mobile","${_csv(e.phoneE164)}","Cronos"',
      );
    }
    return buf.toString();
  }

  /// Elenco testo: una riga per contatto (utile per controllo rapido).
  static String buildPlainTextList(List<PersonaleContactEntry> entries) {
    final buf = StringBuffer();
    for (final e in entries) {
      if (e.phoneE164.isEmpty) continue;
      buf.writeln('${displayNameForExport(e)}\t${e.phoneE164}');
    }
    return buf.toString();
  }

  static String _csv(String s) => s.replaceAll('"', '""');

  static Uint8List encodeUtf8(String text) => Uint8List.fromList(utf8.encode(text));

  static Uint8List vCardBytes(List<PersonaleContactEntry> entries) =>
      encodeUtf8(buildVCard(entries));

  static Uint8List csvBytes(List<PersonaleContactEntry> entries) =>
      encodeUtf8(buildGoogleContactsCsv(entries));

  static Uint8List plainTextBytes(List<PersonaleContactEntry> entries) =>
      encodeUtf8(buildPlainTextList(entries));
}

enum _PersonaleExportFormat { vcard, csv, txt }

/// Dialog + salvataggio file rubrica dipendenti (telefono / WhatsApp).
Future<void> exportPersonaleContactsForPhone(
  BuildContext context, {
  required List<Map<String, dynamic>> personaleRows,
  void Function(String message, {bool error})? messenger,
}) async {
  void notify(String msg, {bool error = false}) {
    if (messenger != null) {
      messenger(msg, error: error);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  final onlyActive = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Esporta rubrica'),
          content: const Text(
            'Esporta i dipendenti con numero di telefono per importarli '
            'nella rubrica del cellulare e creare un gruppo WhatsApp.\n\n'
            'Includere solo dipendenti attivi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tutti con telefono'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Solo attivi'),
            ),
          ],
        ),
      ) ??
      true;

  if (!context.mounted) return;

  final format = await showDialog<_PersonaleExportFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Formato file'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _PersonaleExportFormat.vcard),
          child: const ListTile(
            leading: Icon(Icons.contacts_outlined),
            title: Text('vCard (.vcf) — consigliato'),
            subtitle: Text(
              'Importa in Rubrica Android/iPhone, poi gruppo WhatsApp',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _PersonaleExportFormat.csv),
          child: const ListTile(
            leading: Icon(Icons.table_chart_outlined),
            title: Text('CSV (Google Contatti)'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _PersonaleExportFormat.txt),
          child: const ListTile(
            leading: Icon(Icons.list_alt_outlined),
            title: Text('Elenco testo (.txt)'),
            subtitle: Text('Nome e numero, per controllo'),
          ),
        ),
      ],
    ),
  );

  if (format == null || !context.mounted) return;

  final entries = PersonaleContactsExport.fromPersonaleRows(
    personaleRows,
    onlyActive: onlyActive,
  );
  if (entries.isEmpty) {
    notify(
      'Nessun dipendente con telefono valido trovato.',
      error: true,
    );
    return;
  }

  late final Uint8List bytes;
  late final String ext;
  switch (format) {
    case _PersonaleExportFormat.vcard:
      bytes = PersonaleContactsExport.vCardBytes(entries);
      ext = 'vcf';
    case _PersonaleExportFormat.csv:
      bytes = PersonaleContactsExport.csvBytes(entries);
      ext = 'csv';
    case _PersonaleExportFormat.txt:
      bytes = PersonaleContactsExport.plainTextBytes(entries);
      ext = 'txt';
  }

  final ok = await ExcelExportHelper.saveAndReveal(
    pageName: 'Rubrica_dipendenti_Cronos',
    bytes: bytes,
    extension: ext,
  );
  if (!ok) {
    notify('Salvataggio file annullato o non riuscito.', error: true);
    return;
  }

  final path = ExcelExportHelper.lastSavedPath;
  final n = entries.length;
  notify(
    'Esportati $n contatti${path != null && path.isNotEmpty ? ' → $path' : ''}. '
    '${format == _PersonaleExportFormat.vcard ? 'Apri il file .vcf dalla rubrica del telefono (Importa contatti), poi crea il gruppo WhatsApp e aggiungi i contatti.' : 'Importa il file nei contatti o usalo come riferimento.'}',
  );
}

