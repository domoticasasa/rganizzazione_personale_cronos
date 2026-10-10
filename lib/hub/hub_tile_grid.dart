import 'hub_tile_style.dart';

/// Griglia hub condivisa: 26 colonne × 20 righe (celle piccole = misure libere).
abstract final class HubTileGridConfig {
  HubTileGridConfig._();

  static const int columns = 26;
  static const int rows = 20;
  static const double spacing = 4;

  /// Celle occupate da un tile "normale" (scala 1.0) sulla griglia fine.
  static const int baseColSpan = 4;
  static const int baseRowSpan = 3;

  /// Rapporto larghezza/altezza tile nella griglia adattiva (4×3).
  static const double cellAspectRatio = 4 / 3;

  static String get sizeLabel => '$columns×$rows';

  /// Span proporzionali alla scala: con la griglia fine ogni passo di
  /// ridimensionamento cambia davvero la misura del pulsante.
  static (int colSpan, int rowSpan) spansForScale(double scale) {
    final c = (baseColSpan * scale).round().clamp(1, columns);
    final r = (baseRowSpan * scale).round().clamp(1, rows);
    return (c, r);
  }

  /// Moltiplicatore visivo testo/icona, relativo al tile "normale" base.
  static double visualScaleForSpans(int colSpan, int rowSpan) {
    final linear =
        ((colSpan / baseColSpan) + (rowSpan / baseRowSpan)) / 2.0;
    return linear.clamp(0.55, 2.2);
  }

  static double visualScaleForStyle(HubTileStyle? style, double sizeScale) {
    final spans = style?.effectiveGridSpans(sizeScale) ?? spansForScale(sizeScale);
    return visualScaleForSpans(spans.$1, spans.$2);
  }

  static int migrateColFromPos(double? posX) {
    if (posX == null) return 0;
    return (posX * columns).round().clamp(0, columns - 1);
  }

  static int migrateRowFromPos(double? posY) {
    if (posY == null) return 0;
    return (posY * rows).round().clamp(0, rows - 1);
  }
}

/// Rettangolo occupato sulla griglia (celle intere).
class HubTileGridRect {
  const HubTileGridRect({
    required this.col,
    required this.row,
    required this.colSpan,
    required this.rowSpan,
  });

  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;

  bool get isValid =>
      col >= 0 &&
      row >= 0 &&
      colSpan >= 1 &&
      rowSpan >= 1 &&
      col + colSpan <= HubTileGridConfig.columns &&
      row + rowSpan <= HubTileGridConfig.rows;

  bool overlaps(HubTileGridRect other) {
    if (!isValid || !other.isValid) return false;
    final hSep = col + colSpan <= other.col || other.col + other.colSpan <= col;
    final vSep = row + rowSpan <= other.row || other.row + other.rowSpan <= row;
    return !(hSep || vSep);
  }

  HubTileGridRect clamped() {
    var cs = colSpan.clamp(1, HubTileGridConfig.columns);
    var rs = rowSpan.clamp(1, HubTileGridConfig.rows);
    var c = col.clamp(0, HubTileGridConfig.columns - cs);
    var r = row.clamp(0, HubTileGridConfig.rows - rs);
    return HubTileGridRect(col: c, row: r, colSpan: cs, rowSpan: rs);
  }

  static HubTileGridRect fromStyle(HubTileStyle? style, double scale) {
    if (style == null || !style.hasGridPlacement) {
      return const HubTileGridRect(col: 0, row: 0, colSpan: 1, rowSpan: 1);
    }
    final spans = style.effectiveGridSpans(scale);
    return HubTileGridRect(
      col: style.gridCol!,
      row: style.gridRow!,
      colSpan: spans.$1,
      rowSpan: spans.$2,
    ).clamped();
  }
}

abstract final class HubTileGridLayout {
  HubTileGridLayout._();

  static bool canPlace({
    required HubTileGridRect candidate,
    required Map<String, HubTileGridRect> placed,
    String? exceptKey,
  }) {
    if (!candidate.isValid) return false;
    for (final entry in placed.entries) {
      if (entry.key == exceptKey) continue;
      if (candidate.overlaps(entry.value)) return false;
    }
    return true;
  }

  /// Se [candidate] copre un solo altro tile della stessa dimensione, restituisce la sua chiave (swap).
  static String? swapPartnerKey({
    required HubTileGridRect candidate,
    required Map<String, HubTileGridRect> placed,
    String? exceptKey,
  }) {
    if (!candidate.isValid) return null;
    String? partner;
    for (final entry in placed.entries) {
      if (entry.key == exceptKey) continue;
      if (!candidate.overlaps(entry.value)) continue;
      if (partner != null) return null;
      final other = entry.value;
      if (other.colSpan != candidate.colSpan ||
          other.rowSpan != candidate.rowSpan) {
        return null;
      }
      partner = entry.key;
    }
    return partner;
  }

  static bool canPlaceOrSwap({
    required HubTileGridRect candidate,
    required Map<String, HubTileGridRect> placed,
    String? exceptKey,
  }) {
    if (!candidate.isValid) return false;
    if (canPlace(
      candidate: candidate,
      placed: placed,
      exceptKey: exceptKey,
    )) {
      return true;
    }
    return swapPartnerKey(
          candidate: candidate,
          placed: placed,
          exceptKey: exceptKey,
        ) !=
        null;
  }

  static HubTileGridRect? firstFreeSlot({
    required int colSpan,
    required int rowSpan,
    required Map<String, HubTileGridRect> placed,
  }) {
    for (var r = 0; r < HubTileGridConfig.rows; r++) {
      for (var c = 0; c < HubTileGridConfig.columns; c++) {
        final candidate = HubTileGridRect(
          col: c,
          row: r,
          colSpan: colSpan,
          rowSpan: rowSpan,
        ).clamped();
        if (canPlace(candidate: candidate, placed: placed)) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Risolve posizione per ogni tile (salvata o auto).
  static Map<String, HubTileGridRect> resolve({
    required List<String> keysInOrder,
    required Map<String, HubTileStyle> styles,
    required double Function(String key) scaleForKey,
  }) {
    final out = <String, HubTileGridRect>{};
    for (final key in keysInOrder) {
      final style = styles[key];
      final scale = scaleForKey(key);
      final spans = style?.effectiveGridSpans(scale) ??
          HubTileGridConfig.spansForScale(scale);
      HubTileGridRect? rect;
      if (style?.hasGridPlacement ?? false) {
        rect = HubTileGridRect(
          col: style!.gridCol!,
          row: style.gridRow!,
          colSpan: spans.$1,
          rowSpan: spans.$2,
        ).clamped();
        if (!canPlace(candidate: rect, placed: out)) {
          rect = firstFreeSlot(
            colSpan: spans.$1,
            rowSpan: spans.$2,
            placed: out,
          );
        }
      } else {
        rect = firstFreeSlot(
          colSpan: spans.$1,
          rowSpan: spans.$2,
          placed: out,
        );
      }
      if (rect == null && (spans.$1 > 1 || spans.$2 > 1)) {
        rect = firstFreeSlot(colSpan: 1, rowSpan: 1, placed: out);
      }
      if (rect != null) {
        out[key] = rect;
      }
    }
    return out;
  }

  static (double cellW, double cellH) cellSize({
    required double canvasWidth,
    required double canvasHeight,
  }) {
    const cols = HubTileGridConfig.columns;
    const rows = HubTileGridConfig.rows;
    const gap = HubTileGridConfig.spacing;
    final cellW = (canvasWidth - gap * (cols - 1)) / cols;
    final cellH = (canvasHeight - gap * (rows - 1)) / rows;
    return (cellW, cellH);
  }

  static ({double left, double top, double width, double height}) pixelRect({
    required HubTileGridRect grid,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    final (cellW, cellH) = cellSize(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
    const gap = HubTileGridConfig.spacing;
    return (
      left: grid.col * (cellW + gap),
      top: grid.row * (cellH + gap),
      width: grid.colSpan * cellW + (grid.colSpan - 1) * gap,
      height: grid.rowSpan * cellH + (grid.rowSpan - 1) * gap,
    );
  }

  static HubTileGridRect? cellAtLocalPoint({
    required double localX,
    required double localY,
    required double canvasWidth,
    required double canvasHeight,
    required int colSpan,
    required int rowSpan,
  }) {
    final (cellW, cellH) = cellSize(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
    const gap = HubTileGridConfig.spacing;
    var col = ((localX) / (cellW + gap)).floor();
    var row = ((localY) / (cellH + gap)).floor();
    col = col.clamp(0, HubTileGridConfig.columns - colSpan);
    row = row.clamp(0, HubTileGridConfig.rows - rowSpan);
    final rect = HubTileGridRect(
      col: col,
      row: row,
      colSpan: colSpan,
      rowSpan: rowSpan,
    );
    return rect.isValid ? rect : null;
  }
}
