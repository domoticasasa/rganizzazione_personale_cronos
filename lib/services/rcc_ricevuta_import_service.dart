import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/device.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/web_in_app_camera.dart';
import 'app_device_unlock_gate.dart';
import 'rcc_ricevuta_carburante_parser.dart';
import 'rcc_ricevuta_ocr.dart';
import 'tesserino_foto.dart';
import 'tesserino_web_image_pick.dart';

class _RicevutaPickResult {
  const _RicevutaPickResult({
    this.bytes,
    this.name = 'ricevuta.jpg',
    this.pastedText,
  });

  final Uint8List? bytes;
  final String name;
  final String? pastedText;
}

/// Selezione immagine + OCR (mobile) o incolla testo (desktop/web).
abstract final class RccRicevutaImportService {
  RccRicevutaImportService._();

  static Future<RccRicevutaParsed?> importInteractive(BuildContext context) {
    return AppDeviceUnlockGate.runWithExternalPicker(() async {
    final pick = await _pickRicevutaSource(context);
    if (pick == null) return null;

    RccRicevutaParsed? parsed;
    if (pick.bytes != null) {
      parsed = await _recognizeParsed(context, pick.bytes!, pick.name);
    } else if (pick.pastedText != null) {
      parsed = RccRicevutaCarburanteParser.parse(pick.pastedText!);
    }

    if (parsed == null || !parsed.hasAnyField) {
      if (!context.mounted) return null;
      final edited = await _pasteTextDialog(
        context,
        initialText: pick.pastedText ?? '',
        hint:
            'OCR poco leggibile. Correggi o incolla il testo della ricevuta '
            'o dello scontrino cartaceo.',
      );
      if (edited == null || edited.trim().isEmpty) return null;
      parsed = RccRicevutaCarburanteParser.parse(edited);
      if (!parsed.hasAnyField) {
        if (!context.mounted) return null;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Nessun dato riconosciuto'),
            content: const Text(
              'Non sono stati trovati campi utili nel testo. '
              'Prova uno screenshot dell’app o una foto dello scontrino '
              'ben illuminata, con tutta la ricevuta visibile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return null;
      }
    }

    if (!context.mounted) return parsed;
    return _confirmParsed(context, parsed);
    });
  }

  static Future<RccRicevutaParsed?> _recognizeParsed(
    BuildContext context,
    Uint8List bytes,
    String name,
  ) async {
    return runWithTesserinoPhotoBusy<RccRicevutaParsed?>(
      context,
      () => RccRicevutaOcrPlatform.recognizeParsedFromBytes(bytes, name),
      message: 'Lettura ricevuta in corso…',
    );
  }

  static Future<_RicevutaPickResult?> _pickRicevutaSource(
    BuildContext context,
  ) async {
    final mobileUi = isMobileDevice() || (kIsWeb && useMobileUi(context));

    if (mobileUi && kIsWeb) {
      return _pickRicevutaWebMobile(context);
    }

    if (mobileUi) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Scatta foto ricevuta'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Scegli screenshot o foto scontrino'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Scegli file immagine'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: const Text('Incolla testo ricevuta'),
                onTap: () => Navigator.pop(ctx, 'paste'),
              ),
            ],
          ),
        ),
      );
      if (action == null || !context.mounted) return null;

      if (action == 'paste') {
        final text = await _pasteTextDialog(context);
        if (text == null) return null;
        return _RicevutaPickResult(pastedText: text);
      }
      if (action == 'file') {
        return _pickRicevutaFile(context);
      }
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      return _RicevutaPickResult(bytes: bytes, name: x.name);
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa da ricevuta'),
        content: Text(
          RccRicevutaOcrPlatform.isSupported
              ? 'Carica lo screenshot dell’app o la foto dello scontrino, oppure incolla il testo.'
              : 'Carica lo screenshot o la foto dello scontrino, oppure incolla il testo '
                  '(OCR automatico su telefono; su PC desktop usa incolla testo).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const Text('Scegli immagine'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'paste'),
            child: const Text('Incolla testo'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return null;
    if (action == 'paste') {
      final text = await _pasteTextDialog(context);
      if (text == null) return null;
      return _RicevutaPickResult(pastedText: text);
    }
    return _pickRicevutaFile(context);
  }

  static Future<_RicevutaPickResult?> _pickRicevutaWebMobile(
    BuildContext context,
  ) async {
    final marker = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta foto ricevuta'),
              subtitle: const Text('Resta in CRONOS, senza aprire la Camera'),
              onTap: () => unawaited(_webCaptureRicevutaInApp(sheetCtx)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli screenshot o foto scontrino'),
              onTap: () => _webPickRicevutaFromSheet(sheetCtx, camera: false),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('Incolla testo ricevuta'),
              onTap: () => Navigator.pop(sheetCtx, '__paste__'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return null;
    if (marker == '__paste__') {
      final text = await _pasteTextDialog(context);
      if (text == null) return null;
      return _RicevutaPickResult(pastedText: text);
    }
    if (marker is _RicevutaPickResult) return marker;
    return null;
  }

  static Future<void> _webCaptureRicevutaInApp(BuildContext sheetCtx) async {
    final bytes = await capturePhotoInApp(
      sheetCtx,
      title: 'Foto scontrino',
      hint:
          'Inquadra tutto lo scontrino, ben illuminato, poi tocca Scatta. '
          'CRONOS non lascia l’app: niente Camera di sistema né impronta al rientro.',
    );
    if (!sheetCtx.mounted) return;
    await _finishWebRicevutaBytes(sheetCtx, bytes);
  }

  static void _webPickRicevutaFromSheet(
    BuildContext sheetCtx, {
    required bool camera,
  }) {
    pickTesserinoWebImageOnUserGesture(
      camera: camera,
      onDone: (bytes) => _finishWebRicevutaBytes(sheetCtx, bytes),
    );
  }

  static Future<void> _finishWebRicevutaBytes(
    BuildContext sheetCtx,
    Uint8List? bytes,
  ) async {
    if (!sheetCtx.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    if (sheetCtx.mounted) {
      Navigator.pop(
        sheetCtx,
        _RicevutaPickResult(bytes: bytes, name: 'ricevuta.jpg'),
      );
    }
  }

  static Future<_RicevutaPickResult?> _pickRicevutaFile(
    BuildContext context,
  ) async {
    const group = XTypeGroup(
      label: 'Immagini',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return _RicevutaPickResult(bytes: bytes, name: file.name);
  }

  static Future<String?> _pasteTextDialog(
    BuildContext context, {
    String? hint,
    String? initialText,
  }) async {
    final ctrl = TextEditingController(text: initialText ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Testo ricevuta'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: hint ?? 'Incolla qui il testo della ricevuta…',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Analizza'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || text.isEmpty) return null;
    return text;
  }

  static Future<RccRicevutaParsed?> _confirmParsed(
    BuildContext context,
    RccRicevutaParsed parsed,
  ) async {
    String line(String label, String? v) =>
        v?.trim().isNotEmpty == true ? '$label: ${v!.trim()}' : '$label: —';

    final body = [
      line('Data', parsed.dataGgMmAaaa),
      line('Carta', parsed.numeroCarta),
      line('Litri', parsed.litri),
      line('Euro', parsed.euro),
      line('KM', parsed.km),
      line('Tipo', parsed.tipoCarburante ?? parsed.prodottoOriginale),
      if (parsed.note.isNotEmpty) '',
      ...parsed.note.map((n) => '• $n'),
      '',
      'DT e commessa restano da compilare manualmente.',
    ].join('\n');

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dati rilevati dalla ricevuta'),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compila campi'),
          ),
        ],
      ),
    );

    if (apply == true) return parsed;
    return null;
  }
}
