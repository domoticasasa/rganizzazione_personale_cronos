import 'local_fs_scanner_stub.dart'
    if (dart.library.io) 'local_fs_scanner_io.dart' as impl;

class LocalScanResult {
  final bool supported;
  final List<String> files;
  final String? error;

  const LocalScanResult({
    required this.supported,
    required this.files,
    this.error,
  });
}

Future<LocalScanResult> listLocalFilesRecursive(String rootPath) {
  return impl.listLocalFilesRecursive(rootPath);
}
