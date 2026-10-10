import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/cronos_fonts.dart';

import '../../services/app_branding_service.dart';
import '../../services/agenda_reminder_scheduler.dart';
import '../../services/outlook_calendar_sync_service.dart';
import '../../services/personal_agenda_service.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/date_formatters.dart';
import '../../utils/gestopro_page_chrome.dart';
import '../futuristic/glowing_border_shell.dart';

/// Apre l’agenda ancorata sotto l’orologio (stile Nexus / glass).
Future<void> showPersonalAgenda(
  BuildContext context,
  BuildContext anchor,
) async {
  final size = MediaQuery.sizeOf(context);
  final futuristic = isGestoproFuturisticUi(context);
  final box = anchor.findRenderObject() as RenderBox?;

  if (futuristic && box != null && box.hasSize) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final left = offset.dx;
    final top = offset.dy + box.size.height + 8;
    final panelW = math.min(400.0, size.width - 16);
    final panelH = math.min(560.0, size.height * 0.82);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (dialogCtx) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned(
                left: math
                    .min(left, size.width - panelW - 8)
                    .clamp(8.0, size.width),
                top: math
                    .min(top, size.height - panelH - 8)
                    .clamp(8.0, size.height),
                child: SizedBox(
                  width: panelW,
                  height: panelH,
                  child: PersonalAgendaPanel(
                    compactNexus: true,
                    onClose: () => Navigator.of(dialogCtx).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return;
  }

  final wide = size.width >= 720;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogCtx) {
      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: wide ? 40 : 12,
          vertical: wide ? 28 : 16,
        ),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? 920 : size.width,
            maxHeight: size.height * 0.92,
          ),
          child: PersonalAgendaPanel(
            onClose: () => Navigator.of(dialogCtx).pop(),
          ),
        ),
      );
    },
  );
}

class PersonalAgendaPanel extends StatefulWidget {
  const PersonalAgendaPanel({
    super.key,
    this.onClose,
    this.compactNexus = false,
  });

  final VoidCallback? onClose;
  final bool compactNexus;

  @override
  State<PersonalAgendaPanel> createState() => _PersonalAgendaPanelState();
}

enum _AgendaView { day, week, month, list }

class _PersonalAgendaPanelState extends State<PersonalAgendaPanel> {
  final _svc = PersonalAgendaService.instance;
  final _outlook = OutlookCalendarSyncService.instance;
  final _searchCtrl = TextEditingController();

  _AgendaView _view = _AgendaView.month;
  DateTime _focus = DateTime(
    italyNow().year,
    italyNow().month,
    italyNow().day,
  );
  bool _loading = true;
  String? _error;
  List<AgendaEntry> _entries = const [];
  List<AgendaLinkedAbsence> _absences = const [];
  AgendaEntryKind? _kindFilter;

  @override
  void initState() {
    super.initState();
    _outlook.addListener(_onOutlookChanged);
    unawaited(_bootstrapOutlook());
    _reload();
  }

  Future<void> _bootstrapOutlook() async {
    await _outlook.refreshConnectionState();
    if (_outlook.isConnected) {
      try {
        await _outlook.syncNow(silent: true);
        if (mounted) await _reload();
      } catch (_) {}
    }
  }

  void _onOutlookChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _outlook.removeListener(_onOutlookChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  (DateTime from, DateTime to) _range() {
    switch (_view) {
      case _AgendaView.day:
        final from = DateTime(_focus.year, _focus.month, _focus.day);
        return (from, from.add(const Duration(days: 1)));
      case _AgendaView.week:
        final weekday = _focus.weekday;
        final from = DateTime(_focus.year, _focus.month, _focus.day)
            .subtract(Duration(days: weekday - 1));
        return (from, from.add(const Duration(days: 7)));
      case _AgendaView.month:
        final from = DateTime(_focus.year, _focus.month, 1);
        final to = DateTime(_focus.year, _focus.month + 1, 1);
        return (from, to);
      case _AgendaView.list:
        final from = DateTime(_focus.year, _focus.month, 1)
            .subtract(const Duration(days: 7));
        final to = DateTime(_focus.year, _focus.month + 2, 1);
        return (from, to);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _range();
      final entries = await _svc.listBetween(from: from, to: to);
      final absences = await _svc.loadOwnAbsences(from: from, to: to);
      for (final e in entries) {
        if (e.reminderEnabled) {
          unawaited(AgendaReminderScheduler.instance.scheduleFor(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _absences = absences;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _shift(int delta) {
    setState(() {
      switch (_view) {
        case _AgendaView.day:
          _focus = _focus.add(Duration(days: delta));
        case _AgendaView.week:
          _focus = _focus.add(Duration(days: 7 * delta));
        case _AgendaView.month:
        case _AgendaView.list:
          _focus = DateTime(_focus.year, _focus.month + delta, 1);
      }
    });
    _reload();
  }

  List<AgendaEntry> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _entries.where((e) {
      if (_kindFilter != null && e.kind != _kindFilter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.body.toLowerCase().contains(q) ||
          e.location.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<AgendaEntry> get _dayEntries {
    return _filtered.where((e) {
      final s = e.startsAt;
      if (s == null) return false;
      return s.year == _focus.year &&
          s.month == _focus.month &&
          s.day == _focus.day;
    }).toList(growable: false);
  }

  Future<void> _openEditor([AgendaEntry? existing]) async {
    final draft = existing ??
        AgendaEntry(
          id: '',
          userId: 0,
          kind: AgendaEntryKind.event,
          title: '',
          startsAt: DateTime(_focus.year, _focus.month, _focus.day, 9),
          endsAt: DateTime(_focus.year, _focus.month, _focus.day, 10),
          colorHex: '#1565C0',
        );
    final saved = await showDialog<AgendaEntry>(
      context: context,
      builder: (ctx) => _AgendaEditorDialog(initial: draft),
    );
    if (saved == null) return;
    try {
      await _svc.upsert(saved);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    }
  }

  Future<void> _delete(AgendaEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina voce'),
        content: Text('Eliminare «${e.title}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.delete(e.id);
    await _reload();
  }

  Future<void> _toggleOutlook() async {
    try {
      if (_outlook.isConnected) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Scollega Outlook'),
            content: const Text(
              'Rimuovere il collegamento? Gli eventi già importati restano in agenda.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Scollega'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await _outlook.disconnect();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outlook scollegato')),
        );
      } else {
        await _outlook.startConnect();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _showOutlookConfigInfo() async {
    final configured = OutlookCalendarSyncService.isConfigured;
    final redirect = OutlookCalendarSyncService.instance.redirectUri;
    final tenant = OutlookCalendarSyncService.tenant;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Expanded(child: Text('Outlook aziendale')),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured
                      ? 'Pronto: con «Collega Outlook» accedi col tuo account '
                          'lavoro/scuola. Non serve registrare nulla tu.'
                      : 'Sync non ancora attiva sul server: manca la '
                          'configurazione tecnica (una sola volta, da IT / '
                          'amministratore app). Tu non devi registrarti su Azure.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: configured
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Come funziona\n'
                  '• Hai già Outlook professionale → basta Collega Outlook '
                  'e il login Microsoft.\n'
                  '• Microsoft obbliga un’«app» Azure per parlare col calendario: '
                  'la crea IT una volta sola, non ogni dipendente.\n'
                  '• Non esiste un modo ufficiale senza quella registrazione '
                  '(né password Outlook nell’app).',
                ),
                if (!configured) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Solo per IT / chi pubblica l’app',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Azure → Entra ID → App registrations (SPA, PKCE)\n'
                    '2. Account: directory organizzative (multitenant) o tenant azienda\n'
                    '3. Permessi: User.Read, Calendars.ReadWrite, offline_access\n'
                    '4. Consent admin se richiesto\n'
                    '5. Build con MS_GRAPH_CLIENT_ID (secret CI / dart-define)',
                  ),
                  const SizedBox(height: 12),
                  _ConfigCopyRow(
                    label: 'Redirect URI',
                    value: redirect,
                  ),
                  const SizedBox(height: 8),
                  _ConfigCopyRow(
                    label: 'Tenant',
                    value: tenant,
                  ),
                  const SizedBox(height: 8),
                  const _ConfigCopyRow(
                    label: 'Dart-define',
                    value: '--dart-define=MS_GRAPH_CLIENT_ID=<CLIENT_ID>',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Guida: deploy/outlook-sync/README.md',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
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
      ),
    );
  }

  Widget _outlookHeaderActions({required bool light}) {
    final fg = light ? Colors.white : null;
    final infoBtn = IconButton(
      tooltip: 'Info configurazione Outlook',
      onPressed: _showOutlookConfigInfo,
      icon: Icon(Icons.info_outline, color: fg, size: 18),
      visualDensity: VisualDensity.compact,
    );
    if (_outlook.isConnected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_outlook.isSyncing)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg ?? Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          Tooltip(
            message: _outlook.displayLabel ?? 'Outlook collegato',
            child: ActionChip(
              avatar: Icon(Icons.check_circle, size: 16, color: fg),
              label: Text(
                'Outlook',
                style: TextStyle(color: fg, fontSize: 12),
              ),
              onPressed: _toggleOutlook,
              backgroundColor: light
                  ? Colors.white.withValues(alpha: 0.15)
                  : null,
              side: light
                  ? BorderSide(color: Colors.white.withValues(alpha: 0.35))
                  : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          IconButton(
            tooltip: 'Scollega Outlook',
            onPressed: _toggleOutlook,
            icon: Icon(Icons.link_off, color: fg, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          infoBtn,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _toggleOutlook,
          icon: Icon(Icons.link, color: fg, size: 18),
          label: Text(
            'Collega Outlook',
            style: TextStyle(color: fg, fontSize: 12),
          ),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: fg,
          ),
        ),
        infoBtn,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final futuristic =
        widget.compactNexus || isGestoproFuturisticUi(context);
    final accent = AppBrandingService.instance.topBarColor;
    final fg = futuristic ? Colors.white : theme.colorScheme.onSurface;

    if (futuristic) {
      return _buildNexusShell(fg, theme);
    }

    return Material(
      color: theme.colorScheme.surface,
      elevation: 16,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent,
                  Color.lerp(accent, Colors.black, 0.25)!,
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.view_agenda_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'La mia agenda',
                    style: CronosFonts.exo2(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                _outlookHeaderActions(light: true),
                IconButton(
                  tooltip: 'Nuova voce',
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Chiudi',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(child: _buildClassicBody(fg, theme)),
        ],
      ),
    );
  }

  Widget _buildNexusShell(Color fg, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      elevation: 12,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: GlowingBorderShell(
        color: CronosFuturisticTheme.borderGlow,
        strokeWidth: 2,
        borderRadius: 14,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CronosFuturisticTheme.voidBg.withValues(alpha: 0.78),
                    CronosFuturisticTheme.electricBlue.withValues(alpha: 0.16),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.chevron_left,
                            color: CronosFuturisticTheme.neonCyan
                                .withValues(alpha: 0.85),
                          ),
                          onPressed: () => _shift(-1),
                        ),
                        Expanded(
                          child: Text(
                            _periodLabel(),
                            textAlign: TextAlign.center,
                            style: CronosFonts.orbitron(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.chevron_right,
                            color: CronosFuturisticTheme.neonCyan
                                .withValues(alpha: 0.85),
                          ),
                          onPressed: () => _shift(1),
                        ),
                        Flexible(child: _outlookHeaderActions(light: true)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Nuova voce',
                          onPressed: () => _openEditor(),
                          icon: Icon(
                            Icons.add,
                            color: CronosFuturisticTheme.neonCyan
                                .withValues(alpha: 0.9),
                          ),
                        ),
                        if (widget.onClose != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            onPressed: widget.onClose,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Row(
                      children: [
                        for (final e in [
                          (_AgendaView.month, 'Mese'),
                          (_AgendaView.day, 'Giorno'),
                          (_AgendaView.week, 'Sett.'),
                          (_AgendaView.list, 'Lista'),
                        ])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() => _view = e.$1);
                                  _reload();
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _view == e.$1
                                          ? CronosFuturisticTheme.borderGlow
                                          : Colors.white24,
                                    ),
                                    color: _view == e.$1
                                        ? CronosFuturisticTheme.borderGlow
                                            .withValues(alpha: 0.15)
                                        : null,
                                  ),
                                  child: Text(
                                    e.$2,
                                    textAlign: TextAlign.center,
                                    style: CronosFonts.exo2(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: CronosFuturisticTheme.neonCyan,
                            ),
                          )
                        : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                              )
                            : _view == _AgendaView.month
                                ? Column(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _NexusMonthGrid(
                                          focus: _focus,
                                          entries: _filtered,
                                          absences: _absences,
                                          onSelectDay: (d) {
                                            setState(() {
                                              _focus = d;
                                            });
                                          },
                                        ),
                                      ),
                                      const Divider(
                                        height: 1,
                                        color: Colors.white12,
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: _buildDayStrip(fg, theme),
                                      ),
                                    ],
                                  )
                                : _buildBody(fg, true, theme),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassicBody(Color fg, ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _shift(-1),
                    icon: Icon(Icons.chevron_left, color: fg),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _shift(1),
                    icon: Icon(Icons.chevron_right, color: fg),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        final n = italyNow();
                        _focus = DateTime(n.year, n.month, n.day);
                      });
                      _reload();
                    },
                    child: const Text('Oggi'),
                  ),
                ],
              ),
              SegmentedButton<_AgendaView>(
                segments: const [
                  ButtonSegment(value: _AgendaView.day, label: Text('Giorno')),
                  ButtonSegment(
                      value: _AgendaView.week, label: Text('Settimana')),
                  ButtonSegment(value: _AgendaView.month, label: Text('Mese')),
                  ButtonSegment(value: _AgendaView.list, label: Text('Elenco')),
                ],
                selected: {_view},
                onSelectionChanged: (s) {
                  setState(() => _view = s.first);
                  _reload();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                style: TextStyle(color: fg),
                decoration: InputDecoration(
                  hintText: 'Cerca titolo, note, luogo…',
                  hintStyle: TextStyle(color: fg.withValues(alpha: 0.45)),
                  prefixIcon:
                      Icon(Icons.search, color: fg.withValues(alpha: 0.7)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Tutti'),
                      selected: _kindFilter == null,
                      onSelected: (_) => setState(() => _kindFilter = null),
                    ),
                    const SizedBox(width: 6),
                    for (final k in AgendaEntryKind.values) ...[
                      FilterChip(
                        label: Text(k.labelIt),
                        selected: _kindFilter == k,
                        onSelected: (_) => setState(() => _kindFilter = k),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _buildBody(fg, false, theme),
        ),
      ],
    );
  }

  Widget _buildDayStrip(Color fg, ThemeData theme) {
    final items = _dayEntries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      children: [
        Text(
          'Giorno ${_focus.day}/${_focus.month}',
          style: CronosFonts.orbitron(
            fontSize: 11,
            letterSpacing: 0.8,
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nessuna voce. Tocca + per aggiungerne.',
              style: TextStyle(color: fg.withValues(alpha: 0.55), fontSize: 12),
            ),
          )
        else
          for (final e in items)
            _EntryTile(
              entry: e,
              nexus: true,
              onTap: () => _openEditor(e),
              onDelete: () => _delete(e),
              onToggleComplete: e.kind == AgendaEntryKind.reminder
                  ? () async {
                      await _svc.upsert(e.copyWith(completed: !e.completed));
                      await _reload();
                    }
                  : null,
            ),
      ],
    );
  }

  String _periodLabel() {
    const months = [
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ];
    switch (_view) {
      case _AgendaView.day:
        return '${_focus.day} ${months[_focus.month - 1]} ${_focus.year}';
      case _AgendaView.week:
        final weekday = _focus.weekday;
        final from = DateTime(_focus.year, _focus.month, _focus.day)
            .subtract(Duration(days: weekday - 1));
        final to = from.add(const Duration(days: 6));
        return '${from.day}/${from.month} – ${to.day}/${to.month}/${to.year}';
      case _AgendaView.month:
      case _AgendaView.list:
        return '${months[_focus.month - 1]} ${_focus.year}';
    }
  }

  Widget _buildBody(Color fg, bool futuristic, ThemeData theme) {
    final items = _filtered;
    if (_view == _AgendaView.month) {
      return _NexusMonthGrid(
        focus: _focus,
        entries: items,
        absences: _absences,
        light: !futuristic,
        onSelectDay: (d) {
          setState(() {
            _focus = d;
            _view = _AgendaView.day;
          });
          _reload();
        },
      );
    }

    if (_view == _AgendaView.week) {
      return _WeekDaysView(
        focus: _focus,
        entries: items,
        absences: _absences,
        futuristic: futuristic,
        onSelectDay: (d) {
          setState(() {
            _focus = d;
            _view = _AgendaView.day;
          });
          _reload();
        },
        onAddForDay: (d) {
          setState(() => _focus = d);
          _openEditor();
        },
        onOpenEntry: _openEditor,
        onDeleteEntry: _delete,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        if (_absences.isNotEmpty) ...[
          Text(
            'Assenze ufficiali',
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final a in _absences)
            Card(
              color: futuristic
                  ? Colors.orange.withValues(alpha: 0.12)
                  : Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(Icons.event_busy, color: Colors.orange),
                title: Text(
                  '${a.tipo} · ${a.stato}',
                  style: TextStyle(color: futuristic ? Colors.white : null),
                ),
                subtitle: Text(
                  '${a.dataDal.day}/${a.dataDal.month} → ${a.dataAl.day}/${a.dataAl.month}'
                  '${a.note.isEmpty ? '' : '\n${a.note}'}',
                  style: TextStyle(
                    color: futuristic ? Colors.white70 : null,
                  ),
                ),
                dense: true,
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.event_note_outlined,
                    size: 48, color: fg.withValues(alpha: 0.35)),
                const SizedBox(height: 10),
                Text(
                  'Nessuna voce in questo periodo.\nAggiungi eventi, note, promemoria o assenze.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuova voce'),
                ),
              ],
            ),
          )
        else
          for (final e in items)
            _EntryTile(
              entry: e,
              nexus: futuristic,
              onTap: () => _openEditor(e),
              onDelete: () => _delete(e),
              onToggleComplete: e.kind == AgendaEntryKind.reminder
                  ? () async {
                      await _svc.upsert(e.copyWith(completed: !e.completed));
                      await _reload();
                    }
                  : null,
            ),
      ],
    );
  }
}

class _WeekDaysView extends StatelessWidget {
  const _WeekDaysView({
    required this.focus,
    required this.entries,
    required this.absences,
    required this.futuristic,
    required this.onSelectDay,
    required this.onAddForDay,
    required this.onOpenEntry,
    required this.onDeleteEntry,
  });

  final DateTime focus;
  final List<AgendaEntry> entries;
  final List<AgendaLinkedAbsence> absences;
  final bool futuristic;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onAddForDay;
  final ValueChanged<AgendaEntry> onOpenEntry;
  final ValueChanged<AgendaEntry> onDeleteEntry;

  static const _dayNames = [
    'Lunedì',
    'Martedì',
    'Mercoledì',
    'Giovedì',
    'Venerdì',
    'Sabato',
    'Domenica',
  ];
  static const _dayShort = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

  DateTime get _weekStart {
    final d = DateTime(focus.year, focus.month, focus.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  List<AgendaEntry> _forDay(DateTime day) {
    return entries.where((e) {
      final s = e.startsAt;
      if (s == null) return false;
      return s.year == day.year && s.month == day.month && s.day == day.day;
    }).toList(growable: false);
  }

  List<AgendaLinkedAbsence> _absForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return absences.where((a) {
      final from = DateTime(a.dataDal.year, a.dataDal.month, a.dataDal.day);
      final to = DateTime(a.dataAl.year, a.dataAl.month, a.dataAl.day);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final today = italyNow();
    final start = _weekStart;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final days = List<DateTime>.generate(
      7,
      (i) => start.add(Duration(days: i)),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  color: futuristic ? Colors.white12 : Colors.black12,
                ),
              Expanded(
                child: _dayColumn(
                  day: days[i],
                  label: _dayShort[i],
                  today: today,
                  tall: true,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: 7,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        return _dayColumn(
          day: days[i],
          label: _dayNames[i],
          today: today,
          tall: false,
        );
      },
    );
  }

  Widget _dayColumn({
    required DateTime day,
    required String label,
    required DateTime today,
    required bool tall,
  }) {
    final isToday =
        day.year == today.year && day.month == today.month && day.day == today.day;
    final selected = day.year == focus.year &&
        day.month == focus.month &&
        day.day == focus.day;
    final dayEntries = _forDay(day);
    final dayAbs = _absForDay(day);
    final headerColor = futuristic
        ? (isToday || selected
            ? CronosFuturisticTheme.neonCyan
            : Colors.white70)
        : (isToday || selected ? const Color(0xFF1565C0) : Colors.black87);
    final cardBg = futuristic
        ? Colors.white.withValues(alpha: isToday || selected ? 0.1 : 0.04)
        : (isToday || selected
            ? const Color(0xFF1565C0).withValues(alpha: 0.06)
            : Colors.white);
    final border = Border.all(
      color: isToday || selected
          ? (futuristic
              ? CronosFuturisticTheme.borderGlow
              : const Color(0xFF1565C0))
          : (futuristic ? Colors.white24 : Colors.black12),
      width: isToday || selected ? 1.4 : 1,
    );

    final header = InkWell(
      onTap: () => onSelectDay(day),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: CronosFonts.exo2(
                      fontWeight: FontWeight.w700,
                      fontSize: tall ? 11 : 13,
                      color: headerColor,
                    ),
                  ),
                  Text(
                    '${day.day}/${day.month}',
                    style: TextStyle(
                      fontSize: tall ? 10 : 12,
                      color: futuristic ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Nuova voce',
              onPressed: () => onAddForDay(day),
              icon: Icon(
                Icons.add,
                size: 18,
                color: futuristic
                    ? CronosFuturisticTheme.neonCyan
                    : const Color(0xFF1565C0),
              ),
            ),
          ],
        ),
      ),
    );

    final body = dayEntries.isEmpty && dayAbs.isEmpty
        ? Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: tall ? 12 : 8,
            ),
            child: Text(
              'Nessuna voce',
              style: TextStyle(
                fontSize: 11,
                color: futuristic ? Colors.white38 : Colors.black38,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in dayAbs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Assenza · ${a.tipo}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: futuristic ? Colors.orange.shade200 : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ),
                for (final e in dayEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onOpenEntry(e),
                        onLongPress: () => onDeleteEntry(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              left: BorderSide(
                                color: _entryColor(e),
                                width: 3,
                              ),
                            ),
                            color: futuristic
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.03),
                          ),
                          child: Row(
                            children: [
                              if (e.fromOutlook)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.mail_outline,
                                    size: 12,
                                    color: futuristic
                                        ? CronosFuturisticTheme.neonCyan
                                        : Colors.blueGrey,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  e.title,
                                  maxLines: tall ? 3 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: futuristic
                                        ? Colors.white
                                        : Colors.black87,
                                    decoration: e.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: tall
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Divider(
                  height: 1,
                  color: futuristic ? Colors.white12 : Colors.black12,
                ),
                Expanded(child: SingleChildScrollView(child: body)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Divider(
                  height: 1,
                  color: futuristic ? Colors.white12 : Colors.black12,
                ),
                body,
              ],
            ),
    );
  }

  Color _entryColor(AgendaEntry e) {
    final h = e.colorHex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return const Color(0xFF1565C0);
    return Color(0xFF000000 | v);
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.onToggleComplete,
    this.nexus = false,
  });

  final AgendaEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onToggleComplete;
  final bool nexus;

  Color get _color {
    final h = entry.colorHex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return const Color(0xFF1565C0);
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final time = entry.allDay
        ? 'Tutto il giorno'
        : entry.startsAt == null
            ? entry.kind.labelIt
            : '${entry.startsAt!.hour.toString().padLeft(2, '0')}:'
                '${entry.startsAt!.minute.toString().padLeft(2, '0')}'
                '${entry.endsAt == null ? '' : ' – ${entry.endsAt!.hour.toString().padLeft(2, '0')}:${entry.endsAt!.minute.toString().padLeft(2, '0')}'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: nexus
          ? Colors.white.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 10,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: nexus ? Colors.white : null,
                  decoration:
                      entry.completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (entry.fromOutlook)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Da Outlook',
                  child: Icon(
                    Icons.mail_outline,
                    size: 16,
                    color: nexus
                        ? CronosFuturisticTheme.neonCyan
                        : Colors.blueGrey,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          [
            '${entry.kind.labelIt} · $time',
            if (entry.reminderEnabled)
              'Avviso: ${agendaReminderPresetLabel(entry.reminderMinutesBefore ?? 15)}',
            if (entry.location.isNotEmpty) entry.location,
            if (entry.body.isNotEmpty) entry.body,
          ].join('\n'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: nexus ? Colors.white70 : null),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleComplete != null)
              IconButton(
                tooltip: entry.completed ? 'Riaprì' : 'Completa',
                onPressed: onToggleComplete,
                icon: Icon(
                  entry.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: nexus ? CronosFuturisticTheme.neonCyan : null,
                ),
              ),
            IconButton(
              tooltip: 'Elimina',
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                color: nexus ? Colors.white54 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NexusMonthGrid extends StatelessWidget {
  const _NexusMonthGrid({
    required this.focus,
    required this.entries,
    required this.absences,
    required this.onSelectDay,
    this.light = false,
  });

  final DateTime focus;
  final List<AgendaEntry> entries;
  final List<AgendaLinkedAbsence> absences;
  final ValueChanged<DateTime> onSelectDay;
  final bool light;

  List<({int week, List<DateTime> days})> _weekRows() {
    final first = DateTime(focus.year, focus.month, 1);
    var cursor = first.subtract(Duration(days: first.weekday - 1));
    final rows = <({int week, List<DateTime> days})>[];
    while (rows.length < 6) {
      final days = List<DateTime>.generate(
        7,
        (i) => cursor.add(Duration(days: i)),
      );
      cursor = cursor.add(const Duration(days: 7));
      if (days.any((d) => d.month == focus.month)) {
        rows.add((week: isoWeekNumber(days.first), days: days));
      }
      if (cursor.month > focus.month && cursor.day > 7) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final today = italyNow();
    final rows = _weekRows();
    const dayLabels = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

    bool hasEntry(DateTime day) => entries.any((e) {
          final s = e.startsAt;
          if (s == null) return false;
          return s.year == day.year &&
              s.month == day.month &&
              s.day == day.day;
        });

    bool hasAbs(DateTime day) => absences.any((a) =>
        !day.isBefore(
            DateTime(a.dataDal.year, a.dataDal.month, a.dataDal.day)) &&
        !day.isAfter(DateTime(a.dataAl.year, a.dataAl.month, a.dataAl.day)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  'SET',
                  textAlign: TextAlign.center,
                  style: CronosFonts.orbitron(
                    fontSize: 8,
                    letterSpacing: 0.5,
                    color: light
                        ? Colors.black45
                        : CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.55),
                  ),
                ),
              ),
              ...dayLabels.map(
                (d) => Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: CronosFonts.exo2(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: light
                          ? Colors.black54
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                for (final row in rows)
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            row.week.toString().padLeft(2, '0'),
                            textAlign: TextAlign.center,
                            style: CronosFonts.orbitron(
                              fontSize: 10,
                              color: light
                                  ? Colors.black45
                                  : CronosFuturisticTheme.neonCyan
                                      .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        ...row.days.map((day) {
                          final inMonth = day.month == focus.month;
                          final isToday = day.year == today.year &&
                              day.month == today.month &&
                              day.day == today.day;
                          final selected = day.year == focus.year &&
                              day.month == focus.month &&
                              day.day == focus.day;
                          final marked = hasEntry(day) || hasAbs(day);
                          return Expanded(
                            child: InkWell(
                              onTap: () => onSelectDay(day),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: (isToday || selected)
                                      ? Border.all(
                                          color: light
                                              ? Colors.blue
                                              : CronosFuturisticTheme
                                                  .borderGlow,
                                          width: 1.2,
                                        )
                                      : null,
                                  color: selected
                                      ? (light
                                          ? Colors.blue.withValues(alpha: 0.12)
                                          : CronosFuturisticTheme.borderGlow
                                              .withValues(alpha: 0.14))
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      textAlign: TextAlign.center,
                                      style: CronosFonts.exo2(
                                        fontSize: 11.5,
                                        fontWeight: (isToday || selected)
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: inMonth
                                            ? (light
                                                ? Colors.black87
                                                : Colors.white
                                                    .withValues(alpha: 0.9))
                                            : (light
                                                ? Colors.black26
                                                : Colors.white
                                                    .withValues(alpha: 0.22)),
                                      ),
                                    ),
                                    if (marked)
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: hasAbs(day)
                                              ? Colors.orange
                                              : (light
                                                  ? Colors.blue
                                                  : CronosFuturisticTheme
                                                      .neonCyan),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
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

class _AgendaEditorDialog extends StatefulWidget {
  const _AgendaEditorDialog({required this.initial});

  final AgendaEntry initial;

  @override
  State<_AgendaEditorDialog> createState() => _AgendaEditorDialogState();
}

class _AgendaEditorDialogState extends State<_AgendaEditorDialog> {
  late AgendaEntryKind _kind;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _location;
  late bool _allDay;
  late DateTime? _starts;
  late DateTime? _ends;
  late String _color;
  late AgendaPriority _priority;
  late bool _completed;
  late bool _reminderEnabled;
  late int _reminderMinutes;

  static const _colors = [
    '#1565C0',
    '#2E7D32',
    '#C62828',
    '#6A1B9A',
    '#EF6C00',
    '#00838F',
    '#455A64',
  ];

  bool get _canRemind =>
      _kind == AgendaEntryKind.event || _kind == AgendaEntryKind.reminder;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _kind = i.kind;
    _title = TextEditingController(text: i.title);
    _body = TextEditingController(text: i.body);
    _location = TextEditingController(text: i.location);
    _allDay = i.allDay;
    _starts = i.startsAt;
    _ends = i.endsAt;
    _color = i.colorHex;
    _priority = i.priority;
    _completed = i.completed;
    _reminderEnabled = i.reminderEnabled;
    _reminderMinutes = i.reminderMinutesBefore ?? 15;
    if (!agendaReminderPresets.contains(_reminderMinutes)) {
      _reminderMinutes = 15;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool start}) async {
    final base = (start ? _starts : _ends) ?? italyNow();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    if (_allDay) {
      setState(() {
        if (start) {
          _starts = DateTime(d.year, d.month, d.day);
        } else {
          _ends = DateTime(d.year, d.month, d.day, 23, 59);
        }
      });
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null || !mounted) return;
    setState(() {
      final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (start) {
        _starts = v;
      } else {
        _ends = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.id.isEmpty ? 'Nuova voce' : 'Modifica voce'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AgendaEntryKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final k in AgendaEntryKind.values)
                    DropdownMenuItem(value: k, child: Text(k.labelIt)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _kind = v;
                      if (v != AgendaEntryKind.event &&
                          v != AgendaEntryKind.reminder) {
                        _reminderEnabled = false;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Titolo'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Luogo'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tutto il giorno'),
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Inizio'),
                subtitle: Text(_starts?.toString() ?? '—'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDateTime(start: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fine'),
                subtitle: Text(_ends?.toString() ?? '—'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDateTime(start: false),
              ),
              DropdownButtonFormField<AgendaPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priorità'),
                items: [
                  for (final p in AgendaPriority.values)
                    DropdownMenuItem(value: p, child: Text(p.labelIt)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _priority = v);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _colors)
                    InkWell(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(
                            0xFF000000 |
                                int.parse(c.replaceFirst('#', ''), radix: 16),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c ? Colors.white : Colors.black26,
                            width: _color == c ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_canRemind) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      const Expanded(child: Text('Avviso')),
                      IconButton(
                        tooltip: 'Info avvisi',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline, size: 18),
                        onPressed: () => showAgendaReminderConfigInfo(context),
                      ),
                    ],
                  ),
                  subtitle: const Text(
                    'Notifica locale (e Outlook se collegato)',
                  ),
                  value: _reminderEnabled,
                  onChanged: (v) => setState(() => _reminderEnabled = v),
                ),
                if (_reminderEnabled)
                  DropdownButtonFormField<int>(
                    initialValue: _reminderMinutes,
                    decoration: const InputDecoration(labelText: 'Quando'),
                    items: [
                      for (final m in agendaReminderPresets)
                        DropdownMenuItem(
                          value: m,
                          child: Text(agendaReminderPresetLabel(m)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _reminderMinutes = v);
                    },
                  ),
              ],
              if (_kind == AgendaEntryKind.reminder)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Completato'),
                  value: _completed,
                  onChanged: (v) => setState(() => _completed = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            final remind = _canRemind && _reminderEnabled;
            Navigator.pop(
              context,
              widget.initial.copyWith(
                kind: _kind,
                title: title,
                body: _body.text.trim(),
                location: _location.text.trim(),
                allDay: _allDay,
                startsAt: _starts,
                endsAt: _ends,
                colorHex: _color,
                priority: _priority,
                completed: _completed,
                reminderEnabled: remind,
                reminderMinutesBefore: remind ? _reminderMinutes : null,
                clearReminderMinutes: !remind,
              ),
            );
          },
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

Future<void> showAgendaReminderConfigInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.notifications_active_outlined),
          SizedBox(width: 8),
          Expanded(child: Text('Avvisi agenda')),
        ],
      ),
      content: const SizedBox(
        width: 400,
        child: Text(
          'Attiva Avviso e scegli quando (inizio, 5/15/30/60 min, 1 giorno, 1 settimana).\n\n'
          '• Locale: notifica sull’app (Windows/Android/web con app aperta).\n'
          '• Outlook: se collegato, lo stesso valore va su '
          'reminderMinutesBeforeStart.\n\n'
          'Un solo avviso per voce (come Outlook).',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

class _ConfigCopyRow extends StatelessWidget {
  const _ConfigCopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copia',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copiato')),
              );
            },
          ),
        ],
      ),
    );
  }
}
