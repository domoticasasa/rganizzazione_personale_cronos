import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mezzi_km_service.dart';

class MezziKmReminderService {
  MezziKmReminderService._();

  static final MezziKmReminderService instance = MezziKmReminderService._();
  static const List<_ReminderSlot> _slots = <_ReminderSlot>[
    _ReminderSlot(8, 0, '08:00'),
    _ReminderSlot(11, 50, '11:50'),
    _ReminderSlot(14, 0, '14:00'),
    _ReminderSlot(16, 30, '16:30'),
  ];

  final SupabaseClient _supa = Supabase.instance.client;
  Timer? _timer;
  int? _userId;
  bool _enabled = false;
  bool _runningTick = false;

  void configure({
    required bool enabledForUser,
    required int userId,
  }) {
    _enabled = enabledForUser;
    _userId = userId;
    _timer?.cancel();
    if (!_enabled) return;
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _enabled = false;
    _userId = null;
  }

  Future<void> _tick() async {
    if (!_enabled || _runningTick) return;
    final uid = _userId;
    if (uid == null || uid <= 0) return;
    final now = DateTime.now();
    final slot = _slotForNow(now);
    if (slot == null) return;
    _runningTick = true;
    try {
      if (!MezziKmService.shouldRequireMonthlyKm(now)) return;
      final prefs = await SharedPreferences.getInstance();
      final slotKey = _prefsSlotKey(now, slot.id);
      if (prefs.getBool(slotKey) == true) return;
      final pending =
          await MezziKmService.pendingAssignedMezziForCurrentMonth();
      if (pending.isEmpty) {
        await prefs.setBool(slotKey, true);
        return;
      }
      await _supa.from('notifications').insert({
        'user_id': uid,
        'title': 'Inserimento km mezzi richiesto',
        'message':
            'Promemoria ${slot.id}: inserisci i km mensili dei mezzi assegnati (${pending.length} in attesa).',
        'meta': {
          'action': 'mezzi_km_monthly_reminder_local',
          'slot': slot.id,
          'source': 'app_scheduler',
        },
        'is_read': false,
      });
      await prefs.setBool(slotKey, true);
    } catch (_) {
      // Non bloccare la sessione se un reminder fallisce.
    } finally {
      _runningTick = false;
    }
  }

  _ReminderSlot? _slotForNow(DateTime now) {
    for (final s in _slots) {
      if (now.hour == s.hour && now.minute == s.minute) return s;
    }
    return null;
  }

  String _prefsSlotKey(DateTime day, String slotId) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return 'mezzi_km_slot_sent_$y-$m-${d}_$slotId';
  }
}

class _ReminderSlot {
  final int hour;
  final int minute;
  final String id;
  const _ReminderSlot(this.hour, this.minute, this.id);
}
