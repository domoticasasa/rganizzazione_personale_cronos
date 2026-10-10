import 'package:flutter/material.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/gestopro_mode_prefs.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/cronos_app_background.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_shell_scope.dart';

/// Shell GESTOPRO attiva (scope figlio o sessione).
bool isGestoproFuturisticUi(BuildContext context) =>
    FuturisticShellScope.hideChromeOf(context) ||
    GestoproModePrefs.sessionActive;

/// Orologio/calendario in AppBar classica (tap → stesso popup Gestopro).
/// Su mobile/viewport stretto resta fuori: troppo largo e si sovrappone al titolo.
bool showClassicAppBarClock(BuildContext context) {
  if (isGestoproFuturisticUi(context)) return false;
  if (useMobileUi(context)) return false;
  if (!shouldShowClassicRail(context)) return false;
  final w = MediaQuery.sizeOf(context).width;
  if (w < 900) return false;
  return true;
}

/// Scaffold classico vs GESTOPRO (toolbar inline, senza treno/sfondo chiaro).
Widget buildGestoproAwarePage({
  required BuildContext context,
  required String title,
  List<Widget> toolbarActions = const <Widget>[],
  PreferredSizeWidget? classicAppBar,
  required Widget body,
  bool lightVeilOverTrain = true,
  bool classicUseTrainBackground = true,
  Color? gestoproScaffoldColor,
  Widget Function(BuildContext context, Widget body)? wrapClassicBody,
}) {
  if (isGestoproFuturisticUi(context)) {
    return FuturisticThemedContent(
      child: Scaffold(
        backgroundColor: gestoproScaffoldColor ?? Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FuturisticInlineToolbar(
              title: title,
              actions: toolbarActions,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget classicBody = body;
  if (wrapClassicBody != null) {
    classicBody = wrapClassicBody(context, body);
  } else if (!classicUseTrainBackground) {
    classicBody = body;
  } else if (lightVeilOverTrain) {
    classicBody = Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: CronosAppBackground()),
        ColoredBox(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
          child: body,
        ),
      ],
    );
  } else {
    classicBody = Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: CronosAppBackground()),
        body,
      ],
    );
  }

  return Scaffold(
    appBar: wrapClassicAppBarChrome(
      context,
      classicAppBar ??
          AppBar(
            title: Text(title),
            actions: toolbarActions.isEmpty
                ? null
                : List<Widget>.from(toolbarActions),
          ),
    ),
    body: classicBody,
  );
}
