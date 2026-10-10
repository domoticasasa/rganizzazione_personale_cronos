
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/commessa_tesserino_modelli_service.dart';
import '../services/supabase_service.dart';
import '../services/tesserino_foto.dart';
import '../services/tesserino_pdf_export.dart';
import '../services/tesserino_web_image_pick.dart';
import '../utils/device.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/modify_feedback.dart';
import '../utils/personale_profile_resolver.dart';
import '../widgets/cronos_tesserino_card.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Vista tesserino per il dipendente collegato (anteprima + PDF + foto).
class DipendenteTesserinoPage extends StatefulWidget {
  final int userId;

  const DipendenteTesserinoPage({super.key, required this.userId});

  @override
  State<DipendenteTesserinoPage> createState() => _DipendenteTesserinoPageState();
}

class _DipendenteTesserinoPageState extends State<DipendenteTesserinoPage> {
  final _supa = SupabaseService.client;
  bool _loading = true;
  Map<String, dynamic>? _row;
  int _fotoReloadToken = 0;
  Uint8List? _fotoPreviewBytes;
  List<CommessaTesserinoOpzione> _opzioniCommessa = const [];
  String? _selCommessaUuid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool tryPendingFoto = true}) async {
    setState(() => _loading = true);
    try {
      _row = await resolveMyPersonaleRow(select: kPersonaleTesserinoSelect);
      if (_row != null) {
        final personaleUuid = (_row!['id_uuid'] ?? '').toString().trim();
        _opzioniCommessa = personaleUuid.isEmpty
            ? const []
            : await CommessaTesserinoModelliService.loadOpzioniPerPersonale(
                _supa,
                personaleUuid,
              );
        final saved =
            (_row!['tesserino_commessa_id_uuid'] ?? '').toString().trim();
        _selCommessaUuid = CommessaTesserinoModelliService.findOpzione(
                  _opzioniCommessa,
                  saved.isEmpty ? null : saved,
                ) !=
                null
            ? saved
            : null;
      } else {
        _opzioniCommessa = const [];
        _selCommessaUuid = null;
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore caricamento: $e');
      }
      _row = null;
      _opzioniCommessa = const [];
      _selCommessaUuid = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (tryPendingFoto && mounted && kIsWeb && _row != null) {
      await _provaRipristinaFotoPending();
    }
  }

  /// Dopo reload iOS/PWA: se la fotocamera ha lasciato bytes in sessionStorage, salva.
  Future<void> _provaRipristinaFotoPending() async {
    final pending = peekPendingTesserinoFotoBytes();
    if (pending == null || pending.isEmpty || _row == null) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto da salvare'),
        content: const Text(
          'È stata trovata una foto scattata poco fa (prima del ripristino pagina). '
          'Vuoi salvarla sul tesserino?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Scarta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      if (ok == false) clearPendingTesserinoFotoBytes();
      return;
    }

    clearPendingTesserinoFotoBytes();
    try {
      final picked = await runWithTesserinoPhotoBusy(
        context,
        () => tesserinoPickedFromRawBytes(pending),
        message: 'Elaborazione foto…',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _loading = true;
        _fotoPreviewBytes = picked.bytes;
      });
      final newPath = await runWithTesserinoPhotoBusy(
        context,
        () => uploadTesserinoFotoForPersonale(
          supa: _supa,
          personaleId: _row!['id'] as int,
          personaleIdUuid: (_row!['id_uuid'] ?? '').toString(),
          image: picked,
          existingStoragePath: (_row!['foto_tesserino_path'] ?? '').toString(),
        ),
        message: 'Caricamento foto…',
      );
      if (mounted) {
        _row!['foto_tesserino_path'] = newPath;
        setState(() => _fotoReloadToken++);
        ModifyFeedback.success(context, 'Foto tesserino aggiornata');
      }
      await _load(tryPendingFoto: false);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Salvataggio foto recuperata: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CommessaTesserinoOpzione? get _opzioneSelezionata =>
      CommessaTesserinoModelliService.findOpzione(
        _opzioniCommessa,
        _selCommessaUuid,
      );

  List<String>? get _righeExtraCommessa {
    final opzione = _opzioneSelezionata;
    if (opzione == null || opzione.righeExtra.isEmpty) return null;
    return opzione.righeExtra;
  }

  CronosTesserinoViewData _buildView() {
    return cronosTesserinoDataFromPersonale(
      _row!,
      fotoReloadToken: _fotoReloadToken,
      fotoPreviewBytes: _fotoPreviewBytes,
      righeExtraOverride: _righeExtraCommessa,
    );
  }

  Future<void> _onCommessaChanged(String? uuid) async {
    if (uuid == _selCommessaUuid) return;
    setState(() {
      _selCommessaUuid = uuid;
      _loading = true;
    });
    try {
      await _supa.from('personale').update({
        'tesserino_commessa_id_uuid': uuid,
      }).eq('id', _row!['id']);
      if (_row != null) {
        _row!['tesserino_commessa_id_uuid'] = uuid;
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.hint(
          context,
          'Commessa aggiornata in anteprima; salvataggio preferenza non riuscito.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cambiaFoto() async {
    if (_row == null) return;

    // Non avvolgere la selezione in busy dialog: su mobile web interferisce
    // col file input / fotocamera e puo' resettare la navigazione.
    TesserinoPickedImage? picked;
    try {
      picked = await pickTesserinoImageInteractive(context);
      if (picked == null && kIsWeb && mounted) {
        final pending = takePendingTesserinoFotoBytes();
        if (pending != null && pending.isNotEmpty) {
          picked = await runWithTesserinoPhotoBusy(
            context,
            () => tesserinoPickedFromRawBytes(pending),
            message: 'Recupero foto dopo fotocamera…',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Elaborazione foto: $e');
      }
      return;
    }

    if (picked == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessuna foto selezionata o immagine non leggibile.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _fotoPreviewBytes = picked!.bytes;
    });

    try {
      final newPath = await runWithTesserinoPhotoBusy(
        context,
        () => uploadTesserinoFotoForPersonale(
          supa: _supa,
          personaleId: _row!['id'] as int,
          personaleIdUuid: (_row!['id_uuid'] ?? '').toString(),
          image: picked!,
          existingStoragePath: (_row!['foto_tesserino_path'] ?? '').toString(),
        ),
        message: 'Caricamento foto…',
      );
      clearPendingTesserinoFotoBytes();
      if (mounted) {
        _row!['foto_tesserino_path'] = newPath;
        setState(() => _fotoReloadToken++);
        ModifyFeedback.success(context, 'Foto tesserino aggiornata');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _fotoPreviewBytes = null);
        ModifyFeedback.error(context, 'Upload fallito: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pdf() async {
    if (_row == null) return;
    setState(() => _loading = true);
    try {
      final path = (_row!['foto_tesserino_path'] ?? '').toString();
      final fotoBytes = path.trim().isEmpty
          ? null
          : await loadTesserinoFotoBytes(path);
      final view = _buildView();
      final pdf =
          await buildTesserinoPdfBytes(data: view, fotoBytes: fotoBytes);
      final safeName = (_row!['full_name'] ?? 'tesserino')
          .toString()
          .replaceAll(RegExp(r'[^\w\-]+'), '_');
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'tesserino_$safeName',
        bytes: pdf,
        extension: 'pdf',
        openFile: true,
      );
      if (mounted) {
        final path = ExcelExportHelper.lastSavedPath ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved && path.isNotEmpty
                  ? 'PDF salvato e aperto: $path'
                  : 'PDF salvato',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'PDF: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Widget> _toolbarActions() => [
        IconButton(
          tooltip: 'Scarica PDF',
          onPressed: _loading ? null : _pdf,
          icon: const Icon(Icons.badge_outlined),
        ),
        IconButton(
          tooltip: 'Aggiorna',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ];

  Widget _commessaSelector() {
    if (_opzioniCommessa.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<String?>(
      initialValue: _selCommessaUuid,
      decoration: const InputDecoration(
        labelText: 'Commessa (opzionale)',
        border: OutlineInputBorder(),
        helperText:
            'Opzionale: righe aggiuntive del modello commessa. '
            'Senza selezione restano le righe salvate sul tuo profilo.',
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('— Nessuna commessa —'),
        ),
        for (final o in _opzioniCommessa)
          DropdownMenuItem<String?>(
            value: o.commessaIdUuid,
            child: Text(o.commessaNome),
          ),
      ],
      onChanged: _loading ? null : _onCommessaChanged,
    );
  }

  Widget _buildContent(CronosTesserinoViewData view, double cardW) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _commessaSelector(),
          const SizedBox(height: 16),
          Center(child: CronosTesserinoCard(width: cardW, data: view)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _pdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text(
              'Scarica PDF (A4, tesserino 85,60x53,98 mm)',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _cambiaFoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text(
              'Scatta / aggiorna foto (35×45 mm, sfondo bianco)',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Il mio tesserino';

    if (_loading && _row == null) {
      return buildGestoproAwarePage(
        context: context,
        title: title,
        classicAppBar: wrapClassicAppBarChrome(
          context,
          AppBar(title: const Text(title)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_row == null) {
      return buildGestoproAwarePage(
        context: context,
        title: title,
        classicAppBar: wrapClassicAppBarChrome(
          context,
          AppBar(title: const Text(title)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nessun profilo personale collegato al tuo account. '
              'Contatta l’amministrazione.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final view = _buildView();
    final w = MediaQuery.sizeOf(context).width - 32;
    final cardW = isMobileDevice() ? w.clamp(260.0, 400.0) : 400.0;
    final actions = _toolbarActions();

    return buildGestoproAwarePage(
      context: context,
      title: title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Text(title),
        actions: actions,
      )),
      body: _buildContent(view, cardW),
    );
  }
}
