import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_qr_login_service.dart';

/// Mostra QR da scansionare col telefono; restituisce true se il PC ha ricevuto la sessione.
Future<bool> showAuthQrLoginDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _AuthQrLoginDialog(),
  );
  return ok == true;
}

class _AuthQrLoginDialog extends StatefulWidget {
  const _AuthQrLoginDialog();

  @override
  State<_AuthQrLoginDialog> createState() => _AuthQrLoginDialogState();
}

class _AuthQrLoginDialogState extends State<_AuthQrLoginDialog> {
  AuthQrStartResult? _session;
  String? _error;
  String _statusLabel = 'Generazione QR…';
  bool _loading = true;
  bool _claimed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    // Non cancellare qui: un dispose accidentale (rebuild/route) uccideva
    // sessioni ancora pending mentre il telefono stava confermando.
    // Cancel solo su «Annulla» / «Nuovo QR».
    super.dispose();
  }

  Future<void> _cancelAndClose() async {
    _poll?.cancel();
    final s = _session;
    if (s != null && !_claimed) {
      await AuthQrLoginService.cancel(id: s.id, claimSecret: s.claimSecret);
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _start() async {
    _poll?.cancel();
    final prev = _session;
    if (prev != null && !_claimed) {
      unawaited(
        AuthQrLoginService.cancel(id: prev.id, claimSecret: prev.claimSecret),
      );
    }
    setState(() {
      _loading = true;
      _error = null;
      _claimed = false;
      _session = null;
      _statusLabel = 'Generazione QR…';
    });
    try {
      final started = await AuthQrLoginService.start(
        origin: Uri.base.origin,
      );
      if (!mounted) return;
      setState(() {
        _session = started;
        _loading = false;
        _statusLabel = 'In attesa conferma sul telefono…';
      });
      unawaited(_tick());
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_tick());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _tick() async {
    final s = _session;
    if (s == null || !mounted || _claimed) return;
    try {
      final data = await AuthQrLoginService.poll(
        id: s.id,
        claimSecret: s.claimSecret,
      );
      final status = (data['status'] ?? '').toString();
      if (status == 'pending') {
        if (mounted) {
          setState(() => _statusLabel = 'In attesa conferma sul telefono…');
        }
        return;
      }
      if (status == 'expired' || status == 'cancelled') {
        _poll?.cancel();
        if (!mounted) return;
        setState(() => _error = 'QR scaduto o annullato. Genera un nuovo QR.');
        return;
      }
      if (status == 'claimed') {
        _poll?.cancel();
        if (!mounted) return;
        setState(
          () => _error =
              'Sessione già consumata. Tocca «Nuovo QR» e ripeti dal telefono.',
        );
        return;
      }
      if (status == 'approved') {
        _poll?.cancel();
        final refresh = (data['refresh_token'] ?? '').toString();
        if (refresh.isEmpty) {
          if (!mounted) return;
          setState(() => _error = 'Token assenti dalla conferma telefono.');
          return;
        }
        if (mounted) {
          setState(() => _statusLabel = 'Sessione ricevuta, accesso…');
        }
        await Supabase.instance.client.auth.setSession(refresh);
        if (!mounted) return;
        if (Supabase.instance.client.auth.currentSession == null) {
          setState(() => _error = 'Impossibile aprire la sessione sul PC.');
          return;
        }
        _claimed = true;
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return AlertDialog(
      title: const Text('Accedi con il telefono'),
      content: SizedBox(
        width: 340,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '1) Scansiona il QR col cellulare\n'
                    '2) Accedi sul telefono (impronta)\n'
                    '3) Attendi «Accesso sul PC confermato»\n'
                    '4) Questo dialog si chiude da solo',
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusLabel,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (s != null) ...[
                    QrImageView(
                      data: s.phoneUrl,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      'Codice: ${s.publicCode}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_cancelAndClose()),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => unawaited(_start()),
          child: const Text('Nuovo QR'),
        ),
      ],
    );
  }
}
