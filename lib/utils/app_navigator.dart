import 'package:flutter/material.dart';

/// Navigator globale dell'app (dialog / snackbar senza context locale).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

BuildContext? get appNavigatorContext => appNavigatorKey.currentContext;
