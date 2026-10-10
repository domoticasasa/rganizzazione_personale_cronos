import 'package:flutter/material.dart';

/// Snackbar di feedback dopo salvataggio / errori form.
class ModifyFeedback {
  static ScaffoldMessengerState _messenger(BuildContext context) {
    final direct = ScaffoldMessenger.maybeOf(context);
    if (direct != null) return direct;
    return ScaffoldMessenger.of(context);
  }

  static void success(BuildContext context, String message) {
    _messenger(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  static void error(BuildContext context, String message) {
    _messenger(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  static void hint(BuildContext context, String message) {
    _messenger(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
