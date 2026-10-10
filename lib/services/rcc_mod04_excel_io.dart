import 'dart:convert';

import 'dart:io';

import 'dart:typed_data';



import 'package:path/path.dart' as p;



import '../utils/excel_template_assets.dart';

import 'rcc_mod04_excel_types.dart';



/// Compila il template [Mod.RCC_04.xlsx] (foglio Mod.RCC) via Python + openpyxl.

/// Non usa il pacchetto Dart `excel` su desktop: preserva immagini, bordi e piè di pagina.

class RccMod04Excel {

  RccMod04Excel._();



  static RccMod04FillDiagnostics? lastDiagnostics;



  /// Minimo immagini attese nel template (logo + certificazioni in basso).

  static const int kMinEmbeddedMedia = 6;



  static const _pyScript = r'''

import json

import re

import sys

import zipfile

from openpyxl import load_workbook

from openpyxl.utils.cell import coordinate_to_tuple



template_path = sys.argv[1]

payload_path = sys.argv[2]

output_path = sys.argv[3]



with open(payload_path, "r", encoding="utf-8") as f:

    payload = json.load(f)



with zipfile.ZipFile(template_path) as z_in:

    template_media = [n for n in z_in.namelist() if n.startswith("xl/media/")]



wb = load_workbook(template_path)

if "Mod.RCC" in wb.sheetnames:

    ws = wb["Mod.RCC"]

else:

    ws = wb[wb.sheetnames[0]]



ALLOWED_HEADER = frozenset({"D2", "D3", "C4", "H4", "H36"})

DATA_CELL_RE = re.compile(r"^[A-H](?:[6-9]|[12][0-9]|3[0-5])$", re.I)



def _anchor_for_merged(ref):

    row, col = coordinate_to_tuple(ref)

    for rng in ws.merged_cells.ranges:

        if rng.min_row <= row <= rng.max_row and rng.min_col <= col <= rng.max_col:

            return ws.cell(row=rng.min_row, column=rng.min_col).coordinate

    return ref



for ref, value in payload.items():

    cell = ref.strip().upper()

    if cell not in ALLOWED_HEADER and not DATA_CELL_RE.match(cell):

        continue

    target = _anchor_for_merged(cell)

    if value is None or (isinstance(value, str) and value == ""):

        ws[target].value = None

    else:

        ws[target] = value



wb.save(output_path)



with zipfile.ZipFile(output_path) as z_out:

    out_media = [n for n in z_out.namelist() if n.startswith("xl/media/")]



min_expected = max(1, len(template_media) - 1)

if len(out_media) < min_expected:

    print(

        f"ERRORE: immagini nel file esportato={len(out_media)}, "

        f"nel template={len(template_media)}. "

        "Reinstalla openpyxl per lo stesso Python usato dall'app: "

        "py -3 -m pip install --upgrade openpyxl",

        file=sys.stderr,

    )

    sys.exit(2)



print(f"MEDIA_OK:{len(out_media)}")

''';



  static int _countXlsxMedia(Uint8List bytes) {

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

    String scriptPath,

    String templatePath,

    String jsonPath,

    String outputPath,

  ) {

    final scriptArgs = [scriptPath, templatePath, jsonPath, outputPath];

    final base = p.basename(exe).toLowerCase();

    if (base == 'py' || base == 'py.exe') {

      return ['-3', ...scriptArgs];

    }

    return scriptArgs;

  }



  static Future<Uint8List> fill(Map<String, String> payload) async {

    final tempDir = await Directory.systemTemp.createTemp('rcc_mod04_');

    late final String templatePath;

    try {

      templatePath = await ExcelTemplateAssets.materialize(

        tempDir,

        ExcelTemplateAssets.modRcc04,

        'Mod.RCC_04.xlsx',

      );

    } catch (e) {

      try {

        await tempDir.delete(recursive: true);

      } catch (_) {}

      throw Exception(

        'Template Mod.RCC_04.xlsx non disponibile negli asset. '

        'Verifica assets/Mod.RCC_04.xlsx e pubspec.yaml. Dettaglio: $e',

      );

    }



    final scriptFile = File(p.join(tempDir.path, 'fill_rcc_mod04.py'));

    final jsonFile = File(p.join(tempDir.path, 'payload.json'));

    final outputFile = File(p.join(tempDir.path, 'mod_rcc_export.xlsx'));



    await scriptFile.writeAsString(_pyScript);

    await jsonFile.writeAsString(jsonEncode(payload));



    final candidates = await _pythonCandidates();

    final errors = <String>[];

    final useShell = Platform.isWindows;



    for (final exe in candidates) {

      try {

        final proc = await Process.run(

          exe,

          _processArgs(exe, scriptFile.path, templatePath, jsonFile.path, outputFile.path),

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



        final mediaInZip = _countXlsxMedia(bytes);

        if (mediaInZip < kMinEmbeddedMedia) {

          errors.add(

            '$exe: nel file esportato mancano le immagini del template '

            '(trovate ~$mediaInZip occorrenze xl/media/, attese almeno $kMinEmbeddedMedia).',

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



        lastDiagnostics = RccMod04FillDiagnostics(

          pythonExecutable: exe,

          embeddedMediaCount: mediaCount,

        );



        try {

          await tempDir.delete(recursive: true);

        } catch (_) {}

        return Uint8List.fromList(bytes);

      } catch (e) {

        errors.add('$exe: $e');

      }

    }



    try {

      await tempDir.delete(recursive: true);

    } catch (_) {}



    final hint = Platform.isWindows

        ? 'Su Windows, da Prompt dei comandi:\n'

            '  py -3 -m pip install --upgrade openpyxl\n'

            '  py -3 -c "import openpyxl; print(openpyxl.__version__)"\n'

            'Poi riavvia l\'app CRONOS e riesporta.'

        : 'pip install --upgrade openpyxl';



    throw Exception(

      'Export Mod.RCC richiede Python 3 con openpyxl, per mantenere logo e certificazioni.\n'

      '$hint\n'

      'Tentativi: ${errors.isEmpty ? "nessun interprete trovato" : errors.join(" | ")}',

    );

  }

}


