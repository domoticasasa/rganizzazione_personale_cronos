import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'rcc_mod04_excel_types.dart';

/// Esecuzione condivisa Python/openpyxl per compilare template Excel preservando immagini.
class TemplateExcelPythonFill {
  TemplateExcelPythonFill._();

  static const int kMinEmbeddedMedia = 6;

  static int countXlsxMedia(Uint8List bytes) {
    final needle = 'xl/media/';
    var count = 0;
    var start = 0;
    while (true) {
      final idx = _indexOfBytes(bytes, needle.codeUnits, start);
      if (idx < 0) break;
      count++;
      start = idx + needle.length;
    }
    return count;
  }

  static int _indexOfBytes(Uint8List haystack, List<int> needle, int start) {
    if (needle.isEmpty || start >= haystack.length) return -1;
    final limit = haystack.length - needle.length;
    for (var i = start; i <= limit; i++) {
      var found = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  static Future<List<String>> _pythonCandidates() async {
    final ordered = <String>[];
    if (Platform.isWindows) {
      ordered.addAll(['py', 'python', 'python3']);
      try {
        final proc = await Process.run(
          'where.exe',
          ['python'],
          runInShell: true,
        );
        if (proc.exitCode == 0) {
          for (final line in proc.stdout.toString().split(RegExp(r'\r?\n'))) {
            final path = line.trim();
            if (path.isEmpty) continue;
            if (path.toLowerCase().endsWith('.exe')) ordered.add(path);
          }
        }
      } catch (_) {}
    } else {
      ordered.addAll(['python3', 'python', 'py']);
    }
    final seen = <String>{};
    return [
      for (final e in ordered)
        if (seen.add(e.toLowerCase())) e,
    ];
  }

  static List<String> _processArgs(
    String exe,
    List<String> scriptArgs,
  ) {
    final base = p.basename(exe).toLowerCase();
    if (base == 'py' || base == 'py.exe') {
      return ['-3', ...scriptArgs];
    }
    return scriptArgs;
  }

  static Future<(Uint8List, RccMod04FillDiagnostics)> fill({
    required Directory tempDir,
    required String templatePath,
    required String pyScript,
    required Map<String, String> payload,
    required String tempFilePrefix,
    int? minEmbeddedMedia,
  }) async {
    final minRequired = minEmbeddedMedia ?? kMinEmbeddedMedia;
    final scriptFile = File(p.join(tempDir.path, '$tempFilePrefix.py'));
    final jsonFile = File(p.join(tempDir.path, '${tempFilePrefix}_payload.json'));
    final outputFile = File(p.join(tempDir.path, '${tempFilePrefix}_out.xlsx'));

    await scriptFile.writeAsString(pyScript);
    await jsonFile.writeAsString(jsonEncode(payload));

    final candidates = await _pythonCandidates();
    final errors = <String>[];
    final useShell = Platform.isWindows;

    for (final exe in candidates) {
      try {
        final proc = await Process.run(
          exe,
          _processArgs(
            exe,
            [scriptFile.path, templatePath, jsonFile.path, outputFile.path],
          ),
          runInShell: useShell,
        );
        final stderr = proc.stderr.toString().trim();
        final stdout = proc.stdout.toString().trim();

        if (proc.exitCode == 2) {
          errors.add(
            '$exe: immagini/logo persi in salvataggio. '
            '${stderr.isNotEmpty ? stderr : stdout}',
          );
          continue;
        }

        if (proc.exitCode != 0 || !outputFile.existsSync()) {
          errors.add(
            '$exe: exit ${proc.exitCode}'
            '${stderr.isNotEmpty ? ' — $stderr' : ''}'
            '${stdout.isNotEmpty && stderr.isEmpty ? ' — $stdout' : ''}',
          );
          continue;
        }

        final bytes = await outputFile.readAsBytes();
        if (bytes.isEmpty) {
          errors.add('$exe: file di output vuoto');
          continue;
        }

        final mediaInZip = countXlsxMedia(bytes);
        if (mediaInZip < minRequired) {
          errors.add(
            '$exe: nel file esportato mancano le immagini del template '
            '(trovate ~$mediaInZip occorrenze xl/media/, attese almeno $minRequired).',
          );
          continue;
        }

        var mediaCount = mediaInZip;
        for (final line in stdout.split('\n')) {
          final t = line.trim();
          if (t.startsWith('MEDIA_OK:')) {
            mediaCount = int.tryParse(t.substring('MEDIA_OK:'.length)) ?? mediaCount;
          }
        }

        return (
          Uint8List.fromList(bytes),
          RccMod04FillDiagnostics(
            pythonExecutable: exe,
            embeddedMediaCount: mediaCount,
          ),
        );
      } catch (e) {
        errors.add('$exe: $e');
      }
    }

    final hint = Platform.isWindows
        ? 'Su Windows, da Prompt dei comandi:\n'
            '  py -3 -m pip install --upgrade openpyxl\n'
            '  py -3 -c "import openpyxl; print(openpyxl.__version__)"\n'
            'Poi riavvia l\'app CRONOS e riesporta.'
        : 'pip install --upgrade openpyxl';

    throw Exception(
      'Export Excel richiede Python 3 con openpyxl, per mantenere logo e certificazioni.\n'
      '$hint\n'
      'Tentativi: ${errors.isEmpty ? "nessun interprete trovato" : errors.join(" | ")}',
    );
  }
}
