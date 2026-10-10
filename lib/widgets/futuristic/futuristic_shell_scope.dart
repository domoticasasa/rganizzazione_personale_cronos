import 'package:flutter/material.dart';

import '../../theme/cronos_futuristic_theme.dart';

/// Segnala che una pagina è dentro la shell GESTOPRO/futuristica.
class FuturisticShellScope extends InheritedWidget {
  const FuturisticShellScope({
    super.key,
    required this.hidePageChrome,
    required super.child,
  });

  /// Nasconde AppBar/logo classici della pagina figlia.
  final bool hidePageChrome;

  static FuturisticShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FuturisticShellScope>();
  }

  static bool hideChromeOf(BuildContext context) =>
      maybeOf(context)?.hidePageChrome ?? false;

  @override
  bool updateShouldNotify(FuturisticShellScope oldWidget) =>
      oldWidget.hidePageChrome != hidePageChrome;
}

/// Applica tema futurista + scope alla pagina figlia.
class FuturisticThemedContent extends StatelessWidget {
  const FuturisticThemedContent({
    super.key,
    required this.child,
    this.hidePageChrome = true,
  });

  final Widget child;
  final bool hidePageChrome;

  @override
  Widget build(BuildContext context) {
    final baseTheme = CronosFuturisticTheme.themeData(Theme.of(context).textTheme);
    final theme = hidePageChrome
        ? baseTheme.copyWith(
            appBarTheme: baseTheme.appBarTheme.copyWith(
              toolbarHeight: 0,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.transparent,
              titleSpacing: 0,
            ),
          )
        : baseTheme;

    return FuturisticShellScope(
      hidePageChrome: hidePageChrome,
      child: Theme(
        data: theme,
        child: child,
      ),
    );
  }
}
