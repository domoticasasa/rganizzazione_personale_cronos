import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/app_branding_service.dart';
import '../../services/gestopro_ambient_sound_service.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/gestopro_tap_sound.dart';
import '../../utils/responsive.dart';
import '../app_logo.dart';
import '../ui_view_mode_switch.dart';
import '../user_profile_avatar.dart';
import 'glowing_border_shell.dart';
import 'nexus_clock.dart';

/// Command bar con titolo shimmer e orologio HUD.
class FuturisticTopBar extends StatefulWidget {
  const FuturisticTopBar({
    super.key,
    required this.userName,
    required this.username,
    required this.role,
    this.usersTableId,
    this.onSettings,
    this.onNotifiche,
    this.onVideo,
    this.onSwitchToClassic,
    this.switchToClassicTooltip,
    this.onOpenDipendente,
    this.onOpenDtView,
  });

  final String userName;
  final String username;
  final String role;
  final int? usersTableId;
  final void Function(BuildContext anchor)? onSettings;
  final VoidCallback? onNotifiche;
  final VoidCallback? onVideo;
  final VoidCallback? onSwitchToClassic;
  /// Tooltip al passaggio del mouse sul pulsante griglia (uscita / vista classica).
  final String? switchToClassicTooltip;
  final VoidCallback? onOpenDipendente;
  final VoidCallback? onOpenDtView;

  @override
  State<FuturisticTopBar> createState() => _FuturisticTopBarState();
}

class _FuturisticTopBarState extends State<FuturisticTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    unawaited(GestoproAmbientSoundService.loadMutePreference());
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final topBar = AppBrandingService.instance.topBarColor;
        final glow = Color.lerp(
              topBar,
              CronosFuturisticTheme.borderGlow,
              0.35,
            ) ??
            CronosFuturisticTheme.borderGlow;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < CronosBreakpoints.tablet;
            final ultraCompact = constraints.maxWidth <
                CronosBreakpoints.ultraCompactAppBar + 48;
            return GlowingBorderShell(
              color: glow,
              strokeWidth: 2,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : null,
                    height: compact ? 58 : 76,
                    padding:
                        EdgeInsets.symmetric(horizontal: compact ? 6 : 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          topBar.withValues(alpha: 0.42),
                          CronosFuturisticTheme.voidBg.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (Navigator.canPop(context))
                          _iconBtn(
                            Icons.arrow_back_ios_new_rounded,
                            () => Navigator.maybePop(context),
                            tooltip: 'Indietro',
                            compact: compact,
                          ),
                        if (!ultraCompact) ...[
                          NexusClock(compact: compact),
                          SizedBox(width: compact ? 4 : 6),
                          NexusAgendaPill(compact: compact),
                        ],
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedBuilder(
                                animation: _shimmer,
                                builder: (context, _) {
                                  final shift = _shimmer.value;
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!compact) ...[
                                        CronosWordmark(
                                          height: 38,
                                          textColor: Colors.white,
                                          fontSize: 13.5,
                                        ),
                                      ],
                                      ShaderMask(
                                        shaderCallback: (bounds) {
                                          return LinearGradient(
                                            begin: Alignment(-1 + shift * 2, 0),
                                            end: Alignment(shift * 2, 0),
                                            colors: const [
                                              Colors.white54,
                                              Colors.white,
                                              CronosFuturisticTheme.neonCyan,
                                              Colors.white,
                                              Colors.white54,
                                            ],
                                          ).createShader(bounds);
                                        },
                                        child: Text(
                                          'GESTOPRO',
                                          style: CronosFonts.orbitron(
                                            fontSize: compact ? 15 : 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: compact ? 2 : 6,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                      ),
                    ),
                    if (widget.onVideo != null)
                      _iconBtn(
                        Icons.video_library_outlined,
                        widget.onVideo!,
                        tooltip: 'Video',
                        compact: compact,
                      ),
                    if (widget.onNotifiche != null)
                      _iconBtn(
                        Icons.notifications_active_outlined,
                        widget.onNotifiche!,
                        tooltip: 'Notifiche',
                        compact: compact,
                      ),
                    _ambientMuteBtn(compact: compact),
                    if (widget.onSwitchToClassic != null)
                      Padding(
                        padding: EdgeInsets.only(
                          left: 2,
                          right: compact ? 2 : 4,
                        ),
                        child: UiViewModeSwitch(
                          gestoproSelected: true,
                          lightOnDark: true,
                          compact: true,
                          onSelectClassic: widget.onSwitchToClassic,
                        ),
                      ),
                    if (compact)
                      _overflowMenu(compact: compact)
                    else ...[
                      if (widget.onOpenDtView != null)
                        _iconBtn(
                          Icons.assignment_ind_outlined,
                          widget.onOpenDtView!,
                          tooltip: 'Vista DT',
                          compact: compact,
                        ),
                      if (widget.onSettings != null) _settingsBtn(compact: compact),
                    ],
                    SizedBox(width: compact ? 4 : 10),
                    _UserChip(
                      name: widget.userName,
                      username: widget.username,
                      role: widget.role,
                      usersTableId: widget.usersTableId,
                      onTap: widget.onOpenDipendente,
                      compact: compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
      },
    );
  }

  Widget _overflowMenu({required bool compact}) {
    final items = <PopupMenuEntry<void>>[];
    if (widget.onVideo != null) {
      items.add(
        PopupMenuItem<void>(
          onTap: wrapGestoproTap(widget.onVideo),
          child: const Text('Video'),
        ),
      );
    }
    if (widget.onOpenDtView != null) {
      items.add(
        PopupMenuItem<void>(
          onTap: wrapGestoproTap(widget.onOpenDtView),
          child: const Text('Vista DT'),
        ),
      );
    }
    if (widget.onSettings != null) {
      items.add(
        PopupMenuItem<void>(
          onTap: () {
            final ctx = context;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              widget.onSettings!(ctx);
            });
          },
          child: const Text('Impostazioni rapide'),
        ),
      );
    }
    if (widget.onSwitchToClassic != null) {
      items.add(
        PopupMenuItem<void>(
          onTap: wrapGestoproTap(widget.onSwitchToClassic),
          child: Text(
            widget.switchToClassicTooltip ?? 'Interfaccia classica',
          ),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<void>(
      tooltip: 'Altro',
      icon: Icon(
        Icons.more_vert,
        color: CronosFuturisticTheme.neonCyan,
        size: compact ? 20 : 22,
      ),
      color: CronosFuturisticTheme.voidBg,
      itemBuilder: (context) => items,
    );
  }

  Widget _ambientMuteBtn({required bool compact}) {
    return ValueListenableBuilder<bool>(
      valueListenable: GestoproAmbientSoundService.muted,
      builder: (context, isMuted, _) {
        return _iconBtn(
          isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          () => unawaited(GestoproAmbientSoundService.toggleMuted()),
          tooltip: isMuted ? 'Attiva sottofondo' : 'Silenzia sottofondo',
          compact: compact,
        );
      },
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    bool compact = false,
  }) {
    final btn = IconButton(
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: compact ? const EdgeInsets.all(6) : null,
      constraints: compact
          ? const BoxConstraints(minWidth: 32, minHeight: 32)
          : null,
      onPressed: wrapGestoproPressed(onTap),
      icon: Icon(icon, color: CronosFuturisticTheme.neonCyan, size: 20),
    );
    if (tooltip == null) return btn;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 280),
      child: btn,
    );
  }

  Widget _settingsBtn({bool compact = false}) {
    return Builder(
      builder: (btnCtx) => Tooltip(
        message: 'Impostazioni rapide',
        waitDuration: const Duration(milliseconds: 280),
        child: IconButton(
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          padding: compact ? const EdgeInsets.all(6) : null,
          constraints: compact
              ? const BoxConstraints(minWidth: 32, minHeight: 32)
              : null,
          onPressed: wrapGestoproPressed(() => widget.onSettings!(btnCtx)),
          icon: const Icon(
            Icons.tune,
            color: CronosFuturisticTheme.neonCyan,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({
    required this.name,
    required this.username,
    required this.role,
    this.usersTableId,
    this.onTap,
    this.compact = false,
  });

  final String name;
  final String username;
  final String role;
  final int? usersTableId;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final avatar = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.5),
        ),
      ),
      child: SessionUserAvatar(
        radius: compact ? 12 : 14,
        displayName: name,
        username: username,
        usersTableId: usersTableId,
      ),
    );

    if (compact) {
      final avatarOnly = onTap == null
          ? avatar
          : Tooltip(
              message: '$name\n$role',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: wrapGestoproTap(onTap),
                  customBorder: const CircleBorder(),
                  child: avatar,
                ),
              ),
            );
      return avatarOnly;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: CronosFuturisticTheme.electricBright.withValues(alpha: 0.35),
        ),
        color: CronosFuturisticTheme.electricBlue.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CronosFonts.exo2(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  role.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CronosFonts.exo2(
                    color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.6),
                    fontSize: 8,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;

    return Tooltip(
      message: 'Vista dipendente',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: wrapGestoproTap(onTap),
          borderRadius: BorderRadius.circular(20),
          child: chip,
        ),
      ),
    );
  }
}
