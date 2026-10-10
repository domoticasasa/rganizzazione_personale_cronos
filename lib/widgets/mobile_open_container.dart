import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../utils/futuristic_navigation.dart';
import '../utils/mobile_navigation.dart';

/// Container Transform (Material) per navigazione mobile: il pulsante/card si espande nella pagina.
class MobileOpenContainer extends StatelessWidget {
  const MobileOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.destination,
    this.onClosed,
    this.closedColor,
    this.openColor,
    this.transitionDuration = const Duration(milliseconds: 450),
    this.closedBorderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  /// Widget chiuso (card/pulsante). Riceve [openContainer] per aprire la transizione.
  final Widget Function(BuildContext context, VoidCallback openContainer) closedBuilder;

  /// Pagina di destinazione (tipicamente uno [Scaffold]).
  final Widget destination;

  final VoidCallback? onClosed;
  final Color? closedColor;
  final Color? openColor;
  final Duration transitionDuration;
  final BorderRadius closedBorderRadius;

  static Color closedColorFor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  static Color openColorFor(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  @override
  Widget build(BuildContext context) {
    final closed = closedColor ?? closedColorFor(context);
    final open = openColor ?? openColorFor(context);

    if (!useMobileUi(context)) {
      return closedBuilder(
        context,
        () => _pushFallback(context),
      );
    }

    return OpenContainer(
      transitionDuration: transitionDuration,
      transitionType: ContainerTransitionType.fade,
      closedColor: closed,
      openColor: open,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(borderRadius: closedBorderRadius),
      openShape: const RoundedRectangleBorder(),
      onClosed: (_) => onClosed?.call(),
      closedBuilder: (context, openContainer) =>
          closedBuilder(context, openContainer),
      openBuilder: (context, _) => destination,
    );
  }

  Future<void> _pushFallback(BuildContext context) async {
    await FuturisticNavigation.pushPage<void>(
      context,
      page: destination,
    );
    onClosed?.call();
  }
}
