import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// Su web `excel.delete()` e `excel.rename()` falliscono con
/// "Cannot remove from an unmodifiable list" (liste XML/archive read-only).
Sheet excelUseDefaultSheet(Excel excel) {
  if (excel.tables.isEmpty) return excel['Sheet1'];
  return excel[excel.tables.keys.first];
}

void excelDeleteSheetIfPossible(Excel excel, String name) {
  if (kIsWeb) return;
  try {
    if (excel.sheets.keys.contains(name) || excel.tables.containsKey(name)) {
      excel.delete(name);
    }
  } catch (_) {}
}

void excelRenameIfPossible(Excel excel, String from, String to) {
  if (kIsWeb) return;
  if (from == to || to.trim().isEmpty) return;
  try {
    excel.rename(from, to);
  } catch (_) {}
}
