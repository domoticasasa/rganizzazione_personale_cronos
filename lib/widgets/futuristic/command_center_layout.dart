import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../cronos_futuristic_tile.dart';
import 'command_center_module.dart';
import 'command_center_painters.dart';
import 'cronos_hub_core.dart';

/// Layout radiale command center (replica mockup holographic).
class CommandCenterLayout extends StatefulWidget {
  const CommandCenterLayout({
    super.key,
    required this.tiles,
    required this.colorFor,
    this.hubAssenzeBlinkKeys = const {},
    this.hubAssenzeBlinkOn = true,
    this.onSwitchToClassic,
  });

  final List<CronosFuturisticTile> tiles;
  final Color Function(CronosFuturisticTile tile) colorFor;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;
  final VoidCallback? onSwitchToClassic;

  @override
  State<CommandCenterLayout> createState() => _CommandCenterLayoutState();
}

class _PlacedTile {
  _PlacedTile({
    required this.tile,
    required this.slot,
    required this.color,
  });

  final CronosFuturisticTile tile;
  final CommandCenterSlotDef slot;
  final Color color;
}

class _CommandCenterLayoutState extends State<CommandCenterLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String _hay(CronosFuturisticTile t) =>
      '${t.layoutKey} ${t.label}'.toLowerCase();

  CronosFuturisticTile? _findHubTile() {
    for (final t in widget.tiles) {
      if (isHubGlobeTile(_hay(t))) return t;
    }
    return null;
  }

  List<_PlacedTile> _placeTiles() {
    final hub = _findHubTile();
    final used = <String>{};
    final placed = <_PlacedTile>[];

    for (final slot in kCommandCenterSlots) {
      CronosFuturisticTile? match;
      for (final tile in widget.tiles) {
        if (used.contains(tile.layoutKey)) continue;
        if (isHubGlobeTile(_hay(tile))) continue;
        final hay = _hay(tile);
        if (slot.patterns.any(hay.contains)) {
          match = tile;
          break;
        }
      }
      if (match != null) {
        used.add(match.layoutKey);
        placed.add(_PlacedTile(
          tile: match,
          slot: slot,
          color: slot.defaultColor ?? widget.colorFor(match),
        ));
      }
    }

    // Tile non mappati: riga compatta in basso
    final overflow = widget.tiles
        .where((t) => !used.contains(t.layoutKey) && t != hub)
        .toList();
    if (overflow.isNotEmpty) {
      var col = 0;
      for (final tile in overflow) {
        placed.add(_PlacedTile(
          tile: tile,
          slot: CommandCenterSlotDef(
            patterns: const [],
            rect: CommandCenterRect(
              0.48 + (col % 3) * 0.06,
              0.88,
              0.14,
              0.10,
            ),
            style: styleForHaystack(_hay(tile)),
          ),
          color: widget.colorFor(tile),
        ));
        col++;
      }
    }

    return placed;
  }

  @override
  Widget build(BuildContext context) {
    final hubTile = _findHubTile();
    final placed = _placeTiles();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.onSwitchToClassic != null)
              Positioned(
                left: 8,
                top: 4,
                child: TextButton.icon(
                  onPressed: widget.onSwitchToClassic,
                  icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF00E5FF)),
                  label: Text(
                    'Indietro',
                    style: CronosFonts.montserrat(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: kHubCenterRect.toRect(size),
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, _) => CronosHubCore(
                  t: _anim.value,
                  gpsTile: hubTile,
                ),
              ),
            ),
            for (final p in placed)
              Positioned.fromRect(
                rect: p.slot.rect.toRect(size),
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, _) => CommandCenterModule(
                    tile: p.tile,
                    color: p.color,
                    style: p.slot.style,
                    t: _anim.value,
                    hubAssenzeBlinkKeys: widget.hubAssenzeBlinkKeys,
                    hubAssenzeBlinkOn: widget.hubAssenzeBlinkOn,
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 8,
              child: _NotifyChip(),
            ),
          ],
        );
      },
    );
  }
}

class _NotifyChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A3A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2979FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2979FF).withValues(alpha: 0.25),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        'Abilita notifiche browser',
        style: CronosFonts.montserrat(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
