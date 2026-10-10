import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_qr_payload.dart';
import '../utils/buoni_pasto_scan_gps.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/modify_feedback.dart';
import '../widgets/buoni_pasto_web_qr_scanner.dart';
import '../widgets/classic_app_bar_chrome.dart';

class DipendenteBuonoPastoScanPage extends StatefulWidget {
  final int userId;

  /// Token/URL già letto (es. QR aperto con la fotocamera del telefono).
  final String? initialQr;

  const DipendenteBuonoPastoScanPage({
    super.key,
    required this.userId,
    this.initialQr,
  });

  @override
  State<DipendenteBuonoPastoScanPage> createState() =>
      _DipendenteBuonoPastoScanPageState();
}

class _DipendenteBuonoPastoScanPageState
    extends State<DipendenteBuonoPastoScanPage> {
  final _supa = SupabaseService.client;
  final _manualCtrl = TextEditingController();
  bool _busy = false;
  bool _handled = false;
  bool _loadingStato = true;
  BuoniPastoStatoOggi? _statoOggi;
  MobileScannerController? _scanner;

  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _giaRegistratoOggi =>
      _statoOggi?.giaRegistratoTipoCorrente ?? false;

  @override
  void initState() {
    super.initState();
    if (_isNativeMobile) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    }
    _loadStatoOggi().then((_) {
      final initial = widget.initialQr?.trim() ?? '';
      if (initial.isNotEmpty && mounted) {
        _registra(initial);
      }
    });
  }

  Future<void> _loadStatoOggi() async {
    setState(() => _loadingStato = true);
    try {
      final stato = await BuoniPastoService.loadStatoOggi(_supa);
      if (mounted) setState(() => _statoOggi = stato);
    } finally {
      if (mounted) setState(() => _loadingStato = false);
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _registra(String raw) async {
    if (_busy || _giaRegistratoOggi) return;
    setState(() {
      _busy = true;
      _handled = true;
    });
    try {
      final gps = await BuoniPastoScanGps.capture(
        context: context,
        purpose: GpsPurpose.buonoPasto,
      );
      final res = await BuoniPastoService.registraScansione(
        _supa,
        raw,
        latitudine: gps?.lat,
        longitudine: gps?.lon,
      );
      await _loadStatoOggi();
      if (!mounted) return;
      final gpsLabel = gps != null
          ? formatGpsCoordsText(gps.lat, gps.lon)
          : 'Non rilevata (consenti la posizione nel browser/telefono)';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Buono pasto registrato'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ristorante: ${res.structureName}'),
              Text('Tipo: ${tipoPastoLabel(res.tipoPasto)}'),
              Text(
                'Data: ${res.dataPasto.day.toString().padLeft(2, '0')}/'
                '${res.dataPasto.month.toString().padLeft(2, '0')}/'
                '${res.dataPasto.year}',
              ),
              Text(
                'Ora: ${res.registratoAt.hour.toString().padLeft(2, '0')}:'
                '${res.registratoAt.minute.toString().padLeft(2, '0')}',
              ),
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
    if (_handled || _busy || _giaRegistratoOggi) return;
    final value = raw.trim();
    if (value.isNotEmpty) {
      _registra(value);
    }
  }

  void _onBarcodeCapture(BarcodeCapture capture) {
    if (_handled || _busy || _giaRegistratoOggi) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) {
        _registra(raw);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stato = _statoOggi;
    final tipoCorrente =
        stato?.tipoCorrente ?? tipoPastoFromHour(DateTime.now().hour);
    final tipoPreview = tipoPastoLabel(tipoCorrente);
    final giaRegistrato = _giaRegistratoOggi;
    final pranzoFatto = stato?.pranzoRegistrato ?? false;
    final cenaFatta = stato?.cenaRegistrata ?? false;

    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const Text('Scansiona buono pasto'),
        ),
      ),
      body: _busy || (_loadingStato && stato == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Puoi aprire la fotocamera del telefono e inquadrare il QR '
                      'della struttura senza entrare prima in GESTOPRO360: si apre '
                      'l\'app e parte la registrazione. Restano obbligatori '
                      'accesso e GPS. In alternativa scansiona da qui.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Registrazione automatica: $tipoPreview '
                      '(in base all\'ora attuale, fuso Europe/Rome sul server).',
                    ),
                  ),
                ),
                if (pranzoFatto || cenaFatta) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Oggi hai già registrato:',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (pranzoFatto) const Text('• Pranzo'),
                          if (cenaFatta) const Text('• Cena'),
                        ],
                      ),
                    ),
                  ),
                ],
                if (giaRegistrato) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Non puoi registrare un secondo $tipoPreview oggi. '
                        'È consentito al massimo un pranzo e una cena al giorno.',
                      ),
                    ),
                  ),
                ],
                if (!giaRegistrato && _isNativeMobile && _scanner != null) ...[
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
                  const SizedBox(height: 8),
                  const Text(
                    'Inquadra il QR code esposto dal ristorante.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!giaRegistrato && kIsWeb) ...[
                  const SizedBox(height: 12),
                  BuoniPastoWebQrScanner(
                    onDetect: _onDetect,
                    autoStart: true,
                  ),
                ],
                if (!giaRegistrato && (kIsWeb || !_isNativeMobile)) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    kIsWeb
                        ? 'Oppure inserisci il codice manualmente:'
                        : 'Su questo dispositivo usa l\'inserimento manuale del codice.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manualCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Codice QR o link (bp=... / CRONOS-BP:...)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onDetect,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _onDetect(_manualCtrl.text),
                    icon: const Icon(Icons.check),
                    label: const Text('Registra'),
                  ),
                ],
              ],
            ),
    );
  }
}
