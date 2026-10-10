import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/supabase_service.dart';
import '../services/viaggi_mezzi_stradali_service.dart';
import '../utils/buoni_pasto_scan_gps.dart';
import '../utils/date_formatters.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/modify_feedback.dart';
import '../widgets/buoni_pasto_web_qr_scanner.dart';
import '../widgets/classic_app_bar_chrome.dart';

class DipendenteViaggioMezzoScanPage extends StatefulWidget {
  const DipendenteViaggioMezzoScanPage({
    super.key,
    required this.userId,
    this.initialQr,
  });

  final int userId;

  /// Token/URL già letto (es. QR aperto con la fotocamera del telefono).
  final String? initialQr;

  @override
  State<DipendenteViaggioMezzoScanPage> createState() =>
      _DipendenteViaggioMezzoScanPageState();
}

class _DipendenteViaggioMezzoScanPageState
    extends State<DipendenteViaggioMezzoScanPage> {
  final _supa = SupabaseService.client;
  final _manualCtrl = TextEditingController();
  bool _busy = false;
  bool _handled = false;
  MobileScannerController? _scanner;

  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_isNativeMobile) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    }
    final initial = widget.initialQr?.trim() ?? '';
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _processScan(initial);
      });
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<int?> _askKm({
    required String title,
    required String mezzoLabel,
    int? kmMinimo,
  }) async {
    final ctrl = TextEditingController();
    final res = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          String? errorText;

          void confirm() {
            final raw = ctrl.text.trim();
            if (raw.isEmpty) {
              setSt(() => errorText = 'Inserisci il chilometraggio');
              return;
            }
            final km = int.tryParse(raw);
            if (km == null) {
              setSt(() => errorText = 'Chilometraggio non valido');
              return;
            }
            if (km < 0) {
              setSt(() => errorText = 'Il chilometraggio non può essere negativo');
              return;
            }
            if (kmMinimo != null && km < kmMinimo) {
              setSt(
                () => errorText =
                    'Il km deve essere almeno $kmMinimo (partenza viaggio)',
              );
              return;
            }
            Navigator.pop(ctx, km);
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mezzoLabel),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Chilometraggio *',
                    helperText: kmMinimo != null
                        ? 'Obbligatorio: inserisci manualmente il valore sul cruscotto. '
                            'Non può essere inferiore a $kmMinimo km (apertura).'
                        : 'Obbligatorio: inserisci manualmente il valore sul cruscotto.',
                    errorText: errorText,
                  ),
                  autofocus: true,
                  onChanged: (_) {
                    if (errorText != null) setSt(() => errorText = null);
                  },
                  onSubmitted: (_) => confirm(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: confirm,
                child: const Text('Conferma'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _processScan(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _handled = true;
    });
    try {
      final stato = await ViaggiMezziStradaliService.loadStatoScansione(
        _supa,
        raw,
      );
      if (!mounted) return;

      if (stato.isBloccato) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Viaggio in corso'),
            content: Text(stato.messaggio ?? 'Viaggio già aperto su questo mezzo.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        setState(() => _handled = false);
        return;
      }

      final km = await _askKm(
        title: stato.isChiusura ? 'Chiusura viaggio' : 'Apertura viaggio',
        mezzoLabel: stato.mezzoLabel,
        kmMinimo: stato.isChiusura ? stato.kmPartenza : null,
      );
      if (km == null) {
        setState(() => _handled = false);
        return;
      }

      final gps = await BuoniPastoScanGps.capture(
        context: context,
        purpose: GpsPurpose.viaggioMezzo,
      );
      final res = await ViaggiMezziStradaliService.registraScansione(
        _supa,
        raw,
        km,
        latitudine: gps?.lat,
        longitudine: gps?.lon,
      );
      if (!mounted) return;

      final gpsLabel = gps != null
          ? formatGpsCoordsText(gps.lat, gps.lon)
          : 'Non rilevata';

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(res.isChiusura ? 'Viaggio chiuso' : 'Viaggio aperto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mezzo: ${res.mezzoLabel}'),
              Text('Conducente: ${res.conducenteNome}'),
              Text('Km partenza: ${res.kmPartenza}'),
              if (res.kmArrivo != null) Text('Km arrivo: ${res.kmArrivo}'),
              if (res.kmPercorsi != null) Text('Km percorsi: ${res.kmPercorsi}'),
              if (res.iniziatoAt != null)
                Text('Ora inizio: ${formatDateTimeIt(res.iniziatoAt!)}'),
              if (res.chiusoAt != null)
                Text('Ora fine: ${formatDateTimeIt(res.chiusoAt!)}'),
              const SizedBox(height: 8),
              Text('Posizione: $gpsLabel'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, '$e');
        setState(() => _handled = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(String raw) {
    if (_handled || _busy) return;
    final value = raw.trim();
    if (value.isNotEmpty) _processScan(value);
  }

  void _onBarcodeCapture(BarcodeCapture capture) {
    if (_handled || _busy) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) {
        _processScan(raw);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(title: const Text('Scansiona viaggio mezzo'))),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Puoi aprire la fotocamera del telefono e inquadrare il QR '
                      'senza entrare prima in GESTOPRO360: si apre l\'app e parte '
                      'la registrazione. Restano obbligatori accesso, km del '
                      'cruscotto e GPS. In alternativa scansiona da qui.',
                    ),
                  ),
                ),
                if (_isNativeMobile && _scanner != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 320,
                      child: MobileScanner(
                        controller: _scanner,
                        onDetect: _onBarcodeCapture,
                      ),
                    ),
                  ),
                ],
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  BuoniPastoWebQrScanner(onDetect: _onDetect),
                ],
                if (kIsWeb || !_isNativeMobile) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manualCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Codice QR o link (vm=...)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _onDetect,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _onDetect(_manualCtrl.text),
                    icon: const Icon(Icons.check),
                    label: const Text('Procedi'),
                  ),
                ],
              ],
            ),
    );
  }
}
