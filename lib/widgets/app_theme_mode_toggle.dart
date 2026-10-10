import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_theme_mode_service.dart';

/// Pulsante icona chiaro/scuro (AppBar, menu mobile, ecc.).
class AppThemeModeToggleIconButton extends StatelessWidget {
  const AppThemeModeToggleIconButton({
    super.key,
    this.color,
    this.tooltipPrefix,
  });

  final Color? color;
  final String? tooltipPrefix;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeModeService.instance,
      builder: (context, _) {
        final dark = AppThemeModeService.instance.isDark;
        final label = dark ? 'Tema chiaro' : 'Tema scuro';
        return IconButton(
          tooltip: tooltipPrefix == null ? label : '$tooltipPrefix$label',
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: color,
          ),
          onPressed: () {
            unawaited(AppThemeModeService.instance.toggle());
          },
        );
      },
    );
  }
}

/// Voce menu (PopupMenu / drawer) per alternare tema chiaro/scuro.
class AppThemeModeToggleMenuTile extends StatelessWidget {
  const AppThemeModeToggleMenuTile({super.key, this.dense = true});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeModeService.instance,
      builder: (context, _) {
        final dark = AppThemeModeService.instance.isDark;
        return ListTile(
          dense: dense,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
          title: Text(dark ? 'Tema chiaro' : 'Tema scuro'),
          onTap: () {
            unawaited(AppThemeModeService.instance.toggle());
          },
        );
      },
    );
  }
}
