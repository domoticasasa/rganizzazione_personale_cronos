import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/buoni_pasto_service.dart';
import '../services/supabase_service.dart';
import '../utils/buoni_pasto_qr_payload.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/personale_profile_resolver.dart';
import '../widgets/classic_app_bar_chrome.dart';

class DipendenteBuoniPastoRiepilogoPage extends StatefulWidget {
  final int userId;

  const DipendenteBuoniPastoRiepilogoPage({super.key, required this.userId});

  @override
  State<DipendenteBuoniPastoRiepilogoPage> createState() =>
      _DipendenteBuoniPastoRiepilogoPageState();
}

class _DipendenteBuoniPastoRiepilogoPageState
    extends State<DipendenteBuoniPastoRiepilogoPage> {
  final _supa = SupabaseService.client;
  static final _monthFmt = DateFormat('MMMM yyyy', 'it_IT');
  static const _weekdays = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];
  String? _personaleId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _load();
  }

  DateTime get _monthStart => DateTime(_month.year, _month.month, 1);

  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final personale = await resolveMyPersonaleRow();
      _personaleId = (personale?['id_uuid'] ?? '').toString();
      if (_personaleId != null && _personaleId!.isNotEmpty) {
        _rows = await BuoniPastoService.loadRegistrazioni(
          supa: _supa,
          personaleIdUuid: _personaleId,
          dal: _monthStart,
          al: _monthEnd,
        );
      } else {
        _rows = const [];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _selectedDay = null;
    });
    _load();
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, List<Map<String, dynamic>>> get _rowsByDate {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final key = (row['data_pasto'] ?? '').toString().substring(0, 10);
      out.putIfAbsent(key, () => []).add(row);
    }
    return out;
  }

  int get _pranzo => _rows.where((r) => r['tipo_pasto'] == 'pranzo').length;
  int get _cena => _rows.where((r) => r['tipo_pasto'] == 'cena').length;

  List<DateTime> get _calendarCells {
    final first = _monthStart;
    final last = _monthEnd;
    final startPad = first.weekday - 1;
    final cells = <DateTime>[];
    for (var i = 0; i < startPad; i++) {
      cells.add(first.subtract(Duration(days: startPad - i)));
    }
    for (var d = 1; d <= last.day; d++) {
      cells.add(DateTime(_month.year, _month.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(cells.last.add(const Duration(days: 1)));
    }
    return cells;
  }

  List<Map<String, dynamic>> _rowsForDay(DateTime day) {
    return _rowsByDate[_dateKey(day)] ?? const [];
  }

  String _formatMonthTitle(DateTime month) {
    final raw = _monthFmt.format(month);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final monthTitle = _formatMonthTitle(_monthStart);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const Text('I miei buoni pasto'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _personaleId == null || _personaleId!.isEmpty
              ? const Center(
                  child: Text('Profilo dipendente non collegato a questo account.'),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Mese precedente',
                            onPressed: _loading ? null : () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              monthTitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Mese successivo',
                            onPressed: _loading ? null : () => _shiftMonth(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _chip('Pranzo', _pranzo, Colors.orange.shade700),
                          const SizedBox(width: 8),
                          _chip('Cena', _cena, Colors.indigo.shade700),
                          const Spacer(),
                          Text('Totale: ${_rows.length}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _buildCalendar(),
                    ),
                    const Divider(height: 20),
                    Expanded(child: _buildDayDetails()),
                  ],
                ),
    );
  }

  Widget _buildCalendar() {
    final cells = _calendarCells;
    final today = DateTime.now();
    final todayKey = _dateKey(DateTime(today.year, today.month, today.day));

    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _dayCell(cells[row * 7 + col], todayKey)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime day, String todayKey) {
    final inMonth = day.month == _month.month;
    final key = _dateKey(day);
    final dayRows = _rowsForDay(day);
    final hasPranzo = dayRows.any((r) => r['tipo_pasto'] == 'pranzo');
    final hasCena = dayRows.any((r) => r['tipo_pasto'] == 'cena');
    final selected = _selectedDay != null && _dateKey(_selectedDay!) == key;
    final isToday = key == todayKey;

    return GestureDetector(
      onTap: inMonth
          ? () => setState(() => _selectedDay = DateTime(day.year, day.month, day.day))
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : (inMonth ? null : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : (selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300),
            width: isToday || selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: inMonth ? null : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasPranzo)
                  _mealDot('P', Colors.orange.shade700)
                else
                  const SizedBox(width: 14),
                if (hasCena) ...[
                  const SizedBox(width: 2),
                  _mealDot('C', Colors.indigo.shade700),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealDot(String label, Color color) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _buildDayDetails() {
    final day = _selectedDay;
    if (day == null) {
      return const Center(child: Text('Seleziona un giorno nel calendario.'));
    }
    final rows = _rowsForDay(day);
    final label =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';

    if (rows.isEmpty) {
      return Center(child: Text('Nessun buono pasto il $label.'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...rows.map(_mealTile),
      ],
    );
  }

  Widget _mealTile(Map<String, dynamic> row) {
    final structure = row['structures'];
    final nome =
        structure is Map ? (structure['name'] ?? '').toString() : 'Ristorante';
    final registrato =
        DateTime.tryParse((row['registrato_at'] ?? '').toString());
    final ora = registrato != null
        ? '${registrato.hour.toString().padLeft(2, '0')}:${registrato.minute.toString().padLeft(2, '0')}'
        : '';
    final tipo = tipoPastoLabel((row['tipo_pasto'] ?? '').toString());
    final tipoColor = (row['tipo_pasto'] ?? '') == 'cena'
        ? Colors.indigo.shade700
        : Colors.orange.shade700;
    final gps = mdoGpsCoordsFromRow(row);
    final gpsText = gps != null ? formatGpsCoordsText(gps.$1, gps.$2) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.restaurant_outlined, color: tipoColor),
        title: Text(nome.isEmpty ? 'Ristorante' : nome),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$ora · $tipo'),
            if (gpsText != null)
              Text(
                'GPS: $gpsText',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        isThreeLine: gpsText != null,
      ),
    );
  }

  Widget _chip(String label, int n, Color color) {
    return Chip(
      label: Text('$label: $n'),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
