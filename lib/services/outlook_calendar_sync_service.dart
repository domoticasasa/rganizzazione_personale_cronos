import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'personal_agenda_service.dart';
import 'supabase_service.dart';

/// Sync bidirezionale automatica agenda CRONOS ↔ Microsoft Outlook (Graph).
class OutlookCalendarSyncService extends ChangeNotifier {
  OutlookCalendarSyncService._();
  static final OutlookCalendarSyncService instance =
      OutlookCalendarSyncService._();

  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _authBase = 'https://login.microsoftonline.com';
  static const _scopes = 'openid offline_access User.Read Calendars.ReadWrite';
  static const _pkceStorageKey = 'outlook_oauth_pkce_verifier';
  static const _stateStorageKey = 'outlook_oauth_state';

  /// Client ID Azure (SPA). Vuoto = feature disabilitata.
  static const clientId = String.fromEnvironment(
    'MS_GRAPH_CLIENT_ID',
    defaultValue: '',
  );

  /// Tenant: `organizations` (lavoro/scuola) di default.
  static const tenant = String.fromEnvironment(
    'MS_GRAPH_TENANT',
    defaultValue: 'organizations',
  );

  static bool get isConfigured => clientId.trim().isNotEmpty;

  SupabaseClient get _client => SupabaseService.client;

  Timer? _autoTimer;
  bool _syncing = false;
  bool _connected = false;
  String? _displayLabel;
  String? _lastError;
  DateTime? _lastSyncAt;

  bool get isSyncing => _syncing;
  bool get isConnected => _connected;
  String? get displayLabel => _displayLabel;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;

  String get redirectUri {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/auth/outlook/callback';
    }
    return 'https://www.gestopro360.it/auth/outlook/callback';
  }

  Future<void> init() async {
    await refreshConnectionState();
    _restartAutoTimer();
  }

  void stopAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _connected = false;
    _displayLabel = null;
    _lastSyncAt = null;
    notifyListeners();
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    if (!_connected) return;
    _autoTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncNow(silent: true));
    });
  }

  Future<void> refreshConnectionState() async {
    try {
      final uid = await PersonalAgendaService.instance.currentUserId();
      if (uid == null) {
        _connected = false;
        _displayLabel = null;
        notifyListeners();
        return;
      }
      final row = await _client
          .from('user_outlook_connections')
          .select('graph_display_name, graph_email, last_sync_at')
          .eq('user_id', uid)
          .maybeSingle();
      _connected = row != null;
      if (row != null) {
        final name = (row['graph_display_name'] ?? '').toString().trim();
        final email = (row['graph_email'] ?? '').toString().trim();
        _displayLabel = name.isNotEmpty
            ? name
            : (email.isNotEmpty ? email : 'Outlook collegato');
        _lastSyncAt = DateTime.tryParse((row['last_sync_at'] ?? '').toString())
            ?.toLocal();
      } else {
        _displayLabel = null;
        _lastSyncAt = null;
      }
      notifyListeners();
      _restartAutoTimer();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('OutlookCalendarSyncService.refreshConnectionState: $e');
      }
    }
  }

  Future<void> startConnect() async {
    if (!isConfigured) {
      _lastError =
          'Sync Outlook non attiva: manca la configurazione IT '
          '(MS_GRAPH_CLIENT_ID). Con account aziendale non serve registrarsi: '
          'chiedi all’amministratore di abilitare Outlook una sola volta. '
          'Vedi deploy/outlook-sync/README.md';
      notifyListeners();
      throw Exception(_lastError);
    }
    final verifier = _randomUrlSafe(64);
    final challenge = _codeChallenge(verifier);
    final state = _randomUrlSafe(24);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pkceStorageKey, verifier);
    await prefs.setString(_stateStorageKey, state);

    final authUri = Uri.parse('$_authBase/$tenant/oauth2/v2.0/authorize')
        .replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_mode': 'query',
      'scope': _scopes,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });

    final ok = await launchUrl(
      authUri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    if (!ok) {
      throw Exception('Impossibile aprire il login Microsoft');
    }
  }

  /// Completa OAuth dopo redirect su `/auth/outlook/callback?code=…&state=…`.
  Future<void> completeOAuthFromUri(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final err = uri.queryParameters['error_description'] ??
        uri.queryParameters['error'];
    if (err != null && err.isNotEmpty) {
      throw Exception(err);
    }
    if (code == null || code.isEmpty) {
      throw Exception('Codice OAuth mancante');
    }
    final prefs = await SharedPreferences.getInstance();
    final expectedState = prefs.getString(_stateStorageKey);
    final verifier = prefs.getString(_pkceStorageKey);
    if (expectedState == null ||
        verifier == null ||
        state == null ||
        state != expectedState) {
      throw Exception('Stato OAuth non valido (riprova Collega Outlook)');
    }

    final tokenRes = await http.post(
      Uri.parse('$_authBase/$tenant/oauth2/v2.0/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
        'scope': _scopes,
      },
    );
    if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
      throw Exception('Token Outlook fallito: ${tokenRes.body}');
    }
    final tokenJson = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    final access = (tokenJson['access_token'] ?? '').toString();
    final refresh = (tokenJson['refresh_token'] ?? '').toString();
    final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;
    if (access.isEmpty || refresh.isEmpty) {
      throw Exception('Token Outlook incompleto');
    }

    final me = await http.get(
      Uri.parse('$_graphBase/me'),
      headers: {'Authorization': 'Bearer $access'},
    );
    String? graphId;
    String? displayName;
    String? email;
    if (me.statusCode >= 200 && me.statusCode < 300) {
      final m = jsonDecode(me.body) as Map<String, dynamic>;
      graphId = (m['id'] ?? '').toString();
      displayName = (m['displayName'] ?? '').toString();
      email = (m['mail'] ?? m['userPrincipalName'] ?? '').toString();
    }

    final uid = await PersonalAgendaService.instance.currentUserId();
    if (uid == null) throw Exception('Utente non autenticato');

    await _client.from('user_outlook_connections').upsert({
      'user_id': uid,
      'access_token': access,
      'refresh_token': refresh,
      'token_expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn - 60))
          .toIso8601String(),
      'graph_user_id': graphId,
      'graph_display_name': displayName,
      'graph_email': email,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    await prefs.remove(_pkceStorageKey);
    await prefs.remove(_stateStorageKey);
    await refreshConnectionState();
    await syncNow();
  }

  Future<void> disconnect() async {
    final uid = await PersonalAgendaService.instance.currentUserId();
    if (uid != null) {
      await _client
          .from('user_outlook_connections')
          .delete()
          .eq('user_id', uid);
    }
    _connected = false;
    _displayLabel = null;
    _lastSyncAt = null;
    notifyListeners();
    _restartAutoTimer();
  }

  Future<String> _validAccessToken() async {
    final uid = await PersonalAgendaService.instance.currentUserId();
    if (uid == null) throw Exception('Utente non autenticato');
    final row = await _client
        .from('user_outlook_connections')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) throw Exception('Outlook non collegato');

    final expires =
        DateTime.tryParse((row['token_expires_at'] ?? '').toString())?.toUtc();
    var access = (row['access_token'] ?? '').toString();
    final refresh = (row['refresh_token'] ?? '').toString();
    if (expires != null &&
        expires.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)))) {
      return access;
    }

    final tokenRes = await http.post(
      Uri.parse('$_authBase/$tenant/oauth2/v2.0/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'scope': _scopes,
      },
    );
    if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
      throw Exception('Refresh token Outlook fallito');
    }
    final tokenJson = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    access = (tokenJson['access_token'] ?? '').toString();
    final newRefresh =
        (tokenJson['refresh_token'] ?? refresh).toString();
    final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;
    await _client.from('user_outlook_connections').update({
      'access_token': access,
      'refresh_token': newRefresh,
      'token_expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn - 60))
          .toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
    return access;
  }

  Future<void> syncNow({bool silent = false}) async {
    if (!isConfigured || _syncing) return;
    final uid = await PersonalAgendaService.instance.currentUserId();
    if (uid == null) return;

    final conn = await _client
        .from('user_outlook_connections')
        .select('user_id')
        .eq('user_id', uid)
        .maybeSingle();
    if (conn == null) return;

    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final token = await _validAccessToken();
      await _pullFromOutlook(uid, token);
      await _pushToOutlook(uid, token);
      final now = DateTime.now().toUtc();
      await _client.from('user_outlook_connections').update({
        'last_sync_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('user_id', uid);
      _lastSyncAt = now.toLocal();
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print('OutlookCalendarSyncService.syncNow: $e');
      }
      if (!silent) rethrow;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Push immediato di una singola voce (dopo CRUD locale).
  Future<void> pushEntry(AgendaEntry entry) async {
    if (!_connected || !isConfigured) return;
    if (!_shouldSyncKind(entry)) return;
    try {
      final uid = await PersonalAgendaService.instance.currentUserId();
      if (uid == null) return;
      final token = await _validAccessToken();
      await _upsertGraphEvent(uid, token, entry);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('OutlookCalendarSyncService.pushEntry: $e');
      }
    }
  }

  Future<void> deleteRemoteForEntry(AgendaEntry entry) async {
    final outlookId = entry.outlookEventId;
    if (outlookId == null || outlookId.isEmpty) return;
    if (!_connected || !isConfigured) return;
    try {
      final token = await _validAccessToken();
      await http.delete(
        Uri.parse('$_graphBase/me/events/$outlookId'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('OutlookCalendarSyncService.deleteRemoteForEntry: $e');
      }
    }
  }

  bool _shouldSyncKind(AgendaEntry e) {
    if (e.startsAt == null) return false;
    return e.kind == AgendaEntryKind.event || e.kind == AgendaEntryKind.reminder;
  }

  Future<void> _pullFromOutlook(int uid, String token) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(const Duration(days: 90));
    final to = now.add(const Duration(days: 90));
    final filter =
        "start/dateTime ge '${from.toIso8601String()}' and start/dateTime lt '${to.toIso8601String()}'";
    var url = Uri.parse('$_graphBase/me/calendarView').replace(queryParameters: {
      'startDateTime': from.toIso8601String(),
      'endDateTime': to.toIso8601String(),
      r'$select':
          'id,subject,bodyPreview,location,isAllDay,start,end,lastModifiedDateTime,'
              'isReminderOn,reminderMinutesBeforeStart,changeKey',
      r'$orderby': 'start/dateTime',
      r'$top': '200',
    });
    // Prefer calendarView (handles recurrence instances).
    final seenIds = <String>{};

    while (true) {
      final res = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Prefer': 'outlook.timezone="Europe/Rome"',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Fallback events list with filter.
        final alt = await http.get(
          Uri.parse('$_graphBase/me/events').replace(queryParameters: {
            r'$filter': filter,
            r'$select':
                'id,subject,bodyPreview,location,isAllDay,start,end,lastModifiedDateTime,'
                    'isReminderOn,reminderMinutesBeforeStart,changeKey',
            r'$top': '200',
          }),
          headers: {
            'Authorization': 'Bearer $token',
            'Prefer': 'outlook.timezone="Europe/Rome"',
          },
        );
        if (alt.statusCode < 200 || alt.statusCode >= 300) {
          throw Exception('Lettura Outlook fallita: ${res.body}');
        }
        await _ingestGraphList(uid, jsonDecode(alt.body) as Map<String, dynamic>, seenIds);
        break;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await _ingestGraphList(uid, body, seenIds);
      final next = (body['@odata.nextLink'] ?? '').toString();
      if (next.isEmpty) break;
      url = Uri.parse(next);
    }

    // Elimina locali mappati Outlook non più presenti nella finestra.
    final local = await PersonalAgendaService.instance.listBetween(
      from: from.toLocal(),
      to: to.toLocal(),
    );
    for (final e in local) {
      final oid = e.outlookEventId;
      if (oid == null || oid.isEmpty) continue;
      if (e.syncOrigin != 'outlook' && e.syncOrigin != 'cronos') continue;
      if (!seenIds.contains(oid) && e.syncOrigin == 'outlook') {
        await PersonalAgendaService.instance.delete(e.id, syncRemote: false);
      }
    }
  }

  Future<void> _ingestGraphList(
    int uid,
    Map<String, dynamic> body,
    Set<String> seenIds,
  ) async {
    final values = (body['value'] as List?) ?? const [];
    for (final raw in values) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      seenIds.add(id);
      final start = _parseGraphDate(m['start']);
      final end = _parseGraphDate(m['end']);
      final lastMod =
          DateTime.tryParse((m['lastModifiedDateTime'] ?? '').toString())
              ?.toUtc();
      final reminderOn = m['isReminderOn'] == true;
      final reminderMin =
          (m['reminderMinutesBeforeStart'] as num?)?.toInt();
      final loc = m['location'];
      final location = loc is Map
          ? (loc['displayName'] ?? '').toString()
          : '';
      final draft = AgendaEntry(
        id: '',
        userId: uid,
        kind: AgendaEntryKind.event,
        title: ((m['subject'] ?? 'Evento Outlook').toString().trim().isEmpty)
            ? 'Evento Outlook'
            : m['subject'].toString().trim(),
        body: (m['bodyPreview'] ?? '').toString(),
        location: location,
        allDay: m['isAllDay'] == true,
        startsAt: start?.toLocal(),
        endsAt: end?.toLocal(),
        reminderEnabled: reminderOn,
        reminderMinutesBefore: reminderOn ? (reminderMin ?? 15) : null,
        outlookEventId: id,
        outlookEtag: (m['changeKey'] ?? '').toString(),
        outlookLastModified: lastMod?.toLocal(),
        syncOrigin: 'outlook',
      );
      await PersonalAgendaService.instance.upsertFromOutlook(draft);
    }
  }

  Future<void> _pushToOutlook(int uid, String token) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 90));
    final to = now.add(const Duration(days: 90));
    final local = await PersonalAgendaService.instance.listBetween(
      from: from,
      to: to,
    );
    for (final e in local) {
      if (!_shouldSyncKind(e)) continue;
      await _upsertGraphEvent(uid, token, e);
    }
  }

  Future<void> _upsertGraphEvent(int uid, String token, AgendaEntry entry) async {
    if (!_shouldSyncKind(entry)) return;
    final payload = _toGraphEvent(entry);
    final existingId = entry.outlookEventId;

    if (existingId != null && existingId.isNotEmpty) {
      // Conflitto: se Outlook è più recente, skip push.
      if (entry.outlookLastModified != null &&
          entry.updatedAt != null &&
          entry.outlookLastModified!
              .isAfter(entry.updatedAt!.add(const Duration(seconds: 2)))) {
        return;
      }
      final res = await http.patch(
        Uri.parse('$_graphBase/me/events/$existingId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        await PersonalAgendaService.instance.attachOutlookIds(
          entryId: entry.id,
          outlookEventId: (m['id'] ?? existingId).toString(),
          etag: (m['changeKey'] ?? '').toString(),
          lastModified:
              DateTime.tryParse((m['lastModifiedDateTime'] ?? '').toString()),
        );
      }
      return;
    }

    final res = await http.post(
      Uri.parse('$_graphBase/me/events'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      await PersonalAgendaService.instance.attachOutlookIds(
        entryId: entry.id,
        outlookEventId: (m['id'] ?? '').toString(),
        etag: (m['changeKey'] ?? '').toString(),
        lastModified:
            DateTime.tryParse((m['lastModifiedDateTime'] ?? '').toString()),
      );
    }
  }

  Map<String, dynamic> _toGraphEvent(AgendaEntry e) {
    final start = e.startsAt!.toUtc();
    final end = (e.endsAt ?? e.startsAt!.add(const Duration(hours: 1))).toUtc();
    return {
      'subject': e.title,
      'body': {
        'contentType': 'text',
        'content': e.body,
      },
      'location': {'displayName': e.location},
      'isAllDay': e.allDay,
      'start': {
        'dateTime': start.toIso8601String().replaceFirst('Z', ''),
        'timeZone': 'UTC',
      },
      'end': {
        'dateTime': end.toIso8601String().replaceFirst('Z', ''),
        'timeZone': 'UTC',
      },
      'isReminderOn': e.reminderEnabled,
      if (e.reminderEnabled)
        'reminderMinutesBeforeStart': e.reminderMinutesBefore ?? 15,
    };
  }

  DateTime? _parseGraphDate(dynamic raw) {
    if (raw is! Map) return null;
    final dt = (raw['dateTime'] ?? '').toString();
    if (dt.isEmpty) return null;
    // Graph often returns without Z; treat as local of timeZone or UTC.
    final parsed = DateTime.tryParse(dt.endsWith('Z') ? dt : '${dt}Z');
    return parsed?.toUtc();
  }

  String _randomUrlSafe(int bytes) {
    final r = math.Random.secure();
    final list = List<int>.generate(bytes, (_) => r.nextInt(256));
    return base64UrlEncode(list).replaceAll('=', '');
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
