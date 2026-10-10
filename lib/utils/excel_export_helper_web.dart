
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

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

MimeType _mimeForExtension(String extension) {
  final ext = extension.trim().toLowerCase().replaceAll('.', '');
  return switch (ext) {
    'pdf' => MimeType.pdf,
    'csv' => MimeType.csv,
    'txt' => MimeType.text,
    'vcf' => MimeType.text,
    _ => MimeType.microsoftExcel,
  };
}

String _baseNameWithoutExtension(String fileName, String extension) {
  final ext = extension.trim().toLowerCase().replaceAll('.', '');
  final lower = fileName.toLowerCase();
  final suffix = '.$ext';
  if (lower.endsWith(suffix)) {
    return fileName.substring(0, fileName.length - suffix.length);
  }
  return fileName;
}

Future<bool> saveAndReveal({
  required String pageName,
  required Uint8List bytes,
  String extension = 'xlsx',
  bool openFile = false,
}) async {
  if (bytes.isEmpty) return false;

  final fileName = buildFileName(pageName, extension: extension);
  final ext = extension.trim().replaceAll('.', '');
  final baseName = _baseNameWithoutExtension(fileName, ext);

  try {
    await FileSaver.instance.saveFile(
      name: baseName,
      bytes: bytes,
      ext: ext,
      mimeType: _mimeForExtension(ext),
    );
    _lastSavedPath = fileName;
    return true;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('ExcelExportHelper web: $e\n$st');
    }
    return false;
  }
}
