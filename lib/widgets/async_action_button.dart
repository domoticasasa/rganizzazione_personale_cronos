import 'dart:async';

import 'package:flutter/material.dart';

class AsyncFilledButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;

  const AsyncFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  @override
  State<AsyncFilledButton> createState() => _AsyncFilledButtonState();
}

class _AsyncFilledButtonState extends State<AsyncFilledButton> {
  bool _busy = false;

  Future<void> _handlePressed() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await Future.sync(widget.onPressed!);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy || widget.onPressed == null ? null : _handlePressed,
      style: widget.style,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : widget.child,
    );
  }
}
