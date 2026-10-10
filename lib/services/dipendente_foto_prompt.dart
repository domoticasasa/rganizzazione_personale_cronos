import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../services/tesserino_foto.dart';
import '../utils/modify_feedback.dart';
import '../utils/personale_profile_resolver.dart';
import '../utils/roles.dart';
import '../widgets/user_profile_avatar.dart';

const String _kPersonaleFotoPromptSelect =
    'id, id_uuid, user_id, foto_tesserino_path';

/// Popup foto tesserino all’accesso dipendente, se manca la fotografia.
///
/// «Posponi» chiude solo per questa apertura dell’app: al prossimo accesso
/// la richiesta torna. Con foto già presente non si chiede nulla.
abstract final class DipendenteFotoPrompt {
  static bool _askedThisLaunch = false;

  static void resetSession() {
    _askedThisLaunch = false;
  }

  static Future<void> maybeAsk(
    BuildContext? context, {
    void Function(String fotoPath)? onUploaded,
  }) async {
    if (context == null || !context.mounted) return;
    if (_askedThisLaunch) return;
    _askedThisLaunch = true;

    final bundle = await resolveMyProfileBundle(
      select: _kPersonaleFotoPromptSelect,
    );
    if (!context.mounted) return;

    final role = normalizeRole((bundle.users?['role'] ?? '').toString());
    if (!const {'dipendente', 'dipendenti', 'user'}.contains(role)) return;

    var personale = bundle.personale;
    var existing = (personale?['foto_tesserino_path'] ?? '').toString().trim();
    if (existing.isEmpty) {
      existing = (await resolveMyFotoTesserinoPath() ?? '').trim();
    }
    if (!context.mounted) return;
    if (existing.isNotEmpty) return;

    personale ??= await resolveMyPersonaleRow(select: _kPersonaleFotoPromptSelect);
    if (!context.mounted) return;
    if (personale == null) return;

    final idRaw = personale['id'];
    final personaleId = idRaw is int ? idRaw : int.tryParse('$idRaw');
    final personaleUuid = (personale['id_uuid'] ?? '').toString().trim();
    if (personaleId == null || personaleId <= 0 || personaleUuid.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DipendenteFotoTesserinoPromptDialog(
        personaleId: personaleId,
        personaleUuid: personaleUuid,
        onUploaded: onUploaded,
      ),
    );
  }
}

class _DipendenteFotoTesserinoPromptDialog extends StatefulWidget {
  final int personaleId;
  final String personaleUuid;
  final void Function(String fotoPath)? onUploaded;

  const _DipendenteFotoTesserinoPromptDialog({
    required this.personaleId,
    required this.personaleUuid,
    this.onUploaded,
  });

  @override
  State<_DipendenteFotoTesserinoPromptDialog> createState() =>
      _DipendenteFotoTesserinoPromptDialogState();
}

class _DipendenteFotoTesserinoPromptDialogState
    extends State<_DipendenteFotoTesserinoPromptDialog> {
  bool _busy = false;

  void _posponi() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  Future<void> _apriFotocamera() async {
    if (_busy) return;

    TesserinoPickedImage? picked;
    try {
      picked = await pickTesserinoImageFromCamera(context);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Fotocamera: $e');
      }
      return;
    }
    if (!mounted) return;
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final path = await runWithTesserinoPhotoBusy(
        context,
        () => uploadTesserinoFotoForPersonale(
          supa: SupabaseService.client,
          personaleId: widget.personaleId,
          personaleIdUuid: widget.personaleUuid,
          image: picked!,
        ),
        message: 'Caricamento foto…',
      );
      if (!mounted) return;
      if (path == null || path.trim().isEmpty) {
        ModifyFeedback.error(context, 'Caricamento foto non riuscito.');
        return;
      }
      SessionUserAvatar.rememberFotoPath(path);
      widget.onUploaded?.call(path);
      ModifyFeedback.success(context, 'Foto salvata. Grazie.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Upload foto: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _posponi();
      },
      child: AlertDialog(
        title: const Text('Foto per il tesserino'),
        content: const SingleChildScrollView(
          child: Text(
            'Non abbiamo ancora una tua fotografia.\n\n'
            'Scattala ora con uno sfondo bianco alle spalle '
            '(parete chiara, viso ben illuminato, senza cappello '
            'né occhiali da sole).\n\n'
            'Serve per il tesserino aziendale.',
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: _busy ? null : _posponi,
            child: const Text('Posponi'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _apriFotocamera,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: const Text('Apri fotocamera'),
          ),
        ],
      ),
    );
  }
}
