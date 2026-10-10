import 'package:flutter/material.dart';

/// Contenitore scuro per controlli riordino su tile neon GESTOPRO.
class FuturisticHubChip extends StatelessWidget {
  const FuturisticHubChip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF061020).withValues(alpha: 0.88),
      shape: const CircleBorder(),
      child: child,
    );
  }
}
