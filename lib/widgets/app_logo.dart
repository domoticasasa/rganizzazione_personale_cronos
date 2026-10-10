import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../services/app_branding_service.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/responsive.dart';
import 'futuristic/futuristic_shell_scope.dart';
import 'futuristic/nexus_clock.dart';
import 'premium_glass_hub.dart';
import 'user_profile_avatar.dart';

/// Osservatore route per ripetere l'effetto luce al ritorno indietro.
final RouteObserver<PageRoute<dynamic>> logoLightSweepRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Effetto luce sul logo grande in pagina (non usare in AppBar).
class LogoLightSweep extends StatefulWidget {
  const LogoLightSweep({
    super.key,
    required this.builder,
  });

  /// Due istanze distinte (base + maschera): non riusare lo stesso [Widget].
  final WidgetBuilder builder;

  @override
  State<LogoLightSweep> createState() => _LogoLightSweepState();
}

class _LogoLightSweepState extends State<LogoLightSweep>
    with SingleTickerProviderStateMixin, RouteAware {
  late final AnimationController _controller;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _route)) return;
    if (_route != null) {
      logoLightSweepRouteObserver.unsubscribe(this);
    }
    _route = route;
    logoLightSweepRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    logoLightSweepRouteObserver.unsubscribe(this);
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSweep() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _playSweep());
  }

  void _playSweep() {
    if (!mounted) return;
    _controller
      ..stop()
      ..reset();
    _controller.forward();
  }

  @override
  void didPush() => _scheduleSweep();

  @override
  void didPopNext() => _scheduleSweep();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        const band = 0.32;
        final center = t * (1.0 + band) - band / 2;
        final align = (center * 2 - 1).clamp(-1.0, 1.0);
        final base = widget.builder(context);
        // Copia bianca del logo mascherata dalla fascia luminosa: non tocca
        // trasparenze PNG né colori fuori dal passaggio.
        return Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.hardEdge,
          children: [
            base,
            Positioned.fill(
              child: IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment(align - band, 0),
                      end: Alignment(align + band, 0),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.85),
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.32, 0.5, 0.68, 1.0],
                    ).createShader(bounds);
                  },
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                    child: widget.builder(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Barra ciano sopra la «C» del marchio (default; override da branding).
const Color kCronosLogoBarBlue = Color(0xFF00AEEF);

Color get cronosLogoBarColor => AppBrandingService.instance.logoBarColor;

/// Tinta bianca sul PNG scuro (non sul wordmark di fallback).
const Color _kLogoOnDarkTint = Color(0xFFF5F7FB);

Widget _brandedLogoImage({
  required double height,
  double? width,
  required Widget fallback,
  bool preferLight = false,
}) {
  final branding = AppBrandingService.instance;
  final dedicatedLight =
      preferLight ? branding.dedicatedLogoLightImageProvider : null;
  final provider = dedicatedLight ??
      (preferLight
          ? branding.logoLightImageProvider
          : branding.logoImageProvider);
  if (provider == null) return fallback;
  final tintDarkRaster = preferLight && dedicatedLight == null;
  return Image(
    image: provider,
    width: width,
    height: height,
    fit: BoxFit.contain,
    color: tintDarkRaster ? _kLogoOnDarkTint : null,
    colorBlendMode: tintDarkRaster ? BlendMode.srcIn : null,
    errorBuilder: (_, _, _) => fallback,
  );
}

Widget _assetLogoImage({
  required double height,
  double? width,
  required Widget fallback,
  bool preferLight = false,
}) {
  return Image.asset(
    'assets/logo.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
    color: preferLight ? _kLogoOnDarkTint : null,
    colorBlendMode: preferLight ? BlendMode.srcIn : null,
    errorBuilder: (_, _, _) => fallback,
  );
}

/// Wordmark brand con barra accent sopra la prima lettera.
class CronosWordmark extends StatelessWidget {
  final double height;
  final Color textColor;
  final Color? barColor;
  final double? fontSize;

  const CronosWordmark({
    super.key,
    required this.height,
    required this.textColor,
    this.barColor,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final brand = AppBrandingService.instance.brandName;
        final fs = fontSize ?? (height * 0.36).clamp(10.0, 34.0);
        final barW = fs * 0.52;
        final barH = (fs * 0.11).clamp(2.0, 5.0);
        final gap = fs * 0.06;
        final bar = barColor ?? cronosLogoBarColor;

        return SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: barW,
                height: barH,
                decoration: BoxDecoration(
                  color: bar,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              SizedBox(height: gap),
              Text(
                brand,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  fontSize: fs,
                  height: 1,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Marchio combinato: GESTOPRO360 a sinistra, CRONOS a destra (UI classica).
class CronosGestoproWordmark extends StatelessWidget {
  const CronosGestoproWordmark({
    super.key,
    this.compact = false,
    this.lightOnDark = false,
  });

  final bool compact;
  final bool lightOnDark;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final product = AppBrandingService.instance.productName;
        final cronosColor = lightOnDark ? Colors.white : const Color(0xFF1A1F36);
        final gestoproColor =
            lightOnDark ? Colors.white70 : const Color(0xFF6B7280);
        final cronosH = compact ? 22.0 : 28.0;
        final cronosFs = compact ? 12.0 : 14.5;
        final gestoproFs = compact ? 8.0 : 10.0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              product,
              style: CronosFonts.orbitron(
                fontSize: gestoproFs,
                fontWeight: FontWeight.w700,
                letterSpacing: compact ? 0.8 : 1.2,
                color: gestoproColor,
                height: 1,
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            CronosWordmark(
              height: cronosH,
              textColor: cronosColor,
              fontSize: cronosFs,
            ),
          ],
        );
      },
    );
  }
}

/// Logo dell'app da mostrare in tutte le pagine (es. in AppBar).
class AppLogo extends StatelessWidget {
  final double size;
  final double? width;
  final bool? lightOnDark;
  /// Passaggio luce animato (AppBar e logo grandi).
  final bool lightSweep;

  const AppLogo({
    super.key,
    this.size = 48,
    this.width,
    this.lightOnDark,
    this.lightSweep = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final onDark = lightOnDark ??
            Theme.of(context).brightness == Brightness.dark;
        final branding = AppBrandingService.instance;
        final hasCustomLogo = branding.logoImageProvider != null ||
            branding.logoLightImageProvider != null;

        if (onDark && !hasCustomLogo) {
          final fs = (size * 0.36).clamp(10.0, 18.0);
          final wordmark = CronosWordmark(
            height: size,
            textColor: Colors.white,
            fontSize: fs,
          );
          final content = lightSweep
              ? LogoLightSweep(builder: (_) => wordmark)
              : wordmark;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: content,
          );
        }

        final fallback = Text(
          branding.brandName,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: onDark ? Colors.white : Colors.black87,
            fontSize: (size * 0.36).clamp(10.0, 18.0),
          ),
        );
        final w = width ?? (size * 2.4);
        final logo = _brandedLogoImage(
          height: size,
          width: w,
          preferLight: onDark,
          fallback: _assetLogoImage(
            height: size,
            width: w,
            preferLight: onDark,
            fallback: fallback,
          ),
        );
        final content = lightSweep ? LogoLightSweep(builder: (_) => logo) : logo;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: content,
        );
      },
    );
  }
}

/// Prima nascondeva il logo in verticale/mobile; ora il dual brand è compatto.
bool hidePageTopWordmarkOverBackground(BuildContext context) => false;

/// Logo in cima pagina: GESTOPRO360 a sinistra, CRONOS a destra.
class PageTopLogo extends StatelessWidget {
  final double size;

  const PageTopLogo({super.key, this.size = 144});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppBrandingService.instance,
      builder: (context, _) {
        final branding = AppBrandingService.instance;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final primary = Theme.of(context).colorScheme.primary;
        final muted = dark ? Colors.white70 : const Color(0xFF6B7280);
        final narrow = MediaQuery.sizeOf(context).width < 520;
        final compact = useMobileUi(context) || isMobileWebPlatform() || narrow;
        final orbitIcon = compact
            ? 48.0
            : (size * 0.48).clamp(52.0, 68.0);
        final cronosH = compact
            ? 44.0
            : (size * 0.52).clamp(56.0, 88.0);
        final cronosW = cronosH * 2.35;
        final fallback = CronosWordmark(
          height: cronosH,
          textColor: dark ? Colors.white : primary,
          fontSize: (cronosH * 0.42).clamp(16.0, 36.0),
        );
        final cronosLogo = LogoLightSweep(
          builder: (_) => _brandedLogoImage(
            height: cronosH,
            width: cronosW,
            preferLight: dark,
            fallback: _assetLogoImage(
              height: cronosH,
              width: cronosW,
              preferLight: dark,
              fallback: fallback,
            ),
          ),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(12, compact ? 6 : 10, 12, 4),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestoproOrbitBrandHeader(
                        iconSize: orbitIcon,
                        showTitle: true,
                        showTricolore: true,
                      ),
                      SizedBox(width: compact ? 14 : 28),
                      cronosLogo,
                    ],
                  ),
                ),
                if (branding.welcomeSubtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    branding.welcomeSubtitle.trim(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (size * 0.07).clamp(11.0, 14.0),
                      color: muted,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wrappa il contenuto della pagina con il logo grande in alto (effetto luce).
class PageWithTopLogo extends StatelessWidget {
  final Widget child;
  final bool showLogo;
  final double logoSize;

  const PageWithTopLogo({
    super.key,
    required this.child,
    this.showLogo = true,
    this.logoSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    final hideChrome = FuturisticShellScope.hideChromeOf(context);
    final paddedChild = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: useCompactDataLayout(context)
            ? cronosPageHorizontalPadding(context)
            : 0,
      ),
      child: child,
    );
    if (!showLogo ||
        hideChrome ||
        hidePageTopWordmarkOverBackground(context)) {
      return paddedChild;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTopLogo(size: logoSize),
        Expanded(child: paddedChild),
      ],
    );
  }
}

/// «Benvenuto …» con foto utente loggato (tesserino).
class WelcomeAppBarTitle extends StatelessWidget {
  final String fullName;
  final String username;
  final double avatarRadius;
  /// Se impostato, tap sulla foto apre l’hub dipendente (es. anteprima vista).
  final VoidCallback? onAvatarTap;

  const WelcomeAppBarTitle({
    super.key,
    required this.fullName,
    this.username = '',
    this.avatarRadius = 18,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    // Solo UI classica: in Gestopro il chrome è gestito dalla shell.
    if (FuturisticShellScope.hideChromeOf(context)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final compact = useMobileUi(context);
    final onDark = true; // AppBar classica sempre blu scuro
    final base = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
    final effectiveStyle = base?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: compact ? 15 : null,
      color: theme.colorScheme.onPrimary,
    );
    final radius = compact ? 14.0 : avatarRadius;
    Widget avatar = SessionUserAvatar(
      radius: radius,
      displayName: fullName,
      username: username,
    );
    if (onAvatarTap != null) {
      avatar = Tooltip(
        message: 'Vista dipendente',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: avatar,
          ),
        ),
      );
    }

    // Mobile: solo avatar + nome. Brand e orologio vanno in conflitto con
    // Classica/Gestopro e le actions (vedi screenshot AppBar sovrapposta).
    if (compact) {
      return Row(
        children: [
          avatar,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fullName.trim().isEmpty ? 'Home' : fullName.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: effectiveStyle,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        avatar,
        const SizedBox(width: 10),
        CronosGestoproWordmark(compact: compact, lightOnDark: onDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Benvenuto $fullName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effectiveStyle,
          ),
        ),
        if (showClassicAppBarClock(context)) ...[
          const SizedBox(width: 8),
          const NexusClock(compact: true),
          const SizedBox(width: 4),
          const NexusAgendaPill(compact: true),
        ],
      ],
    );
  }
}

/// Titolo AppBar responsive con logo Cronos + testo ellittico.
class ResponsiveAppBarTitle extends StatelessWidget {
  final String title;
  final double desktopLogoSize;
  final double mobileLogoSize;
  final bool? lightOnDark;
  final FontWeight fontWeight;
  final double? desktopFontSize;
  final double? mobileFontSize;

  const ResponsiveAppBarTitle({
    super.key,
    required this.title,
    this.desktopLogoSize = 44,
    this.mobileLogoSize = 28,
    this.lightOnDark,
    this.fontWeight = FontWeight.w600,
    this.desktopFontSize,
    this.mobileFontSize,
    this.showBrandAndClock = true,
  });

  /// Marchio CRONOS+GESTOPRO e orologio (disattivare su login).
  final bool showBrandAndClock;

  @override
  Widget build(BuildContext context) {
    if (FuturisticShellScope.hideChromeOf(context)) {
      return const SizedBox.shrink();
    }
    final compact = useMobileUi(context);
    final theme = Theme.of(context);
    final onDark = lightOnDark ?? true; // default: barra classica blu
    final base = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;
    final effectiveStyle = base?.copyWith(
      fontWeight: fontWeight,
      fontSize: compact ? (mobileFontSize ?? 16) : (desktopFontSize ?? 21),
      color: onDark ? theme.colorScheme.onPrimary : base.color,
    );
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effectiveStyle,
    );

    // Mobile: solo titolo — brand/orologio saturano la barra e si sovrappongono.
    if (compact) {
      return titleText;
    }

    if (!showBrandAndClock) {
      return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          AppLogo(
            size: desktopLogoSize,
            lightOnDark: onDark,
            lightSweep: true,
          ),
          const SizedBox(width: 8),
          Expanded(child: titleText),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        CronosGestoproWordmark(compact: false, lightOnDark: onDark),
        const SizedBox(width: 10),
        Expanded(child: titleText),
        if (showClassicAppBarClock(context)) ...[
          const SizedBox(width: 8),
          const NexusClock(compact: true),
          const SizedBox(width: 4),
          const NexusAgendaPill(compact: true),
        ],
      ],
    );
  }
}
