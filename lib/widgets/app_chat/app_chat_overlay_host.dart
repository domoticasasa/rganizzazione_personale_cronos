import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_chat_overlay_controller.dart';
import '../../services/app_chat_service.dart';
import '../../utils/app_chat_deep_link.dart';
import '../../utils/app_chat_web_bridge.dart';
import 'app_chat_fab.dart';
import 'app_chat_panel.dart';

/// Layer globale: FAB nuvoletta + pannello chat (nascosto senza sessione).
class AppChatOverlayHost extends StatefulWidget {
  const AppChatOverlayHost({
    super.key,
    required this.child,
    this.forceHide = false,
  });

  final Widget child;
  final bool forceHide;

  @override
  State<AppChatOverlayHost> createState() => _AppChatOverlayHostState();
}

class _AppChatOverlayHostState extends State<AppChatOverlayHost> {
  StreamSubscription<AuthState>? _authSub;
  bool _hasSession = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _hasSession = Supabase.instance.client.auth.currentSession != null;
    unawaited(AppChatOverlayController.ensureFabPositionLoaded());
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final has = data.session != null;
      if (!mounted) return;
      setState(() => _hasSession = has);
      if (!has) {
        AppChatOverlayController.close();
        unawaited(_stopChat());
      } else {
        // Non toccare splashBlocking qui: altrimenti il FAB compare sullo splash
        // se c'è già una sessione salvata.
        unawaited(_startChat());
      }
    });
    if (_hasSession && !widget.forceHide) {
      unawaited(_startChat());
    }
  }

  Future<void> _startChat() async {
    if (_started || widget.forceHide) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    _started = true;
    // Chrome Android PWA: badge Home + apertura da notifica/scorciatoia.
    AppChatOverlayController.ensureWebBadgeSync();
    installAppChatWebBridge(
      onOpenChat: () {
        if (!mounted) return;
        AppChatDeepLink.markPending();
        _maybeOpenFromDeepLink();
      },
    );
    if (consumeJsPendingOpenChat()) {
      AppChatDeepLink.markPending();
    }
    await AppChatService.instance.start();
    _maybeOpenFromDeepLink();
  }

  void _maybeOpenFromDeepLink() {
    if (!AppChatDeepLink.consumePendingOpen()) return;
    // Dopo splash: attendi che la UI chat sia montabile.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (AppChatOverlayController.splashBlocking.value) {
        void listener() {
          if (AppChatOverlayController.splashBlocking.value) return;
          AppChatOverlayController.splashBlocking.removeListener(listener);
          unawaited(AppChatOverlayController.tryOpen(context));
        }

        AppChatOverlayController.splashBlocking.addListener(listener);
        return;
      }
      unawaited(AppChatOverlayController.tryOpen(context));
    });
  }

  Future<void> _stopChat() async {
    if (!_started) return;
    _started = false;
    await AppChatService.instance.stop();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppChatOverlayController.splashBlocking,
      builder: (context, splash, _) {
        final showChatUi =
            !widget.forceHide && _hasSession && !splash;

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (showChatUi)
              ValueListenableBuilder<bool>(
                valueListenable: AppChatOverlayController.isOpen,
                builder: (context, open, _) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (open) const AppChatPanel(),
                      const AppChatFab(),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
