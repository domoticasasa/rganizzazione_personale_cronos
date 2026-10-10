import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/web_push_service.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/gestopro_tap_sound.dart';
import '../../utils/responsive.dart';
import 'glowing_border_shell.dart';

/// Footer con status bar e CTA notifiche.
class FuturisticFooter extends StatefulWidget {
  const FuturisticFooter({super.key});

  @override
  State<FuturisticFooter> createState() => _FuturisticFooterState();
}

class _FuturisticFooterState extends State<FuturisticFooter>
    with WidgetsBindingObserver {
  String _notificationPermission = 'unsupported';
  bool _pushRegistered = false;
  bool _busy = false;
  Timer? _permissionPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      WebPushService.addPermissionChangeListener(_onPermissionChanged);
    }
    _refreshPermission(force: true);
    _startPermissionPoll();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WebPushService.removePermissionChangeListener(_onPermissionChanged);
    }
    _permissionPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission(force: true);
    }
  }

  void _startPermissionPoll() {
    if (!kIsWeb) return;
    _permissionPoll?.cancel();
    _permissionPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_notificationPermission == 'granted' && _pushRegistered) {
        _permissionPoll?.cancel();
        _permissionPoll = null;
        return;
      }
      _refreshPermission();
    });
  }

  void _onPermissionChanged() {
    if (!mounted) return;
    _refreshPermission(force: true);
  }

  void _refreshPermission({bool force = false}) {
    if (!kIsWeb) return;
    final next = WebPushService.isBrowserNotificationGranted
        ? 'granted'
        : WebPushService.notificationPermission;
    final registered = WebPushService.isPushRegisteredOnThisDevice;
    if (!mounted) return;
    if (!force &&
        next == _notificationPermission &&
        registered == _pushRegistered) {
      return;
    }
    setState(() {
      _notificationPermission = next;
      _pushRegistered = registered;
    });
    if (next == 'granted' && registered) {
      _permissionPoll?.cancel();
      _permissionPoll = null;
    }
  }

  Future<void> _enableBrowserNotifications() async {
    if (!kIsWeb || _busy) return;
    setState(() => _busy = true);
    try {
      final granted = await WebPushService.requestBrowserPermissionFromUser();
      if (!granted) {
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          _refreshPermission(force: true);
          if (_notificationPermission == 'granted' && _pushRegistered) break;
        }
      } else {
        _refreshPermission(force: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _notificationPermission = WebPushService.isBrowserNotificationGranted
              ? 'granted'
              : WebPushService.notificationPermission;
          _pushRegistered = WebPushService.isPushRegisteredOnThisDevice;
        });
        if (_notificationPermission == 'granted' && _pushRegistered) {
          _permissionPoll?.cancel();
          _permissionPoll = null;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < CronosBreakpoints.tablet;
    final notificationsGranted = kIsWeb &&
        (WebPushService.isBrowserNotificationGranted ||
            _notificationPermission == 'granted');
    // iOS web (Safari in scheda): niente CTA «Installa Home».
    final hideIosInstallCta = WebPushService.isIosSafariTabWithoutHomeScreen;
    final showNotificationCta = kIsWeb &&
        !hideIosInstallCta &&
        (!notificationsGranted || !_pushRegistered);
    final ctaLabel = !notificationsGranted
        ? (compact ? 'Notifiche' : 'Abilita notifiche browser')
        : (compact ? 'Registra push' : 'Registra push (tab chiusa)');

    return GlowingBorderShell(
      color: CronosFuturisticTheme.borderGlow,
      strokeWidth: 2,
      borderRadius: 12,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              CronosFuturisticTheme.electricBlue.withValues(alpha: 0.1),
              Colors.transparent,
            ],
          ),
        ),
        child: compact
            ? _buildCompactRow(showNotificationCta, ctaLabel)
            : _buildWideRow(showNotificationCta, ctaLabel),
      ),
    );
  }

  Widget _buildWideRow(bool showNotificationCta, String ctaLabel) {
    return Row(
      children: [
        Icon(
          Icons.shield_outlined,
          size: 14,
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 8),
        Text('Sicurezza', style: _tag()),
        const _FooterDot(),
        Text('Controllo', style: _tag()),
        const _FooterDot(),
        Text('Efficienza', style: _tag()),
        const Spacer(),
        _StatusDot(label: 'ONLINE', color: CronosFuturisticTheme.neonGreen),
        if (showNotificationCta) ...[
          const SizedBox(width: 14),
          _BrowserNotificationsButton(
            busy: _busy,
            label: ctaLabel,
            onPressed: wrapGestoproTap(_enableBrowserNotifications),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactRow(bool showNotificationCta, String ctaLabel) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 12,
                  color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text('Sicurezza', style: _tag(compact: true)),
                const _FooterDot(),
                Text('Controllo', style: _tag(compact: true)),
                const _FooterDot(),
                Text('Efficienza', style: _tag(compact: true)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StatusDot(
          label: 'ONLINE',
          color: CronosFuturisticTheme.neonGreen,
          compact: true,
        ),
        if (showNotificationCta) ...[
          const SizedBox(width: 8),
          _BrowserNotificationsButton(
            busy: _busy,
            compact: true,
            label: ctaLabel,
            onPressed: wrapGestoproTap(_enableBrowserNotifications),
          ),
        ],
      ],
    );
  }

  TextStyle _tag({bool compact = false}) => CronosFonts.exo2(
        color: Colors.white38,
        fontSize: compact ? 9 : 10,
        letterSpacing: 0.5,
      );
}

class _BrowserNotificationsButton extends StatelessWidget {
  const _BrowserNotificationsButton({
    required this.busy,
    required this.onPressed,
    required this.label,
    this.compact = false,
  });

  final bool busy;
  final VoidCallback? onPressed;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [
                CronosFuturisticTheme.electricBlue,
                CronosFuturisticTheme.electricBright,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: CronosFuturisticTheme.electricBright.withValues(
                  alpha: 0.45,
                ),
                blurRadius: 14,
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: CronosFonts.exo2(
                    color: Colors.white,
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color, blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: CronosFonts.orbitron(
            fontSize: compact ? 7 : 8,
            color: color.withValues(alpha: 0.85),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
