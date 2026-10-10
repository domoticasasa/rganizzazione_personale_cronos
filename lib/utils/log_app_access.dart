import 'package:flutter/material.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../hub/admin_hub_nav_item.dart';
import '../pages/admin_app_logs_page.dart';
import 'mobile_navigation.dart';

const _kLogAppPassword = 'B3rn1n1';

/// Chiede la password di accesso a Log app.
Future<bool> promptLogAppPassword(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _LogAppPasswordDialog(),
  );
  return ok ?? false;
}

class _LogAppPasswordDialog extends StatefulWidget {
  const _LogAppPasswordDialog();

  @override
  State<_LogAppPasswordDialog> createState() => _LogAppPasswordDialogState();
}

class _LogAppPasswordDialogState extends State<_LogAppPasswordDialog> {
  final _controller = TextEditingController();
  var _obscure = true;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trySubmit() {
    if (_controller.text == _kLogAppPassword) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _errorText = 'Password non corretta');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log app'),
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

/// Apre Log app solo dopo password corretta.
Future<void> openLogAppWithPassword(BuildContext context) async {
  final authorized = await promptLogAppPassword(context);
  if (!authorized || !context.mounted) return;

  final page = useMobileUi(context)
      ? const AdminAppLogsMobilePage()
      : const AdminAppLogsPage();

  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => page),
  );
}

/// Voce hub: password, poi pagina (senza navigazione automatica del tile).
Widget logAppHubDestination(BuildContext context) {
  openLogAppWithPassword(context);
  return const AdminHubActionOnly();
}
