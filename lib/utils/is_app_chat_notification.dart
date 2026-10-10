import 'dart:convert';

/// Notifiche generate dalla chat: non devono finire in pagina Notifiche / campanella.
bool isAppChatNotificationRow(Map<String, dynamic> n) {
  final title = (n['title'] ?? '').toString().trim();
  if (title.startsWith('GESTOPRO Chat')) return true;

  final rawMeta = n['meta'];
  Map<String, dynamic> m = {};
  if (rawMeta is Map) {
    m = Map<String, dynamic>.from(rawMeta);
  } else if (rawMeta is String && rawMeta.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(rawMeta);
      if (decoded is Map) m = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }

  final type = (m['type'] ?? m['tipo'] ?? '').toString().trim().toLowerCase();
  if (type == 'app_chat') return true;
  final action = (m['action'] ?? '').toString().trim().toLowerCase();
  return action == 'app_chat_dm' || action == 'app_chat_group';
}
