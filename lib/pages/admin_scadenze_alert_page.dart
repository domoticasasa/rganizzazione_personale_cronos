import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../services/deadline_nav_highlight.dart';
import '../utils/date_formatters.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/excel_export_helper.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../utils/device.dart';
import '../utils/mobile_navigation.dart';
import '../utils/formazione_programmazione_dates.dart';
import '../utils/users_directory.dart';
import '../utils/roles.dart';
import '../utils/admin_vista_guard.dart';
import 'dt_programmazione_formazioni_page.dart';
import '../widgets/app_logo.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_nav_sub_item.dart';
import '../widgets/futuristic/futuristic_nav_sub_items_scope.dart';
import '../widgets/futuristic/futuristic_shell_scope.dart';
import 'admin_estintori_page.dart';
import 'admin_formazione_dlgs_81_08_page.dart';
import 'admin_formazione_rfi_page.dart';
import 'admin_logistica_casette_ps_page.dart';
import 'admin_logistica_mdo_ferroviari_page.dart';
import 'admin_logistica_mezzi_stradali_page.dart';
import 'admin_logistica_noleggio_page.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Spezza liste per `.inFilter` (limiti lunghezza URL su Supabase/PostgREST).
List<List<T>> _listChunks<T>(List<T> list, int size) {
  if (list.isEmpty) return const [];
  final n = size <= 0 ? list.length : size;
  final out = <List<T>>[];
  for (var i = 0; i < list.length; i += n) {
    final end = i + n > list.length ? list.length : i + n;
    out.add(list.sublist(i, end));
  }
  return out;
}

/// Voce alert: Logistica usa [kAlertHorizonDays] nel futuro; **tutte** le date passate restano visibili.
/// UQSA (formazione): stesso criterio con orizzonte futuro [kUqsaHorizonDays].
class AdminScadenzeAlertPage extends StatefulWidget {
  const AdminScadenzeAlertPage({super.key, this.hideTopLogo});

  /// Su Android/iOS nasconde il [PageTopLogo] verticale per dare più spazio all’elenco.
  /// Se `null`, si usa [isMobileDevice] (telefono = compatto, desktop/web = con logo).
  final bool? hideTopLogo;

  static const int kAlertHorizonDays = 30;
  /// Formazione DLGS / RFI: giorni futuri inclusi nell’alert (gli scaduti sono sempre inclusi).
  static const int kUqsaHorizonDays = 365;

  @override
  State<AdminScadenzeAlertPage> createState() => _AdminScadenzeAlertPageState();
}

enum _AlertKind {
  estintori,
  mezziStradali,
  mdoFerroviari,
  casettePs,
  noleggio,
  formazioneDlgs,
  formazioneRfi,
  formazioneProgrammazione,
}

const List<_AlertKind> _kAlertKindsOrdered = [
  _AlertKind.estintori,
  _AlertKind.mezziStradali,
  _AlertKind.mdoFerroviari,
  _AlertKind.casettePs,
  _AlertKind.noleggio,
  _AlertKind.formazioneDlgs,
  _AlertKind.formazioneProgrammazione,
  _AlertKind.formazioneRfi,
];

class _DeadlineAlert implements Comparable<_DeadlineAlert> {
  final DateTime expiryDay;
  final String moduleLabel;
  final String titleLine;
  final String subtitleLine;
  final _AlertKind kind;
  final String? navUuid;
  final String? navFormazionePid;
  final String? navFormazioneRowId;
  final int? navRfiPersonaleId;
  /// Per export Excel (es. cantiere attuale su MDO).
  final String exportCantiere;

  _DeadlineAlert({
    required this.expiryDay,
    required this.moduleLabel,
    required this.titleLine,
    required this.subtitleLine,
    required this.kind,
    this.navUuid,
    this.navFormazionePid,
    this.navFormazioneRowId,
    this.navRfiPersonaleId,
    this.exportCantiere = '',
  });

  @override
  int compareTo(_DeadlineAlert other) {
    final c = expiryDay.compareTo(other.expiryDay);
    if (c != 0) return c;
    return moduleLabel.compareTo(other.moduleLabel);
  }

  /// Chiave stabile per salvare lo stato workflow su `alert_scadenze_workflow`.
  String get persistenceKey {
    final parts = <String>[
      kind.name,
      navUuid ?? '',
      navFormazionePid ?? '',
      navFormazioneRowId ?? '',
      navRfiPersonaleId?.toString() ?? '',
      moduleLabel,
      titleLine,
      formatDateDdMmYyyyFromDate(expiryDay),
    ];
    return parts.map((e) => e.trim().toLowerCase()).join('|');
  }
}

class _AdminScadenzeAlertPageState extends State<AdminScadenzeAlertPage> {
  final _supa = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  bool get _compactChrome =>
      widget.hideTopLogo ?? isMobileDevice();
  bool _loading = true;
  String? _error;
  List<_DeadlineAlert> _alerts = [];
  /// `null` = mostra tutti i tipi.
  _AlertKind? _filterKind;

  static const String _kStatoDaGestire = 'DA GESTIRE';
  static const String _kStatoInCorso = 'IN CORSO DI GESTIONE';
  static const List<String> _kAlertStati = [
    _kStatoDaGestire,
    _kStatoInCorso,
  ];

  final Map<String, String> _statusByAlertKey = {};
  final Set<String> _savingStatusKeys = {};
  bool _blinkOn = false;
  Timer? _blinkTimer;

  List<_DeadlineAlert> _alertsAfterKindFilter() {
    if (_filterKind == null) return _alerts;
    return _alerts.where((a) => a.kind == _filterKind).toList();
  }

  List<_DeadlineAlert> get _visibleAlerts {
    final base = _alertsAfterKindFilter();
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base
        .where((a) {
          return a.moduleLabel.toLowerCase().contains(q) ||
              a.titleLine.toLowerCase().contains(q) ||
              a.subtitleLine.toLowerCase().contains(q) ||
              a.exportCantiere.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  int _countKind(_AlertKind k) => _alerts.where((a) => a.kind == k).length;

  String _chipLabel(_AlertKind kind) {
    switch (kind) {
      case _AlertKind.estintori:
        return 'Estintori';
      case _AlertKind.mezziStradali:
        return 'Mezzi stradali';
      case _AlertKind.mdoFerroviari:
        return 'MDO ferroviari';
      case _AlertKind.casettePs:
        return 'Cassette P.S.';
      case _AlertKind.noleggio:
        return 'Noleggio';
      case _AlertKind.formazioneDlgs:
        return 'Formazione D.Lgs. 81/08';
      case _AlertKind.formazioneProgrammazione:
        return 'Programmazione formazioni';
      case _AlertKind.formazioneRfi:
        return 'Formazione RFI';
    }
  }

  String _chipTooltip(_AlertKind kind) {
    switch (kind) {
      case _AlertKind.estintori:
        return 'Scadenze revisioni / controlli estintori';
      case _AlertKind.mezziStradali:
        return 'Scadenze documenti e revisioni mezzi stradali';
      case _AlertKind.mdoFerroviari:
        return 'Scadenze mezzi d\'opera ferroviari';
      case _AlertKind.casettePs:
        return 'Scadenze cassette di pronto soccorso';
      case _AlertKind.noleggio:
        return 'Scadenze contratti / mezzi a noleggio';
      case _AlertKind.formazioneDlgs:
        return 'Scadenze attestati formazione D.Lgs. 81/08';
      case _AlertKind.formazioneProgrammazione:
        return 'Corsi programmati in scadenza o da completare';
      case _AlertKind.formazioneRfi:
        return 'Scadenze attestati / abilitazioni formazione RFI';
    }
  }

  IconData _iconForKind(_AlertKind kind) {
    switch (kind) {
      case _AlertKind.estintori:
        return Icons.fire_extinguisher_outlined;
      case _AlertKind.mezziStradali:
        return Icons.local_shipping_outlined;
      case _AlertKind.mdoFerroviari:
        return Icons.train_outlined;
      case _AlertKind.casettePs:
        return Icons.inventory_2_outlined;
      case _AlertKind.noleggio:
        return Icons.car_rental_outlined;
      case _AlertKind.formazioneDlgs:
        return Icons.school_outlined;
      case _AlertKind.formazioneProgrammazione:
        return Icons.event_note_outlined;
      case _AlertKind.formazioneRfi:
        return Icons.badge_outlined;
    }
  }

  void _syncSidebarSubNav() {
    final scope = FuturisticNavSubItemsScope.maybeOf(context);
    if (scope == null || !_compactChrome) return;

    final total = _alerts.length;
    final items = <FuturisticNavSubItem>[
      FuturisticNavSubItem(
        key: 'all',
        icon: Icons.view_list_outlined,
        label: 'Tutti',
        badge: total > 0 ? '$total' : null,
        onTap: () => setState(() => _filterKind = null),
      ),
      for (final k in _kAlertKindsOrdered)
        FuturisticNavSubItem(
          key: k.name,
          icon: _iconForKind(k),
          label: _chipLabel(k),
          badge: () {
            final n = _countKind(k);
            return n > 0 ? '$n' : null;
          }(),
          onTap: () => setState(() => _filterKind = k),
        ),
    ];

    scope.register(items, activeSubKey: _filterKind?.name ?? 'all');
  }

  String _exportFilterLabel() =>
      _filterKind == null ? 'Tutti' : _chipLabel(_filterKind!);

  String _exportPageName() {
    final kind = _exportFilterLabel()
        .replaceAll('.', '')
        .replaceAll(' ', '_');
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return 'Alert_Scadenze_$kind';
    return 'Alert_Scadenze_${kind}_ricerca';
  }

  String _exportUrgencyText(int leftDays) {
    if (leftDays < 0) return 'Scaduto';
    if (leftDays == 0) return 'Oggi';
    if (leftDays == 1) return 'Domani';
    return 'Tra $leftDays gg';
  }

  Future<void> _exportExcel() async {
    final items = List<_DeadlineAlert>.from(_visibleAlerts)..sort();
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun alert da esportare')),
      );
      return;
    }
    try {
      final pageName = _exportPageName();
      final excel = Excel.createExcel();
      // Usa Sheet1: excel.delete() fallisce su web (liste XML non modificabili).
      final sheet = excel['Sheet1'];
      sheet.appendRow(<String>[
        'Categoria',
        'Modulo',
        'Titolo',
        'Dettaglio',
        'Cantiere attuale',
        'Scadenza',
        'Giorni',
        'Urgenza',
        'Stato',
      ]);
      for (final a in items) {
        final leftDays = a.expiryDay.difference(_today).inDays;
        sheet.appendRow(<dynamic>[
          _chipLabel(a.kind),
          a.moduleLabel,
          a.titleLine,
          a.subtitleLine,
          a.exportCantiere,
          formatDateDdMmYyyyFromDate(a.expiryDay),
          leftDays,
          _exportUrgencyText(leftDays),
          _statusByAlertKey[a.persistenceKey] ?? _kStatoDaGestire,
        ]);
      }
      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: pageName,
        bytes: bytes,
      );
      if (!mounted) return;
      if (saved) {
        final p = ExcelExportHelper.lastSavedPath ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export Excel (${_exportFilterLabel()}, ${items.length} righe)${p.isNotEmpty ? ': $p' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore export Excel: $e')),
      );
    }
  }

  static const Color _filterChipBg = Color(0xFFECECEC);
  static const Color _filterChipSelectedBg = Color(0xFF2F6FED);

  Widget _filterChip({
    required ThemeData theme,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    String? tooltip,
  }) {
    final dark = theme.brightness == Brightness.dark;
    final selectedBg = dark
        ? theme.colorScheme.primary.withValues(alpha: 0.32)
        : _filterChipSelectedBg;
    final idleBg = dark
        ? theme.colorScheme.surfaceContainerHigh
        : _filterChipBg;
    final idleBorder = dark
        ? theme.colorScheme.outline.withValues(alpha: 0.35)
        : const Color(0xFFBEBEBE);
    final idleText = dark
        ? theme.colorScheme.secondary
        : const Color(0xFF2F6FED);

    final chip = FilterChip(
      label: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : idleText,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: idleBg,
      selectedColor: selectedBg,
      side: BorderSide(
        color: selected ? theme.colorScheme.primary : idleBorder,
      ),
      elevation: selected && !dark ? 2 : 0,
      shadowColor: const Color(0x40000000),
    );
    final tip = (tooltip ?? '').trim();
    if (tip.isEmpty) return chip;
    return Tooltip(message: tip, child: chip);
  }

  Widget _buildFilterChips(ThemeData theme) {
    final total = _alerts.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _filterChip(
              theme: theme,
              label: 'Tutti${total > 0 ? ' ($total)' : ''}',
              tooltip: 'Mostra tutte le scadenze in alert',
              selected: _filterKind == null,
              onSelected: (_) => setState(() => _filterKind = null),
            ),
          ),
          ..._kAlertKindsOrdered.map((k) {
            final n = _countKind(k);
            final selected = _filterKind == k;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _filterChip(
                theme: theme,
                label: n > 0 ? '${_chipLabel(k)} ($n)' : _chipLabel(k),
                tooltip: _chipTooltip(k),
                selected: selected,
                onSelected: (v) => setState(() => _filterKind = v ? k : null),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAlertIntro(ThemeData theme, int logDays, int uqsaDays) {
    final longText =
        'Logistica (Mezzi, MDO, Cassette, …): date già scadute e '
        'prossime entro $logDays giorni. Noleggio: righe con stato OPEN '
        '(CLOSED esclusi): futuri fino a $logDays giorni e tutti gli OPEN '
        'già scaduti. UQSA (formazione): tutti gli scaduti e '
        'fino a $uqsaDays giorni nel futuro. '
        'Programmazione corsi: inizio entro $logDays giorni '
        'o in corso. '
        'Data odierna ${formatDateDdMmYyyyFromDate(_today)}. '
        'Date entro $logDays giorni: rosse; scadute: rosse lampeggianti; '
        'oltre $logDays giorni: nere. Tocca una riga per aprire il modulo.';

    if (_compactChrome) {
      return Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          title: Text(
            'Criteri elenco · ${formatDateDdMmYyyyFromDate(_today)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Scaduti + entro $logDays gg (logistica). Tocca una riga per aprire.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            Text(
              longText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        longText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _urgencyLabel(int leftDays) {
    if (leftDays < 0) return 'Scad.';
    if (leftDays == 0) return 'Oggi';
    if (leftDays == 1) return 'Domani';
    return 'Tra $leftDays gg';
  }

  /// Larghezza sufficiente per `dd/MM/yyyy` su una riga nel badge «Scad.».
  static const double _urgencyBadgeWidth = 92;

  bool _isExpiredAlert(int leftDays) => leftDays < 0;

  /// Entro [kAlertHorizonDays] giorni (incluso oggi): date in rosso fisso.
  bool _isWithinOneMonth(int leftDays) =>
      leftDays >= 0 && leftDays <= AdminScadenzeAlertPage.kAlertHorizonDays;

  static final RegExp _dateInTextPattern = RegExp(r'\d{2}/\d{2}/\d{4}');

  Color _blinkingExpiredDateColor(ThemeData theme) => _blinkOn
      ? theme.colorScheme.error
      : theme.colorScheme.error.withValues(alpha: 0.32);

  /// Colore per le date (badge e sottotitolo) in base ai giorni alla scadenza.
  Color _dateTextColor(int leftDays, ThemeData theme) {
    if (_isExpiredAlert(leftDays)) return _blinkingExpiredDateColor(theme);
    if (_isWithinOneMonth(leftDays)) return theme.colorScheme.error;
    return theme.colorScheme.onSurface;
  }

  Widget _buildTextWithStyledDates(
    String text,
    TextStyle style,
    ThemeData theme,
    int leftDays, {
    int maxLines = 2,
  }) {
    if (!_dateInTextPattern.hasMatch(text)) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _dateInTextPattern.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start), style: style));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: style.copyWith(
            color: _dateTextColor(leftDays, theme),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildUrgencyBadge(
    int leftDays,
    DateTime expiryDay,
    ThemeData theme,
  ) {
    final expired = _isExpiredAlert(leftDays);
    final dark = theme.brightness == Brightness.dark;
    final fg = dark
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface;
    final bg = dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerHighest;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: fg,
    );
    final dateStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 11,
      height: 1.15,
      letterSpacing: -0.2,
    );

    final Widget inner;
    if (expired) {
      final dateStr = formatDateDdMmYyyyFromDate(expiryDay);
      inner = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Scad.', textAlign: TextAlign.center, style: labelStyle),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              dateStr,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: dateStyle?.copyWith(
                color: _dateTextColor(leftDays, theme),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    } else {
      inner = Text(
        _urgencyLabel(leftDays),
        textAlign: TextAlign.center,
        style: labelStyle?.copyWith(
          color: _dateTextColor(leftDays, theme),
        ),
      );
    }

    return Container(
      width: _urgencyBadgeWidth,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: inner,
    );
  }

  Widget _buildAlertTextBlock(
    _DeadlineAlert a,
    ThemeData theme, {
    int subtitleMaxLines = 2,
    required int leftDays,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.moduleLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          a.titleLine,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        _dateInTextPattern.hasMatch(a.subtitleLine)
            ? _buildTextWithStyledDates(
                a.subtitleLine,
                theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.25,
                ),
                theme,
                leftDays,
                maxLines: subtitleMaxLines,
              )
            : Text(
                a.subtitleLine,
                maxLines: subtitleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
      ],
    );
  }

  Widget _buildAlertCard(_DeadlineAlert a, ThemeData theme) {
    final leftDays = a.expiryDay.difference(_today).inDays;
    final urgencyBadge = Padding(
      padding: const EdgeInsets.only(top: 2, right: 10),
      child: _buildUrgencyBadge(leftDays, a.expiryDay, theme),
    );

    final Widget body;
    if (_compactChrome) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _openTarget(a),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                urgencyBadge,
                const SizedBox(width: 10),
                Expanded(
                  child: _buildAlertTextBlock(
                    a,
                    theme,
                    subtitleMaxLines: 4,
                    leftDays: leftDays,
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildStatusDropdown(a, theme, fullWidth: true),
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openTarget(a),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  urgencyBadge,
                  Expanded(
                    child: _buildAlertTextBlock(
                      a,
                      theme,
                      leftDays: leftDays,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildStatusDropdown(a, theme),
          IconButton(
            tooltip: 'Apri modulo',
            onPressed: () => _openTarget(a),
            icon: Icon(Icons.chevron_right, color: theme.colorScheme.primary),
          ),
        ],
      );
    }

    return Card(
      elevation: _compactChrome ? 0 : 0,
      margin: EdgeInsets.zero,
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      shape: theme.cardTheme.shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.35),
            ),
          ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: body,
      ),
    );
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _withinHorizon(DateTime expiryDay) {
    final days = expiryDay.difference(_today).inDays;
    if (days < 0) return true;
    return days <= AdminScadenzeAlertPage.kAlertHorizonDays;
  }

  bool _withinUqsaHorizon(DateTime expiryDay) {
    final days = expiryDay.difference(_today).inDays;
    if (days < 0) return true;
    return days <= AdminScadenzeAlertPage.kUqsaHorizonDays;
  }

  /// Allineato a [AdminLogisticaNoleggioPage]: OPEN / CLOSED da testo DB.
  String _normalizeNoleggioStato(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase();
    if (s.contains('clos')) return 'CLOSED';
    if (s.contains('open')) return 'OPEN';
    return '';
  }

  DateTime? _calendarDay(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final quick = DateTime.tryParse(s);
    if (quick != null) return DateTime(quick.year, quick.month, quick.day);
    final iso = parseFlexibleDateToIsoDate(s);
    final parsed = iso != null ? DateTime.tryParse(iso) : null;
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    return null;
  }

  DateTime _endOfMonth(DateTime monthAnyDay) {
    final y = monthAnyDay.year;
    final m = monthAnyDay.month;
    final next = m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    return next.subtract(const Duration(days: 1));
  }

  /// Scadenza mensile salvata come primo giorno del mese (Casette P.S.).
  DateTime? _casetteExpiryDay(dynamic raw) {
    final d = _calendarDay(raw);
    if (d == null) return null;
    return _endOfMonth(DateTime(d.year, d.month, 1));
  }

  String _nonEmpty(dynamic v) => (v ?? '').toString().trim();

  String _fmt(dynamic v) => formatDateDdMmYyyy(v);

  /// Data calendario da Postgres (`date` / ISO `yyyy-MM-dd…`) senza ambiguità di giorno locale.
  DateTime? _calendarDayFromDynamic(dynamic vd) {
    if (vd == null) return null;
    if (vd is DateTime) return DateTime(vd.year, vd.month, vd.day);
    final s = vd.toString().trim();
    if (s.isEmpty) return null;
    final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (ymd != null) {
      final y = int.tryParse(ymd.group(1)!);
      final m = int.tryParse(ymd.group(2)!);
      final d = int.tryParse(ymd.group(3)!);
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateTime(dt.year, dt.month, dt.day);
    return null;
  }

  /// Scadenza attestato DLGS: prefisso `yyyy-MM-dd` da Postgres + fallback `_calendarDay` (dd/MM).
  DateTime? _formazioneDlgsScadenzaDay(dynamic v) {
    final iso = _calendarDayFromDynamic(v);
    if (iso != null) return iso;
    return _calendarDay(v);
  }

  Future<List<Map<String, dynamic>>> _fetchAllFormazioneCorsiRows() async {
    /// Solo corsi con scadenza valorizzata (come colonne SCAD della griglia).
    PostgrestFilterBuilder<List<Map<String, dynamic>>> dlgsRowsQuery() {
      return _supa
          .from('formazione_corsi')
          .select('id, corso, personale_id, scadenza_attestato, note')
          .not('scadenza_attestato', 'is', null);
    }

    Future<List<Map<String, dynamic>>> plainSelect() async {
      try {
        final corsi = await dlgsRowsQuery();
        return (corsi as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        final corsi = await _supa
            .from('formazione_corsi')
            .select('id, corso, personale_id, scadenza_attestato, note');
        return (corsi as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }

    try {
      const pageSize = 1000;
      var start = 0;
      final out = <Map<String, dynamic>>[];
      // Ordina per scadenza (non per id): altrimenti le prime pagine sono piene di righe
      // storiche senza scadenza utile e gli alert DLGS risultano quasi vuoti.
      for (var page = 0; page < 100; page++) {
        final batch = await dlgsRowsQuery()
            .order('scadenza_attestato', ascending: true)
            .order('id', ascending: true)
            .range(start, start + pageSize - 1);
        final list = (batch as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (list.isEmpty) break;
        out.addAll(list);
        if (list.length < pageSize) break;
        start += pageSize;
      }
      if (out.isNotEmpty) return out;
    } catch (_) {}
    return plainSelect();
  }

  DateTime? _rfiParseCell(Map<String, dynamic> row) {
    final vd = row['value_date'];
    if (vd != null) {
      final cal = _calendarDayFromDynamic(vd);
      if (cal != null) return cal;
    }
    final textRaw = (row['value_text'] ?? '').toString().trim();
    if (textRaw.isEmpty) return null;
    final iso = parseFlexibleDateToIsoDate(textRaw);
    if (iso != null) {
      final dt = DateTime.tryParse(iso);
      if (dt != null) return DateTime(dt.year, dt.month, dt.day);
    }
    final plain = DateTime.tryParse(textRaw);
    if (plain != null) return DateTime(plain.year, plain.month, plain.day);
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(textRaw);
    if (m != null) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final y = int.tryParse(m.group(3)!);
      if (d != null && mo != null && y != null) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }

  static const String _rfiProssimaScadenzaLabel = 'Prossima Scadenza Mantenimento';

  String _rfiTrackDisplayName(String trackKey) {
    final raw = trackKey.trim().replaceAll('_', ' ');
    if (raw.isEmpty) return 'Corso RFI';
    return raw.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      if (w.length == 1) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String _rfiAlertSubtitle(String courseLabel, DateTime expiryDay) {
    return '$courseLabel · $_rfiProssimaScadenzaLabel: '
        '${formatDateDdMmYyyyFromDate(expiryDay)}';
  }

  /// Solo la **scadenza sintesi del profilo** (PROSSIMA SCADENZA / SCADENZA / verifica annuale).
  /// Esclusi MANTENIMENTO e colonne RINNOVO (…): sono step intermedi con date che possono
  /// risultare «passate» mentre il profilo è ancora coperto dalla PROSSIMA SCADENZA.
  /// (Es. «DATA ATTESTATO … Ultimo Rinnovo» contiene «rinnovo» nel titolo ma non è una scadenza.)
  bool _rfiFieldIsFormazioneExpiryColumn(String fieldKey) {
    final raw = fieldKey.trim();
    if (raw.isEmpty) return false;
    final n = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (n.contains('data attestato')) return false;
    if (n.contains('rilasc')) return false;
    if (n.contains('definizione')) return false;
    if (n.contains('data consegna')) return false;
    if (n.contains('programmazione')) return false;
    if (n.startsWith('mantenimento')) return false;
    if (n.startsWith('rinnovo')) return false;

    if (n.contains('prossima') && n.contains('scadenza')) return true;
    if (n == 'scadenza' || n.endsWith('_scadenza')) return true;
    if (n.contains('sacdenza') && n.contains('verifica')) return true;
    if (n.contains('scadenza') && n.contains('verifica annuale')) return true;
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _alerts = [];
    });

    try {
      final results = await Future.wait<List<_DeadlineAlert>>([
        _loadEstintori(),
        _loadMezziStradali(),
        _loadMdo(),
        _loadCasette(),
        _loadNoleggio(),
        _loadDlgs(),
        _loadProgrammazione(),
        _loadRfi(),
        _loadRfiGriglia(),
      ]);

      final merged = _dedupeFormazioneRfi(results.expand((e) => e).toList())
        ..sort();
      await _loadWorkflowStatuses(merged);
      if (!mounted) return;
      setState(() => _alerts = merged);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusFor(_DeadlineAlert a) =>
      _statusByAlertKey[a.persistenceKey] ?? _kStatoDaGestire;

  Future<void> _loadWorkflowStatuses(List<_DeadlineAlert> alerts) async {
    _statusByAlertKey.clear();
    for (final a in alerts) {
      _statusByAlertKey[a.persistenceKey] = _kStatoDaGestire;
    }
    if (alerts.isEmpty) return;
    // Audit legale A3: stato workflow leggibile solo dagli admin (RLS).
    if (!isAnyAdminRole(currentSessionRole() ?? '')) return;

    try {
      final keys = alerts.map((a) => a.persistenceKey).toSet().toList();
      for (final chunk in _listChunks(keys, 80)) {
        final res = await _supa
            .from('alert_scadenze_workflow')
            .select('alert_key, stato')
            .inFilter('alert_key', chunk);
        for (final row in res as List) {
          final m = Map<String, dynamic>.from(row as Map);
          final key = (m['alert_key'] ?? '').toString();
          final stato = (m['stato'] ?? '').toString().trim();
          if (key.isNotEmpty && _kAlertStati.contains(stato)) {
            _statusByAlertKey[key] = stato;
          }
        }
      }
    } on PostgrestException catch (e) {
      if (e.code != '42P01') rethrow;
    }
  }

  Future<void> _setAlertStatus(_DeadlineAlert a, String stato) async {
    if (!_kAlertStati.contains(stato)) return;
    // Audit legale A3: solo admin con permessi di scrittura.
    if (!canMutateAsAdmin(currentSessionRole() ?? '')) return;
    final key = a.persistenceKey;
    final prev = _statusFor(a);
    setState(() {
      _statusByAlertKey[key] = stato;
      _savingStatusKeys.add(key);
    });
    try {
      await _supa.from('alert_scadenze_workflow').upsert({
        'alert_key': key,
        'stato': stato,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusByAlertKey[key] = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salvataggio stato fallito: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingStatusKeys.remove(key));
      }
    }
  }

  Widget _buildStatusDropdown(
    _DeadlineAlert a,
    ThemeData theme, {
    bool fullWidth = false,
  }) {
    final key = a.persistenceKey;
    final saving = _savingStatusKeys.contains(key);
    final stato = _statusFor(a);
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: stato,
        isDense: true,
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, size: 20),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        items: _kAlertStati
            .map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: saving || !canMutateAsAdmin(currentSessionRole() ?? '')
            ? null
            : (v) {
                if (v != null && v != stato) _setAlertStatus(a, v);
              },
      ),
    );

    final field = InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: theme.inputDecorationTheme.fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        border: theme.inputDecorationTheme.enabledBorder,
        enabledBorder: theme.inputDecorationTheme.enabledBorder,
        focusedBorder: theme.inputDecorationTheme.focusedBorder,
      ),
      child: saving
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : dropdown,
    );

    final dropdownBox = fullWidth
        ? SizedBox(width: double.infinity, child: field)
        : SizedBox(width: 190, child: field);

    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Stato',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          dropdownBox,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Stato:',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        dropdownBox,
      ],
    );
  }

  Future<List<_DeadlineAlert>> _loadEstintori() async {
    final res = await _supa.from('estintori').select();
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final out = <_DeadlineAlert>[];
    const fields = <String, String>{
      'prossimo_controllo': 'Scadenza controllo semestrale',
      'prossima_revisione': 'Scadenza revisione',
      'prossimo_collaudo': 'Scadenza collaudo',
      'scadenza_omologazione': 'Scadenza omologazione',
    };
    for (final r in list) {
      for (final fe in fields.entries) {
        final day = _calendarDay(r[fe.key]);
        if (day == null || !_withinHorizon(day)) continue;
        final idUuid = _nonEmpty(r['id_uuid']);
        out.add(_DeadlineAlert(
          expiryDay: day,
          moduleLabel: 'Logistica · Estintori',
          titleLine:
              '${_nonEmpty(r['codice_interno']).isEmpty ? 'Estintore' : _nonEmpty(r['codice_interno'])} — ${fe.value}',
          subtitleLine: 'Scade il ${_fmt(r[fe.key])}',
          kind: _AlertKind.estintori,
          navUuid: idUuid.isEmpty ? null : idUuid,
        ));
      }
    }
    return out;
  }

  Future<List<_DeadlineAlert>> _loadMezziStradali() async {
    final res = await _supa.from('logistica_mezzi_stradali').select();
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    const fields = <String, String>{
      'scadenza_contratto': 'Scadenza contratto',
      'scadenza_assicurazione': 'Scadenza assicurazione',
      'scadenza_bolli': 'Scadenza bolli',
      'scadenza_revisione': 'Scadenza revisione',
      'scadenza_verifica_periodica_gru': 'Scadenza verifica periodica gru',
      'scadenza_revisione_biennale_cronotachigrafo':
          'Scadenza revisione biennale cronotachigrafo',
    };
    final out = <_DeadlineAlert>[];
    for (final r in list) {
      for (final fe in fields.entries) {
        final day = _calendarDay(r[fe.key]);
        if (day == null || !_withinHorizon(day)) continue;
        final idUuid = _nonEmpty(r['id_uuid']);
        out.add(_DeadlineAlert(
          expiryDay: day,
          moduleLabel: 'Logistica · Mezzi stradali',
          titleLine:
              '${_nonEmpty(r['targa']).isEmpty ? _nonEmpty(r['numerazione']) : _nonEmpty(r['targa'])} — ${fe.value}',
          subtitleLine: 'Scade il ${_fmt(r[fe.key])}',
          kind: _AlertKind.mezziStradali,
          navUuid: idUuid.isEmpty ? null : idUuid,
        ));
      }
    }
    return out;
  }

  Future<List<_DeadlineAlert>> _loadMdo() async {
    final res = await _supa.from('logistica_mdo_ferroviari').select();
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    const fields = <String, String>{
      'scadenza_va': 'Scadenza VA',
      'scadenza_cpo': 'Scadenza CPO',
      'scadenza_vqq': 'Scadenza VQQ',
      'scadenza_terrazzino': 'Scadenza terrazzino',
      'scadenza_gru': 'Scadenza gru',
      'scadenza_cestello': 'Scadenza cestello',
    };
    final out = <_DeadlineAlert>[];
    for (final r in list) {
      for (final fe in fields.entries) {
        final day = _calendarDay(r[fe.key]);
        if (day == null || !_withinHorizon(day)) continue;
        final short =
            _nonEmpty(r['matricola_interna']).isEmpty ? 'MDO' : _nonEmpty(r['matricola_interna']);
        final idUuid = _nonEmpty(r['id_uuid']);
        final hint = _nonEmpty(r['codice_identificativo_targa_rfi']).isEmpty
            ? short
            : _nonEmpty(r['codice_identificativo_targa_rfi']);
        final dt = _nonEmpty(r['dt_nome']);
        final subtitleParts = <String>[
          'Scade il ${_fmt(r[fe.key])}',
          if (hint.isNotEmpty) hint,
          if (dt.isNotEmpty) 'DT: $dt',
        ];
        out.add(_DeadlineAlert(
          expiryDay: day,
          moduleLabel: 'Logistica · MDO ferroviari',
          titleLine: '$short — ${fe.value}',
          subtitleLine: subtitleParts.join(' · '),
          kind: _AlertKind.mdoFerroviari,
          navUuid: idUuid.isEmpty ? null : idUuid,
          exportCantiere: _nonEmpty(r['cantiere_attuale']),
        ));
      }
    }
    return out;
  }

  Future<List<_DeadlineAlert>> _loadCasette() async {
    final res = await _supa.from('logistica_casette_ps').select();
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final commesseRows =
        await _supa.from('commesse').select('id_uuid,nome').eq('active', true);
    final commesse = <String, String>{};
    for (final e in (commesseRows as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      commesse[(m['id_uuid'] ?? '').toString()] = (m['nome'] ?? '').toString();
    }
    final out = <_DeadlineAlert>[];
    for (final r in list) {
      final day = _casetteExpiryDay(r['scadenze']);
      if (day == null || !_withinHorizon(day)) continue;
      final cid = _nonEmpty(r['commessa_id']);
      final idUuid = _nonEmpty(r['id_uuid']);
      final commResolved = (commesse[cid] ?? '').toString().trim();
      final commessaLabel =
          commResolved.isEmpty ? (cid.isEmpty ? '—' : cid) : commResolved;
      out.add(_DeadlineAlert(
        expiryDay: day,
        moduleLabel: 'Logistica · Cassette P.S.',
        titleLine:
            '${_nonEmpty(r['codice_interno']).isEmpty ? 'Cassetta' : _nonEmpty(r['codice_interno'])} — Fine mese',
        subtitleLine: 'Mese ${_fmt(r['scadenze'])} · Commessa: $commessaLabel',
        kind: _AlertKind.casettePs,
        navUuid: idUuid.isEmpty ? null : idUuid,
      ));
    }
    return out;
  }

  Future<List<_DeadlineAlert>> _loadNoleggio() async {
    final res = await _supa.from('logistica_noleggio').select();
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final out = <_DeadlineAlert>[];
    for (final r in list) {
      // Solo OPEN in alert; CLOSED e stati vuoti/non riconosciuti esclusi.
      if (_normalizeNoleggioStato(r['stato']) != 'OPEN') continue;

      final day = _calendarDay(r['nolo_al']);
      if (day == null) continue;
      final daysLeft = day.difference(_today).inDays;
      // OPEN: futuri solo entro orizzonte; scaduti sempre (CLOSED già esclusi sopra).
      if (daysLeft > AdminScadenzeAlertPage.kAlertHorizonDays) continue;
      final title =
          _nonEmpty(r['descrizione']).isEmpty ? 'Noleggio' : _nonEmpty(r['descrizione']);
      final idUuid = _nonEmpty(r['id_uuid']);
      final comm = _nonEmpty(r['commessa']);
      out.add(_DeadlineAlert(
        expiryDay: day,
        moduleLabel: 'Logistica · Noleggio',
        titleLine: title,
        subtitleLine:
            'Nolo fino al ${_fmt(r['nolo_al'])}${comm.isEmpty ? '' : ' · $comm'}',
        kind: _AlertKind.noleggio,
        navUuid: idUuid.isEmpty ? null : idUuid,
      ));
    }
    return out;
  }

  Future<List<_DeadlineAlert>> _loadDlgs() async {
    try {
      final rows = await _fetchAllFormazioneCorsiRows();
      final pids =
          rows.map((r) => _nonEmpty(r['personale_id'])).where((s) => s.isNotEmpty).toSet();
      final names = <String, String>{};
      if (pids.isNotEmpty) {
        for (final slice in _listChunks(pids.toList(), 80)) {
          final pres = await _supa
              .from('personale')
              .select('id_uuid, full_name')
              .inFilter('id_uuid', slice);
          for (final e in (pres as List)) {
            final m = Map<String, dynamic>.from(e as Map);
            if (UsersDirectory.isPersonaleHiddenFromDirectory(m, const {})) {
              continue;
            }
            final id = _nonEmpty(m['id_uuid']);
            if (id.isEmpty) continue;
            names[id] =
                _nonEmpty(m['full_name']).isEmpty ? id : _nonEmpty(m['full_name']);
          }
        }
        final unresolved =
            pids.where((id) => !names.containsKey(id)).toList(growable: false);
        if (unresolved.isNotEmpty) {
          final intIds = unresolved
              .map((s) => int.tryParse(s))
              .whereType<int>()
              .toSet()
              .toList();
          if (intIds.isNotEmpty) {
            try {
              for (final slice in _listChunks(intIds, 80)) {
                final presByInt = await _supa
                    .from('personale')
                    .select('id, id_uuid, full_name')
                    .inFilter('id', slice);
                for (final e in (presByInt as List)) {
                  final m = Map<String, dynamic>.from(e as Map);
                  if (UsersDirectory.isPersonaleHiddenFromDirectory(
                      m, const {})) {
                    continue;
                  }
                  final idInt = int.tryParse((m['id'] ?? '').toString());
                  final uuid = _nonEmpty(m['id_uuid']);
                  final nmRaw = _nonEmpty(m['full_name']);
                  final nm =
                      nmRaw.isEmpty ? (uuid.isEmpty ? 'Dipendente' : uuid) : nmRaw;
                  if (idInt != null) {
                    names[idInt.toString()] = nm;
                  }
                  if (uuid.isNotEmpty) names[uuid] = nm;
                }
              }
            } catch (_) {
              // Ambienti senza `personale.id` filtrabile: ignora fallback.
            }
          }
        }
      }
      final out = <_DeadlineAlert>[];
      for (final r in rows) {
        final day = _formazioneDlgsScadenzaDay(r['scadenza_attestato']);
        if (day == null || !_withinUqsaHorizon(day)) continue;
        final pid = _nonEmpty(r['personale_id']);
        final rowId = (r['id'] ?? '').toString().trim();
        out.add(_DeadlineAlert(
          expiryDay: day,
          moduleLabel: 'UQSA · Formazione D.Lgs. 81/08',
          titleLine: '${names[pid] ?? 'Dipendente'} — ${_nonEmpty(r['corso'])}',
          subtitleLine: 'Scade il ${_fmt(r['scadenza_attestato'])}',
          kind: _AlertKind.formazioneDlgs,
          navFormazionePid: pid.isEmpty ? null : pid,
          navFormazioneRowId: rowId.isEmpty ? null : rowId,
        ));
      }
      return out;
    } catch (_) {
      // Evita che _loadDlgs faccia fallire tutto il Future.wait (lista vuota totale).
      return [];
    }
  }

  Future<Map<String, String>> _loadPersonaleNames(Set<String> pids) async {
    final names = <String, String>{};
    if (pids.isEmpty) return names;
    for (final slice in _listChunks(pids.toList(), 80)) {
      final pres = await _supa
          .from('personale')
          .select('id_uuid, full_name')
          .inFilter('id_uuid', slice);
      for (final e in (pres as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        if (UsersDirectory.isPersonaleHiddenFromDirectory(m, const {})) {
          continue;
        }
        final id = _nonEmpty(m['id_uuid']);
        if (id.isEmpty) continue;
        names[id] =
            _nonEmpty(m['full_name']).isEmpty ? id : _nonEmpty(m['full_name']);
      }
    }
    final unresolved =
        pids.where((id) => !names.containsKey(id)).toList(growable: false);
    if (unresolved.isNotEmpty) {
      final intIds = unresolved
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet()
          .toList();
      if (intIds.isNotEmpty) {
        try {
          for (final slice in _listChunks(intIds, 80)) {
            final presByInt = await _supa
                .from('personale')
                .select('id, id_uuid, full_name')
                .inFilter('id', slice);
            for (final e in (presByInt as List)) {
              final m = Map<String, dynamic>.from(e as Map);
              if (UsersDirectory.isPersonaleHiddenFromDirectory(m, const {})) {
                continue;
              }
              final idInt = int.tryParse((m['id'] ?? '').toString());
              final uuid = _nonEmpty(m['id_uuid']);
              final nmRaw = _nonEmpty(m['full_name']);
              final nm =
                  nmRaw.isEmpty ? (uuid.isEmpty ? 'Dipendente' : uuid) : nmRaw;
              if (idInt != null) names[idInt.toString()] = nm;
              if (uuid.isNotEmpty) names[uuid] = nm;
            }
          }
        } catch (_) {}
      }
    }
    return names;
  }

  /// Corsi con data programmazione imminente o in corso.
  Future<List<_DeadlineAlert>> _loadProgrammazione() async {
    try {
      List<Map<String, dynamic>> rows;
      try {
        final res = await _supa
            .from('formazione_corsi')
            .select(
              'id, corso, personale_id, prima_data, seconda_data, ente, orario, modalita',
            )
            .not('prima_data', 'is', null);
        rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        final res = await _supa
            .from('formazione_corsi')
            .select('id, corso, personale_id, prima_data, ente, orario, modalita')
            .not('prima_data', 'is', null);
        rows = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      final pids = rows
          .map((r) => _nonEmpty(r['personale_id']))
          .where((s) => s.isNotEmpty)
          .toSet();
      final names = await _loadPersonaleNames(pids);
      final horizon = AdminScadenzeAlertPage.kAlertHorizonDays;
      final out = <_DeadlineAlert>[];
      for (final r in rows) {
        final start = parseDateOnly(r['prima_data']);
        if (start == null) continue;
        final end =
            programmazioneEndDate(r['prima_data'], r['seconda_data']) ?? start;
        final daysToStart = start.difference(_today).inDays;
        final daysToEnd = end.difference(_today).inDays;
        var include = false;
        if (daysToStart >= 0 && daysToStart <= horizon) include = true;
        if (daysToStart <= 0 && daysToEnd >= 0) include = true;
        if (!include) continue;

        final expiryDay = daysToStart >= 0 ? start : end;
        final pid = _nonEmpty(r['personale_id']);
        final rowId = (r['id'] ?? '').toString().trim();
        final progLabel =
            formatProgrammazioneDalAl(r['prima_data'], r['seconda_data']);
        final when = daysToStart > 0
            ? 'Inizia il $progLabel'
            : daysToEnd >= 0
                ? 'In corso · $progLabel'
                : 'Terminato il ${_fmt(end)}';
        final extra = <String>[
          if (_nonEmpty(r['orario']).isNotEmpty) _nonEmpty(r['orario']),
          if (_nonEmpty(r['modalita']).isNotEmpty) _nonEmpty(r['modalita']),
        ].join(' · ');
        out.add(_DeadlineAlert(
          expiryDay: expiryDay,
          moduleLabel: 'UQSA · Programmazione formazioni',
          titleLine:
              '${names[pid] ?? 'Dipendente'} — ${_nonEmpty(r['corso'])}',
          subtitleLine: extra.isEmpty ? when : '$when · $extra',
          kind: _AlertKind.formazioneProgrammazione,
          navFormazionePid: pid.isEmpty ? null : pid,
          navFormazioneRowId: rowId.isEmpty ? null : rowId,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<_DeadlineAlert>> _loadRfi() async {
    List<Map<String, dynamic>> rows;
    try {
      final records = await _supa.from('formazione_rfi_records').select(
          'personale_id, track_key, field_key, value_date, value_text');
      rows =
          (records as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
    final pres = await _supa.from('personale').select('id, full_name');
    final names = <int, String>{};
    for (final e in (pres as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      if (UsersDirectory.isPersonaleHiddenFromDirectory(m, const {})) continue;
      final id = int.tryParse((m['id'] ?? '').toString());
      if (id == null) continue;
      final nm = _nonEmpty(m['full_name']);
      names[id] = nm.isEmpty ? 'ID $id' : nm;
    }
    final out = <_DeadlineAlert>[];
    for (final r in rows) {
      final fk = _nonEmpty(r['field_key']);
      if (!_rfiFieldIsFormazioneExpiryColumn(fk)) continue;
      final day = _rfiParseCell(r);
      if (day == null || !_withinUqsaHorizon(day)) continue;
      final pid = int.tryParse((r['personale_id'] ?? '').toString());
      final track = _nonEmpty(r['track_key']);
      final nome = pid != null ? (names[pid] ?? 'Personale $pid') : 'Personale';
      final courseLabel = _rfiTrackDisplayName(track);
      out.add(_DeadlineAlert(
        expiryDay: day,
        moduleLabel: 'UQSA · Formazione RFI',
        titleLine: nome,
        subtitleLine: _rfiAlertSubtitle(courseLabel, day),
        kind: _AlertKind.formazioneRfi,
        navRfiPersonaleId: pid,
      ));
    }
    return out;
  }

  /// Scadenze dalla tabella aggregata `formazione_rfi_corsi` (stesso SQL della UI griglia).
  Future<List<_DeadlineAlert>> _loadRfiGriglia() async {
    List<Map<String, dynamic>> rows;
    try {
      final res = await _supa
          .from('formazione_rfi_corsi')
          .select('personale_id, corso, scadenza_attestato');
      rows =
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
    final uuids =
        rows.map((r) => _nonEmpty(r['personale_id'])).where((s) => s.isNotEmpty).toSet();
    final uuidToInt = <String, int>{};
    final uuidToName = <String, String>{};
    if (uuids.isNotEmpty) {
      try {
        final pres = await _supa
            .from('personale')
            .select('id, id_uuid, full_name')
            .inFilter('id_uuid', uuids.toList());
        for (final e in (pres as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          if (UsersDirectory.isPersonaleHiddenFromDirectory(m, const {})) {
            continue;
          }
          final uuid = _nonEmpty(m['id_uuid']);
          final idInt = int.tryParse((m['id'] ?? '').toString());
          if (uuid.isEmpty || idInt == null) continue;
          uuidToInt[uuid] = idInt;
          final nm = _nonEmpty(m['full_name']);
          uuidToName[uuid] = nm.isEmpty ? 'Personale $idInt' : nm;
        }
      } catch (_) {}
    }
    final out = <_DeadlineAlert>[];
    for (final r in rows) {
      final uuid = _nonEmpty(r['personale_id']);
      final day = _calendarDay(r['scadenza_attestato']);
      if (uuid.isEmpty || day == null || !_withinUqsaHorizon(day)) continue;
      final pidInt = uuidToInt[uuid];
      if (pidInt == null) continue;
      final nome = uuidToName[uuid] ?? 'Personale $pidInt';
      final corso =
          _nonEmpty(r['corso']).isEmpty ? 'Corso RFI' : _nonEmpty(r['corso']);
      out.add(_DeadlineAlert(
        expiryDay: day,
        moduleLabel: 'UQSA · Formazione RFI',
        titleLine: nome,
        subtitleLine: _rfiAlertSubtitle(corso, day),
        kind: _AlertKind.formazioneRfi,
        navRfiPersonaleId: pidInt,
      ));
    }
    return out;
  }

  List<_DeadlineAlert> _dedupeFormazioneRfi(List<_DeadlineAlert> items) {
    final seen = <String>{};
    final out = <_DeadlineAlert>[];
    for (final a in items) {
      if (a.kind != _AlertKind.formazioneRfi) {
        out.add(a);
        continue;
      }
      final pid = a.navRfiPersonaleId ?? -1;
      final key = '$pid|${a.expiryDay.toIso8601String()}|${a.titleLine}';
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(a);
    }
    return out;
  }

  void _openTarget(_DeadlineAlert a) {
    switch (a.kind) {
      case _AlertKind.estintori:
      case _AlertKind.mezziStradali:
      case _AlertKind.mdoFerroviari:
      case _AlertKind.casettePs:
      case _AlertKind.noleggio:
        final u = (a.navUuid ?? '').trim();
        if (u.isNotEmpty) {
          DeadlineNavHighlight.armUuid(u);
        } else {
          DeadlineNavHighlight.clear();
        }
        break;
      case _AlertKind.formazioneDlgs:
      case _AlertKind.formazioneProgrammazione:
        final p = (a.navFormazionePid ?? '').trim();
        final rid = (a.navFormazioneRowId ?? '').trim();
        if (p.isNotEmpty && rid.isNotEmpty) {
          DeadlineNavHighlight.armFormazioneDlgs(personaleId: p, rowId: rid);
        } else {
          DeadlineNavHighlight.clear();
        }
        break;
      case _AlertKind.formazioneRfi:
        final pid = a.navRfiPersonaleId;
        if (pid != null && pid > 0) {
          DeadlineNavHighlight.armRfiPersonRow(pid);
        } else {
          DeadlineNavHighlight.clear();
        }
        break;
    }

    Widget page;
    switch (a.kind) {
      case _AlertKind.estintori:
        page = useMobileUi(context)
            ? const AdminEstintoriMobilePage()
            : const AdminEstintoriPage();
        break;
      case _AlertKind.mezziStradali:
        page = useMobileUi(context)
            ? const AdminLogisticaMezziStradaliMobilePage()
            : const AdminLogisticaMezziStradaliPage();
        break;
      case _AlertKind.mdoFerroviari:
        page = useMobileUi(context)
            ? const AdminLogisticaMdoFerroviariMobilePage()
            : const AdminLogisticaMdoFerroviariPage();
        break;
      case _AlertKind.casettePs:
        page = useMobileUi(context)
            ? const AdminLogisticaCasettePsMobilePage()
            : const AdminLogisticaCasettePsPage();
        break;
      case _AlertKind.noleggio:
        page = useMobileUi(context)
            ? const AdminLogisticaNoleggioMobilePage()
            : const AdminLogisticaNoleggioPage();
        break;
      case _AlertKind.formazioneDlgs:
        page = useMobileUi(context)
            ? const AdminFormazioneDlgsMobilePage()
            : const AdminFormazionePage();
        break;
      case _AlertKind.formazioneProgrammazione:
        page = useMobileUi(context)
            ? const DtProgrammazioneFormazioniMobilePage()
            : const DtProgrammazioneFormazioniPage();
        break;
      case _AlertKind.formazioneRfi:
        page = useMobileUi(context)
            ? const AdminFormazioneRfiMobilePage()
            : const AdminFormazioneRfiPage();
        break;
    }
    FuturisticNavigation.pushPage(context, page: page, title: a.moduleLabel);
  }

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (!mounted) return;
      setState(() => _blinkOn = !_blinkOn);
    });
    _load();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FuturisticNavSubItemsScope.maybeOf(context) != null && _compactChrome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncSidebarSubNav();
      });
    }

    final theme = Theme.of(context);
    final logDays = AdminScadenzeAlertPage.kAlertHorizonDays;
    final uqsaDays = AdminScadenzeAlertPage.kUqsaHorizonDays;
    final scrollBody = _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Errore caricamento:\n$_error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _alerts.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                              Icon(Icons.check_circle_outline,
                                  size: 56, color: theme.colorScheme.outline),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Nessuna scadenza in elenco '
                                  '(Logistica altri moduli: scaduti + entro ~$logDays gg; '
                                  'Noleggio: stato OPEN (CLOSED nascosti); '
                                  'futuri entro ~$logDays gg + OPEN già scaduti; '
                                  'UQSA: scaduti + entro ~$uqsaDays gg).',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          )
                        : Builder(
                            builder: (context) {
                              final kindFiltered = _alertsAfterKindFilter();
                              final vis = _visibleAlerts;
                              final filterEmpty =
                                  _filterKind != null && kindFiltered.isEmpty;
                              final searchEmpty = _searchCtrl.text
                                      .trim()
                                      .isNotEmpty &&
                                  vis.isEmpty &&
                                  kindFiltered.isNotEmpty;
                              final emptySlice = filterEmpty || searchEmpty;
                              final itemCount = 1 + (emptySlice ? 1 : vis.length);
                              return ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                                itemCount: itemCount,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  if (i == 0) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildAlertIntro(theme, logDays, uqsaDays),
                                        Padding(
                                          padding:
                                              const EdgeInsets.fromLTRB(0, 0, 0, 10),
                                          child: TextField(
                                            controller: _searchCtrl,
                                            onChanged: (_) => setState(() {}),
                                            textInputAction: TextInputAction.search,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Cerca per modulo, titolo o dettaglio…',
                                              prefixIcon:
                                                  const Icon(Icons.search_outlined),
                                              suffixIcon: _searchCtrl.text.isEmpty
                                                  ? null
                                                  : IconButton(
                                                      tooltip: 'Cancella ricerca',
                                                      onPressed: () {
                                                        _searchCtrl.clear();
                                                        setState(() {});
                                                      },
                                                      icon: const Icon(Icons.clear),
                                                    ),
                                              isDense: true,
                                              filled: true,
                                              fillColor: theme
                                                  .inputDecorationTheme.fillColor,
                                              border: theme
                                                  .inputDecorationTheme.enabledBorder,
                                              enabledBorder: theme
                                                  .inputDecorationTheme.enabledBorder,
                                              focusedBorder: theme
                                                  .inputDecorationTheme.focusedBorder,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.fromLTRB(0, 0, 0, 8),
                                          child: Text(
                                            'Filtra per tipo di scadenza',
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        _buildFilterChips(theme),
                                      ],
                                    );
                                  }
                                  if (filterEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 24,
                                      ),
                                      child: Text(
                                        'Nessuna scadenza per la categoria selezionata.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  }
                                  if (searchEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 24,
                                      ),
                                      child: Text(
                                        'Nessun risultato per la ricerca.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  }
                                  final a = vis[i - 1];
                                  return _buildAlertCard(a, theme);
                                },
                              );
                            },
                          ),
                        );

    final chromeless = FuturisticShellScope.hideChromeOf(context);

    if (chromeless) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FuturisticInlineToolbar(
            title: 'Alert scadenze',
            actions: [
              IconButton(
                tooltip: 'Export Excel (filtro e ricerca correnti)',
                onPressed: _loading ? null : _exportExcel,
                icon: const Icon(Icons.download_outlined),
              ),
              IconButton(
                tooltip: 'Aggiorna',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(child: scrollBody),
        ],
      );
    }

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Alert scadenze'),
        actions: [
          IconButton(
            tooltip:
                'Export Excel (filtro e ricerca correnti)',
            onPressed: _loading ? null : _exportExcel,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      )),
      body: PageWithTopLogo(
        child: scrollBody,
      ),
    );
  }
}
