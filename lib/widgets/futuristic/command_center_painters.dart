import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stile visivo del modulo nel command center (mockup CRONOS).
enum CommandModuleStyle {
  pyramid,
  trainFrame,
  jetFrame,
  cylinder,
  cubeDocs,
  logistics,
  network,
  pyramidGold,
  alertPyramid,
  medical,
  settingsPedestal,
  glassPanel,
}

/// Posizione normalizzata (0–1) su canvas command center.
class CommandCenterRect {
  const CommandCenterRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  Rect toRect(Size size) => Rect.fromLTWH(
        left * size.width,
        top * size.height,
        width * size.width,
        height * size.height,
      );
}

/// Configurazione slot fissa come nel mockup holographic.
class CommandCenterSlotDef {
  const CommandCenterSlotDef({
    required this.patterns,
    required this.rect,
    required this.style,
    this.defaultColor,
  });

  final List<String> patterns;
  final CommandCenterRect rect;
  final CommandModuleStyle style;
  final Color? defaultColor;
}

/// Slot predefiniti (posizioni dal mockup Gemini).
const kCommandCenterSlots = <CommandCenterSlotDef>[
  CommandCenterSlotDef(
    patterns: ['pernott'],
    rect: CommandCenterRect(0.02, 0.03, 0.17, 0.34),
    style: CommandModuleStyle.pyramid,
    defaultColor: Color(0xFF00E676),
  ),
  CommandCenterSlotDef(
    patterns: ['tren'],
    rect: CommandCenterRect(0.19, 0.04, 0.24, 0.28),
    style: CommandModuleStyle.trainFrame,
    defaultColor: Color(0xFF00E5FF),
  ),
  CommandCenterSlotDef(
    patterns: ['aer'],
    rect: CommandCenterRect(0.43, 0.04, 0.24, 0.28),
    style: CommandModuleStyle.jetFrame,
    defaultColor: Color(0xFFFF1744),
  ),
  CommandCenterSlotDef(
    patterns: ['carbur', 'riforn'],
    rect: CommandCenterRect(0.69, 0.05, 0.12, 0.40),
    style: CommandModuleStyle.cylinder,
    defaultColor: Color(0xFF00BFA5),
  ),
  CommandCenterSlotDef(
    patterns: ['formaz', 'dlgs', 'rfi'],
    rect: CommandCenterRect(0.82, 0.04, 0.16, 0.32),
    style: CommandModuleStyle.cubeDocs,
    defaultColor: Color(0xFFFAFAFA),
  ),
  CommandCenterSlotDef(
    patterns: ['logistic'],
    rect: CommandCenterRect(0.00, 0.50, 0.16, 0.30),
    style: CommandModuleStyle.logistics,
    defaultColor: Color(0xFFFFD700),
  ),
  CommandCenterSlotDef(
    patterns: ['personale', 'dipendent', 'gestione_person'],
    rect: CommandCenterRect(0.13, 0.56, 0.19, 0.28),
    style: CommandModuleStyle.network,
    defaultColor: Color(0xFF2979FF),
  ),
  CommandCenterSlotDef(
    patterns: ['uqsa', 'qsa', 'osa'],
    rect: CommandCenterRect(0.33, 0.62, 0.15, 0.26),
    style: CommandModuleStyle.pyramidGold,
    defaultColor: Color(0xFFFFB300),
  ),
  CommandCenterSlotDef(
    patterns: ['scadenz', 'alert'],
    rect: CommandCenterRect(0.55, 0.64, 0.13, 0.22),
    style: CommandModuleStyle.alertPyramid,
    defaultColor: Color(0xFFFF1744),
  ),
  CommandCenterSlotDef(
    patterns: ['visite', 'medic'],
    rect: CommandCenterRect(0.71, 0.50, 0.15, 0.28),
    style: CommandModuleStyle.medical,
    defaultColor: Color(0xFFFF80AB),
  ),
  CommandCenterSlotDef(
    patterns: ['impostaz', 'settings'],
    rect: CommandCenterRect(0.85, 0.60, 0.14, 0.24),
    style: CommandModuleStyle.settingsPedestal,
    defaultColor: Color(0xFF2979FF),
  ),
];

const kHubCenterRect = CommandCenterRect(0.36, 0.30, 0.28, 0.52);

CommandModuleStyle styleForHaystack(String haystack) {
  if (haystack.contains('pernott')) return CommandModuleStyle.pyramid;
  if (haystack.contains('tren')) return CommandModuleStyle.trainFrame;
  if (haystack.contains('aer')) return CommandModuleStyle.jetFrame;
  if (haystack.contains('carbur') || haystack.contains('riforn')) {
    return CommandModuleStyle.cylinder;
  }
  if (haystack.contains('formaz') || haystack.contains('dlgs')) {
    return CommandModuleStyle.cubeDocs;
  }
  if (haystack.contains('logistic')) return CommandModuleStyle.logistics;
  if (haystack.contains('personale') || haystack.contains('admin')) {
    return CommandModuleStyle.network;
  }
  if (haystack.contains('uqsa') || haystack.contains('qsa') || haystack.contains('osa')) {
    return CommandModuleStyle.pyramidGold;
  }
  if (haystack.contains('scadenz') || haystack.contains('alert')) {
    return CommandModuleStyle.alertPyramid;
  }
  if (haystack.contains('visite') || haystack.contains('medic')) {
    return CommandModuleStyle.medical;
  }
  if (haystack.contains('impostaz') || haystack.contains('settings')) {
    return CommandModuleStyle.settingsPedestal;
  }
  return CommandModuleStyle.glassPanel;
}

bool isHubGlobeTile(String haystack) =>
    haystack.contains('mappa') || haystack.contains('gps');

/// Piramide wireframe neon.
class NeonPyramidPainter extends CustomPainter {
  NeonPyramidPainter({required this.color, required this.t, this.inverted = false});

  final Color color;
  final double t;
  final bool inverted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.35 + pulse * 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final apex = Offset(w * 0.5, inverted ? h * 0.82 : h * 0.18);
    final bl = Offset(w * 0.12, inverted ? h * 0.22 : h * 0.88);
    final br = Offset(w * 0.88, inverted ? h * 0.22 : h * 0.88);
    final path = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..close();
    canvas.drawPath(path, stroke);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0.22),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, fill);

    for (var i = 1; i <= 3; i++) {
      final y = inverted
          ? h * 0.22 + (h * 0.6) * i / 4
          : h * 0.88 - (h * 0.6) * i / 4;
      final inset = w * 0.12 + (w * 0.76) * (1 - i / 4);
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant NeonPyramidPainter old) =>
      old.t != t || old.color != color || old.inverted != inverted;
}

/// Treno wireframe in cornice orizzontale.
class WireframeTrainPainter extends CustomPainter {
  WireframeTrainPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.42, w * 0.84, h * 0.22),
      const Radius.circular(6),
    );
    canvas.drawRRect(body, paint);
    canvas.drawLine(Offset(w * 0.22, h * 0.42), Offset(w * 0.18, h * 0.28), paint);
    canvas.drawLine(Offset(w * 0.78, h * 0.42), Offset(w * 0.82, h * 0.28), paint);
    for (var i = 0; i < 5; i++) {
      final x = w * (0.2 + i * 0.14);
      canvas.drawRect(Rect.fromLTWH(x, h * 0.46, w * 0.08, h * 0.1), paint);
    }
    final glow = Paint()
      ..color = color.withValues(alpha: 0.15 + 0.1 * math.sin(t * math.pi * 2))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(body, glow);
  }

  @override
  bool shouldRepaint(covariant WireframeTrainPainter old) =>
      old.t != t || old.color != color;
}

/// Jet wireframe.
class WireframeJetPainter extends CustomPainter {
  WireframeJetPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.12, h * 0.55)
      ..lineTo(w * 0.45, h * 0.48)
      ..lineTo(w * 0.88, h * 0.52)
      ..lineTo(w * 0.45, h * 0.58)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(Offset(w * 0.45, h * 0.48), Offset(w * 0.42, h * 0.32), paint);
    canvas.drawLine(Offset(w * 0.45, h * 0.58), Offset(w * 0.42, h * 0.72), paint);
    canvas.drawLine(Offset(w * 0.55, h * 0.5), Offset(w * 0.78, h * 0.38), paint);
    canvas.drawLine(Offset(w * 0.55, h * 0.56), Offset(w * 0.78, h * 0.68), paint);
  }

  @override
  bool shouldRepaint(covariant WireframeJetPainter old) =>
      old.t != t || old.color != color;
}

/// Globo GPS con reticolo.
class HubGlobePainter extends CustomPainter {
  HubGlobePainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.42;
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);

    final sphere = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.35),
          const Color(0xFF2979FF).withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, sphere);

    final grid = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35 + pulse * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r, grid);
    for (var i = -2; i <= 2; i++) {
      final dy = c.dy + i * r * 0.35;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        0,
        math.pi,
        false,
        grid,
      );
      canvas.drawLine(Offset(c.dx - r, dy), Offset(c.dx + r, dy), grid);
    }

    final cross = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(c.dx - r * 0.35, c.dy), Offset(c.dx + r * 0.35, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - r * 0.35), Offset(c.dx, c.dy + r * 0.35), cross);
    canvas.drawCircle(c, 4, cross..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant HubGlobePainter old) => old.t != t;
}

/// Pedestale cristallino CRONOS HUB.
class HubPedestalPainter extends CustomPainter {
  HubPedestalPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.25 + pulse * 0.15),
          const Color(0xFF2979FF).withValues(alpha: 0.45),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(w * 0.35, h * 0.05)
      ..lineTo(w * 0.65, h * 0.05)
      ..lineTo(w * 0.78, h * 0.95)
      ..lineTo(w * 0.22, h * 0.95)
      ..close();
    canvas.drawPath(path, paint);

    final edge = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(covariant HubPedestalPainter old) => old.t != t;
}
