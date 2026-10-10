import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assenza_richieste_pending_service.dart';
import 'security_incident_pending_service.dart';

typedef HubPollTick = Future<void> Function();

/// Polling hub condiviso: un solo timer per app, cache, pausa in background.
class HubPendingPollService with WidgetsBindingObserver {
  HubPendingPollService._();

  static final HubPendingPollService instance = HubPendingPollService._();

  static const Duration pollInterval = Duration(minutes: 5);

  final Set<HubPollTick> _listeners = <HubPollTick>{};
  Timer? _timer;
  int _consumers = 0;
  bool _foreground = true;

  int _assenzeCount = 0;
  DateTime? _assenzeFetchedAt;
  Future<int>? _assenzeInFlight;

  int _securityIncidentsCount = 0;
  DateTime? _securityIncidentsFetchedAt;
  Future<int>? _securityIncidentsInFlight;

  int? _dtUuidUserId;
  String? _dtUuid;
  final Map<String, _TrainAereoCache> _trainAereoByDt = <String, _TrainAereoCache>{};
  Future<int>? _trainAereoInFlight;
  String? _trainAereoInFlightKey;

  void attach(HubPollTick listener) {
    _listeners.add(listener);
    _consumers++;
    if (_consumers == 1) {
      WidgetsBinding.instance.addObserver(this);
      _startTimer();
    }
  }

  void detach(HubPollTick listener) {
    _listeners.remove(listener);
    if (_consumers > 0) _consumers--;
    if (_consumers == 0) {
      WidgetsBinding.instance.removeObserver(this);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_consumers > 0) {
      _startTimer();
      unawaited(refreshAllListeners(invalidateCache: true));
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_foreground || _consumers == 0) return;
    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(refreshAllListeners());
    });
  }

  Future<void> refreshAllListeners({bool invalidateCache = false}) async {
    if (invalidateCache) {
      invalidateAssenze();
      invalidateSecurityIncidents();
    }
    for (final listener in _listeners.toList()) {
      try {
        await listener();
      } catch (_) {}
    }
  }

  bool _cacheFresh(DateTime? at) {
    if (at == null) return false;
    return DateTime.now().difference(at) < pollInterval;
  }

  void invalidateAssenze() {
    _assenzeFetchedAt = null;
  }

  void invalidateSecurityIncidents() {
    _securityIncidentsFetchedAt = null;
  }

  void invalidateTrainAereo([String? dtUuid]) {
    if (dtUuid == null || dtUuid.isEmpty) {
      _trainAereoByDt.clear();
      return;
    }
    _trainAereoByDt.remove(dtUuid);
  }

  Future<int> assenzePendingCount(
    SupabaseClient client, {
    bool force = false,
  }) async {
    if (!force && _cacheFresh(_assenzeFetchedAt)) return _assenzeCount;
    if (_assenzeInFlight != null) return _assenzeInFlight!;
    _assenzeInFlight =
        AssenzaRichiestePendingService.countPendingAdminApproval(client);
    try {
      _assenzeCount = await _assenzeInFlight!;
      _assenzeFetchedAt = DateTime.now();
      return _assenzeCount;
    } finally {
      _assenzeInFlight = null;
    }
  }

  Future<int> securityIncidentsOpenCount(
    SupabaseClient client, {
    bool force = false,
  }) async {
    if (!force && _cacheFresh(_securityIncidentsFetchedAt)) {
      return _securityIncidentsCount;
    }
    if (_securityIncidentsInFlight != null) return _securityIncidentsInFlight!;
    _securityIncidentsInFlight =
        SecurityIncidentPendingService.countOpenForAdmin(client);
    try {
      _securityIncidentsCount = await _securityIncidentsInFlight!;
      _securityIncidentsFetchedAt = DateTime.now();
      return _securityIncidentsCount;
    } finally {
      _securityIncidentsInFlight = null;
    }
  }

  Future<int> trainAereoPendingCount(
    SupabaseClient client, {
    required int userId,
    bool force = false,
  }) async {
    final dtUuid = await _resolveDtUuid(client, userId);
    if (dtUuid == null || dtUuid.isEmpty) return 0;

    final cached = _trainAereoByDt[dtUuid];
    if (!force && cached != null && _cacheFresh(cached.at)) {
      return cached.count;
    }

    final inflightKey = dtUuid;
    if (_trainAereoInFlight != null && _trainAereoInFlightKey == inflightKey) {
      return _trainAereoInFlight!;
    }

    _trainAereoInFlightKey = inflightKey;
    _trainAereoInFlight = _fetchTrainAereoCount(client, dtUuid);
    try {
      final count = await _trainAereoInFlight!;
      _trainAereoByDt[dtUuid] = _TrainAereoCache(count: count, at: DateTime.now());
      return count;
    } finally {
      _trainAereoInFlight = null;
      _trainAereoInFlightKey = null;
    }
  }

  Future<String?> _resolveDtUuid(SupabaseClient client, int userId) async {
    if (_dtUuidUserId == userId && _dtUuid != null) return _dtUuid;
    try {
      final u = await client
          .from('users')
          .select('id_uuid')
          .eq('id', userId)
          .maybeSingle();
      _dtUuidUserId = userId;
      _dtUuid = (u?['id_uuid'] ?? '').toString().trim();
      if (_dtUuid!.isEmpty) _dtUuid = null;
      return _dtUuid;
    } catch (_) {
      return null;
    }
  }

  Future<int> _fetchTrainAereoCount(SupabaseClient client, String dtUuid) async {
    try {
      final tr = await client
          .from('bookings_treno')
          .count(CountOption.exact)
          .eq('workflow_status', 'INVIATA_AL_DT')
          .eq('assigned_dt_user_uuid', dtUuid);
      final ar = await client
          .from('bookings_aereo')
          .count(CountOption.exact)
          .eq('workflow_status', 'INVIATA_AL_DT')
          .eq('assigned_dt_user_uuid', dtUuid);
      return tr + ar;
    } catch (_) {
      return 0;
    }
  }
}

class _TrainAereoCache {
  const _TrainAereoCache({required this.count, required this.at});

  final int count;
  final DateTime at;
}
