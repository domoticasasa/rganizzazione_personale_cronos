import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/app_branding_service.dart';
import '../../services/app_chat_overlay_controller.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../futuristic/holographic_painters.dart';

/// Larghezza FAB in base al nome prodotto (es. GESTOPRO360).
double chatFabWidthForProduct(String productName) {
  final label =
      productName.trim().isEmpty ? 'GESTOPRO' : productName.trim().toUpperCase();
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: CronosFonts.orbitron(
        fontWeight: FontWeight.w700,
        fontSize: 9.5,
        letterSpacing: 0.9,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return (painter.width + 32).clamp(104.0, 172.0);
}

/// Pulsante chat: pillola con nome prodotto + «Chat».
/// Tap apre; tieni premuto 0,5s e trascina per spostarlo.
class AppChatFab extends StatefulWidget {
  const AppChatFab({super.key});

  @override
  State<AppChatFab> createState() => _AppChatFabState();
}

class _AppChatFabState extends State<AppChatFab> {
  static const _height = 38.0;

  @override
  void initState() {
    super.initState();
    unawaited(AppChatOverlayController.ensureFabPositionLoaded());
  }

  void _openIfNotDragging() {
    if (AppChatOverlayController.isOpen.value) return;
    unawaited(AppChatOverlayController.tryOpen(context));
  }

  void _updateAnchorFromGlobal(Offset global, Size screen) {
    final x = (global.dx / screen.width).clamp(0.0, 1.0);
    final y = (global.dy / screen.height).clamp(0.0, 1.0);
    AppChatOverlayController.fabAnchor.value = Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);

    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final width =
            chatFabWidthForProduct(AppBrandingService.instance.productName);

        return ValueListenableBuilder<bool>(
          valueListenable: AppChatOverlayController.isOpen,
          builder: (context, open, _) {
            if (open) return const SizedBox.shrink();
            return AnimatedBuilder(
              animation: Listenable.merge([
                AppChatOverlayController.fabAnchor,
                AppChatOverlayController.fabAnchorOverride,
              ]),
              builder: (context, _) {
                final override =
                    AppChatOverlayController.fabAnchorOverride.value;
                final anchor =
                    override ?? AppChatOverlayController.fabAnchor.value;
                final left = (anchor.dx * screen.width) - (width / 2);
                final top = (anchor.dy * screen.height) - (_height / 2);
                final clampedLeft = left
                    .clamp(8.0, math.max(8.0, screen.width - width - 8))
                    .toDouble();
                // Con override (home dipendente) lascia più aria sopra la gesture bar.
                final bottomGap = override != null ? 16.0 : 8.0;
                final clampedTop = top
                    .clamp(
                      pad.top + 8,
                      math.max(
                        pad.top + 8,
                        screen.height - pad.bottom - _height - bottomGap,
                      ),
                    )
                    .toDouble();

                return Positioned(
                  left: clampedLeft,
                  top: clampedTop,
                  child: ValueListenableBuilder<int>(
                    valueListenable: AppChatOverlayController.unreadCount,
                    builder: (context, unread, _) {
                      final chip = _GestoproBubble(
                        width: width,
                        height: _height,
                        dragging: false,
                        unread: unread,
                        futuristic: true,
                      );
                      final tapChild = GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openIfNotDragging,
                        child: chip,
                      );
                      // Con override (home dipendente) il FAB resta fisso al centro.
                      if (override != null) return tapChild;
                      return LongPressDraggable<String>(
                        data: 'gestopro_chat_fab',
                        delay: const Duration(milliseconds: 500),
                        hapticFeedbackOnStart: true,
                        onDragStarted: () {
                          HapticFeedback.mediumImpact();
                        },
                        onDragUpdate: (details) {
                          _updateAnchorFromGlobal(
                            details.globalPosition,
                            screen,
                          );
                        },
                        onDragEnd: (details) {
                          final center = Offset(
                            details.offset.dx + width / 2,
                            details.offset.dy + _height / 2,
                          );
                          _updateAnchorFromGlobal(center, screen);
                          unawaited(
                            AppChatOverlayController.setFabAnchor(
                              AppChatOverlayController.fabAnchor.value,
                            ),
                          );
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          child: Transform.scale(
                            scale: 1.08,
                            child: _GestoproBubble(
                              width: width,
                              height: _height,
                              dragging: true,
                              unread: unread,
                              futuristic: true,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.25,
                          child: chip,
                        ),
                        child: tapChild,
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _GestoproBubble extends StatefulWidget {
  const _GestoproBubble({
    required this.width,
    required this.height,
    required this.dragging,
    required this.unread,
    required this.futuristic,
  });

  final double width;
  final double height;
  final bool dragging;
  final int unread;
  final bool futuristic;

  @override
  State<_GestoproBubble> createState() => _GestoproBubbleState();
}

class _GestoproBubbleState extends State<_GestoproBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.futuristic) _glowCtrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _GestoproBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.futuristic && !_glowCtrl.isAnimating) {
      _glowCtrl.repeat();
    } else if (!widget.futuristic && _glowCtrl.isAnimating) {
      _glowCtrl.stop();
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  String get _productLabel {
    final n = AppBrandingService.instance.productName.trim();
    return n.isEmpty ? 'GESTOPRO' : n.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.futuristic) {
      return AnimatedBuilder(
        animation: _glowCtrl,
        builder: (context, _) => _buildFuturistic(),
      );
    }
    return _buildClassic();
  }

  Widget _buildFuturistic() {
    final w = widget.width;
    final h = widget.height;
    final accent = AppBrandingService.instance.accentColor;
    const stroke = 1.4;
    final label = _productLabel;

    return SizedBox(
      width: w,
      height: h + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 1,
            right: 1,
            top: 4,
            child: Container(
              height: h - 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h / 2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(
                      alpha: widget.dragging ? 0.55 : 0.32,
                    ),
                    blurRadius: widget.dragging ? 18 : 12,
                    spreadRadius: widget.dragging ? 1 : 0,
                    offset: Offset(0, widget.dragging ? 8 : 5),
                  ),
                  BoxShadow(
                    color: CronosFuturisticTheme.neonPurple
                        .withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          CustomPaint(
            painter: GlowingBorderPainter(
              animationValue: _glowCtrl.value,
              color: accent,
              borderRadius: h / 2,
              strokeWidth: stroke,
            ),
            child: Padding(
              padding: const EdgeInsets.all(stroke),
              child: ClipPath(
                clipper: _SoftBubbleClipper(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: SizedBox(
                    width: w - stroke * 2,
                    height: h + 6 - stroke * 2,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                CronosFuturisticTheme.panelBg
                                    .withValues(alpha: 0.96),
                                CronosFuturisticTheme.deepSpace
                                    .withValues(alpha: 0.98),
                                CronosFuturisticTheme.voidBg,
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            height: h * 0.4,
                            margin: const EdgeInsets.fromLTRB(5, 2, 5, 0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  accent.withValues(alpha: 0.2),
                                  accent.withValues(alpha: 0.04),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: CronosFonts.orbitron(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9.5,
                                    letterSpacing: 0.9,
                                    height: 1.05,
                                    color:
                                        Colors.white.withValues(alpha: 0.98),
                                    decoration: TextDecoration.none,
                                    shadows: [
                                      Shadow(
                                        color: accent.withValues(alpha: 0.75),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Chat',
                                style: CronosFonts.exo2(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 8,
                                  letterSpacing: 0.6,
                                  height: 1.05,
                                  color: accent.withValues(alpha: 0.95),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.unread > 0) _unreadBadge(futuristic: true),
        ],
      ),
    );
  }

  Widget _buildClassic() {
    final width = widget.width;
    final height = widget.height;
    final dragging = widget.dragging;
    final accent = AppBrandingService.instance.accentColor;
    final label = _productLabel;
    final onAccent =
        accent.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    return SizedBox(
      width: width,
      height: height + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 2,
            right: 2,
            top: 5,
            child: Container(
              height: height - 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: dragging ? 0.5 : 0.32),
                    blurRadius: dragging ? 18 : 12,
                    offset: Offset(0, dragging ? 8 : 5),
                  ),
                ],
              ),
            ),
          ),
          ClipPath(
            clipper: _SoftBubbleClipper(),
            child: Container(
              width: width,
              height: height + 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(accent, Colors.white, 0.22)!,
                    accent,
                    Color.lerp(accent, Colors.black, 0.18)!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: dragging ? 0.9 : 0.55),
                  width: dragging ? 1.5 : 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.4,
                          color: onAccent,
                          height: 1.05,
                          decoration: TextDecoration.none,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 8,
                        letterSpacing: 0.3,
                        color: onAccent.withValues(alpha: 0.92),
                        height: 1.05,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.unread > 0) _unreadBadge(futuristic: false),
        ],
      ),
    );
  }

  Widget _unreadBadge({required bool futuristic}) {
    final unread = widget.unread;
    return Positioned(
      right: -2,
      top: -4,
      child: Container(
        constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: futuristic
              ? CronosFuturisticTheme.neonMagenta
              : const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: futuristic ? CronosFuturisticTheme.neonCyan : Colors.white,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: (futuristic
                      ? CronosFuturisticTheme.neonMagenta
                      : Colors.black)
                  .withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          unread > 99 ? '99+' : '$unread',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            height: 1.4,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _SoftBubbleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final bodyH = h - 6;
    final r = bodyH / 2;

    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, bodyH),
          Radius.circular(r),
        ),
      )
      ..moveTo(w * 0.42, bodyH - 1)
      ..quadraticBezierTo(w * 0.48, h - 1, w * 0.56, h)
      ..quadraticBezierTo(w * 0.52, bodyH + 1, w * 0.58, bodyH - 1)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
