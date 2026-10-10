import 'package:flutter/material.dart';

/// Icona in base a `tipologia_mezzo` (autovettura, furgone, autocarro, …).
///
/// Restituisce un [Icon] con letterale `Icons.*` per ramo, così il tree-shake
/// delle icone su Flutter web non lascia il “bolino” vuoto.
Widget mezzoTipologiaIcon(
  String? tipologia, {
  Color color = Colors.white,
  double size = 24,
}) {
  final t = (tipologia ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-/]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  bool has(String k) => t.contains(k);

  if (has('moto') || has('scooter') || has('ciclomot')) {
    return Icon(Icons.two_wheeler, color: color, size: size);
  }
  if (has('bici') || has('bike') || has('e-bike') || has('ebike')) {
    return Icon(Icons.pedal_bike, color: color, size: size);
  }
  if (has('bus') || has('autobus') || has('pullman') || has('minibus')) {
    return Icon(Icons.directions_bus, color: color, size: size);
  }
  if (has('furgone') ||
      has('furgon') ||
      has('van') ||
      has('transit') ||
      has('ducato')) {
    return Icon(Icons.airport_shuttle, color: color, size: size);
  }
  if (has('autocarro') ||
      has('camion') ||
      has('truck') ||
      has('motrice') ||
      has('cassone') ||
      has('ribaltabile')) {
    return Icon(Icons.local_shipping, color: color, size: size);
  }
  if (has('pick') ||
      has('pickup') ||
      has('pick up') ||
      has('trattore') ||
      has('agricol') ||
      has('escavator') ||
      has('pala')) {
    return Icon(Icons.agriculture, color: color, size: size);
  }
  if (has('rimorchio') || has('trailer') || has('semirimorchio')) {
    return Icon(Icons.rv_hookup, color: color, size: size);
  }
  if (has('ambulanza') || has('soccorso')) {
    return Icon(Icons.airport_shuttle, color: color, size: size);
  }
  // autovettura / default (anche tipologia vuota)
  return Icon(Icons.directions_car, color: color, size: size);
}

/// [IconData] equivalente (per API che accettano solo IconData).
IconData iconForTipologiaMezzo(String? tipologia) {
  final t = (tipologia ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-/]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return Icons.directions_car;

  bool has(String k) => t.contains(k);

  if (has('moto') || has('scooter') || has('ciclomot')) {
    return Icons.two_wheeler;
  }
  if (has('bici') || has('bike') || has('e-bike') || has('ebike')) {
    return Icons.pedal_bike;
  }
  if (has('bus') || has('autobus') || has('pullman') || has('minibus')) {
    return Icons.directions_bus;
  }
  if (has('furgone') ||
      has('furgon') ||
      has('van') ||
      has('transit') ||
      has('ducato')) {
    return Icons.airport_shuttle;
  }
  if (has('autocarro') ||
      has('camion') ||
      has('truck') ||
      has('motrice') ||
      has('cassone') ||
      has('ribaltabile')) {
    return Icons.local_shipping;
  }
  if (has('pick') ||
      has('pickup') ||
      has('pick up') ||
      has('trattore') ||
      has('agricol') ||
      has('escavator') ||
      has('pala')) {
    return Icons.agriculture;
  }
  if (has('rimorchio') || has('trailer') || has('semirimorchio')) {
    return Icons.rv_hookup;
  }
  if (has('ambulanza') || has('soccorso')) {
    return Icons.airport_shuttle;
  }
  return Icons.directions_car;
}
