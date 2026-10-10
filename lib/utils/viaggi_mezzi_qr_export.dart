import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/viaggi_mezzi_stradali_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/modify_feedback.dart';
import '../widgets/viaggi_mezzi_qr_card.dart';

/// Mostra il QR del mezzo e consente di scaricarlo (PDF 10×10 cm).
Future<void> showViaggiMezziQrExportDialog({
  required BuildContext context,
  required SupabaseClient client,
  required String mezzoIdUuid,
  required String mezzoLabel,
}) async {
  final id = mezzoIdUuid.trim();
  if (id.isEmpty) return;

  String? token;
  try {
    token = await ViaggiMezziStradaliService.ensureQrToken(client, id);
  } catch (e) {
    if (!context.mounted) return;
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    ModifyFeedback.error(
      context,
      msg.trim().isEmpty ? 'Impossibile generare QR per il mezzo.' : msg,
    );
    return;
  }
  if (token == null || token.isEmpty) {
    if (context.mounted) {
      ModifyFeedback.error(context, 'Impossibile generare QR per il mezzo.');
    }
    return;
  }
  if (!context.mounted) return;

  final qrToken = token;
  final qrKey = GlobalKey();
  final label = mezzoLabel.trim().isEmpty ? 'Mezzo' : mezzoLabel.trim();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('QR code mezzo — $label'),
      content: SingleChildScrollView(
        child: ViaggiMezziQrCard(
          repaintBoundaryKey: qrKey,
          mezzoLabel: label,
          qrToken: qrToken,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            final png = await captureViaggiMezziQrPng(qrKey);
            if (png == null || png.isEmpty) {
              if (ctx.mounted) {
                ModifyFeedback.error(
                  ctx,
                  'Impossibile generare immagine QR.',
                );
              }
              return;
            }
            final pdfBytes = await buildViaggiMezziQrPdf(pngBytes: png);
            final safeName = label.replaceAll(RegExp(r'[^\w\-]+'), '_');
            final ok = await ExcelExportHelper.saveAndReveal(
              pageName: 'QR_mezzo_10cm_$safeName',
              bytes: pdfBytes,
              extension: 'pdf',
              openFile: true,
            );
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'QR salvato (PDF 10×10 cm).'
                        : 'Salvataggio QR annullato.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.download_outlined),
          label: const Text('Scarica QR (PDF 10×10 cm)'),
        ),
      ],
    ),
  );
}
