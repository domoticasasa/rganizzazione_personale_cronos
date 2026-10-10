import 'package:supabase_flutter/supabase_flutter.dart';

import 'classic_nav_session_cache.dart';
import 'notification_sender.dart';

class SecurityIncidentReport {
  const SecurityIncidentReport({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.description,
    required this.category,
    required this.severity,
    required this.status,
    required this.reporterName,
    this.reporterRole = '',
    this.deviceInfo = '',
    this.locationInfo = '',
    this.adminNotes,
    this.isPublicSubmit = false,
  });

  final String id;
  final DateTime createdAt;
  final String title;
  final String description;
  final String category;
  final String severity;
  final String status;
  final String reporterName;
  final String reporterRole;
  final String deviceInfo;
  final String locationInfo;
  final String? adminNotes;
  final bool isPublicSubmit;

  bool get isOpen =>
      status == 'aperto' || status == 'in_lavorazione';

  factory SecurityIncidentReport.fromMap(Map<String, dynamic> m) {
    final pub = m['is_public_submit'];
    return SecurityIncidentReport(
      id: (m['id_uuid'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ??
          DateTime.now(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      category: (m['category'] ?? 'altro').toString(),
      severity: (m['severity'] ?? 'media').toString(),
      status: (m['status'] ?? 'aperto').toString(),
      reporterName: (m['reporter_name'] ?? '').toString(),
      reporterRole: (m['reporter_role'] ?? '').toString(),
      deviceInfo: (m['device_info'] ?? '').toString(),
      locationInfo: (m['location_info'] ?? '').toString(),
      adminNotes: (m['admin_notes'] as String?)?.trim(),
      isPublicSubmit: pub == true || pub == 'true' || pub == 't',
    );
  }

  static String categoryLabel(String key) {
    switch (key) {
      case 'phishing':
        return 'Phishing / messaggio sospetto';
      case 'account_compromesso':
        return 'Account compromesso';
      case 'dispositivo_perso':
        return 'Dispositivo perso / rubato';
      case 'malware':
        return 'Malware / comportamento anomalo';
      case 'accesso_non_autorizzato':
        return 'Accesso non autorizzato';
      default:
        return 'Altro';
    }
  }

  static String severityLabel(String key) {
    switch (key) {
      case 'bassa':
        return 'Bassa';
      case 'alta':
        return 'Alta';
      case 'critica':
        return 'Critica';
      default:
        return 'Media';
    }
  }

  static String statusLabel(String key) {
    switch (key) {
      case 'in_lavorazione':
        return 'In lavorazione';
      case 'gestita':
        return 'Gestita';
      case 'chiuso':
        return 'Chiuso';
      default:
        return 'Aperto';
    }
  }
}

abstract final class SecurityIncidentService {
  SecurityIncidentService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<SecurityIncidentReport>> listMineOrAdmin() async {
    final res = await _client
        .from('security_incident_reports')
        .select(
          'id_uuid, created_at, title, description, category, severity, status, '
          'reporter_name, reporter_role, device_info, location_info, admin_notes, '
          'is_public_submit',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return (res as List)
        .map(
          (e) => SecurityIncidentReport.fromMap(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList(growable: false);
  }

  /// Segnalazione senza login (edge `security-incident-public`).
  static Future<void> submitPublic({
    required String reporterName,
    required String category,
    required String severity,
    required String title,
    required String description,
    String deviceInfo = '',
    String locationInfo = '',
    String phone = '',
    String honeypot = '',
  }) async {
    final res = await _client.functions.invoke(
      'security-incident-public',
      body: {
        'reporter_name': reporterName.trim(),
        'category': category,
        'severity': severity,
        'title': title.trim(),
        'description': description.trim(),
        'device_info': deviceInfo.trim(),
        'location_info': locationInfo.trim(),
        'reporter_phone': phone.trim(),
        'website': honeypot,
      },
    );
    if (res.status >= 400) {
      final data = res.data;
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Invio non riuscito (${res.status})';
      throw StateError(msg);
    }
  }

  static Future<void> submit({
    required String category,
    required String severity,
    required String title,
    required String description,
    String deviceInfo = '',
    String locationInfo = '',
    String phone = '',
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('Sessione assente');
    }
    final cache = ClassicNavSessionCache.current;
    final authId = session.user.id;

    final userRow = await _client
        .from('users')
        .select('id, full_name, role')
        .eq('auth_id', authId)
        .maybeSingle();

    final reporterName = (userRow?['full_name'] ??
            cache?.fullName ??
            session.user.email ??
            'Utente')
        .toString()
        .trim();
    final reporterRole =
        (userRow?['role'] ?? cache?.role ?? '').toString().trim();
    final reporterUserId = userRow?['id'] is int
        ? userRow!['id'] as int
        : int.tryParse('${userRow?['id'] ?? ''}');

    await _client.from('security_incident_reports').insert({
      'reporter_user_id': reporterUserId,
      'reporter_auth_id': authId,
      'reporter_name': reporterName,
      'reporter_role': reporterRole,
      'reporter_phone': phone.trim(),
      'category': category,
      'severity': severity,
      'title': title.trim(),
      'description': description.trim(),
      'device_info': deviceInfo.trim(),
      'location_info': locationInfo.trim(),
      'status': 'aperto',
    });

    // Notifica admin / logistica (best effort).
    try {
      final admins = await _client
          .from('users')
          .select('id, role')
          .or(
            'role.eq.admin,role.eq.admin_generale,role.eq.logistica',
          );
      final ids = (admins as List)
          .map((e) => e['id'])
          .whereType<int>()
          .where((id) => id != reporterUserId)
          .toList();
      if (ids.isNotEmpty) {
        await NotificationSender.sendToUserIds(
          userIds: ids,
          bookingId: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
          action: 'security_incident',
          title: 'Segnalazione sicurezza: ${title.trim()}',
          message:
              '$reporterName ha segnalato un incidente '
              '(${SecurityIncidentReport.categoryLabel(category)}, '
              'gravità ${SecurityIncidentReport.severityLabel(severity)}). '
              'Apri Impostazioni → Incidenti sicurezza.',
          bookingType: 'security_incident',
        );
      }
    } catch (_) {
      // La segnalazione è già salvata.
    }
  }

  static Future<void> updateStatus({
    required String id,
    required String status,
    String? adminNotes,
  }) async {
    await _client.from('security_incident_reports').update({
      'status': status,
      'admin_notes': ?adminNotes,
      if (status == 'gestita' || status == 'chiuso')
        'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id_uuid', id);
  }
}
