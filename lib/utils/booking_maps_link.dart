/// Chiavi legacy su riga prenotazione (solo lettura dati storici).
const kBookingMapLinkKeys = [
  'maps_link',
  'map_link_txt',
  'maps_link_txt',
  'map_link',
];

/// UUID struttura dalla riga prenotazione.
String structureIdFromBooking(Map<String, dynamic> booking) {
  for (final k in const [
    'structure_id',
    'struttura_id',
    'structure_uuid',
    'struttura_id_uuid',
  ]) {
    final v = (booking[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// Link Google Maps dalla struttura collegata (anagrafica `structures.maps_link`).
/// Non duplicare il link sulla prenotazione.
String mapsLinkForBooking(
  Map<String, dynamic> booking, {
  required Map<String, String> structureLinksById,
}) {
  final sid = structureIdFromBooking(booking);
  if (sid.isNotEmpty) {
    final fromStructure = (structureLinksById[sid] ?? '').trim();
    if (fromStructure.isNotEmpty) return fromStructure;
  }
  // Solo dati già presenti su righe vecchie (non si scrive più in insert/update).
  for (final k in kBookingMapLinkKeys) {
    final v = (booking[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}
