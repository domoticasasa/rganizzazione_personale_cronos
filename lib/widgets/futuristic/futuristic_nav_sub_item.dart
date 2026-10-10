import 'package:flutter/material.dart';

import '../cronos_futuristic_tile.dart';

/// Voce secondaria nella sidebar GESTOPRO (sotto la sezione attiva).
class FuturisticNavSubItem {
  const FuturisticNavSubItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
    this.badge,
    this.children = const <FuturisticNavSubItem>[],
  });

  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;
  final String? badge;
  final List<FuturisticNavSubItem> children;

  FuturisticNavSubItem copyWith({
    String? key,
    IconData? icon,
    String? label,
    VoidCallback? onTap,
    Color? accentColor,
    String? badge,
    List<FuturisticNavSubItem>? children,
  }) {
    return FuturisticNavSubItem(
      key: key ?? this.key,
      icon: icon ?? this.icon,
      label: label ?? this.label,
      onTap: onTap ?? this.onTap,
      accentColor: accentColor ?? this.accentColor,
      badge: badge ?? this.badge,
      children: children ?? this.children,
    );
  }

  static FuturisticNavSubItem fromTile(
    CronosFuturisticTile tile, {
    Color? accentColor,
  }) {
    return FuturisticNavSubItem(
      key: tile.layoutKey,
      icon: tile.icon,
      label: tile.label,
      onTap: tile.onTap,
      accentColor: accentColor,
    );
  }
}
