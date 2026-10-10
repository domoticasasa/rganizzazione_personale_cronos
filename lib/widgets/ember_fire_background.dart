import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Sfondo scuro "fiammella" Gestopro360 (tema scuro): base grafite/blu notte,
/// braci che salgono lente, bagliore caldo in basso e una scia di fuoco che
/// segue il mouse (desktop/web) o il dito (tocco/trascinamento su mobile).
/// Al click/tap la fiamma fa una piccola fiammata.
///
/// Disegnato con lo shader `shaders/ember_fire.frag` (FragmentProgram);
/// se lo shader non si carica usa un CustomPainter di riserva.
///
/// Come [LiquidWaterBackground] sta DIETRO ai contenuti e non intercetta
/// eventi: ascolta il puntatore con una route globale del [GestureBinding].
class EmberFireBackground extends StatefulWidget {
  const EmberFireBackground({super.key, this.intensity = 1.0});

  /// 0..1.5 circa: intensita' di fuoco, braci e bagliore.
  final double intensity;

  static const String shaderAsset = 'shaders/ember_fire.frag';

  @override
  State<EmberFireBackground> createState() => _EmberFireBackgroundState();
}

class _FirePoint {
  _FirePoint(this.pos, this.born, this.strength);
  final Offset pos;
  final double born;
  final double strength;
}

class _EmberFireBackgroundState extends State<EmberFireBackground>
    with SingleTickerProviderStateMixin {
  static const int maxPoints = 12;
  static const double pointLife = 1.4;

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  late final Ticker _ticker;
  final _EmberFrame _frame = _EmberFrame();
  ui.FragmentShader? _shader;
  bool _shaderFailed = false;
  bool _reduceMotion = false;

  double _time = 0;
  double _lastPaint = -1;
  final List<_FirePoint> _points = <_FirePoint>[];
  Offset? _pointer;
  double _presence = 0;
  double _presenceTarget = 0;
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
        EmberFireBackground.shaderAsset,
      );
    } catch (e) {
      debugPrint('EmberFireBackground: shader non disponibile ($e), '
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
      _points.clear();
      _presence = 0;
      _presenceTarget = 0;
      _frame.tick();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _time).clamp(0.0, 0.1);
    _time = t;
    if (_presenceTarget > 0.5 && t - _lastPointerTime > 3.0) {
      _presenceTarget = 0.45; // puntatore fermo: la fiammella si abbassa
    }
    _presence += (_presenceTarget - _presence) * math.min(1.0, dt * 6);
    _points.removeWhere((p) => t - p.born > pointLife);
    final busy =
        _points.isNotEmpty || (_presence - _presenceTarget).abs() > 0.01;
    // Solo braci lente: 30 fps bastano (meno GPU/batteria).
    if (!busy && t - _lastPaint < 1 / 30) return;
    _lastPaint = t;
    _frame.tick();
  }

  void _onPointer(PointerEvent event) {
    if (!mounted || _reduceMotion) return;
    final mouse = event.kind == PointerDeviceKind.mouse;
    if (event is PointerRemovedEvent ||
        (!mouse && (event is PointerUpEvent || event is PointerCancelEvent))) {
      _presenceTarget = 0;
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
    _pointer = local;
    _presenceTarget = 1;
    if (event is PointerDownEvent) {
      _spawn(local, 1.8); // fiammata
      return;
    }
    final drag = event is PointerMoveEvent;
    final last = _lastSpawnPos;
    if (last == null ||
        ((local - last).distance >= 14.0 && _time - _lastSpawnTime >= 0.03)) {
      _spawn(local, drag ? 0.8 : 0.6);
    }
  }

  void _spawn(Offset pos, double strength) {
    if (_points.length >= maxPoints) _points.removeAt(0);
    _points.add(_FirePoint(pos, _time, strength));
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
            ? _EmberShaderPainter(this, shader)
            : _EmberFallbackPainter(this, animated: _shaderFailed),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EmberFrame extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _EmberShaderPainter extends CustomPainter {
  _EmberShaderPainter(this.state, this.shader) : super(repaint: state._frame);

  final _EmberFireBackgroundState state;
  final ui.FragmentShader shader;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final t = s._time;
    final m = s._pointer ?? Offset(size.width * 0.5, size.height * 0.5);
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t % 3600.0)
      ..setFloat(3, m.dx)
      ..setFloat(4, m.dy)
      ..setFloat(5, s._presence)
      ..setFloat(6, s.widget.intensity.clamp(0.0, 1.5));
    for (var i = 0; i < _EmberFireBackgroundState.maxPoints; i++) {
      final base = 7 + i * 4;
      if (i < s._points.length) {
        final p = s._points[i];
        shader
          ..setFloat(base, p.pos.dx)
          ..setFloat(base + 1, p.pos.dy)
          ..setFloat(base + 2, t - p.born)
          ..setFloat(base + 3, p.strength);
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
  bool shouldRepaint(covariant _EmberShaderPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.shader != shader;
}

/// Riserva senza shader: gradiente scuro, braci, aloni caldi sul puntatore.
class _EmberFallbackPainter extends CustomPainter {
  _EmberFallbackPainter(this.state, {required this.animated})
      : super(repaint: state._frame);

  final _EmberFireBackgroundState state;
  final bool animated;

  static const Color _top = Color(0xFF0A0D14);
  static const Color _bottom = Color(0xFF121826);
  static const Color _orange = Color(0xFFFF7A1A);
  static const Color _amber = Color(0xFFFFB547);
  static const Color _red = Color(0xFFB3261E);

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
          colors: [_top, _bottom],
        ).createShader(rect),
    );
    // Bagliore caldo in basso.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_orange.withValues(alpha: 0.10), Colors.transparent],
          stops: const [0.0, 0.35],
        ).createShader(rect),
    );
    if (!animated) return; // shader in caricamento: solo la base

    // Braci: posizioni pseudo-casuali che salgono e si ripetono.
    final ember = Paint();
    for (var i = 0; i < 40; i++) {
      final seed = i * 12.9898;
      final rx = (math.sin(seed) * 43758.5453) % 1.0;
      final sp = 18 + ((math.sin(seed * 1.7) * 9631.1) % 1.0).abs() * 30;
      final y = size.height -
          ((t * sp + i * 97) % (size.height + 40)) +
          20;
      final x = size.width * rx.abs() + 8 * math.sin(t * 1.2 + i);
      final a = (0.25 + 0.5 * (y / size.height)).clamp(0.0, 0.8) *
          (0.6 + 0.4 * math.sin(t * 4 + i));
      ember
        ..color = _amber.withValues(alpha: a.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(x, y), 1.6, ember);
    }

    // Scia di fuoco.
    final glow = Paint();
    for (final p in state._points) {
      final age = t - p.born;
      final k = (p.strength * math.exp(-age * 3.2)).clamp(0.0, 1.0);
      if (k <= 0.01) continue;
      final c = p.pos.translate(0, -age * 85);
      final r = (14 + age * 42) * (0.75 + 0.3 * p.strength);
      glow
        ..color = Color.lerp(_red, _orange, k)!.withValues(alpha: 0.55 * k)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 1.4, height: r * 2.2),
        glow,
      );
    }
    final m = state._pointer;
    if (m != null && state._presence > 0.01) {
      final flick = 0.85 + 0.15 * math.sin(t * 13) * math.sin(t * 7.3 + 1);
      canvas.drawOval(
        Rect.fromCenter(center: m.translate(0, -8), width: 18, height: 30),
        Paint()
          ..color = _amber.withValues(alpha: 0.85 * state._presence * flick)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmberFallbackPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.animated != animated;
}
