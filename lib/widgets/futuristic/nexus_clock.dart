import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../utils/cronos_fonts.dart';

import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/date_formatters.dart';
import '../personal_agenda/personal_agenda_panel.dart';
import 'nexus_month_calendar.dart';

/// Orologio olografico: tap apre il calendario mensile Nexus.
class NexusClock extends StatefulWidget {
  const NexusClock({
    super.key,
    this.compact = false,
    this.verticalCompact = false,
  });

  /// Versione ridotta per AppBar: ora + data corta (es. «10:48 · Mer 22 Lug»).
  final bool compact;

  /// In modalità compact mostra ora sopra data (utile in sidebar chiusa).
  final bool verticalCompact;

  @override
  State<NexusClock> createState() => _NexusClockState();
}

class _NexusClockState extends State<NexusClock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.transientCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String _dateLabel() {
    const days = <String>[
      'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica',
    ];
    const months = <String>[
      'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
      'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
    ];
    final n = italyNow();
    return '${days[n.weekday - 1]} ${n.day} ${months[n.month - 1]} ${n.year}';
  }

  /// Data corta per AppBar (es. «Mer 22 Lug»).
  String _shortDateLabel() {
    const days = <String>[
      'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom',
    ];
    const months = <String>[
      'Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu',
      'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic',
    ];
    final n = italyNow();
    return '${days[n.weekday - 1]} ${n.day} ${months[n.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = italyNow();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final compact = widget.compact;
    final verticalCompact = compact && widget.verticalCompact;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = 0.35 + _pulse.value * 0.45;
        return Builder(
          builder: (btnCtx) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(compact ? 10 : 14),
              onTap: () => showNexusMonthCalendar(context, btnCtx),
              child: Tooltip(
                message: 'Calendario',
                child: ClipRRect(
                borderRadius: BorderRadius.circular(compact ? 10 : 14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: verticalCompact ? 4 : (compact ? 10 : 16),
                      vertical: compact ? 6 : 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CronosFuturisticTheme.electricBlue.withValues(alpha: 0.22),
                          CronosFuturisticTheme.voidBg.withValues(alpha: 0.65),
                        ],
                      ),
                      border: Border.all(
                        color: CronosFuturisticTheme.neonCyan.withValues(alpha: glow),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CronosFuturisticTheme.electricBright.withValues(
                            alpha: 0.25 + _pulse.value * 0.2,
                          ),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Safety net: in spazi stretti forza il layout verticale.
                        final verticalNow =
                            compact && (verticalCompact || c.maxWidth < 96);
                        if (verticalNow) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                h,
                                style: CronosFonts.orbitron(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                m,
                                style: CronosFonts.exo2(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white
                                      .withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compact)
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: CustomPaint(
                                  painter: _HudRingPainter(
                                    t: _pulse.value,
                                    seconds: now.second,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.schedule,
                                      size: 16,
                                      color: CronosFuturisticTheme.neonCyan
                                          .withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              )
                            else if (!verticalNow)
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: CronosFuturisticTheme.neonCyan
                                    .withValues(alpha: 0.85),
                              ),
                            if (!verticalNow)
                              SizedBox(width: compact ? 6 : 12),
                            if (compact)
                              (verticalNow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          h,
                                          style: CronosFonts.orbitron(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          m,
                                          style: CronosFonts.exo2(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white
                                                .withValues(alpha: 0.88),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$h:$m',
                                          style: CronosFonts.orbitron(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Container(
                                            width: 1,
                                            height: 12,
                                            color: Colors.white
                                                .withValues(alpha: 0.28),
                                          ),
                                        ),
                                        Text(
                                          _shortDateLabel(),
                                          style: CronosFonts.exo2(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white
                                                .withValues(alpha: 0.88),
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ))
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '$h:$m',
                                        style: CronosFonts.orbitron(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 2,
                                          shadows: [
                                            Shadow(
                                              color: CronosFuturisticTheme
                                                  .neonCyan
                                                  .withValues(alpha: glow),
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        ':$s',
                                        style: CronosFonts.orbitron(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: CronosFuturisticTheme.neonCyan
                                              .withValues(
                                            alpha: 0.55 + _pulse.value * 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dateLabel(),
                                    style: CronosFonts.exo2(
                                      fontSize: 9,
                                      color: Colors.white54,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudRingPainter extends CustomPainter {
  _HudRingPainter({required this.t, required this.seconds});

  final double t;
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 2;

    final track = Paint()
      ..color = CronosFuturisticTheme.electricBlue.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r, track);

    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          CronosFuturisticTheme.neonCyan,
          CronosFuturisticTheme.electricBright,
          CronosFuturisticTheme.neonCyan.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final angle = (seconds / 60.0) * math.pi * 2 - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      angle,
      math.pi * 0.55 + t * 0.3,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _HudRingPainter old) =>
      old.t != t || old.seconds != seconds;
}

/// Piccolo pill «Agenda» nello stesso stile dell’orologio HUD.
class NexusAgendaPill extends StatelessWidget {
  const NexusAgendaPill({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnCtx) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          onTap: () => showPersonalAgenda(context, btnCtx),
          child: Tooltip(
            message: 'Agenda',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 10 : 14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        CronosFuturisticTheme.electricBlue
                            .withValues(alpha: 0.22),
                        CronosFuturisticTheme.voidBg.withValues(alpha: 0.65),
                      ],
                    ),
                    border: Border.all(
                      color: CronosFuturisticTheme.neonCyan
                          .withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CronosFuturisticTheme.electricBright
                            .withValues(alpha: 0.28),
                        blurRadius: 14,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.view_agenda_outlined,
                        size: compact ? 13 : 15,
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Agenda',
                        style: CronosFonts.exo2(
                          fontSize: compact ? 11.5 : 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

