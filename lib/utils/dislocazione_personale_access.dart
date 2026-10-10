import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../pages/admin_dislocazione_personale_page.dart';
import 'mobile_navigation.dart';

const _kDislocazionePersonalePassword = 'B3rn1n1';

/// Chiede la password di accesso a Dislocazione Personale.
Future<bool> promptDislocazionePersonalePassword(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DislocazionePersonalePasswordDialog(),
  );
  return ok ?? false;
}

class _DislocazionePersonalePasswordDialog extends StatefulWidget {
  const _DislocazionePersonalePasswordDialog();

  @override
  State<_DislocazionePersonalePasswordDialog> createState() =>
      _DislocazionePersonalePasswordDialogState();
}

class _DislocazionePersonalePasswordDialogState
    extends State<_DislocazionePersonalePasswordDialog> {
  final _controller = TextEditingController();
  var _obscure = true;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trySubmit() {
    if (_controller.text == _kDislocazionePersonalePassword) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _errorText = 'Password non corretta');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dislocazione Personale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Inserisci la password per accedere.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _errorText,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _trySubmit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _trySubmit,
          child: const Text('Accedi'),
        ),
      ],
    );
  }
}

/// Apre Dislocazione Personale solo dopo password corretta.
Future<void> openDislocazionePersonaleWithPassword(
  BuildContext context, {
  required bool readOnly,
}) async {
  final authorized = await promptDislocazionePersonalePassword(context);
  if (!authorized || !context.mounted) return;

  final page = useMobileUi(context)
      ? AdminDislocazionePersonaleMobilePage(readOnly: readOnly)
      : AdminDislocazionePersonalePage(readOnly: readOnly);

  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => page),
  );
}
