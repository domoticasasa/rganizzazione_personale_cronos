import 'package:flutter/material.dart';

/// Scrollbar collegata a un [ScrollController] condiviso: evita errori
/// «ScrollController has no ScrollPosition attached» al primo frame.
class LinkedScrollbar extends StatefulWidget {
  const LinkedScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
    this.thumbVisibility = true,
  });

  final ScrollController controller;
  final Widget child;
  final Axis axis;
  final bool thumbVisibility;

  @override
  State<LinkedScrollbar> createState() => _LinkedScrollbarState();
}

class _LinkedScrollbarState extends State<LinkedScrollbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant LinkedScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showThumb =
        widget.thumbVisibility && widget.controller.hasClients;
    return Scrollbar(
      controller: widget.controller,
      thumbVisibility: showThumb,
      notificationPredicate: (notification) =>
          notification.metrics.axis == widget.axis,
      child: widget.child,
    );
  }
}
