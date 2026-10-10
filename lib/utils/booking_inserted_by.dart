/// Etichetta «Inserito da» / «Richiedente» per prenotazioni.
String bookingInsertedByLabel(
  Map<String, dynamic> booking, {
  required Map<String, String> usersByUuid,
  required Map<String, String> usersById,
  Map<String, String>? userRoleById,
}) {
  String resolve(String key) {
    if (key.isEmpty) return '';
    return (usersByUuid[key] ?? usersById[key] ?? '').trim();
  }

  final createdKey = (booking['created_by'] ?? '').toString().trim();
  final updatedKey = (booking['updated_by'] ?? '').toString().trim();
  final dtKey = (booking['dt_user_uuid'] ?? '').toString().trim();

  final createdLabel = resolve(createdKey);
  final updatedLabel = resolve(updatedKey);

  // Treno/aereo: richiesta inserita da assistente DT (id numerico users.id).
  final reqId = (booking['requested_by_user_id'] ?? '').toString().trim();
  if (reqId.isNotEmpty) {
    final role = (userRoleById?[reqId] ?? '').toLowerCase().trim();
    if (role == 'assistente_dt') {
      final reqLabel = resolve(reqId);
      if (reqLabel.isNotEmpty) return reqLabel;
    }
  }

  // Modifica o inserimento da utente diverso dal DT della prenotazione (es. assistente).
  if (updatedKey.isNotEmpty &&
      dtKey.isNotEmpty &&
      updatedKey != dtKey &&
      updatedLabel.isNotEmpty) {
    return updatedLabel;
  }
  if (createdKey.isNotEmpty &&
      dtKey.isNotEmpty &&
      createdKey != dtKey &&
      createdLabel.isNotEmpty) {
    return createdLabel;
  }

  // Backfill storico: created_by = dt supervisionato ma updated_by = assistente.
  if (createdKey.isNotEmpty &&
      dtKey.isNotEmpty &&
      createdKey == dtKey &&
      updatedKey.isNotEmpty &&
      updatedKey != createdKey &&
      updatedLabel.isNotEmpty) {
    return updatedLabel;
  }

  if (createdLabel.isNotEmpty) return createdLabel;
  if (updatedLabel.isNotEmpty) return updatedLabel;

  final richiedenteLabel = resolve(dtKey);
  if (richiedenteLabel.isNotEmpty) return richiedenteLabel;

  return '—';
}

/// Etichetta «Richiedente»: autore della richiesta iniziale, non l'ultimo editor.
String bookingRequesterLabel(
  Map<String, dynamic> booking, {
  required Map<String, String> usersByUuid,
  required Map<String, String> usersById,
  Map<String, String>? userRoleById,
}) {
  String resolve(String key) {
    if (key.isEmpty) return '';
    return (usersByUuid[key] ?? usersById[key] ?? '').trim();
  }

  final createdKey = (booking['created_by'] ?? '').toString().trim();
  final dtKey = (booking['dt_user_uuid'] ?? '').toString().trim();

  // Treno/aereo: richiesta inserita da assistente DT.
  final reqId = (booking['requested_by_user_id'] ?? '').toString().trim();
  if (reqId.isNotEmpty) {
    final role = (userRoleById?[reqId] ?? '').toLowerCase().trim();
    if (role == 'assistente_dt') {
      final reqLabel = resolve(reqId);
      if (reqLabel.isNotEmpty) return reqLabel;
    }
  }

  final createdLabel = resolve(createdKey);
  if (createdLabel.isNotEmpty) return createdLabel;

  final dtLabel = resolve(dtKey);
  if (dtLabel.isNotEmpty) return dtLabel;

  return '—';
}

/// Mappa prenotazione → campi usati da [bookingInsertedByLabel].
Map<String, dynamic> bookingAuthorFields({
  required String dtUserUuid,
  String? createdBy,
  String? updatedBy,
  Object? requestedByUserId,
}) {
  return {
    'dt_user_uuid': dtUserUuid,
    'created_by': ?createdBy,
    'updated_by': ?updatedBy,
    'requested_by_user_id': ?requestedByUserId,
  };
}
