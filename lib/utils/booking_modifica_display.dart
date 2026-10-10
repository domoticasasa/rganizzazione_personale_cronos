/// Helper per mostrare i campi proposti in una richiesta di modifica booking.
Map<String, dynamic> modificaPayloadOf(Map<String, dynamic> booking) {
  final raw = booking['modifica_payload'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

bool isRichiestaModifica(Map<String, dynamic> booking) =>
    (booking['status'] ?? '').toString().toUpperCase() == 'RICHIESTA_MODIFICA';

String _firstNonEmpty(Iterable<dynamic> values) {
  for (final v in values) {
    final s = (v ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

String bookingFieldId(
  Map<String, dynamic> booking, {
  required List<String> keys,
}) =>
    _firstNonEmpty(keys.map((k) => booking[k]));

/// Valore attuale o proposto (se stato = RICHIESTA_MODIFICA e payload lo contiene).
String bookingDisplayId(
  Map<String, dynamic> booking, {
  required List<String> keys,
}) {
  if (!isRichiestaModifica(booking)) {
    return bookingFieldId(booking, keys: keys);
  }
  final payload = modificaPayloadOf(booking);
  final proposed = bookingFieldId(payload, keys: keys);
  if (proposed.isNotEmpty) return proposed;
  return bookingFieldId(booking, keys: keys);
}

bool bookingFieldIsProposed(
  Map<String, dynamic> booking, {
  required List<String> keys,
}) {
  if (!isRichiestaModifica(booking)) return false;
  final payload = modificaPayloadOf(booking);
  final proposed = bookingFieldId(payload, keys: keys);
  if (proposed.isEmpty) return false;
  final current = bookingFieldId(booking, keys: keys);
  return proposed != current;
}

const kBookingPersonaleKeys = <String>[
  'personale_id',
  'personale_uuid',
  'id_personale',
];
const kBookingStrutturaKeys = <String>[
  'structure_id',
  'struttura_id',
  'structure_uuid',
];
const kBookingCommessaKeys = <String>[
  'commessa_id',
  'commessa_uuid',
  'id_commessa',
];
