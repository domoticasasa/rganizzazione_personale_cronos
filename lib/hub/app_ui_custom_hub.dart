import 'custom_hub_page_config.dart';
import 'custom_hub_structure_type.dart';

/// Pagina hub creata dall'admin (layout salvato in Supabase).
class AppUiCustomHub {
  const AppUiCustomHub({
    required this.layoutKey,
    required this.label,
    required this.structureType,
    required this.slots,
    this.pageConfig,
  });

  final String layoutKey;
  final String label;
  final CustomHubStructureType structureType;
  final List<CustomHubSlot> slots;
  final CustomHubPageConfig? pageConfig;

  bool get isPrenotazioniLayout =>
      structureType == CustomHubStructureType.prenotazioni;

  /// Pagina salvata come Home ma con i 8 pulsanti default (migration mancante).
  bool get looksLikeBrokenPrenotazioniCreate {
    if (structureType != CustomHubStructureType.home || slots.length != 8) {
      return false;
    }
    for (var i = 0; i < 8; i++) {
      if (slots[i].label != 'Pulsante ${i + 1}') return false;
    }
    return true;
  }



  /// Tile sulla dashboard che apre questa pagina.

  String get launcherKey => 'open_$layoutKey';



  static bool isCustomLayoutKey(String key) => key.startsWith('custom_');



  static bool isLauncherKey(String key) => key.startsWith('open_custom_');



  static bool isCustomSlotKey(String key) => key.contains('__slot_');

}


