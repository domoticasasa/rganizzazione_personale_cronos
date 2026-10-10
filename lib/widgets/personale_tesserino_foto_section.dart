import 'package:flutter/material.dart';

/// Riga stato foto + pulsante upload (Gestione dipendenti / tesserini).
class PersonaleTesserinoFotoSection extends StatelessWidget {
  final String? fotoPath;
  final bool canUpload;
  final bool uploading;
  final VoidCallback? onUpload;
  final Color textColor;

  const PersonaleTesserinoFotoSection({
    super.key,
    required this.fotoPath,
    required this.canUpload,
    this.uploading = false,
    this.onUpload,
    this.textColor = const Color(0xFF222222),
  });

  @override
  Widget build(BuildContext context) {
    final hasFoto = (fotoPath ?? '').trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto tesserino: ${hasFoto ? 'presente' : 'assente'}',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (canUpload)
          TextButton(
            onPressed: uploading ? null : onUpload,
            child: uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Scatta / carica foto (35×45 mm, sfondo bianco)'),
          )
        else
          Text(
            'Salva il dipendente per poter caricare la foto.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.55),
                ),
          ),
      ],
    );
  }
}
