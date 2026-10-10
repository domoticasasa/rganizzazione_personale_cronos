import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/user_profile_avatar.dart';

/// Area dipendente: percorsi Formazione RFI e scadenze (UI allineata alle altre viste).
class EmployeeFormazioneRfiScadenzePage extends StatefulWidget {
  final int userId;
  final String fullName;
  final bool forceMobileLayout;

  const EmployeeFormazioneRfiScadenzePage({
    super.key,
    required this.userId,
    required this.fullName,
    this.forceMobileLayout = false,
  });

  @override
  State<EmployeeFormazioneRfiScadenzePage> createState() =>
      _EmployeeFormazioneRfiScadenzePageState();
}

class _EmployeeFormazioneRfiScadenzePageState
    extends State<EmployeeFormazioneRfiScadenzePage>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF0B1F33);
  static const _accent = Color(0xFF1565C0);
  static const _gold = Color(0xFFC9A227);

  /// Campi riservati all’admin (non mostrati al dipendente).
  static const _adminOnlyFieldHints = <String>{
    'oda',
    'ente',
    'tipo',
    'modalita',
    'modalità',
    'struttura',
    'struttura link',
    'struttura_rfi_id',
    'struttura_nome',
    'struttura_indirizzo',
    'struttura_link',
    'primo rilascio',
    'primo_rilascio',
    'aggiornamento',
  };

  bool _loading = true;
  String? _error;
  String _search = '';
  final _searchCtrl = TextEditingController();
  List<_RfiTrack> _tracks = const [];
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
    _searchCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  Future<int?> _resolvePersonaleId() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return null;
    try {
      final p1 = await SupabaseService.client
          .from('personale')
          .select('id')
          .eq('user_id', authUser.id)
          .maybeSingle();
      final id1 = p1?['id'];
      if (id1 is int) return id1;

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
            .select('id')
            .eq('user_id', uid)
            .maybeSingle();
        final id2 = p2?['id'];
        if (id2 is int) return id2;
      }
      if (uuid.isNotEmpty) {
        final p3 = await SupabaseService.client
            .from('personale')
            .select('id')
            .eq('user_id', uuid)
            .maybeSingle();
        final id3 = p3?['id'];
        if (id3 is int) return id3;
      }
    } catch (_) {}
    return null;
  }

  String _normalizeFieldKey(String field) =>
      field.toLowerCase().trim().replaceAll('_', ' ');

  bool _isAdminOnlyField(String field) {
    final n = _normalizeFieldKey(field);
    if (_adminOnlyFieldHints.contains(n)) return true;
    for (final h in _adminOnlyFieldHints) {
      if (n.contains(h)) return true;
    }
    return false;
  }

  DateTime? _resolvePrimaryExpiry(List<Map<String, dynamic>> rows) {
    DateTime? prossima;
    DateTime? scadenza;
    for (final r in rows) {
      final fk = _normalizeFieldKey((r['field_key'] ?? '').toString());
      final dt = _parseDateLike(r['value_date'], r['value_text']);
      if (dt == null) continue;
      if (fk.contains('prossima scadenza')) {
        prossima = dt;
      } else if (fk == 'scadenza') {
        scadenza = dt;
      }
    }
    if (prossima != null) return prossima;
    if (scadenza != null) return scadenza;

    DateTime? latest;
    for (final r in rows) {
      final fk = _normalizeFieldKey((r['field_key'] ?? '').toString());
      if (fk.contains('attestato') && !fk.contains('prossima')) continue;
      final dt = _parseDateLike(r['value_date'], r['value_text']);
      if (dt == null) continue;
      final relevant = fk.contains('rinnovo') ||
          (fk.contains('scadenza') && !fk.contains('attestato'));
      if (!relevant) continue;
      if (latest == null || dt.isAfter(latest)) latest = dt;
    }
    return latest;
  }

  DateTime? _parseDateLike(dynamic valueDate, dynamic valueText) {
    if (valueDate != null && valueDate.toString().trim().isNotEmpty) {
      final dt = DateTime.tryParse(valueDate.toString());
      if (dt != null) return dt;
    }
    final text = (valueText ?? '').toString().trim();
    if (text.isEmpty) return null;
    final iso = parseFlexibleDateToIsoDate(text);
    if (iso != null) return DateTime.tryParse(iso);
    return DateTime.tryParse(text);
  }

  _ExpiryTone _toneOf(DateTime? dt) {
    if (dt == null) return _ExpiryTone.none;
    final today = DateTime.now();
    final only = DateTime(today.year, today.month, today.day);
    final days = DateTime(dt.year, dt.month, dt.day).difference(only).inDays;
    if (days < 0) return _ExpiryTone.expired;
    if (days <= 60) return _ExpiryTone.soon;
    return _ExpiryTone.ok;
  }

  String _prettyFieldLabel(String field) {
    final n = _normalizeFieldKey(field);
    if (n.contains('prossima scadenza')) return 'Prossima scadenza';
    if (n == 'scadenza' || n.contains('scadenza attestato')) return 'Scadenza';
    if (n.contains('data attestato') || n == 'data attestato') {
      return 'Data attestato';
    }
    if (n.contains('programmazione dal')) return 'Programmazione dal';
    if (n.contains('programmazione al')) return 'Programmazione al';
    if (n.contains('programmazione')) return 'Programmazione';
    if (n.contains('orario')) return 'Orario';
    if (n.contains('note')) return 'Note';
    if (n.contains('rinnovo')) return 'Rinnovo';
    // Capitalizza parole del field_key grezzo.
    return field
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  IconData _iconForField(String label) {
    final n = label.toLowerCase();
    if (n.contains('scadenza')) return Icons.event_rounded;
    if (n.contains('attestato')) return Icons.verified_outlined;
    if (n.contains('programmazione')) return Icons.calendar_month_outlined;
    if (n.contains('orario')) return Icons.schedule_rounded;
    if (n.contains('note')) return Icons.notes_outlined;
    if (n.contains('rinnovo')) return Icons.autorenew_rounded;
    return Icons.info_outline_rounded;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final personaleId = await _resolvePersonaleId();
      if (personaleId == null) {
        if (!mounted) return;
        setState(() {
          _tracks = const [];
          _error = 'Impossibile risolvere l’anagrafica dipendente.';
          _loading = false;
        });
        return;
      }

      final res = await SupabaseService.client
          .from('formazione_rfi_records')
          .select('track_key, field_key, value_date, value_text')
          .eq('personale_id', personaleId)
          .order('track_key', ascending: true);

      final byTrack = <String, List<Map<String, dynamic>>>{};
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final track = (row['track_key'] ?? '').toString().trim();
        if (track.isEmpty) continue;
        byTrack.putIfAbsent(track, () => <Map<String, dynamic>>[]).add(row);
      }

      final built = <_RfiTrack>[];
      for (final entry in byTrack.entries) {
        final expiry = _resolvePrimaryExpiry(entry.value);
        final details = <_RfiDetail>[];
        for (final r in entry.value) {
          final field = (r['field_key'] ?? '').toString().trim();
          if (field.isEmpty || _isAdminOnlyField(field)) continue;
          final valueText = (r['value_text'] ?? '').toString().trim();
          final dt = _parseDateLike(r['value_date'], r['value_text']);
          final display = dt != null ? formatDateDdMmYyyy(dt) : valueText;
          if (display.isEmpty) continue;
          final label = _prettyFieldLabel(field);
          // Evita duplicare la riga “Prossima scadenza” già in evidenza.
          final ln = label.toLowerCase();
          if (ln.contains('prossima scadenza') && expiry != null) continue;
          details.add(
            _RfiDetail(
              label: label,
              value: display,
              icon: _iconForField(label),
            ),
          );
        }
        built.add(
          _RfiTrack(
            track: entry.key,
            expiry: expiry,
            details: details,
          ),
        );
      }

      built.sort((a, b) {
        final ad = a.expiry;
        final bd = b.expiry;
        if (ad == null && bd == null) return a.track.compareTo(b.track);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

      if (!mounted) return;
      setState(() {
        _tracks = built;
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

  List<_RfiTrack> get _filtered {
    final k = _search.trim().toLowerCase();
    if (k.isEmpty) return _tracks;
    return _tracks
        .where((t) => t.track.toLowerCase().contains(k))
        .toList(growable: false);
  }

  int get _expiredCount =>
      _tracks.where((t) => _toneOf(t.expiry) == _ExpiryTone.expired).length;
  int get _soonCount =>
      _tracks.where((t) => _toneOf(t.expiry) == _ExpiryTone.soon).length;

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final padH = _compact ? 14.0 : 22.0;
    final name =
        widget.fullName.trim().isEmpty ? 'Dipendente' : widget.fullName.trim();

    return Scaffold(
      backgroundColor: CronosAppThemes.canvasOf(context),
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Formazione RFI',
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
                      usersTableId: widget.userId,
                      total: _tracks.length,
                      expired: _expiredCount,
                      soon: _soonCount,
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
                          onChanged: (v) => setState(() => _search = v),
                          decoration: InputDecoration(
                            hintText: 'Cerca percorso RFI…',
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
                          icon: Icons.account_tree_outlined,
                          title: _tracks.isEmpty
                              ? 'Nessun percorso RFI'
                              : 'Nessun risultato',
                          message: _tracks.isEmpty
                              ? 'Quando verranno caricati i tuoi percorsi Formazione RFI, '
                                  'li troverai qui con le relative scadenze.'
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
                            final t = rows[i];
                            return _TrackCard(
                              track: t,
                              tone: _toneOf(t.expiry),
                              compact: _compact,
                              index: i,
                              animation: _introCtrl,
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

class _RfiTrack {
  final String track;
  final DateTime? expiry;
  final List<_RfiDetail> details;

  const _RfiTrack({
    required this.track,
    required this.expiry,
    required this.details,
  });
}

class _RfiDetail {
  final String label;
  final String value;
  final IconData icon;

  const _RfiDetail({
    required this.label,
    required this.value,
    required this.icon,
  });
}

enum _ExpiryTone { none, ok, soon, expired }

Color _toneColor(_ExpiryTone tone) {
  switch (tone) {
    case _ExpiryTone.expired:
      return const Color(0xFFC62828);
    case _ExpiryTone.soon:
      return const Color(0xFFEF6C00);
    case _ExpiryTone.ok:
      return const Color(0xFF2E7D32);
    case _ExpiryTone.none:
      return const Color(0xFF607D8B);
  }
}

String _toneLabel(_ExpiryTone tone) {
  switch (tone) {
    case _ExpiryTone.expired:
      return 'Scaduto';
    case _ExpiryTone.soon:
      return 'In scadenza';
    case _ExpiryTone.ok:
      return 'Valido';
    case _ExpiryTone.none:
      return 'Senza data';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.compact,
    required this.fullName,
    required this.usersTableId,
    required this.total,
    required this.expired,
    required this.soon,
    required this.animation,
  });

  final bool compact;
  final String fullName;
  final int usersTableId;
  final int total;
  final int expired;
  final int soon;
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
                                'I tuoi percorsi Formazione RFI',
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
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            label: 'Percorsi',
                            value: '$total',
                            icon: Icons.account_tree_rounded,
                            compact: compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatTile(
                            label: 'In scadenza',
                            value: '$soon',
                            icon: Icons.schedule_rounded,
                            compact: compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatTile(
                            label: 'Scaduti',
                            value: '$expired',
                            icon: Icons.warning_amber_rounded,
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
        horizontal: compact ? 8 : 10,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: compact ? 16 : 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 15 : 17,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.tone,
    required this.compact,
    required this.index,
    required this.animation,
  });

  final _RfiTrack track;
  final _ExpiryTone tone;
  final bool compact;
  final int index;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final start = math.min(0.12 + index * 0.05, 0.78);
    final end = math.min(start + 0.32, 1.0);
    final local = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    final accent = _toneColor(tone);
    final expiryLabel = track.expiry == null
        ? '—'
        : formatDateDdMmYyyy(track.expiry);

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
              border: Border.all(color: accent.withValues(alpha: 0.14)),
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
                compact ? 12 : 14,
                compact ? 11 : 13,
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
                          Icons.account_tree_rounded,
                          color: Colors.white,
                          size: compact ? 20 : 22,
                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                              track.track,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 14.5 : 15.5,
                                color: const Color(0xFF0B1F33),
                                height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _toneLabel(tone),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                  const SizedBox(height: 12),
                  _MetaRow(
                    icon: Icons.event_rounded,
                    label: 'Prossima scadenza',
                    value: expiryLabel,
                    valueColor: accent,
                  ),
                  for (final d in track.details)
                    _MetaRow(
                      icon: d.icon,
                      label: d.label,
                      value: d.value,
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
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

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
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF0B1F33),
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
