import 'package:flutter/material.dart';

import '../utils/responsive.dart';
import 'classic_app_bar_chrome.dart';

/// Centra e limita la larghezza del contenuto su schermi larghi (web / Windows).
class CronosAdaptiveContent extends StatelessWidget {
  const CronosAdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final effectiveMax = maxWidth ?? cronosContentMaxWidth(context);
    final hPad = cronosPageHorizontalPadding(context);
    final effectivePadding =
        padding ?? EdgeInsets.symmetric(horizontal: hPad, vertical: 8);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMax.isFinite ? effectiveMax : double.infinity,
        ),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );
  }
}

/// Scaffold con body adattivo e padding coerente su tutti i form factor.
class CronosAdaptiveScaffold extends StatelessWidget {
  const CronosAdaptiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.constrainBody = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final bool constrainBody;

  @override
  Widget build(BuildContext context) {
    final content = constrainBody
        ? CronosAdaptiveContent(child: body)
        : body;

    return Scaffold(
      appBar: appBar == null ? null : wrapClassicAppBarChrome(context, appBar!),
      drawer: drawer,
      endDrawer: endDrawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: content,
      ),
    );
  }
}
