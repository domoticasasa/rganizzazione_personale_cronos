import 'package:flutter/material.dart';

/// Forme marker (enum completo per compatibilità preferenze salvate).
enum MdoMapMarkerShape {
  badge,
  pill,
  circle,
  square,
  iconStack,
  pin,
  roundedRect,
  diamond,
  hexagon,
  shield,
  teardrop,
  star,
  triangle,
  octagon,
  bubble,
  tag,
  banner,
  mapPin,
  arch,
  cross,
  pentagon,
  parallelogram,
  notch,
  estintore,
  casettaPs,
}

/// Icone marker.
enum MdoMapMarkerIcon {
  none,
  train,
  container,
  business,
  place,
  warehouse,
  garage,
}

/// Colori rapidi nell'editor.
const List<Color> kMdoMapMarkerPalette = <Color>[
  Color(0xFF1565C0),
  Color(0xFF0277BD),
  Color(0xFF00838F),
  Color(0xFF2E7D32),
  Color(0xFFE65100),
  Color(0xFFD84315),
  Color(0xFFC62828),
  Color(0xFF6A1B9A),
  Color(0xFF6D4C41),
  Color(0xFF37474F),
  Color(0xFF212121),
  Color(0xFF78909C),
];

/// Stile di una categoria (commessa / MDO / BOX) — sempre indipendente.
class MdoMapMarkerKindStyle {
  const MdoMapMarkerKindStyle({
    required this.shape,
    required this.colorArgb,
    this.icon = MdoMapMarkerIcon.none,
    this.sizeScale = 1.0,
  });

  final MdoMapMarkerShape shape;
  final int colorArgb;
  final MdoMapMarkerIcon icon;
  final double sizeScale;

  Color get color => Color(colorArgb);

  static const commessa = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.pill,
    colorArgb: 0xFFE65100,
    icon: MdoMapMarkerIcon.none,
    sizeScale: 1.05,
  );

  static const mdo = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.pill,
    colorArgb: 0xFF1565C0,
    icon: MdoMapMarkerIcon.none,
    sizeScale: 1.0,
  );

  static const box = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.iconStack,
    colorArgb: 0xFF6D4C41,
    icon: MdoMapMarkerIcon.container,
    sizeScale: 1.0,
  );

  static const estintore = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.estintore,
    colorArgb: 0xFFC62828,
    icon: MdoMapMarkerIcon.none,
    sizeScale: 1.0,
  );

  static const casettaPs = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.casettaPs,
    colorArgb: 0xFF2E7D32,
    icon: MdoMapMarkerIcon.none,
    sizeScale: 1.0,
  );

  static const struttura = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.pill,
    colorArgb: 0xFF6A1B9A,
    icon: MdoMapMarkerIcon.business,
    sizeScale: 1.0,
  );

  static const officina = MdoMapMarkerKindStyle(
    shape: MdoMapMarkerShape.pill,
    colorArgb: 0xFF0F766E,
    icon: MdoMapMarkerIcon.garage,
    sizeScale: 1.0,
  );

  MdoMapMarkerKindStyle copyWith({
    MdoMapMarkerShape? shape,
    int? colorArgb,
    MdoMapMarkerIcon? icon,
    double? sizeScale,
  }) =>
      MdoMapMarkerKindStyle(
        shape: shape ?? this.shape,
        colorArgb: colorArgb ?? this.colorArgb,
        icon: icon ?? this.icon,
        sizeScale: sizeScale ?? this.sizeScale,
      );

  Map<String, dynamic> toJson() => {
        'shape': shape.name,
        'colorArgb': colorArgb,
        'icon': icon.name,
        'sizeScale': sizeScale,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdoMapMarkerKindStyle &&
          shape == other.shape &&
          colorArgb == other.colorArgb &&
          icon == other.icon &&
          sizeScale == other.sizeScale;

  @override
  int get hashCode => Object.hash(shape, colorArgb, icon, sizeScale);

  factory MdoMapMarkerKindStyle.fromJson(
    Map<String, dynamic>? json, {
    required MdoMapMarkerKindStyle fallback,
  }) {
    if (json == null || json.isEmpty) return fallback;
    final shape = _parseShape(json['shape'], fallback.shape);
    final icon = MdoMapMarkerIcon.values.firstWhere(
      (i) => i.name == (json['icon'] ?? '').toString(),
      orElse: () => fallback.icon,
    );
    final color = (json['colorArgb'] as num?)?.toInt() ?? fallback.colorArgb;
    final scale = ((json['sizeScale'] as num?)?.toDouble() ?? fallback.sizeScale)
        .clamp(0.5, 2.5);
    return MdoMapMarkerKindStyle(
      shape: shape,
      colorArgb: color,
      icon: icon,
      sizeScale: scale,
    );
  }
}

class MdoMapMarkerStyle {
  const MdoMapMarkerStyle({
    this.mapSizeScale = 1.0,
    this.commessa = MdoMapMarkerKindStyle.commessa,
    this.mdo = MdoMapMarkerKindStyle.mdo,
    this.box = MdoMapMarkerKindStyle.box,
    this.estintore = MdoMapMarkerKindStyle.estintore,
    this.casettaPs = MdoMapMarkerKindStyle.casettaPs,
    this.struttura = MdoMapMarkerKindStyle.struttura,
    this.officina = MdoMapMarkerKindStyle.officina,
  });

  final double mapSizeScale;
  final MdoMapMarkerKindStyle commessa;
  final MdoMapMarkerKindStyle mdo;
  final MdoMapMarkerKindStyle box;
  final MdoMapMarkerKindStyle estintore;
  final MdoMapMarkerKindStyle casettaPs;
  final MdoMapMarkerKindStyle struttura;
  final MdoMapMarkerKindStyle officina;

  static const defaults = MdoMapMarkerStyle();

  MdoMapMarkerKindStyle kindStyleFor(String kind) => switch (kind) {
        'commessa' => commessa,
        'box' => box,
        'estintore' => estintore,
        'casetta_ps' => casettaPs,
        'struttura' => struttura,
        'officina' => officina,
        _ => mdo,
      };

  MdoMapMarkerStyle copyWith({
    double? mapSizeScale,
    MdoMapMarkerKindStyle? commessa,
    MdoMapMarkerKindStyle? mdo,
    MdoMapMarkerKindStyle? box,
    MdoMapMarkerKindStyle? estintore,
    MdoMapMarkerKindStyle? casettaPs,
    MdoMapMarkerKindStyle? struttura,
    MdoMapMarkerKindStyle? officina,
  }) =>
      MdoMapMarkerStyle(
        mapSizeScale: mapSizeScale ?? this.mapSizeScale,
        commessa: commessa ?? this.commessa,
        mdo: mdo ?? this.mdo,
        box: box ?? this.box,
        estintore: estintore ?? this.estintore,
        casettaPs: casettaPs ?? this.casettaPs,
        struttura: struttura ?? this.struttura,
        officina: officina ?? this.officina,
      );

  ResolvedMapMarkerLook resolveForKind(String kind) {
    final k = kindStyleFor(kind);
    return ResolvedMapMarkerLook(
      color: k.color,
      shape: k.shape,
      icon: k.icon,
      sizeScale: mapSizeScale.clamp(0.5, 2.5) * k.sizeScale.clamp(0.5, 2.5),
    );
  }

  Map<String, dynamic> toJson() => {
        'mapSizeScale': mapSizeScale,
        'commessa': commessa.toJson(),
        'mdo': mdo.toJson(),
        'box': box.toJson(),
        'estintore': estintore.toJson(),
        'casetta_ps': casettaPs.toJson(),
        'struttura': struttura.toJson(),
        'officina': officina.toJson(),
      };

  factory MdoMapMarkerStyle.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final mapScale = ((json['mapSizeScale'] ?? json['sizeScale']) as num?)
            ?.toDouble() ??
        1.0;
    return MdoMapMarkerStyle(
      mapSizeScale: mapScale.clamp(0.5, 2.5),
      commessa: MdoMapMarkerKindStyle.fromJson(
        _map(json['commessa']),
        fallback: MdoMapMarkerKindStyle.commessa,
      ),
      mdo: MdoMapMarkerKindStyle.fromJson(
        _map(json['mdo']),
        fallback: MdoMapMarkerKindStyle.mdo,
      ),
      box: MdoMapMarkerKindStyle.fromJson(
        _map(json['box']),
        fallback: MdoMapMarkerKindStyle.box,
      ),
      estintore: MdoMapMarkerKindStyle.fromJson(
        _map(json['estintore']),
        fallback: MdoMapMarkerKindStyle.estintore,
      ),
      casettaPs: MdoMapMarkerKindStyle.fromJson(
        _map(json['casetta_ps']),
        fallback: MdoMapMarkerKindStyle.casettaPs,
      ),
      struttura: MdoMapMarkerKindStyle.fromJson(
        _map(json['struttura']),
        fallback: MdoMapMarkerKindStyle.struttura,
      ),
      officina: MdoMapMarkerKindStyle.fromJson(
        _map(json['officina']),
        fallback: MdoMapMarkerKindStyle.officina,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdoMapMarkerStyle &&
          mapSizeScale == other.mapSizeScale &&
          commessa == other.commessa &&
          mdo == other.mdo &&
          box == other.box &&
          estintore == other.estintore &&
          casettaPs == other.casettaPs &&
          struttura == other.struttura &&
          officina == other.officina;

  @override
  int get hashCode => Object.hash(
        mapSizeScale,
        commessa,
        mdo,
        box,
        estintore,
        casettaPs,
        struttura,
        officina,
      );
}

class ResolvedMapMarkerLook {
  const ResolvedMapMarkerLook({
    required this.color,
    required this.shape,
    required this.icon,
    required this.sizeScale,
  });

  final Color color;
  final MdoMapMarkerShape shape;
  final MdoMapMarkerIcon icon;
  final double sizeScale;
}

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

MdoMapMarkerShape _parseShape(dynamic raw, MdoMapMarkerShape fallback) {
  final name = (raw ?? '').toString();
  if (name.isEmpty) return fallback;
  return MdoMapMarkerShape.values.firstWhere(
    (s) => s.name == name,
    orElse: () => fallback,
  );
}

/// Forme nel selettore per categoria.
List<MdoMapMarkerShape> mdoMapMarkerPickerShapesFor(String kindId) {
  switch (kindId) {
    case 'estintore':
      return const [
        MdoMapMarkerShape.estintore,
        MdoMapMarkerShape.pill,
        MdoMapMarkerShape.badge,
        MdoMapMarkerShape.mapPin,
      ];
    case 'casetta_ps':
      return const [
        MdoMapMarkerShape.casettaPs,
        MdoMapMarkerShape.pill,
        MdoMapMarkerShape.roundedRect,
        MdoMapMarkerShape.badge,
      ];
    default:
      return kMdoMapMarkerPickerShapes;
  }
}

/// Forme generiche (Commesse, MDO, BOX).
const kMdoMapMarkerPickerShapes = <MdoMapMarkerShape>[
  MdoMapMarkerShape.pill,
  MdoMapMarkerShape.badge,
  MdoMapMarkerShape.roundedRect,
  MdoMapMarkerShape.tag,
  MdoMapMarkerShape.iconStack,
  MdoMapMarkerShape.mapPin,
  MdoMapMarkerShape.circle,
];

extension MdoMapMarkerShapeLabel on MdoMapMarkerShape {
  String get label => switch (this) {
        MdoMapMarkerShape.badge => 'Etichetta',
        MdoMapMarkerShape.pill => 'Pillola',
        MdoMapMarkerShape.circle => 'Cerchio',
        MdoMapMarkerShape.square => 'Quadrato',
        MdoMapMarkerShape.iconStack => 'Icona + testo',
        MdoMapMarkerShape.pin => 'Spillo',
        MdoMapMarkerShape.roundedRect => 'Rettangolo',
        MdoMapMarkerShape.diamond => 'Rombo',
        MdoMapMarkerShape.hexagon => 'Esagono',
        MdoMapMarkerShape.shield => 'Scudo',
        MdoMapMarkerShape.teardrop => 'Goccia',
        MdoMapMarkerShape.star => 'Stella',
        MdoMapMarkerShape.triangle => 'Triangolo',
        MdoMapMarkerShape.octagon => 'Ottagono',
        MdoMapMarkerShape.bubble => 'Fumetto',
        MdoMapMarkerShape.tag => 'Tag',
        MdoMapMarkerShape.banner => 'Banner',
        MdoMapMarkerShape.mapPin => 'Pin GPS',
        MdoMapMarkerShape.arch => 'Arco',
        MdoMapMarkerShape.cross => 'Croce',
        MdoMapMarkerShape.pentagon => 'Pentagono',
        MdoMapMarkerShape.parallelogram => 'Parallelogramma',
        MdoMapMarkerShape.notch => 'Angolo tagliato',
        MdoMapMarkerShape.estintore => 'Estintore',
        MdoMapMarkerShape.casettaPs => 'Cassetta P.S.',
      };

  IconData get pickerIcon => switch (this) {
        MdoMapMarkerShape.badge => Icons.label_outline,
        MdoMapMarkerShape.pill => Icons.rounded_corner,
        MdoMapMarkerShape.circle => Icons.circle_outlined,
        MdoMapMarkerShape.square => Icons.crop_square,
        MdoMapMarkerShape.iconStack => Icons.layers_outlined,
        MdoMapMarkerShape.pin => Icons.push_pin_outlined,
        MdoMapMarkerShape.roundedRect => Icons.rectangle_outlined,
        MdoMapMarkerShape.diamond => Icons.change_history,
        MdoMapMarkerShape.hexagon => Icons.change_history,
        MdoMapMarkerShape.shield => Icons.shield_outlined,
        MdoMapMarkerShape.teardrop => Icons.water_drop_outlined,
        MdoMapMarkerShape.star => Icons.star_outline,
        MdoMapMarkerShape.triangle => Icons.change_history,
        MdoMapMarkerShape.octagon => Icons.emergency_outlined,
        MdoMapMarkerShape.bubble => Icons.chat_bubble_outline,
        MdoMapMarkerShape.tag => Icons.sell_outlined,
        MdoMapMarkerShape.banner => Icons.view_agenda_outlined,
        MdoMapMarkerShape.mapPin => Icons.location_on_outlined,
        MdoMapMarkerShape.arch => Icons.architecture_outlined,
        MdoMapMarkerShape.cross => Icons.add,
        MdoMapMarkerShape.pentagon => Icons.home_outlined,
        MdoMapMarkerShape.parallelogram => Icons.crop_free,
        MdoMapMarkerShape.notch => Icons.crop_landscape_outlined,
        MdoMapMarkerShape.estintore => Icons.fire_extinguisher_outlined,
        MdoMapMarkerShape.casettaPs => Icons.medical_services_outlined,
      };
}

extension MdoMapMarkerIconLabel on MdoMapMarkerIcon {
  String get label => switch (this) {
        MdoMapMarkerIcon.none => 'Nessuna icona',
        MdoMapMarkerIcon.train => 'Treno',
        MdoMapMarkerIcon.container => 'Container',
        MdoMapMarkerIcon.business => 'Commessa',
        MdoMapMarkerIcon.place => 'Luogo',
        MdoMapMarkerIcon.warehouse => 'Magazzino',
        MdoMapMarkerIcon.garage => 'Officina',
      };

  IconData get iconData => switch (this) {
        MdoMapMarkerIcon.none => Icons.remove,
        MdoMapMarkerIcon.train => Icons.train,
        MdoMapMarkerIcon.container => Icons.inventory_2,
        MdoMapMarkerIcon.business => Icons.business,
        MdoMapMarkerIcon.place => Icons.place,
        MdoMapMarkerIcon.warehouse => Icons.warehouse,
        MdoMapMarkerIcon.garage => Icons.garage_outlined,
      };
}

/// Metadati tab editor.
class MdoMapMarkerKindTab {
  const MdoMapMarkerKindTab({
    required this.id,
    required this.title,
    required this.sampleLabel,
    required this.defaultStyle,
    required this.tabIcon,
  });

  final String id;
  final String title;
  final String sampleLabel;
  final MdoMapMarkerKindStyle defaultStyle;
  final IconData tabIcon;
}

const kMdoMapMarkerTabs = <MdoMapMarkerKindTab>[
  MdoMapMarkerKindTab(
    id: 'commessa',
    title: 'Commesse',
    sampleLabel: 'TE-15',
    defaultStyle: MdoMapMarkerKindStyle.commessa,
    tabIcon: Icons.business_center_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'mdo',
    title: 'MDO',
    sampleLabel: 'A76',
    defaultStyle: MdoMapMarkerKindStyle.mdo,
    tabIcon: Icons.train_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'box',
    title: 'BOX',
    sampleLabel: 'CON01',
    defaultStyle: MdoMapMarkerKindStyle.box,
    tabIcon: Icons.inventory_2_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'estintore',
    title: 'Estintori',
    sampleLabel: 'E-12',
    defaultStyle: MdoMapMarkerKindStyle.estintore,
    tabIcon: Icons.fire_extinguisher_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'casetta_ps',
    title: 'Cassette P.S.',
    sampleLabel: 'PS-03',
    defaultStyle: MdoMapMarkerKindStyle.casettaPs,
    tabIcon: Icons.medical_services_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'struttura',
    title: 'Strutture',
    sampleLabel: 'Sede',
    defaultStyle: MdoMapMarkerKindStyle.struttura,
    tabIcon: Icons.apartment_outlined,
  ),
  MdoMapMarkerKindTab(
    id: 'officina',
    title: 'Officine',
    sampleLabel: 'FIAT',
    defaultStyle: MdoMapMarkerKindStyle.officina,
    tabIcon: Icons.garage_outlined,
  ),
];
