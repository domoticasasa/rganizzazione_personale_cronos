import 'package:flutter/material.dart';

import 'futuristic_nav_sub_item.dart';

typedef FuturisticNavSubItemsRegistrar = void Function(
  List<FuturisticNavSubItem> items, {
  String? activeSubKey,
});

/// Permette alle pagine figlie di pubblicare i sotto-pulsanti nella sidebar.
class FuturisticNavSubItemsScope extends InheritedWidget {
  const FuturisticNavSubItemsScope({
    super.key,
    required this.register,
    required super.child,
  });

  final FuturisticNavSubItemsRegistrar register;

  static FuturisticNavSubItemsScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        FuturisticNavSubItemsScope>();
  }

  @override
  bool updateShouldNotify(FuturisticNavSubItemsScope oldWidget) => false;
}
