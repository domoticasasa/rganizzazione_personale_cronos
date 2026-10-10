import 'dart:async';

import 'package:flutter/material.dart';

import '../services/doc_firma_device_unlock.dart';

/// Risultato seconda conferma dispositivo.
class DocFirmaUnlockResult {
  const DocFirmaUnlockResult({
    required this.method,
    this.setup = false,
  });

  /// `webauthn` | `pin` | `pattern`
  final String method;
  final bool setup;
}

/// Dialog: impronta (se disponibile) / PIN / segno 3×3.
Future<DocFirmaUnlockResult?> showDocFirmaDeviceUnlockDialog({
  required BuildContext context,
  required String userId,
  required String userName,
  required String displayName,
  String title = 'Conferma dispositivo',
  String message =
      'Seconda conferma su mobile: impronta (se presente), PIN oppure segno di sblocco.',
  bool autoPromptBiometric = false,
}) {
  return showDialog<DocFirmaUnlockResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DocFirmaUnlockDialog(
      userId: userId,
      userName: userName,
      displayName: displayName,
      title: title,
      message: message,
      autoPromptBiometric: autoPromptBiometric,
    ),
  );
}

class _DocFirmaUnlockDialog extends StatefulWidget {
  const _DocFirmaUnlockDialog({
    required this.userId,
    required this.userName,
    required this.displayName,
    required this.title,
    required this.message,
    required this.autoPromptBiometric,
  });

  final String userId;
  final String userName;
  final String displayName;
  final String title;
  final String message;
  final bool autoPromptBiometric;

  @override
  State<_DocFirmaUnlockDialog> createState() => _DocFirmaUnlockDialogState();
}

class _DocFirmaUnlockDialogState extends State<_DocFirmaUnlockDialog> {
  bool _loading = true;
  bool _busy = false;
  bool _bioAvailable = false;
  bool _hasBio = false;
  bool _hasPin = false;
  bool _hasPattern = false;

  String _mode = 'choose'; // choose | pin | pin_setup | pattern | pattern_setup
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  final _pattern = <int>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bioAvail =
        await DocFirmaDeviceUnlock.isPlatformAuthenticatorAvailable();
    final hasBio = await DocFirmaDeviceUnlock.hasWebAuthn();
    final hasPin = await DocFirmaDeviceUnlock.hasPin();
    final hasPat = await DocFirmaDeviceUnlock.hasPattern();
    if (!mounted) return;
    setState(() {
      _bioAvailable = bioAvail;
      _hasBio = hasBio;
      _hasPin = hasPin;
      _hasPattern = hasPat;
      _loading = false;
    });
    if (widget.autoPromptBiometric && bioAvail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _busy) return;
        unawaited(_tryBio(registerIfMissing: !hasBio));
      });
    }
  }

  Future<void> _tryBio({bool registerIfMissing = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_hasBio) {
        if (!registerIfMissing) {
          setState(() {
            _busy = false;
            _error = 'Prima attiva l\'impronta, oppure usa PIN/segno.';
          });
          return;
        }
        // La registrazione richiede già l'impronta: non rifare authenticate.
        final reg = await DocFirmaDeviceUnlock.registerWebAuthnDetailed(
          userId: widget.userId,
          userName: widget.userName,
          displayName: widget.displayName,
        );
        if (!mounted) return;
        if (!reg.ok) {
          setState(() {
            _busy = false;
            _error = reg.errorMessage ??
                'Impronta non disponibile. Usa PIN o segno.';
          });
          return;
        }
        Navigator.pop(
          context,
          const DocFirmaUnlockResult(method: 'webauthn', setup: true),
        );
        return;
      }

      final auth = await DocFirmaDeviceUnlock.authenticateWebAuthnDetailed();
      if (!mounted) return;
      if (auth.ok) {
        Navigator.pop(
          context,
          const DocFirmaUnlockResult(method: 'webauthn'),
        );
        return;
      }
      setState(() {
        _busy = false;
        _error = auth.errorMessage ??
            'Autenticazione biometrica fallita. Prova PIN o segno.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Impronta non riuscita. Usa PIN o segno.';
      });
    }
  }

  Future<void> _resetBio() async {
    await DocFirmaDeviceUnlock.clearWebAuthn();
    if (!mounted) return;
    setState(() {
      _hasBio = false;
      _error = 'Impronta reimpostata. Tocca «Attiva impronta» e conferma.';
    });
  }

  Future<bool> _confirmReset(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reimposta'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _resetPin() async {
    final ok = await _confirmReset(
      'Reimposta PIN',
      'Il PIN salvato su questo browser verrà eliminato. Poi dovrai crearne uno nuovo.',
    );
    if (!ok) return;
    await DocFirmaDeviceUnlock.clearPin();
    if (!mounted) return;
    setState(() {
      _hasPin = false;
      _mode = 'choose';
      _pinCtrl.clear();
      _pinConfirmCtrl.clear();
      _error = 'PIN reimpostato. Ora puoi crearne uno nuovo.';
    });
  }

  Future<void> _resetPattern() async {
    final ok = await _confirmReset(
      'Reimposta segno',
      'Il segno salvato su questo browser verrà eliminato. Poi dovrai crearne uno nuovo.',
    );
    if (!ok) return;
    await DocFirmaDeviceUnlock.clearPattern();
    if (!mounted) return;
    setState(() {
      _hasPattern = false;
      _mode = 'choose';
      _pattern.clear();
      _error = 'Segno reimpostato. Ora puoi crearne uno nuovo.';
    });
  }

  Future<void> _submitPin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == 'pin_setup') {
        if (_pinCtrl.text != _pinConfirmCtrl.text) {
          throw StateError('I due PIN non coincidono');
        }
        await DocFirmaDeviceUnlock.setPin(_pinCtrl.text);
        if (!mounted) return;
        Navigator.pop(
          context,
          const DocFirmaUnlockResult(method: 'pin', setup: true),
        );
        return;
      }
      final ok = await DocFirmaDeviceUnlock.verifyPin(_pinCtrl.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'PIN non corretto';
        });
        return;
      }
      Navigator.pop(
        context,
        const DocFirmaUnlockResult(method: 'pin'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _submitPattern() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == 'pattern_setup') {
        await DocFirmaDeviceUnlock.setPattern(List<int>.from(_pattern));
        if (!mounted) return;
        Navigator.pop(
          context,
          const DocFirmaUnlockResult(method: 'pattern', setup: true),
        );
        return;
      }
      final ok = await DocFirmaDeviceUnlock.verifyPattern(_pattern);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _pattern.clear();
          _error = 'Segno non corretto';
        });
        return;
      }
      Navigator.pop(
        context,
        const DocFirmaUnlockResult(method: 'pattern'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  void _togglePatternCell(int i) {
    if (_busy) return;
    setState(() {
      if (_pattern.contains(i)) {
        // riparti se ritocca un punto già usato
        _pattern.clear();
        _pattern.add(i);
      } else {
        _pattern.add(i);
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_mode == 'choose') ..._buildChoose(),
                    if (_mode == 'pin' || _mode == 'pin_setup') ..._buildPin(),
                    if (_mode == 'pattern' || _mode == 'pattern_setup')
                      ..._buildPattern(),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        if (_mode == 'pin' || _mode == 'pin_setup')
          FilledButton(
            onPressed: _busy ? null : _submitPin,
            child: Text(_mode == 'pin_setup' ? 'Salva PIN' : 'Sblocca'),
          ),
        if (_mode == 'pattern' || _mode == 'pattern_setup')
          FilledButton(
            onPressed: _busy || _pattern.length < 4 ? null : _submitPattern,
            child: Text(
              _mode == 'pattern_setup' ? 'Salva segno' : 'Sblocca',
            ),
          ),
      ],
    );
  }

  List<Widget> _buildChoose() {
    return [
      if (_bioAvailable)
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _tryBio(registerIfMissing: !_hasBio),
          icon: const Icon(Icons.fingerprint),
          label: Text(
            _hasBio ? 'Usa impronta / Face ID' : 'Attiva impronta / Face ID',
          ),
        ),
      if (_bioAvailable && _hasBio) ...[
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _resetBio,
          child: const Text('Reimposta impronta'),
        ),
      ],
      if (_bioAvailable) const SizedBox(height: 8),
      if (!_bioAvailable)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Impronta non disponibile su questo browser. Usa PIN o segno.',
            style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _mode = _hasPin ? 'pin' : 'pin_setup';
                  _error = null;
                }),
        icon: const Icon(Icons.pin_outlined),
        label: Text(_hasPin ? 'Sblocca con PIN' : 'Crea PIN (4–8 cifre)'),
      ),
      if (_hasPin) ...[
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _resetPin,
          child: const Text('PIN dimenticato? Reimposta PIN'),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _mode = _hasPattern ? 'pattern' : 'pattern_setup';
                  _pattern.clear();
                  _error = null;
                }),
        icon: const Icon(Icons.gesture),
        label: Text(_hasPattern ? 'Sblocca con segno' : 'Crea segno di sblocco'),
      ),
      if (_hasPattern) ...[
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _resetPattern,
          child: const Text('Segno dimenticato? Reimposta segno'),
        ),
      ],
    ];
  }

  List<Widget> _buildPin() {
    return [
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _mode = 'choose';
                  _pinCtrl.clear();
                  _pinConfirmCtrl.clear();
                }),
        child: const Text('← Indietro'),
      ),
      TextField(
        controller: _pinCtrl,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        decoration: InputDecoration(
          labelText: _mode == 'pin_setup' ? 'Nuovo PIN' : 'PIN',
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        onSubmitted: (_) {
          if (_mode == 'pin') _submitPin();
        },
      ),
      if (_mode == 'pin_setup') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _pinConfirmCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'Conferma PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildPattern() {
    return [
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _mode = 'choose';
                  _pattern.clear();
                }),
        child: const Text('← Indietro'),
      ),
      Text(
        _mode == 'pattern_setup'
            ? 'Collega almeno 4 punti in sequenza'
            : 'Ripeti il tuo segno',
      ),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: 1,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: 9,
          itemBuilder: (_, i) {
            final selected = _pattern.contains(i);
            final order = selected ? _pattern.indexOf(i) + 1 : null;
            return Material(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _togglePatternCell(i),
                child: Center(
                  child: Text(
                    order?.toString() ?? '',
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _pattern.clear();
                  _error = null;
                }),
        child: const Text('Pulisci segno'),
      ),
    ];
  }
}
