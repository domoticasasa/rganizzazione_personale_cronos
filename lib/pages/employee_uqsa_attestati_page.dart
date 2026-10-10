import 'dart:math' as math;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import '../services/uqsa_attestati_service.dart';
import '../utils/date_formatters.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/user_profile_avatar.dart';

/// Area dipendente: elenco e download attestati RFI + D.Lgs. 81/08.
class EmployeeUqsaAttestatiPage extends StatefulWidget {
  final int userId;
  final String fullName;
  final bool forceMobileLayout;

  const EmployeeUqsaAttestatiPage({
    super.key,
    required this.userId,
    required this.fullName,
    this.forceMobileLayout = false,
  });

  @override
  State<EmployeeUqsaAttestatiPage> createState() =>
      _EmployeeUqsaAttestatiPageState();
}

class _EmployeeUqsaAttestatiPageState extends State<EmployeeUqsaAttestatiPage>
    with TickerProviderStateMixin {
  static const _ink = Color(0xFF0B1F33);
  static const _accentRfi = Color(0xFF1B6CA8);
  static const _accentL81 = Color(0xFF0F766E);
  static const _gold = Color(0xFFC9A227);

  bool _loading = true;
  String? _error;
  List<UqsaAttestato> _rows = const <UqsaAttestato>[];
  String? _filterTipo;
  String? _busyId;

  late final AnimationController _introCtrl;

  bool get _compact => widget.forceMobileLayout || useMobileUi(context);

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _load();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    super.dispose();
  }

  Future<String?> _resolvePersonaleUuid() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return null;
    try {
      final p1 = await SupabaseService.client
          .from('personale')
          .select('id_uuid')
          .eq('user_id', authUser.id)
          .maybeSingle();
      final pid1 = (p1?['id_uuid'] ?? '').toString().trim();
      if (pid1.isNotEmpty) return pid1;

      final u = await SupabaseService.client
          .from('users')
          .select('id, id_uuid')
          .eq('auth_id', authUser.id)
          .maybeSingle();
      final uid = (u?['id'] ?? '').toString();
      final uuid = (u?['id_uuid'] ?? '').toString();
      if (uid.isNotEmpty) {
        final p2 = await SupabaseService.client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', uid)
            .maybeSingle();
        final pid2 = (p2?['id_uuid'] ?? '').toString().trim();
        if (pid2.isNotEmpty) return pid2;
      }
      if (uuid.isNotEmpty) {
        final p3 = await SupabaseService.client
            .from('personale')
            .select('id_uuid')
            .eq('user_id', uuid)
            .maybeSingle();
        final pid3 = (p3?['id_uuid'] ?? '').toString().trim();
        if (pid3.isNotEmpty) return pid3;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pid = await _resolvePersonaleUuid();
      if (pid == null || pid.isEmpty) {
        setState(() {
          _rows = const [];
          _error = 'Impossibile risolvere l’anagrafica dipendente.';
          _loading = false;
        });
        return;
      }
      final rows = await UqsaAttestatiService.loadForPersonale(pid);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
      _introCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Caricamento non riuscito: $e';
        _loading = false;
      });
    }
  }

  List<UqsaAttestato> get _filtered {
    final t = _filterTipo;
    final list = t == null
        ? List<UqsaAttestato>.from(_rows)
        : _rows.where((r) => r.tipo == t).toList();
    list.sort((a, b) {
      final ta = a.tipo == kUqsaAttestatoTipoRfi
          ? 0
          : (a.tipo == kUqsaAttestatoTipoL81 ? 1 : 2);
      final tb = b.tipo == kUqsaAttestatoTipoRfi
          ? 0
          : (b.tipo == kUqsaAttestatoTipoL81 ? 1 : 2);
      if (ta != tb) return ta.compareTo(tb);
      return b.uploadedAt.compareTo(a.uploadedAt);
    });
    return list;
  }

  List<UqsaAttestato> get _rfiRows => _rows
      .where((r) => r.tipo == kUqsaAttestatoTipoRfi)
      .toList(growable: false);
  List<UqsaAttestato> get _l81Rows => _rows
      .where((r) => r.tipo == kUqsaAttestatoTipoL81)
      .toList(growable: false);

  int get _countRfi =>
      _rows.where((r) => r.tipo == kUqsaAttestatoTipoRfi).length;
  int get _countL81 =>
      _rows.where((r) => r.tipo == kUqsaAttestatoTipoL81).length;

  Color _accentFor(String tipo) {
    if (tipo == kUqsaAttestatoTipoRfi) return _accentRfi;
    if (tipo == kUqsaAttestatoTipoL81) return _accentL81;
    return _ink;
  }

  Future<void> _view(UqsaAttestato row) async {
    setState(() => _busyId = row.id);
    try {
      if (row.isImage) {
        final bytes = await UqsaAttestatiService.downloadBytes(row);
        if (!mounted) return;
        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Chiudi',
          barrierColor: Colors.black.withValues(alpha: 0.72),
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (ctx, a1, a2) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
              child: Material(
                color: CronosAppThemes.cardOf(ctx),
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: _ink,
                      child: ListTile(
                        title: Text(
                          row.titolo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          row.fileName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        child: Center(child: Image.memory(bytes)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          transitionBuilder: (ctx, anim, _, child) {
            final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: c,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(c),
                child: child,
              ),
            );
          },
        );
        return;
      }
      final url = await UqsaAttestatiService.signedUrl(row);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!launched && mounted) {
        ModifyFeedback.error(context, 'Impossibile aprire il file');
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Apertura non riuscita: $e');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _download(UqsaAttestato row) async {
    setState(() => _busyId = row.id);
    try {
      final bytes = await UqsaAttestatiService.downloadBytes(row);
      final name = row.fileName;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 && dot < name.length - 1
          ? name.substring(dot + 1)
          : (row.isPdf ? 'pdf' : 'bin');
      final base = dot >= 0 ? name.substring(0, dot) : name;
      await FileSaver.instance.saveFile(
        name: base.isEmpty ? row.titolo : base,
        bytes: bytes,
        ext: ext,
        mimeType: row.isPdf
            ? MimeType.pdf
            : (ext == 'png'
                ? MimeType.png
                : (ext == 'jpg' || ext == 'jpeg'
                    ? MimeType.jpeg
                    : MimeType.other)),
      );
      if (mounted) {
        ModifyFeedback.success(context, 'Download avviato');
      }
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Download non riuscito: $e');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.fullName.trim();
    final padH = _compact ? 16.0 : 28.0;
    final wide = !_compact && MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      backgroundColor: CronosAppThemes.canvasOf(context),
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'I miei attestati',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      body: _loading
          ? const _LoadingVault()
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _VaultHero(
                      compact: _compact,
                      fullName: name.isEmpty ? 'Dipendente' : name,
                      usersTableId: widget.userId,
                      total: _rows.length,
                      countRfi: _countRfi,
                      countL81: _countL81,
                      animation: _introCtrl,
                      filterTipo: _filterTipo,
                      onSelectRfi: () => setState(
                        () => _filterTipo = kUqsaAttestatoTipoRfi,
                      ),
                      onSelectL81: () => setState(
                        () => _filterTipo = kUqsaAttestatoTipoL81,
                      ),
                      onSelectAll: () => setState(() => _filterTipo = null),
                      onFilterChanged: (v) => setState(() => _filterTipo = v),
                    ),
                  ),
                  if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyVault(
                        icon: Icons.cloud_off_rounded,
                        title: 'Qualcosa non ha funzionato',
                        message: _error!,
                        actionLabel: 'Riprova',
                        onAction: _load,
                      ),
                    )
                  else if (_filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyVault(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Cassaforte vuota',
                        message: _rows.isEmpty
                            ? 'Appena l’amministrazione caricherà i tuoi attestati '
                                'RFI e D.Lgs. 81/08, appariranno qui pronti da aprire o scaricare.'
                            : 'Nessun file in questa categoria. Prova “Tutti”.',
                      ),
                    )
                  else if (wide && _filterTipo == null)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padH, 8, padH, 36),
                      sliver: SliverToBoxAdapter(
                        child: _DualColumns(
                          rfi: _rfiRows,
                          l81: _l81Rows,
                          busyId: _busyId,
                          onView: _view,
                          onDownload: _download,
                          animation: _introCtrl,
                        ),
                      ),
                    )
                  else if (_filterTipo == null)
                    ..._groupedSlivers(
                      padH: padH,
                      compact: _compact,
                      rfi: _rfiRows,
                      l81: _l81Rows,
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(padH, 8, padH, 36),
                      sliver: SliverList.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final row = _filtered[i];
                          return _CertificateCard(
                            row: row,
                            accent: _accentFor(row.tipo),
                            compact: _compact,
                            busy: _busyId == row.id,
                            index: i,
                            animation: _introCtrl,
                            onView: () => _view(row),
                            onDownload: () => _download(row),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  List<Widget> _groupedSlivers({
    required double padH,
    required bool compact,
    required List<UqsaAttestato> rfi,
    required List<UqsaAttestato> l81,
  }) {
    final out = <Widget>[];
    void addGroup({
      required String title,
      required Color accent,
      required IconData icon,
      required List<UqsaAttestato> items,
      required int indexOffset,
    }) {
      if (items.isEmpty) return;
      out.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padH, 14, padH, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: accent.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      out.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, 4),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final row = items[i];
              return _CertificateCard(
                row: row,
                accent: accent,
                compact: compact,
                busy: _busyId == row.id,
                index: indexOffset + i,
                animation: _introCtrl,
                onView: () => _view(row),
                onDownload: () => _download(row),
              );
            },
          ),
        ),
      );
    }

    addGroup(
      title: 'RFI',
      accent: _accentRfi,
      icon: Icons.train_rounded,
      items: rfi,
      indexOffset: 0,
    );
    addGroup(
      title: 'D.Lgs. 81/08',
      accent: _accentL81,
      icon: Icons.health_and_safety_rounded,
      items: l81,
      indexOffset: rfi.length,
    );
    out.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));
    return out;
  }
}

/* ───────────────────────────── Hero ───────────────────────────── */

class _VaultHero extends StatelessWidget {
  const _VaultHero({
    required this.compact,
    required this.fullName,
    required this.usersTableId,
    required this.total,
    required this.countRfi,
    required this.countL81,
    required this.animation,
    required this.filterTipo,
    required this.onSelectRfi,
    required this.onSelectL81,
    required this.onSelectAll,
    required this.onFilterChanged,
  });

  final bool compact;
  final String fullName;
  final int usersTableId;
  final int total;
  final int countRfi;
  final int countL81;
  final Animation<double> animation;
  final String? filterTipo;
  final VoidCallback onSelectRfi;
  final VoidCallback onSelectL81;
  final VoidCallback onSelectAll;
  final ValueChanged<String?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(fade);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0B1F33),
                    Color(0xFF123A56),
                    Color(0xFF0F766E),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -36,
                    top: -24,
                    child: _SoftOrb(
                      size: compact ? 110 : 180,
                      color: const Color(0xFFC9A227).withValues(alpha: 0.16),
                    ),
                  ),
                  Positioned(
                    left: -40,
                    bottom: -10,
                    child: _SoftOrb(
                      size: compact ? 90 : 140,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  const Positioned.fill(
                    child: CustomPaint(painter: _MeshPainter()),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 28,
                      compact ? 12 : 22,
                      compact ? 16 : 28,
                      compact ? 18 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: compact ? 46 : 60,
                              height: compact ? 46 : 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE8C547),
                                    Color(0xFFC9A227),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFC9A227)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: ClipOval(
                                child: ColoredBox(
                                  color: const Color(0xFF0B1F33),
                                  child: SessionUserAvatar(
                                    radius: compact ? 20.5 : 27.5,
                                    displayName: fullName,
                                    usersTableId: usersTableId,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cassaforte attestati',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    fullName,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compact ? 19 : 26,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 14),
                          Text(
                            'I tuoi documenti formativi in un unico posto. '
                            'Apri in anteprima o scarica quando ti servono.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                        SizedBox(height: compact ? 12 : 18),
                        Row(
                          children: [
                            Expanded(
                              child: _HeroStatTile(
                                label: 'Totale',
                                value: '$total',
                                icon: Icons.folder_special_rounded,
                                compact: compact,
                                selected: filterTipo == null,
                                onTap: onSelectAll,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _HeroStatTile(
                                label: 'RFI',
                                value: '$countRfi',
                                icon: Icons.train_rounded,
                                tint: const Color(0xFF5EB1E8),
                                compact: compact,
                                selected: filterTipo == kUqsaAttestatoTipoRfi,
                                onTap: onSelectRfi,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _HeroStatTile(
                                label: '81/08',
                                value: '$countL81',
                                icon: Icons.health_and_safety_rounded,
                                tint: const Color(0xFF5EEAD4),
                                compact: compact,
                                selected: filterTipo == kUqsaAttestatoTipoL81,
                                onTap: onSelectL81,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Transizione morbida + filtri agganciati
            Transform.translate(
              offset: const Offset(0, -14),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: CronosAppThemes.canvasOf(context),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 28,
                  18,
                  compact ? 16 : 28,
                  0,
                ),
                child: _SegmentedFilter(
                  selected: filterTipo,
                  total: total,
                  countRfi: countRfi,
                  countL81: countL81,
                  onChanged: onFilterChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.tint,
    this.compact = false,
    this.selected = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? const Color(0xFFE8C547);
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 8 : 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: compact ? 15 : 17, color: c),
              SizedBox(height: compact ? 4 : 7),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  const _MeshPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* ───────────────────────────── Filter bar ───────────────────────────── */

class _SegmentedFilter extends StatelessWidget {
  const _SegmentedFilter({
    required this.selected,
    required this.total,
    required this.countRfi,
    required this.countL81,
    required this.onChanged,
  });

  final String? selected;
  final int total;
  final int countRfi;
  final int countL81;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CronosAppThemes.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1F33).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _Seg(
            label: 'Tutti',
            count: total,
            selected: selected == null,
            color: const Color(0xFF0B1F33),
            onTap: () => onChanged(null),
          ),
          _Seg(
            label: 'RFI',
            count: countRfi,
            selected: selected == kUqsaAttestatoTipoRfi,
            color: const Color(0xFF1B6CA8),
            onTap: () => onChanged(kUqsaAttestatoTipoRfi),
          ),
          _Seg(
            label: '81/08',
            count: countL81,
            selected: selected == kUqsaAttestatoTipoL81,
            color: const Color(0xFF0F766E),
            onTap: () => onChanged(kUqsaAttestatoTipoL81),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: selected ? Colors.white : color.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : color.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────────── Cards ───────────────────────────── */

class _DualColumns extends StatelessWidget {
  const _DualColumns({
    required this.rfi,
    required this.l81,
    required this.busyId,
    required this.onView,
    required this.onDownload,
    required this.animation,
  });

  final List<UqsaAttestato> rfi;
  final List<UqsaAttestato> l81;
  final String? busyId;
  final Future<void> Function(UqsaAttestato) onView;
  final Future<void> Function(UqsaAttestato) onDownload;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ColumnBlock(
            title: 'RFI',
            accent: const Color(0xFF1B6CA8),
            icon: Icons.train_rounded,
            items: rfi,
            busyId: busyId,
            onView: onView,
            onDownload: onDownload,
            animation: animation,
            indexOffset: 0,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _ColumnBlock(
            title: 'D.Lgs. 81/08',
            accent: const Color(0xFF0F766E),
            icon: Icons.health_and_safety_rounded,
            items: l81,
            busyId: busyId,
            onView: onView,
            onDownload: onDownload,
            animation: animation,
            indexOffset: rfi.length,
          ),
        ),
      ],
    );
  }
}

class _ColumnBlock extends StatelessWidget {
  const _ColumnBlock({
    required this.title,
    required this.accent,
    required this.icon,
    required this.items,
    required this.busyId,
    required this.onView,
    required this.onDownload,
    required this.animation,
    required this.indexOffset,
  });

  final String title;
  final Color accent;
  final IconData icon;
  final List<UqsaAttestato> items;
  final String? busyId;
  final Future<void> Function(UqsaAttestato) onView;
  final Future<void> Function(UqsaAttestato) onDownload;
  final Animation<double> animation;
  final int indexOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: accent,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: accent.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: CronosAppThemes.cardOf(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: Text(
              'Nessun attestato in questa sezione',
              style: TextStyle(color: accent.withValues(alpha: 0.65)),
            ),
          )
        else
          ...List.generate(items.length, (i) {
            final row = items[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
              child: _CertificateCard(
                row: row,
                accent: accent,
                compact: false,
                busy: busyId == row.id,
                index: indexOffset + i,
                animation: animation,
                onView: () => onView(row),
                onDownload: () => onDownload(row),
              ),
            );
          }),
      ],
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.row,
    required this.accent,
    required this.compact,
    required this.busy,
    required this.index,
    required this.animation,
    required this.onView,
    required this.onDownload,
  });

  final UqsaAttestato row;
  final Color accent;
  final bool compact;
  final bool busy;
  final int index;
  final Animation<double> animation;
  final VoidCallback onView;
  final VoidCallback onDownload;

  _ExpiryTone get _expiry {
    final d = row.dataScadenza;
    if (d == null) return _ExpiryTone.none;
    final today = DateTime.now();
    final only = DateTime(today.year, today.month, today.day);
    final days = d.difference(only).inDays;
    if (days < 0) return _ExpiryTone.expired;
    if (days <= 60) return _ExpiryTone.soon;
    return _ExpiryTone.ok;
  }

  @override
  Widget build(BuildContext context) {
    final start = math.min(0.12 + index * 0.05, 0.78);
    final end = math.min(start + 0.32, 1.0);
    final local = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final scad = row.dataScadenza;
    final scadLabel =
        scad == null ? null : formatDateDdMmYyyyFromDate(scad);
    final uploaded = formatDateDdMmYyyy(row.uploadedAt.toIso8601String());
    final sizeKb = row.fileSize == null
        ? null
        : (row.fileSize! / 1024).clamp(0.1, 99999).toDouble().toStringAsFixed(0);
    final tone = _expiry;
    final title = row.titolo.isEmpty ? row.fileName : row.titolo;

    return FadeTransition(
      opacity: local,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(local),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onView,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: CronosAppThemes.cardOf(context),
                border: Border.all(color: accent.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0B1F33).withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 14,
                  compact ? 11 : 13,
                  compact ? 10 : 12,
                  compact ? 10 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: compact ? 40 : 44,
                          height: compact ? 40 : 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                accent,
                                Color.lerp(accent, Colors.black, 0.16)!,
                              ],
                            ),
                          ),
                          child: Icon(
                            row.isPdf
                                ? Icons.picture_as_pdf_rounded
                                : (row.isImage
                                    ? Icons.image_rounded
                                    : Icons.description_rounded),
                            color: Colors.white,
                            size: compact ? 20 : 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      UqsaAttestatiService.tipoLabel(row.tipo),
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (sizeKb != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '$sizeKb KB',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: const Color(0xFF0B1F33)
                                            .withValues(alpha: 0.45),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 14 : 15,
                                  height: 1.2,
                                  color: const Color(0xFF0B1F33),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (scadLabel != null)
                                    'Scad. $scadLabel',
                                  'Caricato $uploaded',
                                ].join('  ·  '),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: switch (tone) {
                                    _ExpiryTone.expired =>
                                      const Color(0xFFB91C1C),
                                    _ExpiryTone.soon =>
                                      const Color(0xFFB45309),
                                    _ => const Color(0xFF64748B),
                                  },
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    if (busy)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.12),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onView,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide(
                                  color: accent.withValues(alpha: 0.3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.visibility_rounded,
                                  size: 16),
                              label: const Text('Apri'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: onDownload,
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.download_rounded,
                                  size: 16),
                              label: const Text('Scarica'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ExpiryTone { none, ok, soon, expired }

/* ───────────────────────────── Empty / loading ───────────────────────────── */

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0B1F33).withValues(alpha: 0.08),
                      const Color(0xFF0F766E).withValues(alpha: 0.12),
                    ],
                  ),
                ),
                child: Icon(icon, size: 40, color: const Color(0xFF0B1F33)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1F33),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  color: const Color(0xFF0B1F33).withValues(alpha: 0.65),
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B1F33),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingVault extends StatefulWidget {
  const _LoadingVault();

  @override
  State<_LoadingVault> createState() => _LoadingVaultState();
}

class _LoadingVaultState extends State<_LoadingVault>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _c,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFC9A227),
                  width: 3,
                ),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF0B1F33),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Apertura cassaforte…',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0B1F33).withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
