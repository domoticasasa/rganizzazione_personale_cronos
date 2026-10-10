import 'local_fs_scanner.dart';

Future<LocalScanResult> listLocalFilesRecursive(String rootPath) async {
  return const LocalScanResult(
    supported: false,
    files: <String>[],
    error: 'Scansione cartelle locali non supportata su questa piattaforma.',
  );
}
