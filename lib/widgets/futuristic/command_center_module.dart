import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/assenza_richieste_pending_service.dart';
import '../../utils/gestopro_tap_sound.dart';
import '../cronos_futuristic_tile.dart';
import 'command_center_painters.dart';
import 'holographic_painters.dart';

/// Modulo singolo del command center (stile mockup).
class CommandCenterModule extends StatefulWidget {
  const CommandCenterModule({
    super.key,
    required this.tile,
    required this.color,
    required this.style,
    required this.t,
    this.hubAssenzeBlinkKeys = const {},
    this.hubAssenzeBlinkOn = true,
  });

  final CronosFuturisticTile tile;
  final Color color;
  final CommandModuleStyle style;
  final double t;
  final Set<String> hubAssenzeBlinkKeys;
  final bool hubAssenzeBlinkOn;

  @override
  State<CommandCenterModule> createState() => _CommandCenterModuleState();
}

class _CommandCenterModuleState extends State<CommandCenterModule> {
  bool _hover = false;

  Color get _color => AssenzaRichiestePendingService.blinkIconColor(
        layoutKey: widget.tile.layoutKey,
        blinkKeys: widget.hubAssenzeBlinkKeys,
        blinkOn: widget.hubAssenzeBlinkOn,
        fallback: widget.color,
      );

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: wrapGestoproTap(widget.tile.onTap),
        child: AnimatedScale(
          scale: _hover ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (widget.style) {
      case CommandModuleStyle.pyramid:
        return _pyramid(inverted: false);
      case CommandModuleStyle.pyramidGold:
        return _pyramid(inverted: false, textured: true);
      case CommandModuleStyle.alertPyramid:
        return _pyramid(inverted: true, showWarning: true);
      case CommandModuleStyle.trainFrame:
        return _framed(WireframeTrainPainter(color: _color, t: widget.t));
      case CommandModuleStyle.jetFrame:
        return _framed(WireframeJetPainter(color: _color, t: widget.t));
      case CommandModuleStyle.cylinder:
        return _cylinder();
      case CommandModuleStyle.cubeDocs:
        return _cubeDocs();
      case CommandModuleStyle.logistics:
        return _logistics();
      case CommandModuleStyle.network:
        return _network();
      case CommandModuleStyle.medical:
        return _medical();
      case CommandModuleStyle.settingsPedestal:
        return _settingsPedestal();
      case CommandModuleStyle.glassPanel:
        return _glassPanel();
    }
  }

  Widget _label(String text, {double size = 11}) {
    return Text(
      text.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: CronosFonts.montserrat(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: _color.withValues(alpha: 0.95),
        shadows: [
          Shadow(color: _color.withValues(alpha: 0.8), blurRadius: 10),
        ],
      ),
    );
  }

  Widget _pyramid({
    required bool inverted,
    bool textured = false,
    bool showWarning = false,
  }) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: NeonPyramidPainter(
                  color: _color,
                  t: widget.t,
                  inverted: inverted,
                ),
              ),
              if (showWarning)
                Icon(Icons.warning_amber_rounded, color: _color, size: 36)
              else
                Icon(
                  widget.tile.icon,
                  color: _color.withValues(alpha: 0.9),
                  size: 32,
                  shadows: [Shadow(color: _color, blurRadius: 16)],
                ),
              if (textured)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.15,
                    child: CustomPaint(
                      painter: _CircuitTexturePainter(_color),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _label(widget.tile.label),
      ],
    );
  }

  Widget _framed(CustomPainter painter) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _color.withValues(alpha: 0.55), width: 1.5),
              color: const Color(0xFF131D2F).withValues(alpha: 0.55),
              boxShadow: [
                BoxShadow(
                  color: _color.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: GlassReflectPainter(opacity: 0.06)),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: painter),
                  ),
                  Center(
                    child: Icon(
                      widget.tile.icon,
                      color: _color.withValues(alpha: 0.35),
                      size: 48,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _label(widget.tile.label),
      ],
    );
  }

  Widget _cylinder() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: _color.withValues(alpha: 0.6), width: 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _color.withValues(alpha: 0.15),
                  const Color(0xFF131D2F).withValues(alpha: 0.8),
                  _color.withValues(alpha: 0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _color.withValues(alpha: 0.35),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Center(
              child: Icon(widget.tile.icon, color: _color, size: 40),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _label(widget.tile.label),
      ],
    );
  }

  Widget _cubeDocs() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(0.4)
                  ..rotateX(-0.25),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.white54),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(widget.tile.icon, color: Colors.white70, size: 28),
                ),
              ),
              Positioned(right: 8, top: 8, child: _docPane(0.7)),
              Positioned(left: 4, bottom: 12, child: _docPane(0.5)),
            ],
          ),
        ),
        _label(widget.tile.label),
      ],
    );
  }

  Widget _docPane(double opacity) {
    return Container(
      width: 28,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06 * opacity),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _logistics() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.precision_manufacturing_outlined, color: _color, size: 36),
        Icon(Icons.local_shipping_outlined, color: _color, size: 44),
        const SizedBox(height: 6),
        _label(widget.tile.label),
      ],
    );
  }

  Widget _network() {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _NetworkPainter(_color, widget.t),
            child: Center(
              child: Icon(Icons.hub_outlined, color: _color, size: 28),
            ),
          ),
        ),
        _label(widget.tile.label, size: 10),
        if (widget.tile.subtitle != null)
          Text(
            widget.tile.subtitle!,
            style: CronosFonts.montserrat(
              fontSize: 9,
              color: _color.withValues(alpha: 0.65),
            ),
          ),
      ],
    );
  }

  Widget _medical() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite, color: _color, size: 36),
            const SizedBox(width: 8),
            Icon(Icons.medical_services_outlined, color: _color, size: 36),
          ],
        ),
        const SizedBox(height: 8),
        _label(widget.tile.label, size: 10),
      ],
    );
  }

  Widget _settingsPedestal() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                left: 20,
                right: 20,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _color.withValues(alpha: 0.1),
                        _color.withValues(alpha: 0.35),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _color.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              Positioned(
                bottom: 28,
                child: Container(
                  width: 64,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2A3A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _color),
                    boxShadow: [
                      BoxShadow(color: _color.withValues(alpha: 0.4), blurRadius: 14),
                    ],
                  ),
                  child: Icon(widget.tile.icon, color: _color, size: 28),
                ),
              ),
            ],
          ),
        ),
        _label(widget.tile.label, size: 10),
      ],
    );
  }

  Widget _glassPanel() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF131D2F).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _color.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: _color.withValues(alpha: 0.25), blurRadius: 14),
            ],
          ),
          child: Icon(widget.tile.icon, color: _color, size: 36),
        ),
        const SizedBox(height: 8),
        _label(widget.tile.label, size: 10),
      ],
    );
  }
}

class _CircuitTexturePainter extends CustomPainter {
  _CircuitTexturePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 6),
        Offset(size.width, size.height * (i + 1) / 6),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = <Offset>[
      Offset(size.width * 0.5, size.height * 0.2),
      Offset(size.width * 0.2, size.height * 0.55),
      Offset(size.width * 0.8, size.height * 0.55),
      Offset(size.width * 0.35, size.height * 0.82),
      Offset(size.width * 0.65, size.height * 0.82),
    ];
    final line = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        canvas.drawLine(nodes[i], nodes[j], line);
      }
    }
    final dot = Paint()..color = color;
    for (final n in nodes) {
      canvas.drawCircle(n, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter old) =>
      old.t != t || old.color != color;
}
