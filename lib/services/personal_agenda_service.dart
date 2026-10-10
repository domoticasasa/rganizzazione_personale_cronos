import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'agenda_reminder_scheduler.dart';
import 'outlook_calendar_sync_service.dart';
import 'supabase_service.dart';

enum AgendaEntryKind {
  event,
  note,
  reminder,
  absence,
}

extension AgendaEntryKindX on AgendaEntryKind {
  String get dbValue => name;

  String get labelIt => switch (this) {
        AgendaEntryKind.event => 'Evento',
        AgendaEntryKind.note => 'Nota',
        AgendaEntryKind.reminder => 'Promemoria',
        AgendaEntryKind.absence => 'Assenza',
      };

  static AgendaEntryKind fromDb(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'note':
        return AgendaEntryKind.note;
      case 'reminder':
        return AgendaEntryKind.reminder;
      case 'absence':
        return AgendaEntryKind.absence;
      default:
        return AgendaEntryKind.event;
    }
  }
}

enum AgendaPriority { low, normal, high }

extension AgendaPriorityX on AgendaPriority {
  String get dbValue => name;

  String get labelIt => switch (this) {
        AgendaPriority.low => 'Bassa',
        AgendaPriority.normal => 'Normale',
        AgendaPriority.high => 'Alta',
      };

  static AgendaPriority fromDb(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'low':
        return AgendaPriority.low;
      case 'high':
        return AgendaPriority.high;
      default:
        return AgendaPriority.normal;
    }
  }
}

/// Preset minuti prima per avvisi UI.
const agendaReminderPresets = <int>[
  0,
  5,
  15,
  30,
  60,
  24 * 60,
  7 * 24 * 60,
];

String agendaReminderPresetLabel(int minutes) {
  switch (minutes) {
    case 0:
      return 'All’inizio';
    case 5:
      return '5 minuti prima';
    case 15:
      return '15 minuti prima';
    case 30:
      return '30 minuti prima';
    case 60:
      return '1 ora prima';
    case 1440:
      return '1 giorno prima';
    case 10080:
      return '1 settimana prima';
    default:
      return '$minutes minuti prima';
  }
}

class AgendaEntry {
  const AgendaEntry({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    this.body = '',
    this.location = '',
    this.allDay = false,
    this.startsAt,
    this.endsAt,
    this.colorHex = '#1565C0',
    this.priority = AgendaPriority.normal,
    this.completed = false,
    this.assenzaIdUuid,
    this.reminderEnabled = false,
    this.reminderMinutesBefore,
    this.outlookEventId,
    this.outlookEtag,
    this.outlookLastModified,
    this.syncOrigin = 'cronos',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final int userId;
  final AgendaEntryKind kind;
  final String title;
  final String body;
  final String location;
  final bool allDay;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String colorHex;
  final AgendaPriority priority;
  final bool completed;
  final String? assenzaIdUuid;
  final bool reminderEnabled;
  final int? reminderMinutesBefore;
  final String? outlookEventId;
  final String? outlookEtag;
  final DateTime? outlookLastModified;
  final String syncOrigin;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get fromOutlook =>
      syncOrigin == 'outlook' ||
      (outlookEventId != null && outlookEventId!.isNotEmpty);

  factory AgendaEntry.fromMap(Map<String, dynamic> m) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    return AgendaEntry(
      id: (m['id'] ?? '').toString(),
      userId: (m['user_id'] as num?)?.toInt() ?? 0,
      kind: AgendaEntryKindX.fromDb(m['kind']?.toString()),
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      location: (m['location'] ?? '').toString(),
      allDay: m['all_day'] == true,
      startsAt: ts(m['starts_at']),
      endsAt: ts(m['ends_at']),
      colorHex: ((m['color_hex'] ?? '#1565C0').toString().trim().isEmpty)
          ? '#1565C0'
          : m['color_hex'].toString(),
      priority: AgendaPriorityX.fromDb(m['priority']?.toString()),
      completed: m['completed'] == true,
      assenzaIdUuid: (m['assenza_id_uuid']?.toString().trim().isEmpty ?? true)
          ? null
          : m['assenza_id_uuid'].toString(),
      reminderEnabled: m['reminder_enabled'] == true,
      reminderMinutesBefore:
          (m['reminder_minutes_before'] as num?)?.toInt(),
      outlookEventId: (m['outlook_event_id']?.toString().trim().isEmpty ?? true)
          ? null
          : m['outlook_event_id'].toString(),
      outlookEtag: (m['outlook_etag']?.toString().trim().isEmpty ?? true)
          ? null
          : m['outlook_etag'].toString(),
      outlookLastModified: ts(m['outlook_last_modified']),
      syncOrigin: ((m['sync_origin'] ?? 'cronos').toString().trim().isEmpty)
          ? 'cronos'
          : m['sync_origin'].toString(),
      createdAt: ts(m['created_at']),
      updatedAt: ts(m['updated_at']),
    );
  }

  Map<String, dynamic> toInsertMap(int userId) => {
        'user_id': userId,
        'kind': kind.dbValue,
        'title': title.trim(),
        'body': body.trim(),
        'location': location.trim(),
        'all_day': allDay,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'color_hex': colorHex,
        'priority': priority.dbValue,
        'completed': completed,
        'assenza_id_uuid': assenzaIdUuid,
        'reminder_enabled': reminderEnabled,
        'reminder_minutes_before':
            reminderEnabled ? (reminderMinutesBefore ?? 15) : null,
        'outlook_event_id': outlookEventId,
        'outlook_etag': outlookEtag,
        'outlook_last_modified':
            outlookLastModified?.toUtc().toIso8601String(),
        'sync_origin': syncOrigin,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> toUpdateMap() => {
        'kind': kind.dbValue,
        'title': title.trim(),
        'body': body.trim(),
        'location': location.trim(),
        'all_day': allDay,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'color_hex': colorHex,
        'priority': priority.dbValue,
        'completed': completed,
        'assenza_id_uuid': assenzaIdUuid,
        'reminder_enabled': reminderEnabled,
        'reminder_minutes_before':
            reminderEnabled ? (reminderMinutesBefore ?? 15) : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  AgendaEntry copyWith({
    String? id,
    int? userId,
    AgendaEntryKind? kind,
    String? title,
    String? body,
    String? location,
    bool? allDay,
    DateTime? startsAt,
    DateTime? endsAt,
    String? colorHex,
    AgendaPriority? priority,
    bool? completed,
    String? assenzaIdUuid,
    bool? reminderEnabled,
    int? reminderMinutesBefore,
    String? outlookEventId,
    String? outlookEtag,
    DateTime? outlookLastModified,
    String? syncOrigin,
    bool clearStarts = false,
    bool clearEnds = false,
    bool clearAssenza = false,
    bool clearReminderMinutes = false,
    bool clearOutlook = false,
  }) {
    return AgendaEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      body: body ?? this.body,
      location: location ?? this.location,
      allDay: allDay ?? this.allDay,
      startsAt: clearStarts ? null : (startsAt ?? this.startsAt),
      endsAt: clearEnds ? null : (endsAt ?? this.endsAt),
      colorHex: colorHex ?? this.colorHex,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      assenzaIdUuid:
          clearAssenza ? null : (assenzaIdUuid ?? this.assenzaIdUuid),
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutesBefore: clearReminderMinutes
          ? null
          : (reminderMinutesBefore ?? this.reminderMinutesBefore),
      outlookEventId:
          clearOutlook ? null : (outlookEventId ?? this.outlookEventId),
      outlookEtag: clearOutlook ? null : (outlookEtag ?? this.outlookEtag),
      outlookLastModified: clearOutlook
          ? null
          : (outlookLastModified ?? this.outlookLastModified),
      syncOrigin: syncOrigin ?? this.syncOrigin,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Assenza ufficiale (read-only) da mostrare in agenda.
class AgendaLinkedAbsence {
  const AgendaLinkedAbsence({
    required this.idUuid,
    required this.tipo,
    required this.dataDal,
    required this.dataAl,
    this.note = '',
    this.stato = '',
  });

  final String idUuid;
  final String tipo;
  final DateTime dataDal;
  final DateTime dataAl;
  final String note;
  final String stato;
}

class PersonalAgendaService {
  PersonalAgendaService._();
  static final PersonalAgendaService instance = PersonalAgendaService._();

  static const table = 'user_agenda_entries';

  SupabaseClient get _client => SupabaseService.client;

  Future<int?> currentUserId() async {
    try {
      final authId = _client.auth.currentUser?.id;
      if (authId == null) return null;
      final row = await _client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      return (row?['id'] as num?)?.toInt();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PersonalAgendaService.currentUserId: $e');
      }
      return null;
    }
  }

  Future<List<AgendaEntry>> listBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final uid = await currentUserId();
    if (uid == null) return const [];
    final fromUtc = from.toUtc().toIso8601String();
    final toUtc = to.toUtc().toIso8601String();
    try {
      final rows = await _client
          .from(table)
          .select()
          .eq('user_id', uid)
          .or(
            'and(starts_at.gte.$fromUtc,starts_at.lt.$toUtc),'
            'and(starts_at.is.null,created_at.gte.$fromUtc,created_at.lt.$toUtc),'
            'and(ends_at.gte.$fromUtc,starts_at.lt.$toUtc)',
          )
          .order('starts_at', ascending: true);
      return (rows as List)
          .map((e) => AgendaEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PersonalAgendaService.listBetween filter: $e');
      }
      final rows = await _client
          .from(table)
          .select()
          .eq('user_id', uid)
          .order('starts_at', ascending: true);
      final list = (rows as List)
          .map((e) => AgendaEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      return list.where((e) {
        final s = e.startsAt ?? e.createdAt;
        if (s == null) return true;
        return !s.isBefore(from) && s.isBefore(to);
      }).toList(growable: false);
    }
  }

  Future<AgendaEntry> upsert(
    AgendaEntry draft, {
    bool syncRemote = true,
  }) async {
    final uid = await currentUserId();
    if (uid == null) throw Exception('Utente non autenticato');
    if (draft.title.trim().isEmpty) {
      throw Exception('Il titolo è obbligatorio');
    }
    AgendaEntry saved;
    if (draft.id.isEmpty) {
      final row = await _client
          .from(table)
          .insert(draft.toInsertMap(uid))
          .select()
          .single();
      saved = AgendaEntry.fromMap(Map<String, dynamic>.from(row));
    } else {
      final row = await _client
          .from(table)
          .update(draft.toUpdateMap())
          .eq('id', draft.id)
          .eq('user_id', uid)
          .select()
          .single();
      saved = AgendaEntry.fromMap(Map<String, dynamic>.from(row));
    }
    await AgendaReminderScheduler.instance.scheduleFor(saved);
    if (syncRemote) {
      await OutlookCalendarSyncService.instance.pushEntry(saved);
    }
    return saved;
  }

  /// Upsert da pull Outlook (niente push remoto, merge per outlook_event_id).
  Future<AgendaEntry> upsertFromOutlook(AgendaEntry draft) async {
    final uid = await currentUserId();
    if (uid == null) throw Exception('Utente non autenticato');
    final oid = draft.outlookEventId;
    if (oid == null || oid.isEmpty) {
      return upsert(draft, syncRemote: false);
    }

    final existing = await _client
        .from(table)
        .select()
        .eq('user_id', uid)
        .eq('outlook_event_id', oid)
        .maybeSingle();

    if (existing == null) {
      final row = await _client
          .from(table)
          .insert(draft.toInsertMap(uid))
          .select()
          .single();
      final saved = AgendaEntry.fromMap(Map<String, dynamic>.from(row));
      await AgendaReminderScheduler.instance.scheduleFor(saved);
      return saved;
    }

    final local = AgendaEntry.fromMap(Map<String, dynamic>.from(existing));
    // Se locale più recente di Outlook, non sovrascrivere.
    if (local.updatedAt != null &&
        draft.outlookLastModified != null &&
        local.updatedAt!
            .isAfter(draft.outlookLastModified!.add(const Duration(seconds: 2))) &&
        local.syncOrigin == 'cronos') {
      return local;
    }

    final merged = local.copyWith(
      title: draft.title,
      body: draft.body,
      location: draft.location,
      allDay: draft.allDay,
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      reminderEnabled: draft.reminderEnabled,
      reminderMinutesBefore: draft.reminderMinutesBefore,
      outlookEtag: draft.outlookEtag,
      outlookLastModified: draft.outlookLastModified,
      syncOrigin: 'outlook',
    );
    final row = await _client
        .from(table)
        .update({
          ...merged.toUpdateMap(),
          'outlook_etag': draft.outlookEtag,
          'outlook_last_modified':
              draft.outlookLastModified?.toUtc().toIso8601String(),
          'sync_origin': 'outlook',
        })
        .eq('id', local.id)
        .eq('user_id', uid)
        .select()
        .single();
    final saved = AgendaEntry.fromMap(Map<String, dynamic>.from(row));
    await AgendaReminderScheduler.instance.scheduleFor(saved);
    return saved;
  }

  Future<void> attachOutlookIds({
    required String entryId,
    required String outlookEventId,
    String? etag,
    DateTime? lastModified,
  }) async {
    final uid = await currentUserId();
    if (uid == null || entryId.isEmpty || outlookEventId.isEmpty) return;
    await _client.from(table).update({
      'outlook_event_id': outlookEventId,
      'outlook_etag': etag,
      'outlook_last_modified': lastModified?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', entryId).eq('user_id', uid);
  }

  Future<void> delete(String id, {bool syncRemote = true}) async {
    final uid = await currentUserId();
    if (uid == null) throw Exception('Utente non autenticato');
    AgendaEntry? existing;
    try {
      final row = await _client
          .from(table)
          .select()
          .eq('id', id)
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        existing = AgendaEntry.fromMap(Map<String, dynamic>.from(row));
      }
    } catch (_) {}

    await _client.from(table).delete().eq('id', id).eq('user_id', uid);
    await AgendaReminderScheduler.instance.cancelFor(id);
    if (syncRemote && existing != null) {
      await OutlookCalendarSyncService.instance.deleteRemoteForEntry(existing);
    }
  }

  Future<List<AgendaLinkedAbsence>> loadOwnAbsences({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final authId = _client.auth.currentUser?.id;
      if (authId == null) return const [];
      final user = await _client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      final userId = (user?['id'] as num?)?.toInt();
      if (userId == null) return const [];

      final personale = await _client
          .from('personale')
          .select('id_uuid')
          .eq('user_id', userId)
          .maybeSingle();
      Map<String, dynamic>? p = personale == null
          ? null
          : Map<String, dynamic>.from(personale);
      if (p == null) {
        final alt = await _client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', authId)
            .maybeSingle();
        if (alt != null) p = Map<String, dynamic>.from(alt);
      }
      final pid = (p?['id_uuid'] ?? '').toString().trim();
      if (pid.isEmpty) return const [];

      final rows = await _client
          .from('dipendente_assenze')
          .select('id_uuid, tipo_assenza, data_dal, data_al, note, stato')
          .eq('personale_id_uuid', pid)
          .gte('data_al', from.toIso8601String().substring(0, 10))
          .lte('data_dal', to.toIso8601String().substring(0, 10))
          .order('data_dal');

      return (rows as List).map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final dal = DateTime.tryParse((m['data_dal'] ?? '').toString()) ?? from;
        final al = DateTime.tryParse((m['data_al'] ?? '').toString()) ?? dal;
        return AgendaLinkedAbsence(
          idUuid: (m['id_uuid'] ?? '').toString(),
          tipo: (m['tipo_assenza'] ?? 'ASSENZA').toString(),
          dataDal: dal,
          dataAl: al,
          note: (m['note'] ?? '').toString(),
          stato: (m['stato'] ?? '').toString(),
        );
      }).toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('PersonalAgendaService.loadOwnAbsences: $e');
      }
      return const [];
    }
  }
}
