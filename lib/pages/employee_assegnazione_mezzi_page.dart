import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_assegnazione_mezzi_documenti_service.dart';
import '../services/mezzi_km_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/logistica_layout.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/user_profile_avatar.dart';
import '../utils/mezzo_tipologia_icon.dart';

/// Apre il popup PDF di assegnazione per un mezzo (riusabile da Il mio mezzo).
Future<void> showEmployeeAssegnazionePdfDialog(
  BuildContext context, {
  required Map<String, dynamic> row,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _EmployeeAssegnazionePdfDialog(row: row),
  );
}

/// Vista dipendente: mezzi assegnati + PDF di assegnazione (stile attestati).
class EmployeeAssegnazioneMezziPage extends StatefulWidget {
  final bool forceMobileLayout;

  const EmployeeAssegnazioneMezziPage({
    super.key,
    this.forceMobileLayout = false,
  });

  @override
  State<EmployeeAssegnazioneMezziPage> createState() =>
      _EmployeeAssegnazioneMezziPageState();
}

class _EmployeeAssegnazioneMezziPageState
    extends State<EmployeeAssegnazioneMezziPage>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF0B1F33);
  static const _accent = Color(0xFF1565C0);
  static const _teal = Color(0xFF0F766E);
  static const _gold = Color(0xFFC9A227);

  final _searchCtrl = TextEditingController();
  late final AnimationController _introCtrl;

  bool _loading = true;
  String? _error;
  String _search = '';
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, int> _pdfCounts = const {};
  String _myUserIdUuid = '';
  String _myNameNorm = '';

  bool get _compact => widget.forceMobileLayout || useMobileUi(context);

  String get _displayName {
    final n = ClassicNavSessionCache.current?.fullName.trim() ?? '';
    if (n.isNotEmpty) return n;
    return _myNameNorm.isEmpty ? 'Dipendente' : _myNameNorm;
  }

  int? get _usersTableId {
    final id = ClassicNavSessionCache.current?.userId;
    if (id == null || id <= 0) return null;
    return id;
  }

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _search = _searchCtrl.text.trim());
    });
  }

  Future<void> _bootstrap() async {
    final ident = await MezziKmService.loadCurrentUserIdentity();
    if (!mounted) return;
    _myUserIdUuid = ident.uuid;
    _myNameNorm = ident.nameNorm;
    await _load();
  }

  bool _isMine(Map<String, dynamic> row) {
    return MezziKmService.isRowAssignedToCurrentUser(
      row,
      _myUserIdUuid,
      _myNameNorm,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('logistica_mezzi_stradali')
          .select(
            'id_uuid,numerazione,targa,marca,modello,tipologia_mezzo,'
            'assegnatario_attuale,assegnatario_user_uuid,'
            'periodo_assegnatario_attuale,data_fine_assegnatario_attuale,'
            'multicard,telepass,note',
          )
          .order('numerazione', ascending: true);
      Map<String, int> counts = const {};
      try {
        counts =
            await LogisticaAssegnazioneMezziDocumentiService.countByMezzo();
      } catch (_) {}
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      ).where(_isMine).toList(growable: false);
      setState(() {
        _rows = list;
        _pdfCounts = counts;
        _loading = false;
      });
      _introCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final k = _search.toLowerCase();
    if (k.isEmpty) return _rows;
    return _rows.where((r) {
      final fields = [
        r['numerazione'],
        r['targa'],
        r['marca'],
        r['modello'],
        r['tipologia_mezzo'],
        r['note'],
      ].map((v) => (v ?? '').toString().toLowerCase());
      return fields.any((f) => f.contains(k));
    }).toList(growable: false);
  }

  int get _withPdfCount {
    var n = 0;
    for (final r in _rows) {
      final id = (r['id_uuid'] ?? '').toString();
      if ((_pdfCounts[id] ?? 0) > 0) n++;
    }
    return n;
  }

  String _mezzoLabel(Map<String, dynamic> row) => mezzoLabelFromParts(
        targa: (row['targa'] ?? '').toString(),
        marca: (row['marca'] ?? '').toString(),
        modello: (row['modello'] ?? '').toString(),
      );

  Future<void> _openDocs(Map<String, dynamic> row) async {
    await showEmployeeAssegnazionePdfDialog(context, row: row);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final padH = _compact ? 14.0 : 22.0;
    final name = _displayName;

    return Scaffold(
      backgroundColor: CronosAppThemes.canvasOf(context),
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'La mia assegnazione',
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
          ? const _EmpLoading()
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _EmpHero(
                      compact: _compact,
                      fullName: name,
                      usersTableId: _usersTableId,
                      total: _rows.length,
                      withPdf: _withPdfCount,
                      animation: _introCtrl,
                    ),
                  ),
                  if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmpEmpty(
                        icon: Icons.cloud_off_rounded,
                        title: 'Qualcosa non ha funzionato',
                        message: _error!,
                        actionLabel: 'Riprova',
                        onAction: _load,
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(padH, 12, padH, 4),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Cerca targa o mezzo…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _ink.withValues(alpha: 0.08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _ink.withValues(alpha: 0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: _accent,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmpEmpty(
                          icon: Icons.directions_car_outlined,
                          title: _rows.isEmpty
                              ? 'Nessun mezzo assegnato'
                              : 'Nessun risultato',
                          message: _rows.isEmpty
                              ? 'Quando Logistica ti assegnerà un mezzo stradale, '
                                  'lo troverai qui con i documenti di assegnazione '
                                  'pronti da aprire o scaricare.'
                              : 'Prova un’altra ricerca.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(padH, 10, padH, 36),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            final id = (row['id_uuid'] ?? '').toString();
                            return _VehicleCard(
                              label: _mezzoLabel(row),
                              tipologia:
                                  (row['tipologia_mezzo'] ?? '').toString(),
                              inizio: formatDateDdMmYyyy(
                                row['periodo_assegnatario_attuale'],
                              ),
                              fine: formatDateDdMmYyyy(
                                row['data_fine_assegnatario_attuale'],
                              ),
                              pdfCount: _pdfCounts[id] ?? 0,
                              compact: _compact,
                              index: i,
                              animation: _introCtrl,
                              onOpen: () => _openDocs(row),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _EmpHero extends StatelessWidget {
  const _EmpHero({
    required this.compact,
    required this.fullName,
    required this.usersTableId,
    required this.total,
    required this.withPdf,
    required this.animation,
  });

  final bool compact;
  final String fullName;
  final int? usersTableId;
  final int total;
  final int withPdf;
  final Animation<double> animation;

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
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0B1F33),
                Color(0xFF123A56),
                Color(0xFF1565C0),
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
                                'Documenti di assegnazione',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
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
                        'Consulta il mezzo assegnato e scarica il PDF '
                        'di assegnazione quando ti serve.',
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
                          child: _StatTile(
                            label: 'Mezzi',
                            value: '$total',
                            icon: Icons.directions_car_filled_rounded,
                            compact: compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatTile(
                            label: 'Con PDF',
                            value: '$withPdf',
                            icon: Icons.picture_as_pdf_rounded,
                            compact: compact,
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
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.compact,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: compact ? 18 : 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 16 : 18,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.label,
    required this.tipologia,
    required this.inizio,
    required this.fine,
    required this.pdfCount,
    required this.compact,
    required this.index,
    required this.animation,
    required this.onOpen,
  });

  final String label;
  final String tipologia;
  final String inizio;
  final String fine;
  final int pdfCount;
  final bool compact;
  final int index;
  final Animation<double> animation;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final start = math.min(0.12 + index * 0.05, 0.78);
    final end = math.min(start + 0.32, 1.0);
    final local = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final accent = pdfCount > 0
        ? _EmployeeAssegnazioneMezziPageState._teal
        : _EmployeeAssegnazioneMezziPageState._accent;
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
            onTap: onOpen,
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
                        _MezzoTipoBadge(
                          tipologia: tipologia,
                          color: accent,
                          size: compact ? 46 : 50,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 14.5 : 15.5,
                                  color: const Color(0xFF0B1F33),
                                  height: 1.2,
                                ),
                              ),
                              if (tipologia.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    tipologia.trim().toUpperCase(),
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (pdfCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf,
                                  color: accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$pdfCount',
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Icon(
                            Icons.picture_as_pdf_outlined,
                            color: Colors.black.withValues(alpha: 0.28),
                            size: 22,
                          ),
                      ],
                    ),
                    if (inizio.isNotEmpty || fine.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (inizio.isNotEmpty)
                            _MetaChip(
                              icon: Icons.event_available_rounded,
                              text: 'Inizio $inizio',
                            ),
                          if (fine.isNotEmpty)
                            _MetaChip(
                              icon: Icons.event_busy_rounded,
                              text: 'Fine $fine',
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: Icon(
                          pdfCount > 0
                              ? Icons.folder_open_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          pdfCount > 0
                              ? 'Apri / scarica PDF'
                              : 'Dettagli assegnazione',
                        ),
                        style: FilledButton.styleFrom(
                          foregroundColor: accent,
                          backgroundColor: accent.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.black54),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _EmpEmpty extends StatelessWidget {
  const _EmpEmpty({
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
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 34, color: const Color(0xFF1565C0)),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF0B1F33),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmpLoading extends StatelessWidget {
  const _EmpLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFFC9A227)),
    );
  }
}

class _MezzoTipoBadge extends StatelessWidget {
  const _MezzoTipoBadge({
    required this.tipologia,
    required this.color,
    this.size = 48,
  });

  final String tipologia;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, Colors.black, 0.18)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: mezzoTipologiaIcon(
        tipologia,
        color: Colors.white,
        size: size * 0.52,
      ),
    );
  }
}

class _EmployeeAssegnazionePdfDialog extends StatefulWidget {
  const _EmployeeAssegnazionePdfDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_EmployeeAssegnazionePdfDialog> createState() =>
      _EmployeeAssegnazionePdfDialogState();
}

class _EmployeeAssegnazionePdfDialogState
    extends State<_EmployeeAssegnazionePdfDialog> {
  bool _loading = true;
  List<AssegnazioneMezzoDocumento> _docs = const [];

  String get _mezzoId => (widget.row['id_uuid'] ?? '').toString().trim();

  String get _mezzoLabel => mezzoLabelFromParts(
        targa: (widget.row['targa'] ?? '').toString(),
        marca: (widget.row['marca'] ?? '').toString(),
        modello: (widget.row['modello'] ?? '').toString(),
      );

  String _friendlyName(String raw) {
    var n = raw.trim().replaceAll(r'\', '/');
    if (n.contains('/')) n = n.split('/').last;
    n = n.replaceAll(RegExp(r'_signed', caseSensitive: false), '');
    n = n.replaceAll(RegExp(r'_+'), ' ').trim();
    if (n.toLowerCase().endsWith('.pdf')) {
      n = n.substring(0, n.length - 4).trim();
    }
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 'Documento di assegnazione';
    if (n.length > 42) return '${n.substring(0, 40)}…';
    return n;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs =
          await LogisticaAssegnazioneMezziDocumentiService.listForMezzo(
        _mezzoId,
      );
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ModifyFeedback.error(context, 'Errore documenti: $e');
    }
  }

  Future<void> _open(AssegnazioneMezzoDocumento doc) async {
    try {
      final url =
          await LogisticaAssegnazioneMezziDocumentiService.signedUrl(doc);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!launched && mounted) {
        ModifyFeedback.error(context, 'Impossibile aprire il PDF.');
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Apertura fallita: $e');
    }
  }

  Future<void> _download(AssegnazioneMezzoDocumento doc) async {
    try {
      final bytes =
          await LogisticaAssegnazioneMezziDocumentiService.downloadBytes(doc);
      var base = doc.fileName.trim();
      if (base.toLowerCase().endsWith('.pdf')) {
        base = base.substring(0, base.length - 4);
      }
      if (base.isEmpty) base = 'assegnazione';
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: base,
        bytes: bytes,
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ModifyFeedback.hint(context, 'Download completato.');
        return;
      }
      final url =
          await LogisticaAssegnazioneMezziDocumentiService.signedUrl(doc);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_blank' : null,
      );
      if (!mounted) return;
      ModifyFeedback.hint(
        context,
        launched ? 'PDF aperto in una nuova scheda.' : 'Download annullato.',
      );
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Download fallito: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = (widget.row['tipologia_mezzo'] ?? '').toString();
    const ink = Color(0xFF0B1F33);
    const accent = Color(0xFF0F766E);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: logisticaDialogWidth(context, desktop: 420),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MezzoTipoBadge(tipologia: tip, color: accent, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Documenti PDF',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _mezzoLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chiudi',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_docs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CronosAppThemes.cardMutedOf(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Nessun PDF caricato per questo mezzo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = _docs[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: ink.withValues(alpha: 0.07),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _friendlyName(doc.fileName),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: ink,
                                          height: 1.25,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        formatDateTimeIt(doc.uploadedAt),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _open(doc),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Apri'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: accent,
                                      side: BorderSide(
                                        color: accent.withValues(alpha: 0.35),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 11,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _download(doc),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Scarica'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 11,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
