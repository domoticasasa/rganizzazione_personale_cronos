import 'dart:io' as io;

import 'local_fs_scanner.dart';

Future<LocalScanResult> listLocalFilesRecursive(String rootPath) async {
  try {
    final root = io.Directory(rootPath);
    if (!await root.exists()) {
      return const LocalScanResult(
        supported: true,
        files: <String>[],
        error: 'La cartella selezionata non esiste.',
      );
    }

    final out = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is io.File) {
        out.add(entity.path);
      }
    }

    return LocalScanResult(supported: true, files: out);
  } catch (e) {
    return LocalScanResult(
      supported: true,
      files: const <String>[],
      error: 'Errore scansione cartelle: $e',
    );
  }
}
