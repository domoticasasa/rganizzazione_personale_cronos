import 'dart:async';
import 'dart:typed_data';

import '../services/app_activity_log_service.dart';
import 'excel_export_helper_io.dart'
    if (dart.library.html) 'excel_export_helper_web.dart' as impl;

class ExcelExportHelper {
  ExcelExportHelper._();

  static String? get lastSavedPath => impl.lastSavedPath;

  static String buildFileName(
    String pageName, {
    String extension = 'xlsx',
  }) =>
      impl.buildFileName(pageName, extension: extension);

  static Future<bool> saveAndReveal({
    required String pageName,
    required Uint8List bytes,
    String extension = 'xlsx',
    bool openFile = false,
  }) async {
    final ok = await impl.saveAndReveal(
      pageName: pageName,
      bytes: bytes,
      extension: extension,
      openFile: openFile,
    );
    if (ok) {
      final ext = extension.trim().replaceAll('.', '').toUpperCase();
      unawaited(
        AppActivityLogService.record(
          action: 'export',
          detail: '$ext $pageName',
        ),
      );
    }
    return ok;
  }
}
