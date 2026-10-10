import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Tipi di asset brand caricabili su Storage.
enum AppBrandingAssetKind {
  logo,
  logoLight,
  bgLandscape,
  bgPortrait,
}

extension AppBrandingAssetKindX on AppBrandingAssetKind {
  String get pathColumn => switch (this) {
        AppBrandingAssetKind.logo => 'logo_path',
        AppBrandingAssetKind.logoLight => 'logo_light_path',
        AppBrandingAssetKind.bgLandscape => 'bg_landscape_path',
        AppBrandingAssetKind.bgPortrait => 'bg_portrait_path',
      };

  String get storagePrefix => switch (this) {
        AppBrandingAssetKind.logo => 'logo',
        AppBrandingAssetKind.logoLight => 'logo_light',
        AppBrandingAssetKind.bgLandscape => 'bg_landscape',
        AppBrandingAssetKind.bgPortrait => 'bg_portrait',
      };
}

/// Snapshot branding organizzazione (singleton DB `app_branding` id=1).
class AppBrandingSnapshot {
  const AppBrandingSnapshot({
    required this.brandName,
    required this.productName,
    required this.appTitle,
    required this.welcomeSubtitle,
    required this.accentColorHex,
    required this.logoBarColorHex,
    required this.topBarColorHex,
    required this.sidebarColorHex,
    this.copyrightShort,
    this.copyrightFull,
    this.logoPath,
    this.logoLightPath,
    this.bgLandscapePath,
    this.bgPortraitPath,
  });

  final String brandName;
  final String productName;
  final String appTitle;
  final String welcomeSubtitle;
  final String accentColorHex;
  final String logoBarColorHex;
  final String topBarColorHex;
  final String sidebarColorHex;
  final String? copyrightShort;
  final String? copyrightFull;
  final String? logoPath;
  final String? logoLightPath;
  final String? bgLandscapePath;
  final String? bgPortraitPath;

  static const AppBrandingSnapshot defaults = AppBrandingSnapshot(
    brandName: 'CRONOS',
    productName: 'GESTOPRO360',
    appTitle: 'Cronos Gestopro360',
    welcomeSubtitle: '',
    accentColorHex: '#1565C0',
    logoBarColorHex: '#00AEEF',
    topBarColorHex: '#1565C0',
    sidebarColorHex: '#EEF3FA',
  );

  static const String defaultCopyrightShortFallback =
      'GESTOPRO. Tutti i diritti riservati.';

  static String defaultCopyrightFullFor(String product) =>
      'Tutti i diritti riservati.\n\n'
      'REGOLE DI UTILIZZO\n\n'
      '1. Proprietà\n'
      'Il software, l\'interfaccia, il marchio $product, i loghi, '
      'la documentazione e i contenuti correlati sono protetti dalle norme '
      'sul diritto d\'autore e sulla proprietà industriale.\n\n'
      '2. Uso consentito\n'
      'L\'accesso è consentito solo agli utenti autorizzati, per le finalità '
      'aziendali previste. Le credenziali sono personali e non vanno '
      'condivise.\n\n'
      '3. Divieti\n'
      'È vietata la copia, la modifica, la distribuzione, il reverse '
      'engineering, la sublicenza o qualsiasi uso non autorizzato, in tutto '
      'o in parte, senza previo consenso scritto del titolare.\n\n'
      '4. Dati e privacy\n'
      'I dati trattati nell\'applicazione devono essere usati nel rispetto '
      'delle policy aziendali e della normativa applicabile.\n\n'
      '5. Responsabilità\n'
      'L\'utente è responsabile delle operazioni eseguite con il proprio '
      'account.';

  factory AppBrandingSnapshot.fromMap(Map<String, dynamic> m) {
    String? s(String key) {
      final v = (m[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    String req(String key, String fallback) {
      final v = s(key);
      return (v == null || v.isEmpty) ? fallback : v;
    }

    return AppBrandingSnapshot(
      brandName: req('brand_name', defaults.brandName),
      productName: req('product_name', defaults.productName),
      appTitle: req('app_title', defaults.appTitle),
      welcomeSubtitle: s('welcome_subtitle') ?? '',
      accentColorHex: req('accent_color', defaults.accentColorHex),
      logoBarColorHex: req('logo_bar_color', defaults.logoBarColorHex),
      topBarColorHex: req('top_bar_color', defaults.topBarColorHex),
      sidebarColorHex: req('sidebar_color', defaults.sidebarColorHex),
      copyrightShort: s('copyright_short'),
      copyrightFull: s('copyright_full'),
      logoPath: s('logo_path'),
      logoLightPath: s('logo_light_path'),
      bgLandscapePath: s('bg_landscape_path'),
      bgPortraitPath: s('bg_portrait_path'),
    );
  }

  Map<String, dynamic> toUpsertMap({int? updatedBy}) {
    return <String, dynamic>{
      'id': 1,
      'brand_name': brandName.trim().isEmpty ? defaults.brandName : brandName.trim(),
      'product_name':
          productName.trim().isEmpty ? defaults.productName : productName.trim(),
      'app_title': appTitle.trim().isEmpty ? defaults.appTitle : appTitle.trim(),
      'welcome_subtitle': welcomeSubtitle.trim(),
      'accent_color': _normalizeHex(accentColorHex) ?? defaults.accentColorHex,
      'logo_bar_color':
          _normalizeHex(logoBarColorHex) ?? defaults.logoBarColorHex,
      'top_bar_color':
          _normalizeHex(topBarColorHex) ?? defaults.topBarColorHex,
      'sidebar_color':
          _normalizeHex(sidebarColorHex) ?? defaults.sidebarColorHex,
      'copyright_short': copyrightShort?.trim(),
      'copyright_full': copyrightFull?.trim(),
      'logo_path': logoPath,
      'logo_light_path': logoLightPath,
      'bg_landscape_path': bgLandscapePath,
      'bg_portrait_path': bgPortraitPath,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': ?updatedBy,
    };
  }

  AppBrandingSnapshot copyWith({
    String? brandName,
    String? productName,
    String? appTitle,
    String? welcomeSubtitle,
    String? accentColorHex,
    String? logoBarColorHex,
    String? topBarColorHex,
    String? sidebarColorHex,
    String? copyrightShort,
    String? copyrightFull,
    String? logoPath,
    String? logoLightPath,
    String? bgLandscapePath,
    String? bgPortraitPath,
    bool clearCopyrightShort = false,
    bool clearCopyrightFull = false,
    bool clearLogoPath = false,
    bool clearLogoLightPath = false,
    bool clearBgLandscapePath = false,
    bool clearBgPortraitPath = false,
  }) {
    return AppBrandingSnapshot(
      brandName: brandName ?? this.brandName,
      productName: productName ?? this.productName,
      appTitle: appTitle ?? this.appTitle,
      welcomeSubtitle: welcomeSubtitle ?? this.welcomeSubtitle,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      logoBarColorHex: logoBarColorHex ?? this.logoBarColorHex,
      topBarColorHex: topBarColorHex ?? this.topBarColorHex,
      sidebarColorHex: sidebarColorHex ?? this.sidebarColorHex,
      copyrightShort:
          clearCopyrightShort ? null : (copyrightShort ?? this.copyrightShort),
      copyrightFull:
          clearCopyrightFull ? null : (copyrightFull ?? this.copyrightFull),
      logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
      logoLightPath:
          clearLogoLightPath ? null : (logoLightPath ?? this.logoLightPath),
      bgLandscapePath: clearBgLandscapePath
          ? null
          : (bgLandscapePath ?? this.bgLandscapePath),
      bgPortraitPath:
          clearBgPortraitPath ? null : (bgPortraitPath ?? this.bgPortraitPath),
    );
  }
}

String? _normalizeHex(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.startsWith('#')) s = '#$s';
  if (s.length == 4) {
    // #RGB -> #RRGGBB
    s = '#${s[1]}${s[1]}${s[2]}${s[2]}${s[3]}${s[3]}';
  }
  if (s.length != 7) return null;
  final ok = RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s);
  return ok ? s.toUpperCase() : null;
}

Color parseBrandHex(String hex, {Color fallback = const Color(0xFF1565C0)}) {
  final n = _normalizeHex(hex);
  if (n == null) return fallback;
  final v = int.tryParse(n.substring(1), radix: 16);
  if (v == null) return fallback;
  return Color(0xFF000000 | v);
}

/// Branding organizzazione: cache + notify UI.
class AppBrandingService extends ChangeNotifier {
  AppBrandingService._();
  static final AppBrandingService instance = AppBrandingService._();

  static const String bucket = 'app_branding';
  static const String table = 'app_branding';

  AppBrandingSnapshot _data = AppBrandingSnapshot.defaults;
  bool _loaded = false;
  bool _loading = false;

  AppBrandingSnapshot get data => _data;
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  String get brandName => _data.brandName;
  String get productName => _data.productName;
  String get appTitle => _data.appTitle;
  String get welcomeSubtitle => _data.welcomeSubtitle;

  Color get accentColor =>
      parseBrandHex(_data.accentColorHex, fallback: const Color(0xFF1565C0));
  Color get logoBarColor =>
      parseBrandHex(_data.logoBarColorHex, fallback: const Color(0xFF00AEEF));
  Color get topBarColor =>
      parseBrandHex(_data.topBarColorHex, fallback: const Color(0xFF1565C0));
  Color get sidebarColor =>
      parseBrandHex(_data.sidebarColorHex, fallback: const Color(0xFFEEF3FA));

  /// Accent sidebar GESTOPRO (derivato dalla barra superiore se non custom neon).
  Color get chromeAccentColor => topBarColor;

  String get copyrightShort {
    final custom = _data.copyrightShort?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return '${_data.productName}. Tutti i diritti riservati.';
  }

  String get copyrightFull {
    final custom = _data.copyrightFull?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return AppBrandingSnapshot.defaultCopyrightFullFor(_data.productName);
  }

  String? publicUrlFor(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;
    try {
      return SupabaseService.client.storage.from(bucket).getPublicUrl(p);
    } catch (_) {
      return null;
    }
  }

  ImageProvider? imageProviderFor(String? path) {
    final url = publicUrlFor(path);
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  ImageProvider? get logoImageProvider => imageProviderFor(_data.logoPath);
  bool get hasDedicatedLogoLight =>
      (_data.logoLightPath ?? '').trim().isNotEmpty;
  ImageProvider? get dedicatedLogoLightImageProvider =>
      imageProviderFor(_data.logoLightPath);
  ImageProvider? get logoLightImageProvider =>
      dedicatedLogoLightImageProvider ?? logoImageProvider;
  ImageProvider? get bgLandscapeImageProvider =>
      imageProviderFor(_data.bgLandscapePath);
  ImageProvider? get bgPortraitImageProvider =>
      imageProviderFor(_data.bgPortraitPath);

  String? pathFor(AppBrandingAssetKind kind) => switch (kind) {
        AppBrandingAssetKind.logo => _data.logoPath,
        AppBrandingAssetKind.logoLight => _data.logoLightPath,
        AppBrandingAssetKind.bgLandscape => _data.bgLandscapePath,
        AppBrandingAssetKind.bgPortrait => _data.bgPortraitPath,
      };

  /// Carica da Supabase; in caso di errore resta sui default.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final row = await SupabaseService.client
          .from(table)
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row != null) {
        _data = AppBrandingSnapshot.fromMap(Map<String, dynamic>.from(row));
      } else {
        _data = AppBrandingSnapshot.defaults;
      }
      _loaded = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AppBrandingService.load: $e');
      }
      _data = AppBrandingSnapshot.defaults;
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<int?> _currentUserId() async {
    try {
      final authId = SupabaseService.client.auth.currentUser?.id;
      if (authId == null) return null;
      final row = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      return (row?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(AppBrandingSnapshot next) async {
    final uid = await _currentUserId();
    final payload = next.toUpsertMap(updatedBy: uid);
    await SupabaseService.client.from(table).upsert(payload);
    _data = next;
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveTextsAndColors({
    required String brandName,
    required String productName,
    required String appTitle,
    required String welcomeSubtitle,
    required String accentColorHex,
    required String logoBarColorHex,
    required String topBarColorHex,
    required String sidebarColorHex,
    String? copyrightShort,
    String? copyrightFull,
  }) async {
    final next = _data.copyWith(
      brandName: brandName,
      productName: productName,
      appTitle: appTitle,
      welcomeSubtitle: welcomeSubtitle,
      accentColorHex: accentColorHex,
      logoBarColorHex: logoBarColorHex,
      topBarColorHex: topBarColorHex,
      sidebarColorHex: sidebarColorHex,
      copyrightShort: copyrightShort,
      copyrightFull: copyrightFull,
      clearCopyrightShort: (copyrightShort ?? '').trim().isEmpty,
      clearCopyrightFull: (copyrightFull ?? '').trim().isEmpty,
    );
    await saveSnapshot(next);
  }

  Future<void> uploadAsset({
    required AppBrandingAssetKind kind,
    required Uint8List bytes,
    required String ext,
    String? mimeType,
  }) async {
    final cleanExt = ext.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final safeExt = cleanExt.isEmpty ? 'png' : cleanExt;
    final objectPath =
        '${kind.storagePrefix}_${DateTime.now().toUtc().millisecondsSinceEpoch}.$safeExt';
    final contentType = mimeType ??
        switch (safeExt) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'webp' => 'image/webp',
          'gif' => 'image/gif',
          _ => 'image/png',
        };

    final oldPath = pathFor(kind);
    await SupabaseService.client.storage.from(bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    AppBrandingSnapshot next;
    switch (kind) {
      case AppBrandingAssetKind.logo:
        next = _data.copyWith(logoPath: objectPath);
      case AppBrandingAssetKind.logoLight:
        next = _data.copyWith(logoLightPath: objectPath);
      case AppBrandingAssetKind.bgLandscape:
        next = _data.copyWith(bgLandscapePath: objectPath);
      case AppBrandingAssetKind.bgPortrait:
        next = _data.copyWith(bgPortraitPath: objectPath);
    }
    await saveSnapshot(next);

    if (oldPath != null && oldPath.isNotEmpty && oldPath != objectPath) {
      try {
        await SupabaseService.client.storage.from(bucket).remove([oldPath]);
      } catch (_) {}
    }
  }

  Future<void> clearAsset(AppBrandingAssetKind kind) async {
    final oldPath = pathFor(kind);
    AppBrandingSnapshot next;
    switch (kind) {
      case AppBrandingAssetKind.logo:
        next = _data.copyWith(clearLogoPath: true);
      case AppBrandingAssetKind.logoLight:
        next = _data.copyWith(clearLogoLightPath: true);
      case AppBrandingAssetKind.bgLandscape:
        next = _data.copyWith(clearBgLandscapePath: true);
      case AppBrandingAssetKind.bgPortrait:
        next = _data.copyWith(clearBgPortraitPath: true);
    }
    await saveSnapshot(next);
    if (oldPath != null && oldPath.isNotEmpty) {
      try {
        await SupabaseService.client.storage.from(bucket).remove([oldPath]);
      } catch (_) {}
    }
  }

  Future<void> resetToDefaults() async {
    final paths = <String>[
      if ((_data.logoPath ?? '').isNotEmpty) _data.logoPath!,
      if ((_data.logoLightPath ?? '').isNotEmpty) _data.logoLightPath!,
      if ((_data.bgLandscapePath ?? '').isNotEmpty) _data.bgLandscapePath!,
      if ((_data.bgPortraitPath ?? '').isNotEmpty) _data.bgPortraitPath!,
    ];
    await saveSnapshot(AppBrandingSnapshot.defaults);
    if (paths.isNotEmpty) {
      try {
        await SupabaseService.client.storage.from(bucket).remove(paths);
      } catch (_) {}
    }
  }
}
