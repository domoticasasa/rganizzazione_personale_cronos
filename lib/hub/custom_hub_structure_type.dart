import 'package:flutter/material.dart';

/// Modello di layout per una pagina hub personalizzata.
enum CustomHubStructureType {
  prenotazioni('prenotazioni', 'Prenotazioni', Icons.event_available_outlined),
  home('home', 'Home', Icons.home_outlined),
  formazioni('formazioni', 'Formazioni', Icons.school_outlined),
  alert('alert', 'Alert', Icons.warning_amber_rounded);

  const CustomHubStructureType(this.storageKey, this.label, this.icon);

  final String storageKey;
  final String label;
  final IconData icon;

  static CustomHubStructureType? fromStorage(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    for (final t in CustomHubStructureType.values) {
      if (t.storageKey == v) return t;
    }
    return null;
  }
}

class CustomHubSlot {
  const CustomHubSlot({required this.key, required this.label});

  final String key;
  final String label;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'label': label,
      };

  factory CustomHubSlot.fromJson(Map<String, dynamic> json) {
    return CustomHubSlot(
      key: (json['key'] ?? '').toString().trim(),
      label: (json['label'] ?? '').toString().trim(),
    );
  }

  CustomHubSlot copyWith({String? label}) =>
      CustomHubSlot(key: key, label: label ?? this.label);
}
