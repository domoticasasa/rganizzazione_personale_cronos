import 'package:flutter/material.dart';

String buildNotePreview(String input, {int maxChars = 10}) {
  final clean = input.trim();
  if (clean.isEmpty) return '';
  if (clean.length <= maxChars) return clean;
  return '${clean.substring(0, maxChars)}...';
}

class NotePreviewText extends StatelessWidget {
  final String note;
  final String? prefix;
  final int maxChars;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final String emptyText;

  const NotePreviewText({
    super.key,
    required this.note,
    this.prefix,
    this.maxChars = 10,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.visible,
    this.emptyText = '',
  });

  @override
  Widget build(BuildContext context) {
    final clean = note.trim();
    if (clean.isEmpty) {
      return Text(
        emptyText,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    final short = buildNotePreview(clean, maxChars: maxChars);
    final shown = '${prefix ?? ''}$short';
    final full = '${prefix ?? ''}$clean';
    return Tooltip(
      message: full,
      waitDuration: const Duration(milliseconds: 250),
      child: Text(
        shown,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
