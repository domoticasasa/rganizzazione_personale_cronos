import 'package:flutter/material.dart';

/// Segnala che [onTap] ha già gestito l’azione (menu/dialog), senza navigazione.
class AdminHubActionOnly extends StatelessWidget {
  const AdminHubActionOnly({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Voce hub spostabile tra le pagine admin.
class AdminHubNavItem {
  const AdminHubNavItem({
    required this.layoutKey,
    required this.defaultLayoutKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
  });

  final String layoutKey;
  final String defaultLayoutKey;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final Widget Function(BuildContext context) onTap;
}
