import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/field_timestamps.dart';

const Duration kAuditHoverTooltipWait = Duration(milliseconds: 220);

DataCell decorateDataCellWithAuditHover(
  DataCell cell, {
  required Map<String, dynamic> row,
  required String fieldKey,
  Map<String, String> userNamesByUuid = const {},
  bool rowAuditWhenFieldMissing = true,
  String? fieldLabel,
  String? copyOnDoubleTapText,
  void Function(String text)? onTextCopied,
}) {
  VoidCallback? onDoubleTap = cell.onDoubleTap;
  if (onDoubleTap == null) {
    final copyText = (copyOnDoubleTapText ?? '').trim();
    if (copyText.isNotEmpty) {
      onDoubleTap = () async {
        await Clipboard.setData(ClipboardData(text: copyText));
        onTextCopied?.call(copyText);
      };
    }
  }

  return DataCell(
    Tooltip(
      message: fieldAuditHoverMessage(
        row,
        fieldKey,
        userNamesByUuid,
        rowAuditWhenFieldMissing: rowAuditWhenFieldMissing,
        fieldLabel: fieldLabel,
      ),
      waitDuration: kAuditHoverTooltipWait,
      showDuration: const Duration(seconds: 12),
      preferBelow: false,
      child: cell.child,
    ),
    placeholder: cell.placeholder,
    showEditIcon: cell.showEditIcon,
    onTap: cell.onTap,
    onDoubleTap: onDoubleTap,
    onLongPress: cell.onLongPress,
    onTapDown: cell.onTapDown,
    onTapCancel: cell.onTapCancel,
  );
}

/// Alias per tabelle con celle già costruite e chiave colonna nota.
DataCell decorateDataCellWithFieldAudit(
  DataCell cell, {
  required Map<String, dynamic> row,
  required String fieldKey,
  Map<String, String> userNamesByUuid = const {},
  bool rowAuditWhenFieldMissing = true,
  String? fieldLabel,
  String? copyOnDoubleTapText,
  void Function(String text)? onTextCopied,
}) =>
    decorateDataCellWithAuditHover(
      cell,
      row: row,
      fieldKey: fieldKey,
      userNamesByUuid: userNamesByUuid,
      rowAuditWhenFieldMissing: rowAuditWhenFieldMissing,
      fieldLabel: fieldLabel,
      copyOnDoubleTapText: copyOnDoubleTapText,
      onTextCopied: onTextCopied,
    );

Widget wrapWithAuditHover(
  Widget child, {
  required Map<String, dynamic> row,
  required String fieldKey,
  Map<String, String> userNamesByUuid = const {},
  bool rowAuditWhenFieldMissing = true,
  String? fieldLabel,
}) {
  return Tooltip(
    message: fieldAuditHoverMessage(
      row,
      fieldKey,
      userNamesByUuid,
      rowAuditWhenFieldMissing: rowAuditWhenFieldMissing,
      fieldLabel: fieldLabel,
    ),
    waitDuration: kAuditHoverTooltipWait,
    showDuration: const Duration(seconds: 12),
    preferBelow: false,
    child: child,
  );
}
