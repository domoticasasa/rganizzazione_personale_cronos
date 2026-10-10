import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_chat_overlay_controller.dart';
import '../services/auth_qr_pending.dart';
import '../services/gestopro_splash_sound.dart';
import '../services/password_recovery_gate.dart';
import '../widgets/gestopro_intro_splash.dart';
import '../theme/cronos_app_themes.dart';

/// Splash all'apertura app: intro premium Gestopro360, poi login.
class GestoproSplashPage extends StatefulWidget {
  const GestoproSplashPage({super.key});

  @override
  State<GestoproSplashPage> createState() => _GestoproSplashPageState();
}

class _GestoproSplashPageState extends State<GestoproSplashPage> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    AppChatOverlayController.splashBlocking.value = true;
    // QR login PC: salta lo splash e vai subito al login/conferma.
    if (PasswordRecoveryGate.shouldOpenResetPage ||
        AuthQrPending.hasPendingCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goNext());
    } else {
      unawaited(_playSound());
    }
  }

  Future<void> _playSound() async {
    try {
      await GestoproSplashSound.prepare();
      await GestoproSplashSound.play();
    } catch (_) {}
  }

  void _goNext() {
    if (!mounted || _navigated) return;
    _navigated = true;
    AppChatOverlayController.clearSplashBlock();
    if (PasswordRecoveryGate.shouldOpenResetPage) {
      Navigator.of(context).pushReplacementNamed('/password-recovery');
      return;
    }
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  void dispose() {
    AppChatOverlayController.clearSplashBlock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PasswordRecoveryGate.shouldOpenResetPage) {
      return Scaffold(
        backgroundColor: CronosAppThemes.canvasOf(context),
        body: const SizedBox.expand(),
      );
    }
    return Scaffold(
      backgroundColor: CronosAppThemes.canvasOf(context),
      body: GestoproIntroSplash(
        duration: GestoproIntroSplash.defaultDuration,
        glowIntensity: GestoproIntroSplash.defaultGlowIntensity,
        onPointerDown: () => unawaited(_playSound()),
        onFinished: _goNext,
      ),
    );
  }
}
