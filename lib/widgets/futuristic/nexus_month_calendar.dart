import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/date_formatters.dart';
import 'glowing_border_shell.dart';

/// Calendario mensile futuristico con numeri settimana ISO.
class NexusMonthCalendar extends StatefulWidget {
  const NexusMonthCalendar({
    super.key,
    required this.initialMonth,
    this.onClose,
  });

  final DateTime initialMonth;
  final VoidCallback? onClose;

  @override
  State<NexusMonthCalendar> createState() => _NexusMonthCalendarState();
}

class _NexusMonthCalendarState extends State<NexusMonthCalendar> {
  static const _months = <String>[
    'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
    'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
  ];

  late DateTime _visible;

  @override
  void initState() {
    super.initState();
    _visible = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visible = DateTime(_visible.year, _visible.month + delta);
    });
  }

  /// Numero settimana ISO 8601 per la riga (lunedì della settimana).
  int _isoWeek(DateTime date) => isoWeekNumber(date);

  List<({int week, List<DateTime> days})> _weekRows() {
    final first = DateTime(_visible.year, _visible.month, 1);
    var cursor = first.subtract(Duration(days: first.weekday - 1));
    final rows = <({int week, List<DateTime> days})>[];

    while (rows.length < 6) {
      final days = List<DateTime>.generate(
        7,
        (i) => cursor.add(Duration(days: i)),
      );
      cursor = cursor.add(const Duration(days: 7));
      if (days.any((d) => d.month == _visible.month)) {
        rows.add((week: _isoWeek(days.first), days: days));
      }
      if (cursor.month > _visible.month && cursor.day > 7) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final today = italyNow();
    final rows = _weekRows();
    const dayLabels = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

    return Material(
      color: Colors.transparent,
      child: GlowingBorderShell(
      color: CronosFuturisticTheme.borderGlow,
      strokeWidth: 2,
      borderRadius: 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CronosFuturisticTheme.voidBg.withValues(alpha: 0.72),
                  CronosFuturisticTheme.electricBlue.withValues(alpha: 0.14),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.chevron_left,
                        color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.8),
                        size: 22,
                      ),
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Expanded(
                      child: Text(
                        '${_months[_visible.month - 1]} ${_visible.year}',
                        textAlign: TextAlign.center,
                        style: CronosFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.chevron_right,
                        color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.8),
                        size: 22,
                      ),
                      onPressed: () => _shiftMonth(1),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        'SET',
                        textAlign: TextAlign.center,
                        style: CronosFonts.orbitron(
                          fontSize: 8,
                          letterSpacing: 0.5,
                          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    ...dayLabels.map(
                      (d) => Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: CronosFonts.exo2(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...rows.map((row) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            row.week.toString().padLeft(2, '0'),
                            textAlign: TextAlign.center,
                            style: CronosFonts.orbitron(
                              fontSize: 10,
                              color: CronosFuturisticTheme.neonCyan
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        ...row.days.map((day) {
                          final inMonth = day.month == _visible.month;
                          final isToday = day.year == today.year &&
                              day.month == today.month &&
                              day.day == today.day;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: isToday
                                    ? Border.all(
                                        color: CronosFuturisticTheme.borderGlow,
                                        width: 1.2,
                                      )
                                    : null,
                                color: isToday
                                    ? CronosFuturisticTheme.borderGlow
                                        .withValues(alpha: 0.12)
                                    : null,
                              ),
                              child: Text(
                                '${day.day}',
                                textAlign: TextAlign.center,
                                style: CronosFonts.exo2(
                                  fontSize: 11.5,
                                  fontWeight:
                                      isToday ? FontWeight.w700 : FontWeight.w400,
                                  color: inMonth
                                      ? (isToday
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.88))
                                      : Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Mostra il calendario sotto l'ancora (es. orologio HUD).
Future<void> showNexusMonthCalendar(
  BuildContext context,
  BuildContext anchor,
) async {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
  final left = offset.dx;
  final top = offset.dy + box.size.height + 8;
  final screen = overlay.size;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogCtx) {
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: math.min(left, screen.width - 375).clamp(8.0, screen.width),
              top: math.min(top, screen.height - 360).clamp(8.0, screen.height),
              child: Material(
                color: Colors.transparent,
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: NexusMonthCalendar(
                  initialMonth: italyNow(),
                  onClose: () => Navigator.of(dialogCtx).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
