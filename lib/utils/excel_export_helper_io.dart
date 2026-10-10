import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String? _lastSavedPath;
String? get lastSavedPath => _lastSavedPath;

String buildFileName(String pageName, {String extension = 'xlsx'}) {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final safePage = pageName
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  final ext = extension.trim().replaceAll('.', '');
  return '${safePage}_$y-$m-${d}_$hh-$mm.$ext';
}

Future<void> _openFileWithDefaultApp(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start(
        'cmd',
        ['/c', 'start', '', path],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
    } else if (Platform.isMacOS) {
      await Process.start('open', [path], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    }
  } catch (_) {}
}

Future<bool> saveAndReveal({
  required String pageName,
  required Uint8List bytes,
  String extension = 'xlsx',
  bool openFile = false,
}) async {
  final suggestedName = buildFileName(pageName, extension: extension);
  Directory? baseDir;
  try {
    baseDir = await getDownloadsDirectory();
  } catch (_) {}
  baseDir ??= await getApplicationDocumentsDirectory();
  final file = File('${baseDir.path}${Platform.pathSeparator}$suggestedName');
  await file.writeAsBytes(bytes, flush: true);
  _lastSavedPath = file.path;

  try {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', file.path],
          mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', file.path],
          mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [file.parent.path],
          mode: ProcessStartMode.detached);
    }
  } catch (_) {
    // Non bloccare il flusso export se l'apertura cartella fallisce.
  }
  if (openFile) {
    await _openFileWithDefaultApp(file.path);
  }
  return true;
}
