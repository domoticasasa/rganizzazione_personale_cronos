import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../hub/app_ui_hub_registry.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/gestopro_page_chrome.dart';

/// Menu: sposta il tile su un hub a scelta.
class CronosHubMoveToLayoutButton extends StatelessWidget {
  const CronosHubMoveToLayoutButton({
    super.key,
    required this.currentLayoutKey,
    required this.itemKey,
    required this.onMoveTo,
  });

  final String currentLayoutKey;
  final String itemKey;
  final void Function(String targetLayoutKey) onMoveTo;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppUiHubRegistry.labelsRevision,
      builder: (context, _, _) => _buildMenu(context),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final targets = AppUiHubRegistry.targetsExcept(currentLayoutKey);
    if (targets.isEmpty) return const SizedBox.shrink();

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String>(
        tooltip: 'Sposta in un\'altra pagina',
        icon: const Icon(Icons.open_with, size: 20),
        onSelected: (layoutKey) => onMoveTo(layoutKey),
        itemBuilder: (context) => [
          for (final t in targets)
            PopupMenuItem<String>(
              value: t.layoutKey,
              child: Text('Sposta in ${t.label}'),
            ),
        ],
      ),
    );
  }
}

/// Maniglia: trascina verso una delle barre destinazione in basso.
class CronosHubCrossLayoutDragHandle extends StatelessWidget {
  const CronosHubCrossLayoutDragHandle({
    super.key,
    required this.itemKey,
    required this.label,
  });

  final String itemKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gestopro = isGestoproFuturisticUi(context);
    return Draggable<String>(
      data: itemKey,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: gestopro
            ? CronosFuturisticTheme.electricBlue.withValues(alpha: 0.92)
            : theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: gestopro
                  ? CronosFuturisticTheme.neonCyan
                  : theme.colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: Icon(
          Icons.swap_horiz,
          size: 20,
          color: gestopro
              ? CronosFuturisticTheme.neonCyan
              : theme.colorScheme.primary,
        ),
      ),
      child: Tooltip(
        message: 'Trascina su una barra in basso per cambiare pagina',
        child: gestopro
            ? FuturisticHubDragChip(
                icon: Icons.swap_horiz,
              )
            : Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.swap_horiz,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Chip scuro per maniglie drag in modalità GESTOPRO.
class FuturisticHubDragChip extends StatelessWidget {
  const FuturisticHubDragChip({
    super.key,
    required this.icon,
    this.size = 18,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF061020).withValues(alpha: 0.88),
      shape: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: size,
          color: CronosFuturisticTheme.neonCyan,
        ),
      ),
    );
  }
}

/// Barre di rilascio per ogni hub destinazione (tranne quella corrente).
class CronosHubCrossLayoutDropBar extends StatelessWidget {
  const CronosHubCrossLayoutDropBar({
    super.key,
    required this.currentLayoutKey,
    required this.onAcceptItemKey,
    this.styleForLayoutKey,
    this.onScaleLayoutTarget,
  });

  final String currentLayoutKey;
  final void Function(String itemKey, String targetLayoutKey) onAcceptItemKey;
  final double? Function(String layoutKey)? styleForLayoutKey;
  final void Function(String targetLayoutKey, double nextScale)?
      onScaleLayoutTarget;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppUiHubRegistry.labelsRevision,
      builder: (context, _, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final targets = AppUiHubRegistry.targetsExcept(currentLayoutKey);
    if (targets.isEmpty) return const SizedBox.shrink();
    final gestopro = isGestoproFuturisticUi(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: gestopro
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in targets) ...[
                    _HubDropChip(
                      label: t.label,
                      sizeScale: styleForLayoutKey?.call(t.layoutKey) ?? 1.0,
                      onScaleChanged: onScaleLayoutTarget == null
                          ? null
                          : (next) => onScaleLayoutTarget!(t.layoutKey, next),
                      futuristic: true,
                      onAccept: (key) => onAcceptItemKey(key, t.layoutKey),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final t in targets)
                  _HubDropChip(
                    label: t.label,
                    sizeScale: styleForLayoutKey?.call(t.layoutKey) ?? 1.0,
                    onScaleChanged: onScaleLayoutTarget == null
                        ? null
                        : (next) => onScaleLayoutTarget!(t.layoutKey, next),
                    onAccept: (key) => onAcceptItemKey(key, t.layoutKey),
                  ),
              ],
            ),
    );
  }
}

class _HubDropChip extends StatelessWidget {
  const _HubDropChip({
    required this.label,
    required this.onAccept,
    this.futuristic = false,
    this.sizeScale = 1.0,
    this.onScaleChanged,
  });

  final String label;
  final void Function(String itemKey) onAccept;
  final bool futuristic;
  final double sizeScale;
  final void Function(double nextScale)? onScaleChanged;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data.isNotEmpty,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        final theme = Theme.of(context);
        if (futuristic) {
          final iconSize = (16 * sizeScale).clamp(12.0, 28.0);
          final fontSize = (12 * sizeScale).clamp(10.0, 20.0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: (14 * sizeScale).clamp(8.0, 30.0),
              vertical: (8 * sizeScale).clamp(5.0, 18.0),
            ),
            decoration: BoxDecoration(
              color: active
                  ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.18)
                  : const Color(0xFF061020).withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? CronosFuturisticTheme.neonCyan
                    : CronosFuturisticTheme.neonCyan.withValues(alpha: 0.35),
                width: active ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onScaleChanged != null) ...[
                  _ScaleChipButton(
                    icon: Icons.remove,
                    tooltip: 'Riduci dimensione pulsante',
                    onPressed: () =>
                        onScaleChanged!((sizeScale - 0.1).clamp(0.7, 2.2)),
                    futuristic: true,
                  ),
                  SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
                ],
                Icon(
                  Icons.move_to_inbox_outlined,
                  size: iconSize,
                  color: CronosFuturisticTheme.neonCyan.withValues(
                    alpha: active ? 1 : 0.75,
                  ),
                ),
                SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
                Text(
                  label,
                  style: CronosFonts.exo2(
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                    color: Colors.white.withValues(alpha: active ? 0.95 : 0.75),
                  ),
                ),
                if (onScaleChanged != null) ...[
                  SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
                  _ScaleChipButton(
                    icon: Icons.add,
                    tooltip: 'Aumenta dimensione pulsante',
                    onPressed: () =>
                        onScaleChanged!((sizeScale + 0.1).clamp(0.7, 2.2)),
                    futuristic: true,
                  ),
                ],
              ],
            ),
          );
        }
        final iconSize = (18 * sizeScale).clamp(14.0, 32.0);
        final fontSize = (13 * sizeScale).clamp(11.0, 21.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: (14 * sizeScale).clamp(8.0, 30.0),
            vertical: (10 * sizeScale).clamp(6.0, 20.0),
          ),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onScaleChanged != null) ...[
                _ScaleChipButton(
                  icon: Icons.remove,
                  tooltip: 'Riduci dimensione pulsante',
                  onPressed: () =>
                      onScaleChanged!((sizeScale - 0.1).clamp(0.7, 2.2)),
                ),
                SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
              ],
              Icon(
                Icons.move_to_inbox_outlined,
                size: iconSize,
                color: theme.colorScheme.primary,
              ),
              SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
              Text(
                '→ $label',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (onScaleChanged != null) ...[
                SizedBox(width: (6 * sizeScale).clamp(4.0, 10.0)),
                _ScaleChipButton(
                  icon: Icons.add,
                  tooltip: 'Aumenta dimensione pulsante',
                  onPressed: () =>
                      onScaleChanged!((sizeScale + 0.1).clamp(0.7, 2.2)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ScaleChipButton extends StatelessWidget {
  const _ScaleChipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.futuristic = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool futuristic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: futuristic
                ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.12)
                : theme.colorScheme.primary.withValues(alpha: 0.1),
            border: Border.all(
              color: futuristic
                  ? CronosFuturisticTheme.neonCyan.withValues(alpha: 0.45)
                  : theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: futuristic
                ? CronosFuturisticTheme.neonCyan
                : theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
