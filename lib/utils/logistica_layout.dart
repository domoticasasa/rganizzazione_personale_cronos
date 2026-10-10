import 'package:flutter/material.dart';

import 'responsive.dart';

/// Layout compatto per pagine Logistica: card/lista invece di tabelle larghe.
bool isLogisticaCompactLayout(
  BuildContext context, {
  bool force = false,
}) {
  if (force) return true;
  return useCompactDataLayout(context);
}

/// Larghezza campi filtro / ricerca adattata al viewport.
double logisticaFieldWidth(
  BuildContext context, {
  double desktop = 320,
  double horizontalPadding = 32,
}) {
  final w = MediaQuery.sizeOf(context).width;
  if (isLogisticaCompactLayout(context)) {
    return (w - horizontalPadding).clamp(200.0, w);
  }
  return desktop.clamp(200.0, w * 0.45);
}

/// Larghezza dialog form logistica.
double logisticaDialogWidth(
  BuildContext context, {
  double desktop = 520,
}) {
  return cronosDialogWidth(context, desktop: desktop);
}

/// Tabella o griglia larga con scroll orizzontale nel viewport disponibile.
Widget logisticaScrollableTable({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(8, 0, 8, 8),
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      return Padding(
        padding: padding,
        child: Scrollbar(
          thumbVisibility: !cronosIsPhone(context),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Barra filtri: [Wrap] su schermo stretto, [Row] su desktop.
Widget logisticaFilterBar({
  required BuildContext context,
  required List<Widget> children,
  double spacing = 8,
  double runSpacing = 8,
}) {
  if (isLogisticaCompactLayout(context)) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(width: spacing),
        Flexible(child: children[i]),
      ],
    ],
  );
}
