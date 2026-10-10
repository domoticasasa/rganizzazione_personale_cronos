import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Sfondo "acqua liquida" azzurro Gestopro360: caustiche che scorrono lente,
/// rifrazione morbida e increspature che seguono il mouse (desktop/web) o
/// nascono al tocco/trascinamento (mobile).
///
/// Disegnato con lo shader `shaders/liquid_water.frag` (FragmentProgram,
/// ok su web CanvasKit/skwasm e mobile); se lo shader non si carica usa un
/// CustomPainter di riserva.
///
/// Sta DIETRO ai contenuti e non intercetta nessun evento: legge il puntatore
/// con una route globale del [GestureBinding] (solo ascolto), quindi funziona
/// anche dentro [IgnorePointer] e sotto pagine/card.
class LiquidWaterBackground extends StatefulWidget {
  const LiquidWaterBackground({super.key, this.intensity = 1.0});

  /// 0..1.5 circa: intensita' di caustiche e increspature.
  final double intensity;

  static const String shaderAsset = 'shaders/liquid_water.frag';

  @override
  State<LiquidWaterBackground> createState() => _LiquidWaterBackgroundState();
}

class _Ripple {
  _Ripple(this.pos, this.born, this.strength);
  final Offset pos;
  final double born;
  final double strength;
}

class _LiquidWaterBackgroundState extends State<LiquidWaterBackground>
    with SingleTickerProviderStateMixin {
  static const int maxRipples = 10;
  static const double rippleLife = 3.2;

  // Programma condiviso tra tutte le istanze (caricato una volta).
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  late final Ticker _ticker;
  final _LiquidFrame _frame = _LiquidFrame();
  ui.FragmentShader? _shader;
  bool _shaderFailed = false;
  bool _reduceMotion = false;

  double _time = 0;
  double _lastPaint = -1;
  final List<_Ripple> _ripples = <_Ripple>[];
  Offset? _mouse;
  double _mousePresence = 0;
  double _mouseTarget = 0;
  double _lastPointerTime = -10;
  Offset? _lastSpawnPos;
  double _lastSpawnTime = -10;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _initShader();
  }

  static Future<ui.FragmentProgram?> _loadProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        LiquidWaterBackground.shaderAsset,
      );
    } catch (e) {
      debugPrint('LiquidWaterBackground: shader non disponibile ($e), '
          'uso il fallback.');
      return null;
    }
  }

  Future<void> _initShader() async {
    final program = _program ?? await (_loading ??= _loadProgram());
    if (!mounted) return;
    if (program == null) {
      setState(() => _shaderFailed = true);
      return;
    }
    _program = program;
    setState(() => _shader = program.fragmentShader());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      if (_ticker.isActive) _ticker.stop();
      _ripples.clear();
      _frame.tick();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _time).clamp(0.0, 0.1);
    _time = t;
    if (_mouseTarget > 0.5 && t - _lastPointerTime > 2.5) {
      _mouseTarget = 0.35; // mouse fermo: la luce si attenua
    }
    _mousePresence += (_mouseTarget - _mousePresence) * math.min(1.0, dt * 4);
    _ripples.removeWhere((r) => t - r.born > rippleLife);
    final busy =
        _ripples.isNotEmpty || (_mousePresence - _mouseTarget).abs() > 0.01;
    // Solo flusso lento: 30 fps bastano (meno GPU/batteria).
    if (!busy && t - _lastPaint < 1 / 30) return;
    _lastPaint = t;
    _frame.tick();
  }

  void _onPointer(PointerEvent event) {
    if (!mounted || _reduceMotion) return;
    if (event is PointerRemovedEvent) {
      _mouseTarget = 0;
      return;
    }
    if (event is! PointerHoverEvent &&
        event is! PointerMoveEvent &&
        event is! PointerDownEvent) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    if (!(Offset.zero & box.size).contains(local)) return;

    _lastPointerTime = _time;
    if (event.kind == PointerDeviceKind.mouse) {
      _mouse = local;
      _mouseTarget = 1;
    }
    if (event is PointerDownEvent) {
      _spawn(local, 1.0);
      return;
    }
    final drag = event is PointerMoveEvent;
    final last = _lastSpawnPos;
    if (last == null ||
        ((local - last).distance >= (drag ? 36.0 : 30.0) &&
            _time - _lastSpawnTime >= 0.07)) {
      _spawn(local, drag ? 0.8 : 0.55);
    }
  }

  void _spawn(Offset pos, double strength) {
    if (_ripples.length >= maxRipples) _ripples.removeAt(0);
    _ripples.add(_Ripple(pos, _time, strength));
    _lastSpawnPos = pos;
    _lastSpawnTime = _time;
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _ticker.dispose();
    _shader?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return RepaintBoundary(
      child: CustomPaint(
        painter: shader != null
            ? _LiquidShaderPainter(this, shader)
            : _LiquidFallbackPainter(this, animated: _shaderFailed),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LiquidFrame extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _LiquidShaderPainter extends CustomPainter {
  _LiquidShaderPainter(this.state, this.shader) : super(repaint: state._frame);

  final _LiquidWaterBackgroundState state;
  final ui.FragmentShader shader;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final t = s._time;
    final m = s._mouse ?? Offset(size.width * 0.5, size.height * 0.35);
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t % 3600.0)
      ..setFloat(3, m.dx)
      ..setFloat(4, m.dy)
      ..setFloat(5, s._mousePresence)
      ..setFloat(6, s.widget.intensity.clamp(0.0, 1.5));
    for (var i = 0; i < _LiquidWaterBackgroundState.maxRipples; i++) {
      final base = 7 + i * 4;
      if (i < s._ripples.length) {
        final r = s._ripples[i];
        shader
          ..setFloat(base, r.pos.dx)
          ..setFloat(base + 1, r.pos.dy)
          ..setFloat(base + 2, t - r.born)
          ..setFloat(base + 3, r.strength);
      } else {
        shader
          ..setFloat(base, 0)
          ..setFloat(base + 1, 0)
          ..setFloat(base + 2, 0)
          ..setFloat(base + 3, 0);
      }
    }
    _paint.shader = shader;
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidShaderPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.shader != shader;
}

/// Riserva senza shader: gradiente azzurro, macchie di luce lente, anelli.
class _LiquidFallbackPainter extends CustomPainter {
  _LiquidFallbackPainter(this.state, {required this.animated})
      : super(repaint: state._frame);

  final _LiquidWaterBackgroundState state;
  final bool animated;

  static const Color _top = Color(0xFFEEF6FD);
  static const Color _deep = Color(0xFFC7E2F5);
  static const Color _cyan = Color(0xFF00AEEF);
  static const Color _accent = Color(0xFF1565C0);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = state._time;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_top, _deep],
        ).createShader(rect),
    );
    if (!animated) return; // shader in caricamento: solo il gradiente

    final glow = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.08);
    for (var i = 0; i < 5; i++) {
      final a = t * (0.05 + i * 0.012) + i * 1.7;
      glow.color = (i.isEven ? Colors.white : _cyan)
          .withValues(alpha: i.isEven ? 0.30 : 0.07);
      canvas.drawCircle(
        Offset(
          size.width * (0.5 + 0.38 * math.cos(a)),
          size.height * (0.5 + 0.34 * math.sin(a * 1.3)),
        ),
        size.shortestSide * (0.16 + 0.03 * i),
        glow,
      );
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final r in state._ripples) {
      final age = t - r.born;
      final k = (r.strength * math.exp(-age * 1.5)).clamp(0.0, 1.0);
      for (var j = 0; j < 3; j++) {
        final radius = age * 240 - j * 45;
        if (radius <= 0) continue;
        ring
          ..strokeWidth = 3.0 - j * 0.6
          ..color = (j.isEven ? Colors.white : _cyan)
              .withValues(alpha: k * (j.isEven ? 0.55 : 0.18));
        canvas.drawCircle(r.pos, radius, ring);
      }
    }

    final m = state._mouse;
    if (m != null && state._mousePresence > 0.01) {
      canvas.drawCircle(
        m,
        150,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * state._mousePresence)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.1,
          colors: [Colors.transparent, _accent.withValues(alpha: 0.08)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidFallbackPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.animated != animated;
}
