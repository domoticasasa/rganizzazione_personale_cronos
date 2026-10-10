import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../theme/cronos_futuristic_theme.dart';

/// Barra azioni compatta per pagine senza AppBar classica (dentro shell futuristica).
class FuturisticInlineToolbar extends StatelessWidget {
  const FuturisticInlineToolbar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CronosFonts.exo2(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
