import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../theme/cronos_futuristic_theme.dart';
import 'futuristic_shell_scope.dart';
import 'glowing_border_shell.dart';
import 'particles_background.dart';

/// Dialog / pannello in stile GESTOPRO (scuro, bordo neon, blur).
class FuturisticDialog extends StatelessWidget {
  const FuturisticDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.onClose,
    this.fullScreen = false,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? () => Navigator.of(context).pop();

    final panel = GlowingBorderShell(
      color: CronosFuturisticTheme.borderGlow,
      strokeWidth: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CronosFuturisticTheme.panelBg.withValues(alpha: 0.94),
                  CronosFuturisticTheme.voidBg.withValues(alpha: 0.92),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: fullScreen ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune,
                        color: CronosFuturisticTheme.neonCyan,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: CronosFonts.orbitron(
                            fontSize: 12,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Chiudi',
                        onPressed: close,
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.18),
                ),
                if (fullScreen)
                  Expanded(
                    child: FuturisticThemedContent(child: child),
                  )
                else
                  Flexible(
                    child: FuturisticThemedContent(child: child),
                  ),
                if (actions != null && actions!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions!,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (fullScreen) {
      return Theme(
        data: CronosFuturisticTheme.themeData(Theme.of(context).textTheme),
        child: Scaffold(
          backgroundColor: CronosFuturisticTheme.voidBg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ParticlesBackground(),
              SafeArea(child: panel),
            ],
          ),
        ),
      );
    }

    return Theme(
      data: CronosFuturisticTheme.themeData(Theme.of(context).textTheme),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: panel,
      ),
    );
  }
}
