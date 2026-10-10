import 'custom_hub_structure_type.dart';

/// Etichette iniziali (vuote / da collegare) per ogni modello.
abstract final class CustomHubStructureTemplates {
  static List<String> defaultLabelsFor(CustomHubStructureType type) {
    switch (type) {
      case CustomHubStructureType.prenotazioni:
        // Layout pagina intera (form + calendario + tabella), non tile hub.
        return <String>[];
      case CustomHubStructureType.home:
        return <String>[
          'Pulsante 1',
          'Pulsante 2',
          'Pulsante 3',
          'Pulsante 4',
          'Pulsante 5',
          'Pulsante 6',
          'Pulsante 7',
          'Pulsante 8',
        ];
      case CustomHubStructureType.formazioni:
        return <String>[
          'Formazione D.Lgs.',
          'Formazione RFI',
          'Programmazione corsi',
          'Scadenze',
          'Calendario',
          'Report formazione',
        ];
      case CustomHubStructureType.alert:
        return <String>[
          'Alert scadenze',
          'Avvisi urgenti',
          'Scadenze DPI',
          'Scadenze visite',
          'Report alert',
        ];
    }
  }

  static List<CustomHubSlot> buildSlots({
    required String layoutKey,
    required CustomHubStructureType type,
    List<String>? labels,
  }) {
    final names = labels ?? defaultLabelsFor(type);
    return List<CustomHubSlot>.generate(
      names.length,
      (i) => CustomHubSlot(
        key: '${layoutKey}__slot_$i',
        label: names[i],
      ),
      growable: false,
    );
  }

  static bool usesFilledPrimaryStyle(CustomHubStructureType type) {
    return type == CustomHubStructureType.prenotazioni ||
        type == CustomHubStructureType.home;
  }

  static bool usesAlertAccent(CustomHubStructureType type) {
    return type == CustomHubStructureType.alert;
  }
}
