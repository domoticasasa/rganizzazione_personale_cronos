import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/confirm_sound_service.dart';
import '../services/logistica_assegnazione_mezzi_documenti_service.dart';
import '../services/mezzi_km_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/logistica_layout.dart';
import '../utils/logistica_multicard_mezzo_sync.dart';
import '../utils/mezzo_tipologia_icon.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/viaggi_mezzi_qr_export.dart';
import '../utils/viaggi_mezzi_qr_payload.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/user_profile_avatar.dart';
import 'employee_assegnazione_mezzi_page.dart';

/// Vista dipendente: il proprio mezzo stradale + aggiornamento gomme.
class EmployeeMezziStradaliPage extends StatefulWidget {
  final bool forceMobileLayout;

  const EmployeeMezziStradaliPage({
    super.key,
    this.forceMobileLayout = false,
  });

  @override
  State<EmployeeMezziStradaliPage> createState() =>
      _EmployeeMezziStradaliPageState();
}

class _EmployeeMezziStradaliPageState extends State<EmployeeMezziStradaliPage>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF0B1F33);
  static const _accent = Color(0xFF2F6FED);
  static const _gold = Color(0xFFC9A227);

  final _supa = Supabase.instance.client;
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

  String _formatKmDisplay(int km) {
    final negative = km < 0;
    var n = km.abs();
    final parts = <String>[];
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    final body = parts.join('.');
    return negative ? '-$body' : body;
  }

  String _kmLabel(Map<String, dynamic> row) =>
      MezziKmService.kmAttualiLabel(row, formatKm: _formatKmDisplay);

  String _kmAggLabel(Map<String, dynamic> row) =>
      MezziKmService.kmUltimoAggiornamentoLabel(row);

  String _mezzoLabel(Map<String, dynamic> row) => mezzoLabelFromParts(
        targa: (row['targa'] ?? '').toString(),
        marca: (row['marca'] ?? '').toString(),
        modello: (row['modello'] ?? '').toString(),
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supa
          .from('logistica_mezzi_stradali')
          .select()
          .order('numerazione', ascending: true);
      var list = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      try {
        final cardRes = await _supa
            .from('logistica_multicard')
            .select('multicard,mezzo_targa');
        applyGestioneMulticardOntoMezziRows(
          mezzi: list,
          multicardRows: List<Map<String, dynamic>>.from(
            (cardRes as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
        );
      } catch (_) {}
      list = list.where(_isMine).toList(growable: false);
      Map<String, int> counts = const {};
      try {
        counts =
            await LogisticaAssegnazioneMezziDocumentiService.countByMezzo();
      } catch (_) {}
      if (!mounted) return;
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
        r['kit_ruota_di_scorta'],
        r['deposito_gomme'],
        r['note'],
      ].map((v) => (v ?? '').toString().toLowerCase());
      return fields.any((f) => f.contains(k));
    }).toList(growable: false);
  }

  Future<void> _openGomme(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _EmployeeGommeDialog(row: row),
    );
    if (ok != true || !mounted) return;
    ModifyFeedback.success(context, 'Dati gomme aggiornati.');
    unawaited(ConfirmSoundService.play());
    await _load();
  }

  Future<void> _openPdf(Map<String, dynamic> row) async {
    await showEmployeeAssegnazionePdfDialog(context, row: row);
    if (mounted) await _load();
  }

  Future<void> _openQr(Map<String, dynamic> row) async {
    await showViaggiMezziQrExportDialog(
      context: context,
      client: _supa,
      mezzoIdUuid: (row['id_uuid'] ?? '').toString(),
      mezzoLabel: _mezzoLabel(row),
    );
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
            'Il mio mezzo',
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
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _Hero(
                      compact: _compact,
                      fullName: name,
                      usersTableId: _usersTableId,
                      total: _rows.length,
                      animation: _introCtrl,
                    ),
                  ),
                  if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
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
                        child: _EmptyState(
                          icon: Icons.directions_car_outlined,
                          title: _rows.isEmpty
                              ? 'Nessun mezzo assegnato'
                              : 'Nessun risultato',
                          message: _rows.isEmpty
                              ? 'Quando Logistica ti assegnerà un mezzo stradale, '
                                  'lo vedrai qui con PDF di assegnazione e sezione gomme.'
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
                            return _MezzoCard(
                              label: _mezzoLabel(row),
                              tipologia:
                                  (row['tipologia_mezzo'] ?? '').toString(),
                              km: _kmLabel(row),
                              kmAgg: _kmAggLabel(row),
                              kitRuota:
                                  (row['kit_ruota_di_scorta'] ?? '').toString(),
                              deposito:
                                  (row['deposito_gomme'] ?? '').toString(),
                              scadenzaRevisione: formatDateDdMmYyyy(
                                row['scadenza_revisione'],
                              ),
                              scadenzaAssicurazione: formatDateDdMmYyyy(
                                row['scadenza_assicurazione'],
                              ),
                              multicard:
                                  (row['multicard'] ?? '').toString().trim(),
                              telepass:
                                  (row['telepass'] ?? '').toString().trim(),
                              pdfCount: _pdfCounts[
                                      (row['id_uuid'] ?? '').toString()] ??
                                  0,
                              compact: _compact,
                              index: i,
                              animation: _introCtrl,
                              onOpenGomme: () => _openGomme(row),
                              onOpenPdf: () => _openPdf(row),
                              onDownloadQr: () => unawaited(_openQr(row)),
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

class _Hero extends StatelessWidget {
  const _Hero({
    required this.compact,
    required this.fullName,
    required this.usersTableId,
    required this.total,
    required this.animation,
  });

  final bool compact;
  final String fullName;
  final int? usersTableId;
  final int total;
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
                Color(0xFF2F6FED),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -36,
                top: -24,
                child: _Orb(
                  size: compact ? 110 : 180,
                  color: const Color(0xFFC9A227).withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                left: -40,
                bottom: -10,
                child: _Orb(
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
                                'Mezzo assegnato a te',
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
                    SizedBox(height: compact ? 12 : 18),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: compact ? 9 : 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_car_filled_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$total mezz${total == 1 ? 'o' : 'i'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 15 : 17,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'PDF, QR code e gomme',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _MezzoCard extends StatelessWidget {
  const _MezzoCard({
    required this.label,
    required this.tipologia,
    required this.km,
    required this.kmAgg,
    required this.kitRuota,
    required this.deposito,
    required this.scadenzaRevisione,
    required this.scadenzaAssicurazione,
    required this.multicard,
    required this.telepass,
    required this.pdfCount,
    required this.compact,
    required this.index,
    required this.animation,
    required this.onOpenGomme,
    required this.onOpenPdf,
    required this.onDownloadQr,
  });

  final String label;
  final String tipologia;
  final String km;
  final String kmAgg;
  final String kitRuota;
  final String deposito;
  final String scadenzaRevisione;
  final String scadenzaAssicurazione;
  final String multicard;
  final String telepass;
  final int pdfCount;
  final bool compact;
  final int index;
  final Animation<double> animation;
  final VoidCallback onOpenGomme;
  final VoidCallback onOpenPdf;
  final VoidCallback onDownloadQr;

  @override
  Widget build(BuildContext context) {
    final start = math.min(0.12 + index * 0.05, 0.78);
    final end = math.min(start + 0.32, 1.0);
    final local = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    const accent = Color(0xFF2F6FED);
    const teal = Color(0xFF0F766E);

    return FadeTransition(
      opacity: local,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(local),
        child: Material(
          color: Colors.transparent,
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
                        width: compact ? 46 : 50,
                        height: compact ? 46 : 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              accent,
                              Color.lerp(accent, Colors.black, 0.16)!,
                            ],
                          ),
                        ),
                        child: mezzoTipologiaIcon(
                          tipologia,
                          color: Colors.white,
                          size: compact ? 24 : 26,
                        ),
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
                                  style: const TextStyle(
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
                            color: teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.picture_as_pdf,
                                color: teal,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$pdfCount',
                                style: const TextStyle(
                                  color: teal,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (km.trim().isNotEmpty)
                    _MetaRow(
                      icon: Icons.speed_rounded,
                      label: 'Km attuali',
                      value: km,
                    ),
                  if (kmAgg.trim().isNotEmpty)
                    _MetaRow(
                      icon: Icons.update_rounded,
                      label: 'Ultimo agg. km',
                      value: kmAgg,
                    ),
                  if (kitRuota.trim().isNotEmpty)
                    _MetaRow(
                      icon: Icons.tire_repair_outlined,
                      label: 'Kit ruota',
                      value: kitRuota.trim(),
                    ),
                  if (deposito.trim().isNotEmpty)
                    _MetaRow(
                      icon: Icons.warehouse_outlined,
                      label: 'Deposito gomme',
                      value: deposito.trim(),
                    ),
                  if (scadenzaRevisione.isNotEmpty)
                    _MetaRow(
                      icon: Icons.event_rounded,
                      label: 'Scad. revisione',
                      value: scadenzaRevisione,
                    ),
                  if (scadenzaAssicurazione.isNotEmpty)
                    _MetaRow(
                      icon: Icons.verified_user_outlined,
                      label: 'Scad. assicurazione',
                      value: scadenzaAssicurazione,
                    ),
                  if (multicard.isNotEmpty)
                    _MetaRow(
                      icon: Icons.credit_card_outlined,
                      label: 'Multicard',
                      value: multicard,
                    ),
                  if (telepass.isNotEmpty)
                    _MetaRow(
                      icon: Icons.toll_outlined,
                      label: 'Telepass',
                      value: telepass,
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onOpenPdf,
                      icon: Icon(
                        pdfCount > 0
                            ? Icons.picture_as_pdf_rounded
                            : Icons.assignment_outlined,
                        size: 18,
                      ),
                      label: Text(
                        pdfCount > 0
                            ? 'PDF assegnazione ($pdfCount)'
                            : 'PDF assegnazione',
                      ),
                      style: FilledButton.styleFrom(
                        foregroundColor: teal,
                        backgroundColor: teal.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onDownloadQr,
                      icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                      label: const Text('Scarica QR code'),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF4338CA),
                        backgroundColor:
                            const Color(0xFF4338CA).withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onOpenGomme,
                      icon: const Icon(Icons.tire_repair, size: 18),
                      label: const Text('Aggiorna sezione gomme'),
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
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.black45),
          const SizedBox(width: 6),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B1F33),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
                  color: const Color(0xFF2F6FED).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 34, color: const Color(0xFF2F6FED)),
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

class _EmployeeGommeDialog extends StatefulWidget {
  const _EmployeeGommeDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_EmployeeGommeDialog> createState() => _EmployeeGommeDialogState();
}

class _EmployeeGommeDialogState extends State<_EmployeeGommeDialog> {
  final _supa = Supabase.instance.client;
  late final TextEditingController kitRuotaCtrl;
  late final TextEditingController depositoGommeCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    kitRuotaCtrl = TextEditingController(
      text: (r['kit_ruota_di_scorta'] ?? '').toString(),
    );
    depositoGommeCtrl = TextEditingController(
      text: (r['deposito_gomme'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    kitRuotaCtrl.dispose();
    depositoGommeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = (widget.row['id_uuid'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    try {
      await _supa.from('logistica_mezzi_stradali').update({
        'kit_ruota_di_scorta': kitRuotaCtrl.text.trim().isEmpty
            ? null
            : kitRuotaCtrl.text.trim(),
        'deposito_gomme': depositoGommeCtrl.text.trim().isEmpty
            ? null
            : depositoGommeCtrl.text.trim(),
      }).eq('id_uuid', id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Errore salvataggio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogW = logisticaDialogWidth(context, desktop: 540);
    final label = mezzoLabelFromParts(
      targa: (widget.row['targa'] ?? '').toString(),
      marca: (widget.row['marca'] ?? '').toString(),
      modello: (widget.row['modello'] ?? '').toString(),
    );
    return AlertDialog(
      title: const Text('Sezione gomme'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kitRuotaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kit ruota di scorta',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: depositoGommeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Deposito gomme',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        AsyncFilledButton(onPressed: _save, child: const Text('Salva')),
      ],
    );
  }
}
