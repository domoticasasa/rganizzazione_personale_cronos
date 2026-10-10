import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/classic_nav_session_cache.dart';
import '../../services/gestopro_mode_prefs.dart';
import '../../theme/cronos_futuristic_theme.dart';
import 'futuristic_shell_scope.dart';
import 'gestopro_click_sound_scope.dart';
import 'particles_background.dart';

/// Wrapper GESTOPRO — tema scuro e barra superiore per pagine classiche.
class FuturisticPageShell extends StatelessWidget {
  const FuturisticPageShell({
    super.key,
    required this.child,
    this.title,
    this.showBack = true,
    this.showGestoproBranding = true,
  });

  final Widget child;
  final String? title;
  final bool showBack;
  final bool showGestoproBranding;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CronosFuturisticTheme.themeData(Theme.of(context).textTheme),
      child: GestoproClickSoundScope(
        child: Scaffold(
        backgroundColor: CronosFuturisticTheme.voidBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ParticlesBackground(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GestoproTopBar(
                  title: title,
                  showBack: showBack,
                  showGestoproBranding: showGestoproBranding,
                ),
                Expanded(
                  child: FuturisticThemedContent(child: child),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _GestoproTopBar extends StatelessWidget {
  const _GestoproTopBar({
    this.title,
    required this.showBack,
    required this.showGestoproBranding,
  });

  final String? title;
  final bool showBack;
  final bool showGestoproBranding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 4,
        12,
        8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CronosFuturisticTheme.electricBlue.withValues(alpha: 0.15),
            CronosFuturisticTheme.voidBg.withValues(alpha: 0.6),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'Indietro',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: CronosFuturisticTheme.neonCyan,
                size: 20,
              ),
            ),
          if (showGestoproBranding)
            Text(
              'GESTOPRO',
              style: CronosFonts.orbitron(
                fontSize: 13,
                letterSpacing: 3,
                fontWeight: FontWeight.w800,
                color: CronosFuturisticTheme.neonCyan,
              ),
            ),
          if (title != null) ...[
            if (showGestoproBranding)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '·',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CronosFonts.exo2(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ] else if (!showGestoproBranding)
            const Spacer(),
          if (showGestoproBranding)
            TextButton(
              onPressed: () async {
                await GestoproModePrefs.deactivate();
                ClassicNavSessionCache.markClassicChrome(forceNotify: true);
                if (!context.mounted) return;
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: Text(
                'Esci GESTOPRO',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
