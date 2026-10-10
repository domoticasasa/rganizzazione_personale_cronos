import 'package:flutter/material.dart';

import '../hub/hub_tile_style.dart';

/// Tile per la dashboard admin in stile futuristico.
class CronosFuturisticTile {
  final String layoutKey;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? accentColor;
  final HubTileStyle? tileStyle;
  final VoidCallback onTap;

  const CronosFuturisticTile({
    required this.layoutKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.accentColor,
    this.tileStyle,
  });
}
