import 'dart:convert';
import 'dart:io';

/// Generates a simple PDF (ASCII-only) with guidance for the page
/// "Admin — Regole Notifiche".
///
/// Notes:
/// - We intentionally keep the content ASCII-only to avoid font encoding issues.
/// - This is a minimal PDF generator: it supports text drawing only.
void main() async {
  final outPath = File('admin_regole_notifiche.pdf').absolute.path;

  final pageWidth = 595.0; // A4 points
  final pageHeight = 842.0; // A4 points
  final margin = 50.0;

  const fontSize = 10.0;
  const leading = 14.0;

  final maxCharsPerLine =
      ((pageWidth - 2 * margin) / (fontSize * 0.55)).floor().clamp(40, 120);

  final rawLines = <String>[
    'ADMIN - REGOLE NOTIFICHE (GUIDA RAPIDA)',
    '',
    'A COSA SERVE QUESTA PAGINA',
    '- Qui controlli come l app decide a chi inviare le notifiche.',
    '- Ci sono due livelli: regole di routing (notification_routing_rules) e',
    '  eccezioni "quando" / "action" controllate da Supabase.',
    '',
    'TAB "REGOLE" (routing notifiche)',
    '- Ogni card e una regola identificata da rule_key (chiave tecnica nel DB).',
    '- Mostra anche: label (testo leggibile) e Destinatari (targets).',
    '- Il toggle "Regola attiva" abilita/disabilita quella regola.',
    '',
    'COME CAMBIARE UNA REGOLA (routing)',
    '1) Vai su "Admin — Regole Notifiche" e assicurati che il TAB attivo sia "Regole".',
    '2) Clicca la card della regola che vuoi cambiare.',
    '3) Nella finestra che si apre:',
    '   - Seleziona i nuovi destinatari spuntando le caselle (targets).',
    '   - Se e una regola esistente, la chiave rule_key non e modificabile.',
    '   - Se hai un caso nuovo (nuova regola) puoi impostare rule_key e label.',
    '4) Premi "Salva".',
    '',
    'BOTTONI UTILI NEL TAB "REGOLE"',
    '- "Riallinea regole standard": rimette notification_routing_rules ai valori di default.',
    '  (Utile se qualcuno ha cancellato/alterato regole e vuoi tornare alla base.)',
    '- "Riesegui verifica": ricarica e controlla se mancano regole obbligatorie o se',
    '  ci sono target non riconosciuti.',
    '',
    'ECceZIONI "QUANDO" (Supabase)',
    '- Questa sezione e una logica extra usata dal backend (Edge Function).',
    '- Le modifiche qui scrivono direttamente su Supabase, quindi funzionano subito dopo',
    '  che l app riesegue l invio (o al prossimo evento).',
    '',
    '1) BLOCCA ADMIN SU action=create PER workflow_status (treno/aereo)',
    '- Tabella: notification_admin_create_skip_workflow_statuses.',
    '- Cosa fa: se una workflow_status e abilitata, l Edge Function blocca le notifiche',
    '  agli admin quando action = "create" per quella situazione.',
    '',
    'COME MODIFICARE',
    '- Spunta/aggiungi workflow_status nella lista.',
    '- Premi "Aggiungi" per inserire un nuovo workflow_status.',
    '',
    '2) FILTRA admin_generale: azioni CHE SALTANO IL FILTRO',
    '- Tabella: notification_admin_generale_filter_skip_actions.',
    '- Cosa fa: per alcune azioni, il filtro che normalmente esclude "admin_generale" dalla',
    '  lista destinatari puo essere saltato.',
    '- In pratica: se un action_key e abilitato qui, per quell azione admin_generale puo',
    '  rimanere incluso tra i destinatari.',
    '',
    'COME MODIFICARE',
    '- Spunta/aggiungi action_key nella lista.',
    '- Premi "Aggiungi" per inserire un nuovo action_key.',
    '',
    'TAB "LOG" (debug/test)',
    '- Legge le righe recenti da Supabase (tabella notifications, max 500).',
    '- Puoi cercare per utente, titolo, messaggio, action, booking_id.',
    '- Le icone distinguono: notifica letta o non letta.',
    '',
    'PROCEDURA TIPICA DI TEST (consigliata)',
    '1) Cambia una regola o un eccezione "quando".',
    '2) Fai un azione nell app che dovrebbe generare la notifica',
    '   (esempio: crea/conferma/aggiorna prenotazione).',
    '3) Attendi 1-10 secondi.',
    '4) Apri TAB "Log" e verifica:',
    '   - che la riga compaia per il/i destinatari attesi',
    '   - che non compaia per chi doveva essere escluso',
    '',
    'MATERIALE TECNICO (collegamento backend)',
    '- L Edge Function principale e "admin-send-notification".',
    '- Questa function legge:',
    '  - notification_admin_create_skip_workflow_statuses (regole "quando")',
    '  - notification_admin_generale_filter_skip_actions (regole "action")',
    '  - e usa inoltre le regole di routing da notification_routing_rules.',
    '',
    'Se vuoi, dimmi esattamente quale notifica non arriva o deve cambiare,',
    'e ti dico quale rule_key o quale eccezione (workflow_status/action_key)',
    'probabilmente va toccata.',
  ];

  // Wrap into page-sized text lines.
  final pagesLines = <List<String>>[];
  var current = <String>[];

  final availableLinesPerPage = ((pageHeight - 2 * margin) / leading).floor();

  int lineCountOnPage = 0;
  for (final raw in rawLines) {
    final sanitized = _sanitizeToAscii(raw);
    if (sanitized.trim().isEmpty) {
      // Empty line
      current.add('');
      lineCountOnPage++;
    } else {
      final wrapped = _wrapText(sanitized, maxCharsPerLine);
      for (final ln in wrapped) {
        current.add(ln);
        lineCountOnPage++;
      }
    }

    if (lineCountOnPage >= availableLinesPerPage) {
      pagesLines.add(current);
      current = <String>[];
      lineCountOnPage = 0;
    }
  }
  if (current.isNotEmpty) pagesLines.add(current);

  final pdf = _buildPdf(
    pages: pagesLines,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    margin: margin,
    fontSize: fontSize,
    leading: leading,
  );

  await File(outPath).writeAsBytes(pdf);
  stdout.writeln(outPath);
}

String _sanitizeToAscii(String s) {
  // Replace common Italian diacritics to avoid encoding issues.
  final map = <String, String>{
    'à': 'a',
    'è': 'e',
    'é': 'e',
    'ì': 'i',
    'ò': 'o',
    'ù': 'u',
    'À': 'A',
    'È': 'E',
    'É': 'E',
    'Ì': 'I',
    'Ò': 'O',
    'Ù': 'U',
    'ç': 'c',
    'Ç': 'C',
    '“': '"',
    '”': '"',
    '’': '\'',
    '•': '*',
  };

  var out = s;
  map.forEach((k, v) => out = out.replaceAll(k, v));
  // Some punctuation cleanup
  out = out.replaceAll('`', '\'');
  return out;
}

List<String> _wrapText(String text, int maxChars) {
  // Simple word wrap. If a single word is longer than maxChars, we hard-split it.
  final words = text.split(RegExp(r'\s+'));
  final lines = <String>[];
  var line = '';

  for (var w in words) {
    if (w.isEmpty) continue;
    if (line.isEmpty) {
      if (w.length <= maxChars) {
        line = w;
      } else {
        // Hard split long word.
        lines.add(w.substring(0, maxChars));
        final rest = w.substring(maxChars);
        line = rest.length <= maxChars ? rest : '';
        if (rest.length > maxChars) {
          var idx = 0;
          while (idx + maxChars < w.length) {
            idx += maxChars;
            if (idx + maxChars <= w.length) {
              lines.add(w.substring(idx, idx + maxChars));
            }
          }
          line = w.substring((w.length ~/ maxChars) * maxChars);
        }
      }
    } else {
      if ((line.length + 1 + w.length) <= maxChars) {
        line = '$line $w';
      } else {
        lines.add(line);
        if (w.length <= maxChars) {
          line = w;
        } else {
          lines.add(w.substring(0, maxChars));
          line = w.substring(maxChars);
        }
      }
    }
  }

  if (line.isNotEmpty) lines.add(line);
  return lines;
}

String _escapePdfString(String s) {
  // Escape backslash and parentheses.
  return s.replaceAll('\\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
}

List<int> _buildPdf({
  required List<List<String>> pages,
  required double pageWidth,
  required double pageHeight,
  required double margin,
  required double fontSize,
  required double leading,
}) {
  // Object numbering:
  // 1: Catalog
  // 2: Pages
  // 3: Font
  // For each page i (0-based):
  //   content object = 4 + i*2
  //   page object    = 5 + i*2
  final pageCount = pages.length;
  final maxObjId = 5 + (pageCount - 1) * 2;

  // Keep the header ASCII-only to avoid encoding issues.
  final header = '%PDF-1.4\n%CRONOS_GENERATED\n';
  final out = <int>[];
  out.addAll(utf8.encode(header));

  final offsets = List<int>.filled(maxObjId + 1, 0);

  void writeObj(int id, String body) {
    offsets[id] = out.length;
    out.addAll(utf8.encode('$id 0 obj\n$body\nendobj\n'));
  }

  // Font object (3 0 R)
  writeObj(
    3,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  );

  // Content + page objects
  final pageObjIds = <int>[];
  for (var i = 0; i < pageCount; i++) {
    final contentObjId = 4 + i * 2;
    final pageObjId = 5 + i * 2;
    pageObjIds.add(pageObjId);

    final lines = pages[i];
    final startX = margin;
    final startY = pageHeight - margin;

    final content = StringBuffer();
    content.writeln('BT');
    content.writeln('/F1 ${fontSize.toStringAsFixed(2)} Tf');
    content.writeln('${leading.toStringAsFixed(2)} TL');
    content.writeln('1 0 0 1 ${startX.toStringAsFixed(2)} ${startY.toStringAsFixed(2)} Tm');

    for (final ln in lines) {
      final esc = _escapePdfString(ln);
      content.writeln('($esc) Tj');
      content.writeln('T*');
    }
    content.writeln('ET');

    final contentStr = content.toString();
    final contentBytes = utf8.encode(contentStr);
    final length = contentBytes.length;

    writeObj(
      contentObjId,
      '<< /Length $length >>\nstream\n$contentStr\nendstream',
    );

    writeObj(
      pageObjId,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth.toStringAsFixed(0)} ${pageHeight.toStringAsFixed(0)}] '
          '/Resources << /Font << /F1 3 0 R >> >> '
          '/Contents $contentObjId 0 R >>',
    );
  }

  // Catalog and Pages
  writeObj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  writeObj(2, '<< /Type /Pages /Kids [${pageObjIds.map((id) => '$id 0 R').join(' ')}] /Count $pageCount >>');

  // xref table
  final xrefOffset = out.length;
  final size = maxObjId + 1;

  out.addAll(utf8.encode('xref\n0 $size\n'));
  out.addAll(utf8.encode('0000000000 65535 f \n'));

  for (var id = 1; id <= maxObjId; id++) {
    final off = offsets[id];
    out.addAll(utf8.encode('${off.toString().padLeft(10, '0')} 00000 n \n'));
  }

  out.addAll(utf8.encode('trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF'));

  return out;
}

