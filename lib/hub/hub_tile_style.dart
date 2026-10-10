import 'package:flutter/material.dart';

import 'hub_icon_catalog.dart';
import 'hub_tile_fonts.dart';
import 'hub_tile_grid.dart';

/// Stile globale di un tile hub (salvato in Supabase).
class HubTileStyle {
  const HubTileStyle({
    this.customLabel,
    this.customSubtitle,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
    this.sizeScale = 1.0,
    this.iconCodepoint,
    this.fontFamilyKey,
    this.titleFontSize,
    this.iconFontSize,
    this.posX,
    this.posY,
    this.gridCol,
    this.gridRow,
    this.gridColSpan,
    this.gridRowSpan,
  });

  final String? customLabel;
  final String? customSubtitle;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;
  final double sizeScale;

  /// Codepoint Material Icons; null = icona predefinita del pulsante.
  final int? iconCodepoint;

  /// Chiave famiglia font ([HubTileFonts]).
  final String? fontFamilyKey;

  /// Dimensione titolo in px (1–50); null = deriva da [sizeScale].
  final double? titleFontSize;

  /// Dimensione icona in px (1–50); null = deriva da [sizeScale].
  final double? iconFontSize;

  final double? posX;
  final double? posY;
  final int? gridCol;
  final int? gridRow;
  final int? gridColSpan;
  final int? gridRowSpan;

  static const double minScale = 0.6;
  static const double maxScale = 2.0;
  static const double minTitleFontSize = 1;
  static const double maxTitleFontSize = 50;
  static const double minIconFontSize = 1;
  static const double maxIconFontSize = 50;

  static const List<double> sizePresets = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

  bool get hasGridPlacement => gridCol != null && gridRow != null;
  bool get hasCustomPosition => hasGridPlacement;
  bool get hasCustomIcon => iconCodepoint != null;

  bool get hasOverrides =>
      (customLabel?.trim().isNotEmpty ?? false) ||
      (customSubtitle?.trim().isNotEmpty ?? false) ||
      backgroundColor != null ||
      textColor != null ||
      iconColor != null ||
      hasCustomIcon ||
      (fontFamilyKey != null &&
          fontFamilyKey != HubTileFonts.keyDefault) ||
      titleFontSize != null ||
      iconFontSize != null ||
      (sizeScale - 1.0).abs() > 0.01 ||
      hasGridPlacement ||
      gridColSpan != null ||
      gridRowSpan != null;

  IconData effectiveIcon(IconData defaultIcon) =>
      HubIconCatalog.iconFromCodepoint(iconCodepoint, defaultIcon);

  TextStyle titleTextStyle({
    required TextStyle base,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final scale = sizeScale;
    final size = titleFontSize ?? (base.fontSize ?? 15) * scale;
    return base.copyWith(
      fontSize: size.clamp(minTitleFontSize, maxTitleFontSize),
      fontWeight: fontWeight,
      color: color ?? base.color,
      fontFamily: HubTileFonts.familyForKey(fontFamilyKey) ?? base.fontFamily,
    );
  }

  (int colSpan, int rowSpan) effectiveGridSpans(double scale) {
    if (gridColSpan != null && gridRowSpan != null) {
      return (gridColSpan!, gridRowSpan!);
    }
    return HubTileGridConfig.spansForScale(scale);
  }

  String effectiveLabel(String defaultLabel) {
    final custom = customLabel?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return defaultLabel;
  }

  String effectiveSubtitle(String defaultSubtitle) {
    final custom = customSubtitle?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return defaultSubtitle;
  }

  HubTileStyle copyWith({
    String? customLabel,
    String? customSubtitle,
    Color? backgroundColor,
    Color? textColor,
    Color? iconColor,
    double? sizeScale,
    int? iconCodepoint,
    String? fontFamilyKey,
    double? titleFontSize,
    double? iconFontSize,
    double? posX,
    double? posY,
    int? gridCol,
    int? gridRow,
    int? gridColSpan,
    int? gridRowSpan,
    bool clearCustomLabel = false,
    bool clearCustomSubtitle = false,
    bool clearBackgroundColor = false,
    bool clearTextColor = false,
    bool clearIconColor = false,
    bool clearIcon = false,
    bool clearFontFamily = false,
    bool clearTitleFontSize = false,
    bool clearIconFontSize = false,
    bool clearPosition = false,
    bool clearGridSpan = false,
  }) {
    return HubTileStyle(
      customLabel:
          clearCustomLabel ? null : (customLabel ?? this.customLabel),
      customSubtitle: clearCustomSubtitle
          ? null
          : (customSubtitle ?? this.customSubtitle),
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      textColor: clearTextColor ? null : (textColor ?? this.textColor),
      iconColor: clearIconColor ? null : (iconColor ?? this.iconColor),
      sizeScale: sizeScale ?? this.sizeScale,
      iconCodepoint: clearIcon ? null : (iconCodepoint ?? this.iconCodepoint),
      fontFamilyKey: clearFontFamily
          ? null
          : (fontFamilyKey ?? this.fontFamilyKey),
      titleFontSize: clearTitleFontSize
          ? null
          : (titleFontSize ?? this.titleFontSize),
      iconFontSize: clearIconFontSize
          ? null
          : (iconFontSize ?? this.iconFontSize),
      posX: clearPosition ? null : (posX ?? this.posX),
      posY: clearPosition ? null : (posY ?? this.posY),
      gridCol: clearPosition ? null : (gridCol ?? this.gridCol),
      gridRow: clearPosition ? null : (gridRow ?? this.gridRow),
      gridColSpan: clearPosition || clearGridSpan
          ? null
          : (gridColSpan ?? this.gridColSpan),
      gridRowSpan: clearPosition || clearGridSpan
          ? null
          : (gridRowSpan ?? this.gridRowSpan),
    );
  }

  Map<String, dynamic> toJson() => toAppearanceJson();

  Map<String, dynamic> toAppearanceJson() {
    return <String, dynamic>{
      if (customLabel?.trim().isNotEmpty ?? false)
        'custom_label': customLabel!.trim(),
      if (customSubtitle?.trim().isNotEmpty ?? false)
        'custom_subtitle': customSubtitle!.trim(),
      if (backgroundColor != null)
        'background_color': _colorToHex(backgroundColor!),
      if (textColor != null) 'text_color': _colorToHex(textColor!),
      if (iconColor != null) 'icon_color': _colorToHex(iconColor!),
      if (iconCodepoint != null) 'icon_codepoint': iconCodepoint,
      if (fontFamilyKey != null &&
          fontFamilyKey != HubTileFonts.keyDefault)
        'font_family': fontFamilyKey,
      if (titleFontSize != null) 'title_font_size': titleFontSize,
      if (iconFontSize != null) 'icon_font_size': iconFontSize,
      if ((sizeScale - 1.0).abs() > 0.01) 'size_scale': sizeScale,
    };
  }

  Map<String, dynamic> toGridPlacementDbRow({
    required String layoutKey,
    required String itemKey,
    required String updatedAt,
  }) {
    return <String, dynamic>{
      'layout_key': layoutKey,
      'item_key': itemKey,
      'grid_col': gridCol,
      'grid_row': gridRow,
      'grid_col_span': gridColSpan ?? 1,
      'grid_row_span': gridRowSpan ?? 1,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toPersistRow({
    required String itemKey,
    required String updatedAt,
  }) {
    return <String, dynamic>{
      'item_key': itemKey,
      'size_scale': sizeScale,
      'updated_at': updatedAt,
      if (customLabel?.trim().isNotEmpty ?? false)
        'custom_label': customLabel!.trim(),
      if (customSubtitle?.trim().isNotEmpty ?? false)
        'custom_subtitle': customSubtitle!.trim(),
      'background_color': backgroundColor != null
          ? _colorToHex(backgroundColor!)
          : null,
      'text_color': textColor != null ? _colorToHex(textColor!) : null,
      'icon_color': iconColor != null ? _colorToHex(iconColor!) : null,
      if (iconCodepoint != null) 'icon_codepoint': iconCodepoint,
      if (fontFamilyKey != null &&
          fontFamilyKey != HubTileFonts.keyDefault)
        'font_family': fontFamilyKey,
      if (titleFontSize != null) 'title_font_size': titleFontSize,
      if (iconFontSize != null) 'icon_font_size': iconFontSize,
    };
  }

  Map<String, dynamic> toDbRow({
    required String itemKey,
    required String updatedAt,
  }) =>
      toPersistRow(itemKey: itemKey, updatedAt: updatedAt);

  factory HubTileStyle.fromGridPlacementJson(Map<String, dynamic> json) {
    return HubTileStyle(
      gridCol: _parseGridInt(json['grid_col']),
      gridRow: _parseGridInt(json['grid_row']),
      gridColSpan: _parseGridInt(json['grid_col_span']),
      gridRowSpan: _parseGridInt(json['grid_row_span']),
    );
  }

  factory HubTileStyle.fromJson(Map<String, dynamic> json) {
    final posX = _parsePos(json['pos_x']);
    final posY = _parsePos(json['pos_y']);
    var gridCol = _parseGridInt(json['grid_col']);
    var gridRow = _parseGridInt(json['grid_row']);
    if (gridCol == null && posX != null) {
      gridCol = HubTileGridConfig.migrateColFromPos(posX);
    }
    if (gridRow == null && posY != null) {
      gridRow = HubTileGridConfig.migrateRowFromPos(posY);
    }
    final scale = _parseScale(json['size_scale']);
    var fontKey = json['font_family']?.toString().trim();
    if (fontKey != null && fontKey.isEmpty) fontKey = null;
    return HubTileStyle(
      customLabel: json['custom_label']?.toString(),
      customSubtitle: json['custom_subtitle']?.toString(),
      backgroundColor: parseColor(json['background_color']?.toString()),
      textColor: parseColor(json['text_color']?.toString()),
      iconColor: parseColor(json['icon_color']?.toString()),
      sizeScale: scale,
      iconCodepoint: _parseGridInt(json['icon_codepoint']),
      fontFamilyKey: fontKey,
      titleFontSize: _parseTitleFontSize(json['title_font_size']),
      iconFontSize: _parseIconFontSize(json['icon_font_size']),
      gridCol: gridCol,
      gridRow: gridRow,
      gridColSpan: _parseGridInt(json['grid_col_span']),
      gridRowSpan: _parseGridInt(json['grid_row_span']),
    );
  }

  static int? _parseGridInt(Object? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  static double? _parseTitleFontSize(Object? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.toString());
    if (v == null) return null;
    return v.clamp(minTitleFontSize, maxTitleFontSize);
  }

  static double? _parseIconFontSize(Object? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.toString());
    if (v == null) return null;
    return v.clamp(minIconFontSize, maxIconFontSize);
  }

  /// Icona in px: [iconFontSize] oppure base × [sizeScale].
  double resolveIconSize({required bool fillCell, double scale = 1.0}) {
    if (iconFontSize != null) {
      return iconFontSize!.clamp(minIconFontSize, maxIconFontSize);
    }
    return (fillCell ? 30.0 : 36.0) * scale;
  }

  static double? _parsePos(Object? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.toString());
    if (v == null) return null;
    return v.clamp(0.0, 1.0);
  }

  static double _parseScale(Object? raw) {
    if (raw == null) return 1.0;
    final v = double.tryParse(raw.toString());
    if (v == null) return 1.0;
    return v.clamp(minScale, maxScale);
  }

  static Color? parseColor(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  static String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
  }
}
