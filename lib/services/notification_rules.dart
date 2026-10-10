// lib/services/notification_rules.dart

typedef NotificationPredicate = bool Function(Map<String, dynamic> n);

/// La tua pagina mostra tutte le notifiche dell’utente,
/// quindi il popup deve mostrarsi per OGNI nuova notifica valida.
/// La regola di destinatari è gestita dal NotificationSender.
/// Qui non filtriamo nulla.
bool notificationPopupRule(Map<String, dynamic> n) {
  return true;
}