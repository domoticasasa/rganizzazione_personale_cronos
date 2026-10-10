import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

/// Selettore vista Classica / GESTOPRO per la barra in alto.
class UiViewModeSwitch extends StatelessWidget {
  const UiViewModeSwitch({
    super.key,
    required this.gestoproSelected,
    this.onSelectClassic,
    this.onSelectGestopro,
    this.lightOnDark = false,
    this.compact = false,
  });

  final bool gestoproSelected;
  final VoidCallback? onSelectClassic;
  final VoidCallback? onSelectGestopro;
  final bool lightOnDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final border = lightOnDark
        ? Colors.white.withValues(alpha: 0.35)
        : Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.35);
    final idleFg = lightOnDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75);
    final activeBg = lightOnDark
        ? const Color(0xFF00E5FF).withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.22);
    final activeFg = lightOnDark
        ? Colors.white
        : Theme.of(context).colorScheme.onPrimary;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback? onTap,
    }) {
      return Material(
        color: selected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          mouseCursor: selected
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            child: Text(
              label,
              style: CronosFonts.orbitron(
                fontSize: compact ? 9 : 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: compact ? 0.4 : 0.6,
                color: selected ? activeFg : idleFg,
                height: 1,
              ),
            ),
          ),
        ),
      );
    }

    // Niente Tooltip: su web/desktop il primo tap lo “mangia”.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(
            label: 'Classica',
            selected: !gestoproSelected,
            onTap: onSelectClassic,
          ),
          chip(
            label: 'Gestopro',
            selected: gestoproSelected,
            onTap: onSelectGestopro,
          ),
        ],
      ),
    );
  }
}
