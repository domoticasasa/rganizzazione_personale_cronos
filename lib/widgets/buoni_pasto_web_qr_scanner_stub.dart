import 'package:flutter/material.dart';

/// Placeholder fuori dal web.
class BuoniPastoWebQrScanner extends StatelessWidget {
  const BuoniPastoWebQrScanner({
    super.key,
    required this.onDetect,
    this.height = 320,
    this.autoStart = false,
  });

  final ValueChanged<String> onDetect;
  final double height;
  final bool autoStart;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
