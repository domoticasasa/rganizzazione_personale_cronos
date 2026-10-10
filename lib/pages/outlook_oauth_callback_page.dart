import 'package:flutter/material.dart';

import '../services/outlook_calendar_sync_service.dart';
import '../utils/app_navigator.dart';

/// Completa OAuth Microsoft dopo redirect `/auth/outlook/callback`.
class OutlookOAuthCallbackPage extends StatefulWidget {
  const OutlookOAuthCallbackPage({super.key, required this.uri});

  final Uri uri;

  @override
  State<OutlookOAuthCallbackPage> createState() =>
      _OutlookOAuthCallbackPageState();
}

class _OutlookOAuthCallbackPageState extends State<OutlookOAuthCallbackPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _complete();
  }

  Future<void> _complete() async {
    try {
      await OutlookCalendarSyncService.instance.completeOAuthFromUri(widget.uri);
      if (!mounted) return;
      final nav = appNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      } else {
        nav?.pushNamedAndRemoveUntil('/splash', (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Collegamento Outlook non riuscito',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final nav = appNavigatorKey.currentState;
                    if (nav != null && nav.canPop()) {
                      nav.pop();
                    } else {
                      nav?.pushNamedAndRemoveUntil('/login', (_) => false);
                    }
                  },
                  child: const Text('Chiudi'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Collegamento Outlook in corso…'),
          ],
        ),
      ),
    );
  }
}
