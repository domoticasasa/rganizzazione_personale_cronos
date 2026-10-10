import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/roles.dart';
import '../utils/users_directory.dart';
import 'app_chat_alerts.dart';
import 'app_chat_overlay_controller.dart';
import 'supabase_service.dart';

class AppChatMessage {
  AppChatMessage({
    required this.id,
    required this.senderUserId,
    required this.senderAuthId,
    required this.senderName,
    required this.recipientUserId,
    required this.recipientAuthId,
    required this.recipientName,
    required this.body,
    required this.replyToId,
    required this.attachmentPath,
    required this.attachmentName,
    required this.attachmentMime,
    required this.attachmentSize,
    required this.createdAt,
    required this.deletedAt,
    this.groupId,
    this.replyPreview,
  });

  final String id;
  final int senderUserId;
  final String senderAuthId;
  final String senderName;
  final int? recipientUserId;
  final String? recipientAuthId;
  final String? recipientName;
  final String? groupId;
  final String? body;
  final String? replyToId;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMime;
  final int? attachmentSize;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final AppChatMessage? replyPreview;

  bool get isDeleted => deletedAt != null;

  bool get isDirect =>
      recipientUserId != null || (recipientAuthId ?? '').isNotEmpty;

  bool get isGroup => !isDirect && (groupId ?? '').isNotEmpty;

  bool get hasAttachment =>
      !isDeleted && (attachmentPath ?? '').trim().isNotEmpty;

  bool get isImage {
    final mime = (attachmentMime ?? '').toLowerCase();
    final name = (attachmentName ?? '').toLowerCase();
    return mime.startsWith('image/') ||
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif');
  }

  factory AppChatMessage.fromMap(
    Map<String, dynamic> m, {
    AppChatMessage? replyPreview,
  }) {
    final created = parseSupabaseTimestampToUtc(m['created_at']) ??
        DateTime.now().toUtc();
    final deleted = parseSupabaseTimestampToUtc(m['deleted_at']);
    int? asInt(dynamic v) => (v as num?)?.toInt();
    String? asNonEmpty(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return AppChatMessage(
      id: (m['id'] ?? '').toString(),
      senderUserId: asInt(m['sender_user_id']) ?? 0,
      senderAuthId: (m['sender_auth_id'] ?? '').toString(),
      senderName: asNonEmpty(m['sender_name']) ?? 'Utente',
      recipientUserId: asInt(m['recipient_user_id']),
      recipientAuthId: asNonEmpty(m['recipient_auth_id']),
      recipientName: asNonEmpty(m['recipient_name']),
      groupId: asNonEmpty(m['group_id']),
      body: deleted != null ? null : asNonEmpty(m['body']),
      replyToId: asNonEmpty(m['reply_to_id']),
      attachmentPath: deleted != null ? null : asNonEmpty(m['attachment_path']),
      attachmentName: deleted != null ? null : asNonEmpty(m['attachment_name']),
      attachmentMime: deleted != null ? null : asNonEmpty(m['attachment_mime']),
      attachmentSize: deleted != null ? null : asInt(m['attachment_size']),
      createdAt: created,
      deletedAt: deleted,
      replyPreview: replyPreview,
    );
  }
}

class AppChatPeer {
  const AppChatPeer({
    required this.userId,
    required this.authId,
    required this.displayName,
  });

  final int userId;
  final String authId;
  final String displayName;
}

/// Hint presenza/foto per avatar chat (RPC [app_chat_peer_presence_hints]).
class AppChatPresenceHint {
  const AppChatPresenceHint({
    required this.authId,
    this.fotoPath,
    this.lastAppOpenAt,
  });

  final String authId;
  final String? fotoPath;
  final DateTime? lastAppOpenAt;

  /// Online se ha aperto l'app negli ultimi [onlineWindow].
  bool isOnline({
    Duration onlineWindow = const Duration(minutes: 2),
    DateTime? now,
  }) {
    final at = lastAppOpenAt;
    if (at == null) return false;
    final n = now ?? DateTime.now().toUtc();
    final age = n.difference(at.toUtc());
    return !age.isNegative && age <= onlineWindow;
  }
}

/// Utente che ha aperto/letto la chat di gruppo (cursore last_read_at).
class AppChatGroupReader {
  const AppChatGroupReader({
    required this.userId,
    required this.authId,
    required this.displayName,
    required this.lastReadAt,
  });

  final int userId;
  final String authId;
  final String displayName;
  final DateTime lastReadAt;
}

class AppChatGroup {
  const AppChatGroup({
    required this.id,
    required this.name,
    this.description,
    this.memberCount = 0,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final String? description;
  final int memberCount;
  final bool isArchived;

  factory AppChatGroup.fromMap(Map<String, dynamic> m) {
    return AppChatGroup(
      id: (m['id'] ?? '').toString(),
      name: ((m['name'] ?? '') as Object).toString().trim().isEmpty
          ? 'Gruppo'
          : (m['name'] ?? '').toString().trim(),
      description: () {
        final s = (m['description'] ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }(),
      memberCount: (m['member_count'] as num?)?.toInt() ?? 0,
      isArchived: m['is_archived'] == true,
    );
  }
}

class AppChatAttachmentBytes {
  const AppChatAttachmentBytes({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

const _selectCols =
    'id, sender_user_id, sender_auth_id, sender_name, '
    'recipient_user_id, recipient_auth_id, recipient_name, group_id, body, '
    'reply_to_id, attachment_path, attachment_name, attachment_mime, '
    'attachment_size, created_at, deleted_at';

/// Chat di gruppo + messaggi privati (ultimi 7 giorni).
class AppChatService {
  AppChatService._();

  static final AppChatService instance = AppChatService._();

  static const String bucket = 'chat_allegati';
  static const Duration retention = Duration(days: 7);
  static const int maxAttachmentBytes = 50 * 1024 * 1024;

  final _controller = StreamController<List<AppChatMessage>>.broadcast();
  final List<AppChatMessage> _messages = <AppChatMessage>[];
  RealtimeChannel? _channel;
  bool _listening = false;
  String? _myAuthId;
  int? _myUserId;

  /// peer_auth_id → quando il peer ha letto la chat con me (ricevute «Letto»).
  final ValueNotifier<Map<String, DateTime>> dmPeerLastReadByAuth =
      ValueNotifier<Map<String, DateTime>>(const {});

  /// peer_auth_id -> count DM non letti ricevuti da quel peer.
  final ValueNotifier<Map<String, int>> dmUnreadByPeerAuth =
      ValueNotifier<Map<String, int>>(const {});

  /// Ricevute lettura gruppo (last_read_at per utente del gruppo attivo).
  final ValueNotifier<List<AppChatGroupReader>> groupReadStates =
      ValueNotifier<List<AppChatGroupReader>>(const []);

  /// Gruppi a cui appartengo (o tutti se admin).
  final ValueNotifier<List<AppChatGroup>> myGroups =
      ValueNotifier<List<AppChatGroup>>(const []);

  /// Cache presenza/foto per auth_id (avatar + online in chat).
  final ValueNotifier<Map<String, AppChatPresenceHint>> presenceByAuth =
      ValueNotifier<Map<String, AppChatPresenceHint>>(const {});

  Timer? _groupReadRefreshDebounce;
  String? _activeGroupIdForReceipts;
  DateTime? _lastPresenceFetchAt;

  Stream<List<AppChatMessage>> get messagesStream => _controller.stream;
  List<AppChatMessage> get currentMessages =>
      List<AppChatMessage>.unmodifiable(_messages);

  DateTime get _cutoffUtc => DateTime.now().toUtc().subtract(retention);

  Future<void> start() async {
    final auth = Supabase.instance.client.auth.currentUser;
    _myAuthId = auth?.id;
    await _resolveMyUserId();
    await refreshMyGroups();
    await refresh();
    await _ensureRealtime();
    await refreshUnreadBadge();
  }

  Future<void> _resolveMyUserId() async {
    final authId = _myAuthId;
    if (authId == null || authId.isEmpty) {
      _myUserId = null;
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('users')
          .select('id')
          .or('auth_id.eq.$authId,id_uuid.eq.$authId')
          .maybeSingle();
      _myUserId = (row?['id'] as num?)?.toInt();
    } catch (_) {
      _myUserId = null;
    }
  }

  Future<void> refreshUnreadBadge() async {
    unawaited(refreshDmUnreadByPeer());
    try {
      final raw =
          await SupabaseService.client.rpc('app_chat_unread_breakdown');
      Map<String, dynamic>? map;
      if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().startsWith('{')) {
        // PostgREST a volte serializza jsonb come stringa.
        final g = RegExp(r'"group"\s*:\s*(\d+)').firstMatch(raw);
        final d = RegExp(r'"dm"\s*:\s*(\d+)').firstMatch(raw);
        map = {
          'group': int.tryParse(g?.group(1) ?? '') ?? 0,
          'dm': int.tryParse(d?.group(1) ?? '') ?? 0,
        };
      }
      if (map != null) {
        final groupRaw = map['group'];
        final dmRaw = map['dm'];
        final group = groupRaw is int
            ? groupRaw
            : int.tryParse(groupRaw?.toString() ?? '') ?? 0;
        final dm = dmRaw is int
            ? dmRaw
            : int.tryParse(dmRaw?.toString() ?? '') ?? 0;
        AppChatOverlayController.setUnreadBreakdown(group: group, dm: dm);
        return;
      }
    } catch (_) {}
    // Fallback: solo totale (schema senza breakdown).
    if (AppChatOverlayController.isOpen.value) {
      AppChatOverlayController.setUnreadCount(0);
      return;
    }
    try {
      final raw = await SupabaseService.client.rpc('app_chat_unread_count');
      final n = raw is int
          ? raw
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      AppChatOverlayController.setUnreadCount(n);
    } catch (_) {}
  }

  Future<void> refreshDmUnreadByPeer() async {
    try {
      final raw = await SupabaseService.client.rpc('app_chat_dm_unread_by_peer');
      final next = <String, int>{};
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final row = Map<String, dynamic>.from(item);
          final auth = (row['peer_auth_id'] ?? '').toString().trim();
          if (auth.isEmpty) continue;
          final countRaw = row['unread_count'];
          final count = countRaw is int
              ? countRaw
              : int.tryParse(countRaw?.toString() ?? '') ?? 0;
          if (count > 0) next[auth] = count;
        }
      }
      dmUnreadByPeerAuth.value = next;
    } catch (_) {
      dmUnreadByPeerAuth.value = const {};
    }
  }

  int dmUnreadCountForPeer(AppChatPeer peer) =>
      dmUnreadByPeerAuth.value[peer.authId] ?? 0;

  Future<void> stop() async {
    _groupReadRefreshDebounce?.cancel();
    _groupReadRefreshDebounce = null;
    dmUnreadByPeerAuth.value = const {};
    presenceByAuth.value = const {};
    _lastPresenceFetchAt = null;
    final ch = _channel;
    _channel = null;
    _listening = false;
    if (ch != null) {
      try {
        await SupabaseService.client.removeChannel(ch);
      } catch (_) {}
    }
  }

  AppChatPresenceHint? presenceHintFor(String? authId) {
    final id = (authId ?? '').trim();
    if (id.isEmpty) return null;
    return presenceByAuth.value[id];
  }

  /// Carica/aggiorna foto + last_app_open_at per gli [authIds] mancanti o forzati.
  Future<void> ensurePresenceHints(
    Iterable<String> authIds, {
    bool force = false,
  }) async {
    final ids = <String>{};
    for (final raw in authIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;

    final now = DateTime.now().toUtc();
    final last = _lastPresenceFetchAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 45) &&
        ids.every((id) => presenceByAuth.value.containsKey(id))) {
      return;
    }

    final missing = force
        ? ids
        : ids.where((id) => !presenceByAuth.value.containsKey(id)).toSet();
    if (missing.isEmpty && !force) return;

    final fetchIds = force ? ids : missing;
    try {
      final raw = await SupabaseService.client.rpc(
        'app_chat_peer_presence_hints',
        params: {'p_auth_ids': fetchIds.toList(growable: false)},
      );
      final next = Map<String, AppChatPresenceHint>.from(presenceByAuth.value);
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final auth = (item['auth_id'] ?? '').toString().trim();
          if (auth.isEmpty) continue;
          final foto = (item['foto_tesserino_path'] ?? '').toString().trim();
          final lastOpen = parseSupabaseTimestampToUtc(item['last_app_open_at']);
          next[auth] = AppChatPresenceHint(
            authId: auth,
            fotoPath: foto.isEmpty ? null : foto,
            lastAppOpenAt: lastOpen,
          );
        }
      }
      for (final id in fetchIds) {
        next.putIfAbsent(
          id,
          () => AppChatPresenceHint(authId: id),
        );
      }
      presenceByAuth.value = next;
      _lastPresenceFetchAt = now;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.ensurePresenceHints: $e');
    }
  }

  List<AppChatMessage> groupMessages([String? groupId]) {
    final gid = (groupId ?? '').trim();
    return _messages.where((m) {
      if (m.isDirect) return false;
      if (gid.isEmpty) return true;
      return m.groupId == gid;
    }).toList(growable: false);
  }

  List<AppChatMessage> directMessagesWith(AppChatPeer peer) {
    final myAuth = _myAuthId ?? '';
    return _messages.where((m) {
      if (!m.isDirect) return false;
      final a = m.senderAuthId;
      final b = m.recipientAuthId ?? '';
      return (a == myAuth && b == peer.authId) ||
          (a == peer.authId && b == myAuth) ||
          (m.senderUserId == peer.userId && m.recipientUserId == _myUserId) ||
          (m.senderUserId == _myUserId && m.recipientUserId == peer.userId);
    }).toList(growable: false);
  }

  /// Contatti con cui hai già scambiato messaggi privati.
  List<AppChatPeer> recentDirectPeers() {
    final myAuth = _myAuthId ?? '';
    final myId = _myUserId;
    final byKey = <String, AppChatPeer>{};
    final lastAt = <String, DateTime>{};

    for (final m in _messages) {
      if (!m.isDirect) continue;
      final iAmSender = m.senderAuthId == myAuth ||
          (myId != null && m.senderUserId == myId);
      late final AppChatPeer peer;
      if (iAmSender) {
        final auth = (m.recipientAuthId ?? '').trim();
        final uid = m.recipientUserId ?? 0;
        if (auth.isEmpty || uid <= 0) continue;
        peer = AppChatPeer(
          userId: uid,
          authId: auth,
          displayName: (m.recipientName ?? '').trim().isEmpty
              ? 'Utente'
              : m.recipientName!.trim(),
        );
      } else {
        peer = AppChatPeer(
          userId: m.senderUserId,
          authId: m.senderAuthId,
          displayName: m.senderName,
        );
      }
      final key = peer.authId;
      final prev = lastAt[key];
      if (prev == null || m.createdAt.isAfter(prev)) {
        lastAt[key] = m.createdAt;
        byKey[key] = peer;
      }
    }

    final list = byKey.values.toList();
    list.sort((a, b) {
      final ta = lastAt[a.authId] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = lastAt[b.authId] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return list;
  }

  /// Elenco utenti con login (escluso me) per nuovo messaggio privato.
  Future<List<AppChatPeer>> listDirectory({String query = ''}) async {
    final authId = _myAuthId;
    if (authId == null) return const [];
    try {
      List res;
      try {
        res = await SupabaseService.client
            .from('users')
            .select(
              'id, auth_id, id_uuid, full_name, username, email, hidden_from_directory',
            )
            .order('full_name', ascending: true)
            .limit(400) as List;
      } catch (_) {
        res = await SupabaseService.client
            .from('users')
            .select('id, auth_id, id_uuid, full_name, username, email')
            .order('full_name', ascending: true)
            .limit(400) as List;
      }

      final q = query.trim().toLowerCase();
      final out = <AppChatPeer>[];
      for (final raw in res) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (!UsersDirectory.isVisibleInDirectory(row)) continue;
        final id = (row['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final a = (row['auth_id'] ?? '').toString().trim();
        final u = (row['id_uuid'] ?? '').toString().trim();
        final peerAuth = a.isNotEmpty ? a : u;
        if (peerAuth.isEmpty || peerAuth == authId) continue;
        if (id == _myUserId) continue;

        final name = (row['full_name'] ?? '').toString().trim();
        final username = (row['username'] ?? '').toString().trim();
        final email = (row['email'] ?? '').toString().trim();
        final display = name.isNotEmpty
            ? name
            : (username.isNotEmpty
                ? username
                : (email.isNotEmpty ? email : 'Utente'));
        if (q.isNotEmpty) {
          final hay =
              '$display $username $email'.toLowerCase();
          if (!hay.contains(q)) continue;
        }
        out.add(AppChatPeer(userId: id, authId: peerAuth, displayName: display));
      }
      return out;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.listDirectory: $e');
      return const [];
    }
  }

  Future<void> refresh() async {
    try {
      final cutoffIso = _cutoffUtc.toIso8601String();
      final res = await SupabaseService.client
          .from('app_chat_messages')
          .select(_selectCols)
          .gte('created_at', cutoffIso)
          .order('created_at', ascending: true)
          .limit(500);

      final rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

      final byId = <String, AppChatMessage>{};
      for (final row in rows) {
        final msg = AppChatMessage.fromMap(row);
        byId[msg.id] = msg;
      }

      final list = <AppChatMessage>[];
      for (final row in rows) {
        final base = AppChatMessage.fromMap(row);
        final replyId = base.replyToId;
        final reply = replyId == null ? null : byId[replyId];
        list.add(
          reply == null
              ? base
              : AppChatMessage.fromMap(row, replyPreview: reply),
        );
      }

      _messages
        ..clear()
        ..addAll(list);
      _emit();
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.refresh: $e');
    }
  }

  Future<void> _ensureRealtime() async {
    if (_listening) return;
    final ch = SupabaseService.client.channel('app_chat_messages_global');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'app_chat_messages',
      callback: (payload) {
        final row = Map<String, dynamic>.from(payload.newRecord);
        unawaited(_onInsert(row));
      },
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'app_chat_messages',
      callback: (payload) {
        final row = Map<String, dynamic>.from(payload.newRecord);
        unawaited(_onUpdate(row));
      },
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'app_chat_dm_read_state',
      callback: (payload) {
        _onDmReadStateChange(Map<String, dynamic>.from(payload.newRecord));
      },
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'app_chat_dm_read_state',
      callback: (payload) {
        _onDmReadStateChange(Map<String, dynamic>.from(payload.newRecord));
      },
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'app_chat_group_read_state',
      callback: (_) => _scheduleRefreshGroupReadStates(),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'app_chat_group_read_state',
      callback: (_) => _scheduleRefreshGroupReadStates(),
    );
    ch.subscribe();
    _channel = ch;
    _listening = true;
  }

  void _scheduleRefreshGroupReadStates() {
    _groupReadRefreshDebounce?.cancel();
    _groupReadRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(refreshGroupReadStates(_activeGroupIdForReceipts));
    });
  }

  Future<void> refreshGroupReadStates([String? groupId]) async {
    final gid = (groupId ?? _activeGroupIdForReceipts ?? '').trim();
    if (gid.isEmpty) {
      groupReadStates.value = const [];
      return;
    }
    _activeGroupIdForReceipts = gid;
    try {
      final raw = await SupabaseService.client.rpc(
        'app_chat_group_read_states',
        params: {'p_group_id': gid},
      );
      final list = <AppChatGroupReader>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final row = Map<String, dynamic>.from(item);
          final authId = (row['auth_id'] ?? '').toString().trim();
          final ts = parseSupabaseTimestampToUtc(row['last_read_at']);
          final userId = (row['user_id'] as num?)?.toInt() ?? 0;
          if (authId.isEmpty || ts == null || userId <= 0) continue;
          final name = (row['display_name'] ?? '').toString().trim();
          list.add(
            AppChatGroupReader(
              userId: userId,
              authId: authId,
              displayName: name.isEmpty ? 'Utente' : name,
              lastReadAt: ts,
            ),
          );
        }
      }
      list.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      groupReadStates.value = list;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.refreshGroupReadStates: $e');
    }
  }

  Future<List<AppChatGroup>> refreshMyGroups() async {
    try {
      final raw = await SupabaseService.client.rpc('app_chat_list_my_groups');
      final list = <AppChatGroup>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final g = AppChatGroup.fromMap(Map<String, dynamic>.from(item));
          if (g.id.isEmpty) continue;
          list.add(g);
        }
      }
      myGroups.value = list;
      return list;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.refreshMyGroups: $e');
      return myGroups.value;
    }
  }

  Future<String?> createGroup({
    required String name,
    List<int> memberUserIds = const [],
    String? description,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw Exception('Nome gruppo obbligatorio.');
    final raw = await SupabaseService.client.rpc(
      'app_chat_create_group',
      params: {
        'p_name': n,
        'p_member_user_ids': memberUserIds,
        'p_description': description,
      },
    );
    final id = (raw ?? '').toString().trim();
    await refreshMyGroups();
    return id.isEmpty ? null : id;
  }

  Future<void> setGroupMembers({
    required String groupId,
    required List<int> memberUserIds,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    await SupabaseService.client.rpc(
      'app_chat_set_group_members',
      params: {
        'p_group_id': gid,
        'p_member_user_ids': memberUserIds,
      },
    );
    await refreshMyGroups();
  }

  Future<List<AppChatPeer>> listGroupMembers(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return const [];
    try {
      final raw = await SupabaseService.client.rpc(
        'app_chat_list_group_members',
        params: {'p_group_id': gid},
      );
      final out = <AppChatPeer>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final row = Map<String, dynamic>.from(item);
          final id = (row['user_id'] as num?)?.toInt() ?? 0;
          final auth = (row['auth_id'] ?? '').toString().trim();
          final name = (row['display_name'] ?? '').toString().trim();
          if (id <= 0 || auth.isEmpty) continue;
          out.add(
            AppChatPeer(
              userId: id,
              authId: auth,
              displayName: name.isEmpty ? 'Utente' : name,
            ),
          );
        }
      }
      return out;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.listGroupMembers: $e');
      return const [];
    }
  }

  Future<void> markGroupRead(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    try {
      await SupabaseService.client.rpc(
        'app_chat_mark_group_read',
        params: {'p_group_id': gid},
      );
      await refreshUnreadBadge();
      unawaited(refreshGroupReadStates(gid));
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.markGroupRead: $e');
    }
  }

  /// Chi ha letto un messaggio di gruppo (last_read_at >= created_at), escluso il mittente.
  List<AppChatGroupReader> groupReadersForMessage(AppChatMessage m) {
    if (m.isDirect || m.isDeleted) return const [];
    final gid = (m.groupId ?? '').trim();
    if (gid.isEmpty) return const [];
    if (_activeGroupIdForReceipts != null &&
        _activeGroupIdForReceipts != gid) {
      // Stati caricati per un altro gruppo.
      return const [];
    }
    final senderAuth = m.senderAuthId;
    final created = m.createdAt.toUtc();
    return groupReadStates.value
        .where((r) {
          if (r.authId == senderAuth) return false;
          if (r.userId == m.senderUserId) return false;
          return !r.lastReadAt.toUtc().isBefore(created);
        })
        .toList(growable: false);
  }

  void _onDmReadStateChange(Map<String, dynamic> row) {
    final myAuth = _myAuthId ?? '';
    if (myAuth.isEmpty) return;
    // Il peer ha aggiornato la lettura della chat con me.
    final peerAuthOfReader = (row['peer_auth_id'] ?? '').toString().trim();
    final readerAuth = (row['auth_id'] ?? '').toString().trim();
    if (peerAuthOfReader != myAuth || readerAuth.isEmpty) return;
    final ts = parseSupabaseTimestampToUtc(row['last_read_at']);
    if (ts == null) return;
    final next = Map<String, DateTime>.from(dmPeerLastReadByAuth.value);
    next[readerAuth] = ts;
    dmPeerLastReadByAuth.value = next;
  }

  /// Segna letti i messaggi privati con [peer] e aggiorna anche il badge globale.
  Future<void> markDmConversationRead(AppChatPeer peer) async {
    try {
      await SupabaseService.client.rpc(
        'app_chat_dm_mark_read',
        params: {
          'p_peer_user_id': peer.userId,
          'p_peer_auth_id': peer.authId,
        },
      );
      AppChatOverlayController.markDmSeen();
      await refreshUnreadBadge();
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.markDmConversationRead: $e');
    }
  }

  Future<int> deleteDmConversation(AppChatPeer peer) async {
    try {
      final raw = await SupabaseService.client.rpc(
        'app_chat_dm_delete_conversation',
        params: {
          'p_peer_user_id': peer.userId,
          'p_peer_auth_id': peer.authId,
        },
      );
      final deleted = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;

      final myAuth = _myAuthId ?? '';
      _messages.removeWhere((m) {
        if (!m.isDirect) return false;
        final a = m.senderAuthId;
        final b = m.recipientAuthId ?? '';
        return (a == myAuth && b == peer.authId) || (a == peer.authId && b == myAuth);
      });
      _emit();
      await refreshUnreadBadge();
      return deleted;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.deleteDmConversation: $e');
      rethrow;
    }
  }

  /// Carica quando [peer] ha letto l'ultima volta i miei messaggi.
  Future<DateTime?> refreshPeerDmLastRead(AppChatPeer peer) async {
    try {
      final raw = await SupabaseService.client.rpc(
        'app_chat_dm_peer_last_read',
        params: {
          'p_peer_user_id': peer.userId,
          'p_peer_auth_id': peer.authId,
        },
      );
      final ts = parseSupabaseTimestampToUtc(raw) ??
          (raw is String ? parseSupabaseTimestampToUtc(raw) : null) ??
          (raw == null ? null : DateTime.tryParse(raw.toString())?.toUtc());
      if (ts != null) {
        final next = Map<String, DateTime>.from(dmPeerLastReadByAuth.value);
        next[peer.authId] = ts;
        dmPeerLastReadByAuth.value = next;
      }
      return ts;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.refreshPeerDmLastRead: $e');
      return dmPeerLastReadByAuth.value[peer.authId];
    }
  }

  bool isDmMessageReadByPeer(AppChatMessage m, AppChatPeer peer) {
    if (!m.isDirect || m.isDeleted) return false;
    final last = dmPeerLastReadByAuth.value[peer.authId];
    if (last == null) return false;
    return !m.createdAt.isAfter(last);
  }

  Future<void> _onUpdate(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) {
      await _onInsert(row);
      return;
    }
    final prev = _messages[idx];
    final updated = AppChatMessage.fromMap(row, replyPreview: prev.replyPreview);
    if (!_isVisibleToMe(updated)) {
      _messages.removeAt(idx);
      _emit();
      return;
    }
    _messages[idx] = updated;
    // Aggiorna anteprime reply che puntano a questo messaggio.
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.replyToId == id) {
        _messages[i] = AppChatMessage(
          id: m.id,
          senderUserId: m.senderUserId,
          senderAuthId: m.senderAuthId,
          senderName: m.senderName,
          recipientUserId: m.recipientUserId,
          recipientAuthId: m.recipientAuthId,
          recipientName: m.recipientName,
          groupId: m.groupId,
          body: m.body,
          replyToId: m.replyToId,
          attachmentPath: m.attachmentPath,
          attachmentName: m.attachmentName,
          attachmentMime: m.attachmentMime,
          attachmentSize: m.attachmentSize,
          createdAt: m.createdAt,
          deletedAt: m.deletedAt,
          replyPreview: updated,
        );
      }
    }
    _emit();
  }

  /// Soft-delete: il messaggio resta con testo «Messaggio cancellato».
  Future<bool> deleteMessage(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return false;
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId == null || authId.isEmpty) {
      throw Exception('Non autenticato.');
    }

    try {
      Map<String, dynamic>? updated;
      try {
        final row = await SupabaseService.client
            .from('app_chat_messages')
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'body': null,
              'attachment_path': null,
              'attachment_name': null,
              'attachment_mime': null,
              'attachment_size': null,
            })
            .eq('id', id)
            .eq('sender_auth_id', authId)
            .isFilter('deleted_at', null)
            .select(_selectCols)
            .maybeSingle();
        if (row != null) {
          updated = Map<String, dynamic>.from(row);
        }
      } catch (e) {
        // ignore: avoid_print
        if (kDebugMode) print('>>> AppChatService.deleteMessage update: $e');
      }

      if (updated == null) {
        final raw = await SupabaseService.client.rpc(
          'app_chat_delete_message',
          params: {'p_message_id': id},
        );
        final rpcOk = raw == true || raw?.toString() == 'true';
        if (!rpcOk) return false;
      } else {
        await _onUpdate(updated);
        return true;
      }

      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        final prev = _messages[idx];
        _messages[idx] = AppChatMessage(
          id: prev.id,
          senderUserId: prev.senderUserId,
          senderAuthId: prev.senderAuthId,
          senderName: prev.senderName,
          recipientUserId: prev.recipientUserId,
          recipientAuthId: prev.recipientAuthId,
          recipientName: prev.recipientName,
          groupId: prev.groupId,
          body: null,
          replyToId: prev.replyToId,
          attachmentPath: null,
          attachmentName: null,
          attachmentMime: null,
          attachmentSize: null,
          createdAt: prev.createdAt,
          deletedAt: DateTime.now().toUtc(),
          replyPreview: prev.replyPreview,
        );
        _emit();
      }
      return true;
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('>>> AppChatService.deleteMessage: $e');
      rethrow;
    }
  }

  Future<void> _onInsert(Map<String, dynamic> row) async {
    final created = parseSupabaseTimestampToUtc(row['created_at']);
    if (created != null && created.isBefore(_cutoffUtc)) return;

    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (_messages.any((m) => m.id == id)) return;

    // Filtra subito i DM altrui (Realtime può consegnare prima del RLS client).
    final msgProbe = AppChatMessage.fromMap(row);
    if (!_isVisibleToMe(msgProbe)) return;

    AppChatMessage? reply;
    final replyId = (row['reply_to_id'] ?? '').toString().trim();
    if (replyId.isNotEmpty) {
      for (final m in _messages) {
        if (m.id == replyId) {
          reply = m;
          break;
        }
      }
      if (reply == null) {
        try {
          final r = await SupabaseService.client
              .from('app_chat_messages')
              .select(_selectCols)
              .eq('id', replyId)
              .maybeSingle();
          if (r != null) {
            reply = AppChatMessage.fromMap(Map<String, dynamic>.from(r));
          }
        } catch (_) {}
      }
    }

    final msg = AppChatMessage.fromMap(row, replyPreview: reply);
    _messages.add(msg);
    _pruneExpired();
    _emit();

    final authId = _myAuthId ?? '';
    if (authId.isNotEmpty && msg.senderAuthId != authId) {
      unawaited(AppChatAlerts.onIncoming(msg, myAuthId: authId));
      // Anche a chat aperta: aggiorna lampeggio tab Gruppo/Privato.
      unawaited(refreshUnreadBadge());
    }
  }

  bool _isVisibleToMe(AppChatMessage m) {
    final auth = _myAuthId ?? '';
    if (auth.isEmpty) return false;
    if (m.isDirect) {
      return m.senderAuthId == auth || m.recipientAuthId == auth;
    }
    final gid = (m.groupId ?? '').trim();
    if (gid.isEmpty) return false;
    // Finché i gruppi non sono caricati, fidati di RLS (il row è già arrivato).
    if (myGroups.value.isEmpty) return true;
    return myGroups.value.any((g) => g.id == gid);
  }

  void _pruneExpired() {
    final cutoff = _cutoffUtc;
    _messages.removeWhere((m) => m.createdAt.isBefore(cutoff));
  }

  void _emit() => _controller.add(currentMessages);

  Future<({int userId, String authId, String name})?> _resolveSender() async {
    final auth = Supabase.instance.client.auth.currentUser;
    if (auth == null) return null;
    final authId = auth.id;
    try {
      final row = await SupabaseService.client
          .from('users')
          .select('id, full_name, username, email')
          .or('auth_id.eq.$authId,id_uuid.eq.$authId')
          .maybeSingle();
      if (row == null) return null;
      final id = (row['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) return null;
      _myUserId = id;
      final name = (row['full_name'] ?? '').toString().trim();
      final username = (row['username'] ?? '').toString().trim();
      final email = (row['email'] ?? '').toString().trim();
      final display = name.isNotEmpty
          ? name
          : (username.isNotEmpty
              ? username
              : (email.isNotEmpty ? email : 'Utente'));
      return (userId: id, authId: authId, name: display);
    } catch (_) {
      return null;
    }
  }

  Future<AppChatMessage?> sendText({
    required String text,
    String? replyToId,
    AppChatPeer? to,
    String? groupId,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return null;
    final sender = await _resolveSender();
    if (sender == null) {
      throw Exception('Utente non trovato: impossibile inviare.');
    }
    if (to != null && to.authId == sender.authId) {
      throw Exception('Non puoi scrivere a te stesso.');
    }
    final gid = (groupId ?? '').trim();
    if (to == null && gid.isEmpty) {
      throw Exception('Seleziona un gruppo.');
    }

    final payload = <String, dynamic>{
      'sender_user_id': sender.userId,
      'sender_auth_id': sender.authId,
      'sender_name': sender.name,
      'body': body,
      if (to != null) ...{
        'recipient_user_id': to.userId,
        'recipient_auth_id': to.authId,
        'recipient_name': to.displayName,
      },
      if (to == null) 'group_id': gid,
      if (replyToId != null && replyToId.trim().isNotEmpty)
        'reply_to_id': replyToId.trim(),
    };

    final inserted = await SupabaseService.client
        .from('app_chat_messages')
        .insert(payload)
        .select(_selectCols)
        .single();

    final map = Map<String, dynamic>.from(inserted);
    await _onInsert(map);
    final msg = AppChatMessage.fromMap(map);
    unawaited(_notifyRecipients(msg.id));
    return msg;
  }

  Future<AppChatMessage?> sendAttachment({
    required AppChatAttachmentBytes file,
    String? caption,
    String? replyToId,
    AppChatPeer? to,
    String? groupId,
  }) async {
    if (to != null &&
        !canMutateAsAdmin(currentSessionRole() ?? '')) {
      throw Exception(
        'Nelle chat private solo gli amministratori possono '
        'inviare foto o documenti.',
      );
    }
    final gid = (groupId ?? '').trim();
    if (to == null && gid.isEmpty) {
      throw Exception('Seleziona un gruppo.');
    }
    if (to != null && to.authId.trim().isEmpty) {
      throw Exception('Destinatario non valido.');
    }
    if (file.bytes.length > maxAttachmentBytes) {
      throw Exception('Allegato troppo grande (max 50 MB).');
    }
    final sender = await _resolveSender();
    if (sender == null) {
      throw Exception('Utente non trovato: impossibile inviare.');
    }
    if (to != null && to.authId == sender.authId) {
      throw Exception('Non puoi scrivere a te stesso.');
    }

    final safeName = _sanitizeFileName(file.fileName);
    final path =
        '${sender.authId}/${DateTime.now().toUtc().millisecondsSinceEpoch}_$safeName';

    await SupabaseService.client.storage.from(bucket).uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(
            contentType: file.mimeType,
            upsert: false,
          ),
        );

    final body = (caption ?? '').trim();
    final payload = <String, dynamic>{
      'sender_user_id': sender.userId,
      'sender_auth_id': sender.authId,
      'sender_name': sender.name,
      if (to != null) ...{
        'recipient_user_id': to.userId,
        'recipient_auth_id': to.authId,
        'recipient_name': to.displayName,
      },
      if (to == null) 'group_id': gid,
      if (body.isNotEmpty) 'body': body,
      'attachment_path': path,
      'attachment_name': safeName,
      'attachment_mime': file.mimeType,
      'attachment_size': file.bytes.length,
      if (replyToId != null && replyToId.trim().isNotEmpty)
        'reply_to_id': replyToId.trim(),
    };

    final inserted = await SupabaseService.client
        .from('app_chat_messages')
        .insert(payload)
        .select(_selectCols)
        .single();

    final map = Map<String, dynamic>.from(inserted);
    await _onInsert(map);
    final msg = AppChatMessage.fromMap(map);
    unawaited(_notifyRecipients(msg.id));
    return msg;
  }

  /// Notifica push (web) a destinatari gruppo/privato.
  Future<void> _notifyRecipients(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await SupabaseService.client.functions.invoke(
          'app-chat-notify',
          body: {'message_id': id},
        );
        if (res.status < 400) return;
        // ignore: avoid_print
        if (kDebugMode) {
          print(
            '>>> AppChatService._notifyRecipients status=${res.status} data=${res.data}',
          );
        }
      } catch (e) {
        // ignore: avoid_print
        if (kDebugMode) print('>>> AppChatService._notifyRecipients: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  Future<String?> signedUrlFor(String? path) async {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;
    try {
      return await SupabaseService.client.storage
          .from(bucket)
          .createSignedUrl(p, 3600);
    } catch (_) {
      return null;
    }
  }

  /// Byte originali dall'allegato (stessa risoluzione caricata).
  Future<Uint8List?> downloadAttachmentBytes(String? path) async {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;
    try {
      final bytes =
          await SupabaseService.client.storage.from(bucket).download(p);
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeFileName(String raw) {
    final base = raw.trim().replaceAll(RegExp(r'[\\/]+'), '_');
    final cleaned = base.replaceAll(RegExp(r'[^\w.\- ()àèéìòùÀÈÉÌÒÙ]+'), '_');
    if (cleaned.isEmpty) return 'file.bin';
    return cleaned.length > 120 ? cleaned.substring(cleaned.length - 120) : cleaned;
  }
}
