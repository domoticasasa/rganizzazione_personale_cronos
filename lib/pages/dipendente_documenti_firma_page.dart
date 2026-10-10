import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/doc_firma_service.dart';
import '../services/passkey_auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_page_chrome.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Area dipendente: documenti da firmare / scaricare.
class DipendenteDocumentiFirmaPage extends StatefulWidget {
  const DipendenteDocumentiFirmaPage({
    super.key,
    required this.userId,
    this.fullName = '',
    this.forceMobileLayout = false,
  });

  final int userId;
  final String fullName;
  final bool forceMobileLayout;

  @override
  State<DipendenteDocumentiFirmaPage> createState() =>
      _DipendenteDocumentiFirmaPageState();
}

class _DipendenteDocumentiFirmaPageState
    extends State<DipendenteDocumentiFirmaPage> {
  bool _loading = true;
  String? _error;
  List<DocFirmaAssignment> _rows = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await DocFirmaService.listMyAssignments();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _download(DocFirmaAssignment a) async {
    try {
      final bytes = await DocFirmaService.downloadSignedPdf(a);
      final name = a.title.replaceAll(RegExp(r'[^\w]+'), '_');
      await ExcelExportHelper.saveAndReveal(
        pageName: 'Firmato_$name',
        bytes: bytes,
        extension: 'pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openSign(DocFirmaAssignment a) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _FirmaDocumentoPage(
          assignment: a,
          fullName: widget.fullName,
        ),
      ),
    );
    if (ok == true) await _reload();
  }

  Color _statusColor(DocFirmaAssignment a) {
    switch (a.status) {
      case 'pending':
        return a.canSign ? Colors.orange : Colors.red;
      case 'signed':
        return a.canDownload ? Colors.green : Colors.grey;
      case 'expired':
        return Colors.red.shade700;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _statusLabel(DocFirmaAssignment a) {
    switch (a.status) {
      case 'pending':
        return a.canSign ? 'Da firmare' : 'Scaduto';
      case 'signed':
        return a.canDownload ? 'Firmato — scarica entro scadenza' : 'Firmato (download scaduto)';
      case 'expired':
        return 'Scaduto senza firma';
      case 'cancelled':
        return 'Annullato dall\'admin';
      default:
        return a.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Firma digitale';
    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: pageTitle),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Protezioni in ordine: Passkey, OTP email, firma grafica, '
                            'poi marca temporale server + blocco PDF. '
                            'Hai ${DocFirmaService.signWindowDays} giorni per firmare e '
                            '${DocFirmaService.downloadWindowDays} per scaricare; '
                            'dopo la scadenza i PDF vengono eliminati '
                            '(le evidenze restano nel ledger).',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nessun documento.')),
                        )
                      else
                        for (final a in _rows)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    a.canSign
                                        ? Icons.fingerprint
                                        : Icons.description_outlined,
                                    color: _statusColor(a),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              a.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                            _badge(
                                                _statusLabel(a), _statusColor(a)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Scadenza firma: ${formatDateDdMmYyyy(a.signDeadline)}'
                                          '${a.downloadUntil != null ? ' · Download fino: ${formatDateDdMmYyyy(a.downloadUntil)}' : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Wrap(
                                    spacing: 4,
                                    children: [
                                      if (a.canSign)
                                        FilledButton.icon(
                                          onPressed: () => _openSign(a),
                                          icon: const Icon(Icons.fingerprint,
                                              size: 18),
                                          label: const Text('Firma'),
                                        ),
                                      if (a.canDownload)
                                        IconButton(
                                          tooltip: 'Scarica PDF firmato',
                                          onPressed: () => _download(a),
                                          icon: const Icon(
                                              Icons.download_rounded),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _FirmaDocumentoPage extends StatefulWidget {
  const _FirmaDocumentoPage({
    required this.assignment,
    required this.fullName,
  });

  final DocFirmaAssignment assignment;
  final String fullName;

  @override
  State<_FirmaDocumentoPage> createState() => _FirmaDocumentoPageState();
}

class _FirmaDocumentoPageState extends State<_FirmaDocumentoPage> {
  final _otpCtrl = TextEditingController();
  final _sigKey = GlobalKey();
  final _sigPad = _SignaturePadController();

  bool _otpSent = false;
  bool _otpOk = false;
  bool _passkeyOk = false;
  bool _hasPasskey = false;
  bool _busy = false;
  String? _emailMasked;
  String? _email;
  int? _pdfPages;
  bool _pdfLoading = true;
  String? _pdfError;
  bool _drawingSignature = false;

  /// Tutte e 3 le protezioni: Passkey → OTP → firma grafica.
  bool get _canDrawSignature => _passkeyOk && _otpOk;

  @override
  void initState() {
    super.initState();
    _loadEmail();
    _loadPdfMeta();
    _loadPasskeyAvailability();
  }

  Future<void> _loadPasskeyAvailability() async {
    if (!PasskeyAuthService.isPlatformSupported) return;
    try {
      final has = await PasskeyAuthService.hasAnyPasskey();
      if (!mounted) return;
      setState(() => _hasPasskey = has);
    } catch (_) {}
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _sigPad.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    try {
      final authId = SupabaseService.client.auth.currentUser?.id;
      if (authId == null) return;
      final u = await SupabaseService.client
          .from('users')
          .select('email, full_name')
          .eq('auth_id', authId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _email = (u?['email'] ?? '').toString();
      });
    } catch (_) {}
  }

  Future<void> _loadPdfMeta() async {
    try {
      final bytes =
          await DocFirmaService.downloadOriginalPdf(widget.assignment);
      final doc = PdfDocument(inputBytes: bytes);
      final pages = doc.pages.count;
      doc.dispose();
      if (!mounted) return;
      setState(() {
        _pdfPages = pages;
        _pdfLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfError = e.toString();
        _pdfLoading = false;
      });
    }
  }

  Future<void> _previewPdf() async {
    setState(() => _busy = true);
    try {
      final bytes =
          await DocFirmaService.downloadOriginalPdf(widget.assignment);
      final name = widget.assignment.title.replaceAll(RegExp(r'[^\w]+'), '_');
      await ExcelExportHelper.saveAndReveal(
        pageName: 'Anteprima_$name',
        bytes: bytes,
        extension: 'pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() async {
    setState(() => _busy = true);
    try {
      final res = await DocFirmaService.requestOtp(widget.assignment.id);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _emailMasked = (res['email_masked'] ?? '').toString();
        _busy = false;
      });
      final emailed = res['emailed'] == true;
      final emailErr = (res['email_error'] ?? '').toString().trim();
      final String msg;
      if (emailed) {
        msg = 'Codice inviato a ${_emailMasked ?? 'email'}';
      } else if (emailErr.contains('RESEND_API_KEY')) {
        msg =
            'Email non configurata sul server: apri Notifiche — il codice OTP è lì (valido 10 min).';
      } else if (emailErr.isNotEmpty) {
        msg =
            'Invio email non riuscito (spesso serve dominio verificato su Resend). '
            'Apri Notifiche: il codice OTP è lì (valido 10 min).';
      } else {
        msg =
            'Codice disponibile in Notifiche (valido 10 min). Controlla anche la mail.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: Duration(seconds: emailed ? 4 : 8),
          backgroundColor: emailed ? null : Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _busy = true);
    try {
      final ok = await DocFirmaService.verifyOtp(
        widget.assignment.id,
        _otpCtrl.text,
      );
      if (!mounted) return;
      if (!_passkeyOk) {
        throw StateError('Prima completa la verifica Passkey (passo 1).');
      }
      setState(() {
        _otpOk = ok;
        _busy = false;
      });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Codice non valido'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP verificato — ora disegna la firma (passo 3)'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _verifyWithPasskey() async {
    setState(() => _busy = true);
    try {
      if (!_hasPasskey) {
        throw StateError(
          'Nessuna Passkey sull\'account. Registrala dal profilo sicurezza / login '
          'prima di firmare (obbligatoria insieme a OTP e firma grafica).',
        );
      }
      await PasskeyAuthService.verifyAsSecondFactor();
      await DocFirmaService.recordPasskeyAuth(widget.assignment.id);
      if (!mounted) return;
      setState(() {
        _passkeyOk = true;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passkey verificata — ora richiedi l\'OTP (passo 2)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(PasskeyAuthService.userMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List?> _exportSignature() async {
    if (!_sigPad.hasInk) return null;
    final captured = await DocFirmaService.captureSignaturePng(_sigKey);
    if (captured != null && captured.isNotEmpty) return captured;
    return _sigPad.renderPng(const Size(400, 160));
  }

  Future<void> _confirmSign() async {
    if (!_passkeyOk || !_otpOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa prima Passkey (1) e OTP (2)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final png = await _exportSignature();
    if (!mounted) return;
    if (png == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disegna la firma (passo 3)')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final name = widget.fullName.trim().isNotEmpty
          ? widget.fullName.trim()
          : 'Dipendente';
      final email = (_email ?? '').trim();
      await DocFirmaService.completeSign(
        assignment: widget.assignment,
        signaturePng: png,
        signerName: name,
        signerEmail: email,
        deviceUnlock: <String, dynamic>{
          'method': 'passkey+otp',
          'protections': const ['passkey', 'otp', 'signature'],
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: ResponsiveAppBarTitle(title: widget.assignment.title),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        // Mentre firmi blocca lo scroll: altrimenti il ListView ruba il gesto.
        physics: _drawingSignature
            ? const NeverScrollableScrollPhysics()
            : null,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documento',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(widget.assignment.originalFileName.isNotEmpty
                      ? widget.assignment.originalFileName
                      : widget.assignment.title),
                  if (_pdfLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_pdfError != null)
                    Text(
                      'Anteprima non disponibile',
                      style: TextStyle(color: Colors.orange.shade800),
                    )
                  else
                    Text(
                      'Pagine: ${_pdfPages ?? '?'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy || _pdfLoading ? null : _previewPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Apri anteprima PDF'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '1. Passkey account (obbligatoria)\n'
            '2. OTP email (obbligatoria, dopo la Passkey)\n'
            '3. Firma grafica digitale\n'
            '4. Marca temporale server CRONOS (automatica alla conferma)\n\n'
            'Sul PDF: «firma digitale» + codice pagina; attestato con timestamp; '
            'blocco anti-modifica/estrazione/assemblaggio. '
            'Non e firma qualificata eIDAS ne TSA esterna.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Passo 1 — Passkey',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ||
                    _passkeyOk ||
                    !PasskeyAuthService.isPlatformSupported
                ? null
                : _verifyWithPasskey,
            icon: Icon(_passkeyOk ? Icons.verified : Icons.fingerprint),
            label: Text(
              _passkeyOk
                  ? '1/3 Passkey OK'
                  : (_hasPasskey
                      ? '1/3 Verifica Passkey'
                      : 'Passkey non registrata'),
            ),
          ),
          if (!PasskeyAuthService.isPlatformSupported)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Passkey non supportata su questo client: impossibile firmare da qui.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade700,
                    ),
              ),
            )
          else if (!_hasPasskey)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Registra una Passkey dal profilo sicurezza / login: è obbligatoria.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Passo 2 — OTP email',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy || !_passkeyOk || _otpOk ? null : _sendOtp,
            icon: const Icon(Icons.email_outlined),
            label: Text(
              !_passkeyOk
                  ? '2/3 Disponibile dopo Passkey'
                  : (_otpSent ? 'Reinvia codice OTP' : '2/3 Invia codice email'),
            ),
          ),
          if (_emailMasked != null) ...[
            const SizedBox(height: 6),
            Text('Inviato a: $_emailMasked'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otpCtrl,
                  enabled: _passkeyOk && !_otpOk,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Codice OTP',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed:
                    _busy || !_passkeyOk || !_otpSent || _otpOk
                        ? null
                        : _verifyOtp,
                child: Text(_otpOk ? '2/3 OK' : 'Verifica'),
              ),
            ],
          ),
          if (_canDrawSignature) ...[
              const SizedBox(height: 16),
              Text(
                'Passo 3 — Firma grafica',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Passkey + OTP OK — disegna la firma. '
                'Sul documento originale va solo «firma digitale» + codice pagina; '
                'la grafica resta nella pagina attestato.',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Puoi alzare il dito e continuare: ogni tratto resta salvato.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              RepaintBoundary(
                key: _sigKey,
                child: _SignaturePad(
                  key: const ValueKey('doc_firma_signature_pad'),
                  controller: _sigPad,
                  height: 200,
                  onDrawStart: () {
                    if (!_drawingSignature) {
                      setState(() => _drawingSignature = true);
                    }
                  },
                  onDrawEnd: () {
                    if (_drawingSignature) {
                      setState(() => _drawingSignature = false);
                    }
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _sigPad.clear,
                  child: const Text('Pulisci firma'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _confirmSign,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('3/3 Conferma firma'),
              ),
            ],
        ],
      ),
    );
  }
}

/// Controller firma: aggiorna solo il pad (niente setState sulla pagina intera).
class _SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> strokes = <List<Offset>>[];
  List<Offset>? _current;
  int? _activePointer;

  bool get hasInk {
    if (_current != null && _current!.length > 1) return true;
    return strokes.any((s) => s.length > 1);
  }

  void clear() {
    strokes.clear();
    _current = null;
    _activePointer = null;
    notifyListeners();
  }

  void start(int pointer, Offset local) {
    // Un solo dito alla volta: evita conflitti gesture.
    if (_activePointer != null && _activePointer != pointer) return;
    _activePointer = pointer;
    _current = <Offset>[local];
    notifyListeners();
  }

  void move(int pointer, Offset local) {
    if (_activePointer != pointer || _current == null) return;
    final last = _current!.isEmpty ? null : _current!.last;
    // Skip punti troppo vicini: meno lavoro, traccia più fluida.
    if (last != null && (last - local).distance < 1.6) return;
    _current!.add(local);
    notifyListeners();
  }

  void end(int pointer) {
    if (_activePointer != pointer) return;
    final stroke = _current;
    _current = null;
    _activePointer = null;
    if (stroke != null && stroke.length > 1) {
      strokes.add(stroke);
    }
    notifyListeners();
  }

  void cancel(int pointer) {
    if (_activePointer != pointer) return;
    final stroke = _current;
    _current = null;
    _activePointer = null;
    // Se il gesto viene interrotto (scroll), salva comunque il tratto utile.
    if (stroke != null && stroke.length > 1) {
      strokes.add(stroke);
    }
    notifyListeners();
  }

  List<List<Offset>> paintStrokes() {
    final out = List<List<Offset>>.from(strokes);
    final cur = _current;
    if (cur != null && cur.length > 1) out.add(cur);
    return out;
  }

  Future<Uint8List?> renderPng(Size size) async {
    final all = paintStrokes();
    if (all.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final stroke in all) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({
    super.key,
    required this.controller,
    this.height = 200,
    this.onDrawStart,
    this.onDrawEnd,
  });

  final _SignaturePadController controller;
  final double height;
  final VoidCallback? onDrawStart;
  final VoidCallback? onDrawEnd;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // Listener riceve i pointer PRIMA del gesture arena del ListView.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            widget.onDrawStart?.call();
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            widget.controller.start(e.pointer, box.globalToLocal(e.position));
          },
          onPointerMove: (e) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            widget.controller.move(e.pointer, box.globalToLocal(e.position));
          },
          onPointerUp: (e) {
            widget.controller.end(e.pointer);
            widget.onDrawEnd?.call();
          },
          onPointerCancel: (e) {
            widget.controller.cancel(e.pointer);
            widget.onDrawEnd?.call();
          },
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _SignaturePainter(
                  strokes: widget.controller.paintStrokes(),
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes});
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes);
}
