import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import '../theme/cronos_app_themes.dart';
import '../utils/date_formatters.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../utils/modify_feedback.dart';
import '../utils/personale_contacts_export.dart';
import '../utils/rubrica_privacy_notice.dart';
import '../utils/users_directory.dart';
import '../widgets/classic_app_bar_chrome.dart';

String _s(dynamic v) => (v ?? '').toString().trim();

DateTime? _parseBirth(dynamic raw) {
  final iso = parseFlexibleDateToIsoDate(_s(raw));
  if (iso == null) return null;
  final p = DateTime.tryParse(iso);
  if (p == null) return null;
  return DateTime(p.year, p.month, p.day);
}

int? _ageYears(DateTime birth, DateTime today) {
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age--;
  }
  if (age < 0 || age > 120) return null;
  return age;
}

String _itDec(double v, {int decimals = 1}) =>
    v.toStringAsFixed(decimals).replaceAll('.', ',');

String _itPct(double v) => '${_itDec(v)}%';

class _RubricaEtaStats {
  const _RubricaEtaStats({
    required this.total,
    required this.withAge,
    required this.withoutAge,
    required this.avgAge,
    required this.under30,
    required this.age30to40,
    required this.age41to50,
    required this.age50to60,
    required this.over60,
  });

  final int total;
  final int withAge;
  final int withoutAge;
  final double? avgAge;
  final int under30;
  final int age30to40;
  final int age41to50;
  final int age50to60;
  final int over60;

  double pct(int n) => withAge == 0 ? 0 : (n * 100.0 / withAge);

  factory _RubricaEtaStats.fromRows(List<Map<String, dynamic>> rows) {
    final today = italyNow();
    final ages = <int>[];
    for (final r in rows) {
      final birth = _parseBirth(r['data_nascita']);
      if (birth == null) continue;
      final age = _ageYears(birth, today);
      if (age == null) continue;
      ages.add(age);
    }
    var u30 = 0;
    var m3040 = 0;
    var m4150 = 0;
    var m5060 = 0;
    var o60 = 0;
    var sum = 0;
    for (final a in ages) {
      sum += a;
      if (a < 30) {
        u30++;
      } else if (a <= 40) {
        m3040++;
      } else if (a <= 50) {
        m4150++;
      } else if (a <= 60) {
        m5060++;
      } else {
        o60++;
      }
    }
    return _RubricaEtaStats(
      total: rows.length,
      withAge: ages.length,
      withoutAge: rows.length - ages.length,
      avgAge: ages.isEmpty ? null : sum / ages.length,
      under30: u30,
      age30to40: m3040,
      age41to50: m4150,
      age50to60: m5060,
      over60: o60,
    );
  }
}

class DtRubricaPage extends StatefulWidget {
  const DtRubricaPage({super.key});

  @override
  State<DtRubricaPage> createState() => _DtRubricaPageState();
}

class _DtRubricaPageState extends State<DtRubricaPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _privacyOk = false;
  bool _loading = false;
  String? _error;
  String _search = '';
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_gatePrivacyThenLoad());
    });
  }

  Future<void> _gatePrivacyThenLoad() async {
    if (!mounted) return;
    final ok = await RubricaPrivacyNotice.confirm(context);
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _privacyOk = true);
    await _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _digits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  int? _rowAge(Map<String, dynamic> r) {
    final birth = _parseBirth(r['data_nascita']);
    if (birth == null) return null;
    return _ageYears(birth, italyNow());
  }

  String _nascitaLabel(dynamic raw) {
    final s = formatDateDdMmYyyy(raw);
    return s.isEmpty ? '—' : s;
  }

  List<String> _todaysBirthdayLabels() {
    final now = italyNow();
    final out = <String>[];
    for (final r in _rows) {
      final birth = _parseBirth(r['data_nascita']);
      if (birth == null) continue;
      if (birth.month != now.month || birth.day != now.day) continue;
      final name = _s(r['full_name']);
      if (name.isEmpty) continue;
      final age = _ageYears(birth, now);
      out.add(age == null ? name : '$name ($age)');
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  Widget _birthdayStrip({bool gestopro = false}) {
    return _RubricaBirthdayStrip(
      loading: _loading,
      names: _todaysBirthdayLabels(),
      onStats: (!_privacyOk || _loading) ? null : _showEtaStats,
      gestopro: gestopro,
    );
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    final qDigits = _digits(q);
    return _rows.where((r) {
      final name = _s(r['full_name']).toLowerCase();
      final email = _s(r['email']).toLowerCase();
      final tel = _s(r['telefono']);
      final nascita = formatDateDdMmYyyy(r['data_nascita']).toLowerCase();
      final age = _rowAge(r);
      if (name.contains(q) ||
          email.contains(q) ||
          tel.toLowerCase().contains(q) ||
          nascita.contains(q)) {
        return true;
      }
      if (age != null && '$age' == qDigits && qDigits.isNotEmpty) return true;
      if (qDigits.isNotEmpty && _digits(tel).contains(qDigits)) return true;
      return false;
    }).toList(growable: false);
  }

  Future<void> _load() async {
    if (!_privacyOk) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await SupabaseService.client
          .from('personale')
          .select(
            'id, id_uuid, full_name, email, telefono, data_nascita, active, user_id',
          )
          .eq('active', true)
          .order('full_name', ascending: true);
      final visible = await UsersDirectory.visiblePersonale(res as List);
      visible.sort((a, b) {
        final an = _s(a['full_name']).toLowerCase();
        final bn = _s(b['full_name']).toLowerCase();
        return an.compareTo(bn);
      });
      if (!mounted) return;
      setState(() {
        _rows = visible;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    ModifyFeedback.hint(context, '$label copiato.');
  }

  Future<void> _launch(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ModifyFeedback.error(context, 'Impossibile aprire il collegamento.');
    }
  }

  Future<void> _call(String raw) async {
    final e164 = PersonaleContactsExport.normalizePhoneItaly(raw) ?? raw.trim();
    if (e164.isEmpty) return;
    await _launch(Uri(scheme: 'tel', path: e164));
  }

  Future<void> _whatsapp(String raw) async {
    final e164 = PersonaleContactsExport.normalizePhoneItaly(raw);
    if (e164 == null || e164.isEmpty) return;
    final digits = _digits(e164);
    if (digits.isEmpty) return;
    await _launch(Uri.parse('https://wa.me/$digits'));
  }

  Future<void> _mail(String email) async {
    final e = email.trim();
    if (e.isEmpty) return;
    await _launch(Uri(scheme: 'mailto', path: e));
  }

  Future<void> _showEtaStats() async {
    final stats = _RubricaEtaStats.fromRows(_rows);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Statistiche età'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statKv('Lavoratori', '${stats.total}'),
                  _statKv(
                    'Età media',
                    stats.avgAge == null
                        ? '—'
                        : '${_itDec(stats.avgAge!)} anni',
                  ),
                  if (stats.withoutAge > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Calcolo su ${stats.withAge} con data di nascita '
                        '(${stats.withoutAge} senza).',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                  const Divider(height: 20),
                  Text(
                    'Fasce d’età',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _statBand(
                    label: 'Sotto i 30',
                    count: stats.under30,
                    pct: stats.pct(stats.under30),
                    color: scheme.primary,
                  ),
                  _statBand(
                    label: '30–40 anni',
                    count: stats.age30to40,
                    pct: stats.pct(stats.age30to40),
                    color: scheme.tertiary,
                  ),
                  _statBand(
                    label: '41–50 anni',
                    count: stats.age41to50,
                    pct: stats.pct(stats.age41to50),
                    color: scheme.secondary,
                  ),
                  _statBand(
                    label: '50–60 anni',
                    count: stats.age50to60,
                    pct: stats.pct(stats.age50to60),
                    color: const Color(0xFF00897B),
                  ),
                  _statBand(
                    label: 'Oltre i 60',
                    count: stats.over60,
                    pct: stats.pct(stats.over60),
                    color: const Color(0xFF5C6BC0),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Widget _statKv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _statBand({
    required String label,
    required int count,
    required double pct,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$count  (${_itPct(pct)})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneCell(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return Text('—', style: TextStyle(color: CronosAppThemes.mutedOf(context)));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: InkWell(
            onTap: () => _call(t),
            onLongPress: () => _copy('Telefono', t),
            child: Text(
              t,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Chiama',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.call_outlined),
          onPressed: () => _call(t),
        ),
        IconButton(
          tooltip: 'WhatsApp',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.chat_outlined),
          onPressed: () => _whatsapp(t),
        ),
      ],
    );
  }

  Widget _emailCell(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return Text('—', style: TextStyle(color: CronosAppThemes.mutedOf(context)));
    }
    return InkWell(
      onTap: () => _mail(t),
      onLongPress: () => _copy('Email', t),
      child: Text(
        t,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Cerca nome, telefono, email o età…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Pulisci',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> items) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 24,
        ),
        child: DataTable(
          columnSpacing: 18,
          horizontalMargin: 12,
          headingRowColor: WidgetStateProperty.all(
            theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          ),
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Nome')),
            DataColumn(label: Text('Data di nascita')),
            DataColumn(label: Text('Età'), numeric: true),
            DataColumn(label: Text('Telefono')),
            DataColumn(label: Text('Email')),
          ],
          rows: [
            for (var i = 0; i < items.length; i++)
              DataRow(
                cells: [
                  DataCell(Text(
                    '${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
                  DataCell(Text(
                    _s(items[i]['full_name']),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
                  DataCell(Text(_nascitaLabel(items[i]['data_nascita']))),
                  DataCell(Text(
                    '${_rowAge(items[i]) ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )),
                  DataCell(_phoneCell(_s(items[i]['telefono']))),
                  DataCell(_emailCell(_s(items[i]['email']))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cards(List<Map<String, dynamic>> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = items[i];
        final name = _s(r['full_name']);
        final tel = _s(r['telefono']);
        final email = _s(r['email']);
        final nascita = formatDateDdMmYyyy(r['data_nascita']);
        final age = _rowAge(r);
        return Material(
          color: CronosAppThemes.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.  $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nascita.isEmpty
                      ? 'Nascita: —'
                      : 'Nascita: $nascita'
                          '${age == null ? '' : '   ·   $age anni'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                _phoneCell(tel),
                const SizedBox(height: 2),
                _emailCell(email),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Rubrica';
    final items = _filtered;
    final compact = useMobileUi(context);
    final actions = <Widget>[
      IconButton(
        tooltip: 'Aggiorna',
        onPressed: (_privacyOk && !_loading) ? _load : null,
        icon: const Icon(Icons.refresh),
      ),
    ];
    final gestopro = isGestoproFuturisticUi(context);

    return buildGestoproAwarePage(
      context: context,
      title: title,
      toolbarActions: actions,
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const Text(title),
          actions: actions,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: _birthdayStrip(),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gestopro) _birthdayStrip(gestopro: true),
          _searchBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _loading
                  ? 'Caricamento…'
                  : !_privacyOk
                      ? 'In attesa di conferma…'
                      : '${items.length} contatt${items.length == 1 ? 'o' : 'i'}'
                          '${_search.trim().isEmpty ? '' : ' (filtro attivo)'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          if (!_privacyOk)
            const Expanded(
              child: Center(
                child: Text(
                  'Conferma l’informativa per visualizzare i contatti.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Errore: $_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            )
          else if (items.isEmpty)
            const Expanded(
              child: Center(child: Text('Nessun contatto trovato.')),
            )
          else
            Expanded(
              child: compact
                  ? _cards(items)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        children: [_table(items)],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _RubricaBirthdayStrip extends StatelessWidget {
  const _RubricaBirthdayStrip({
    required this.loading,
    required this.names,
    required this.onStats,
    this.gestopro = false,
  });

  final bool loading;
  final List<String> names;
  final VoidCallback? onStats;
  final bool gestopro;

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    final text = loading
        ? 'Compleanni oggi…'
        : (names.isEmpty
            ? 'Nessun compleanno oggi'
            : 'Compleanni oggi:  ${names.join('   ·   ')}');
    return ColoredBox(
      color: gestopro
          ? const Color(0xFF141B24)
          : Colors.black.withValues(alpha: 0.18),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.cake_outlined, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: _MarqueeText(
                text: text,
                style: const TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Statistiche età',
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onStats,
                  borderRadius: BorderRadius.circular(14),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pie_chart_outline, size: 15, color: fg),
                        SizedBox(width: 4),
                        Text(
                          'Età',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ctrl
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.maxWidth;
        if (box <= 0) return const SizedBox.shrink();
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textW = painter.width;
        if (textW <= box + 4) {
          if (_ctrl.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _ctrl.isAnimating) _ctrl.stop();
            });
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        const gap = 48.0;
        final loopW = textW + gap;
        final d = Duration(
          milliseconds: (loopW * 22).round().clamp(7000, 40000),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_ctrl.duration != d) _ctrl.duration = d;
          if (!_ctrl.isAnimating) _ctrl.repeat();
        });
        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_ctrl.value * loopW, 0),
                child: child,
              );
            },
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.text,
                    style: widget.style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                  const SizedBox(width: gap),
                  Text(
                    widget.text,
                    style: widget.style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
