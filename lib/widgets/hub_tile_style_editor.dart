import 'package:flutter/material.dart';
import '../utils/cronos_fonts.dart';

import '../hub/hub_icon_catalog.dart';
import '../hub/hub_tile_color_palette.dart';
import '../hub/hub_tile_fonts.dart';
import '../hub/hub_tile_grid.dart';
import '../hub/hub_tile_style.dart';
import '../theme/cronos_futuristic_theme.dart';
import 'cronos_3d_surface.dart';
import 'futuristic/neon_card.dart';
import 'hub_icon_picker_sheet.dart';
import 'hub_tile_auto_fit_text.dart';

/// Editor aspetto tile: nome, dimensioni, colori.
Future<HubTileStyle?> showHubTileStyleEditor({
  required BuildContext context,
  required String itemKey,
  required String defaultLabel,
  required IconData defaultIcon,
  String defaultSubtitle = '',
  HubTileStyle? initial,
  /// Pulsanti a pillola (lista dipendente): solo colori/testo/icona, no griglia.
  bool pillButtonOnly = false,
  /// Tema scuro Nexus con anteprima NeonCard e slider dimensioni.
  bool futuristicMode = false,
}) {
  return showDialog<HubTileStyle>(
    context: context,
    builder: (ctx) => _HubTileStyleEditorDialog(
      itemKey: itemKey,
      defaultLabel: defaultLabel,
      defaultSubtitle: defaultSubtitle,
      defaultIcon: defaultIcon,
      initial: initial ?? const HubTileStyle(),
      pillButtonOnly: pillButtonOnly,
      futuristicMode: futuristicMode,
    ),
  );
}

class _HubTileStyleEditorDialog extends StatefulWidget {
  const _HubTileStyleEditorDialog({
    required this.itemKey,
    required this.defaultLabel,
    required this.defaultSubtitle,
    required this.defaultIcon,
    required this.initial,
    this.pillButtonOnly = false,
    this.futuristicMode = false,
  });

  final String itemKey;
  final String defaultLabel;
  final String defaultSubtitle;
  final IconData defaultIcon;
  final HubTileStyle initial;
  final bool pillButtonOnly;
  final bool futuristicMode;

  @override
  State<_HubTileStyleEditorDialog> createState() =>
      _HubTileStyleEditorDialogState();
}

class _HubTileStyleEditorDialogState extends State<_HubTileStyleEditorDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _subtitleCtrl;
  late double _sizeScale;
  Color? _backgroundColor;
  Color? _textColor;
  Color? _iconColor;
  int? _gridCol;
  int? _gridRow;
  int? _iconCodepoint;
  String? _fontFamilyKey;
  double? _titleFontSize;
  double? _iconFontSize;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(
      text: widget.initial.effectiveLabel(widget.defaultLabel),
    );
    _subtitleCtrl = TextEditingController(
      text: widget.initial.effectiveSubtitle(widget.defaultSubtitle),
    );
    _sizeScale = widget.initial.sizeScale;
    _backgroundColor = widget.initial.backgroundColor;
    _textColor = widget.initial.textColor;
    _iconColor = widget.initial.iconColor;
    _gridCol = widget.initial.gridCol;
    _gridRow = widget.initial.gridRow;
    _iconCodepoint = widget.initial.iconCodepoint;
    _fontFamilyKey = widget.initial.fontFamilyKey ?? HubTileFonts.keyDefault;
    _titleFontSize = widget.initial.titleFontSize;
    _iconFontSize = widget.initial.iconFontSize;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  HubTileStyle _buildResult() {
    final custom = _labelOrNull(_labelCtrl.text, widget.defaultLabel);
    final customSub =
        _labelOrNull(_subtitleCtrl.text, widget.defaultSubtitle);
    if (widget.pillButtonOnly) {
      return HubTileStyle(
        customLabel: custom,
        customSubtitle: customSub,
        backgroundColor: _backgroundColor,
        textColor: _textColor,
        iconColor: _iconColor,
        sizeScale: _sizeScale,
        iconCodepoint: _iconCodepoint,
        fontFamilyKey: _fontFamilyKey == HubTileFonts.keyDefault
            ? null
            : _fontFamilyKey,
        titleFontSize: _titleFontSize,
        iconFontSize: _iconFontSize,
      );
    }
    final spans = HubTileGridConfig.spansForScale(_sizeScale);
    return HubTileStyle(
      customLabel: custom,
      customSubtitle: customSub,
      backgroundColor: _backgroundColor,
      textColor: _textColor,
      iconColor: _iconColor,
      sizeScale: _sizeScale,
      iconCodepoint: _iconCodepoint,
      fontFamilyKey: _fontFamilyKey == HubTileFonts.keyDefault
          ? null
          : _fontFamilyKey,
      titleFontSize: _titleFontSize,
      iconFontSize: _iconFontSize,
      gridCol: _gridCol,
      gridRow: _gridRow,
      gridColSpan: spans.$1,
      gridRowSpan: spans.$2,
    );
  }

  Future<void> _pickIcon() async {
    final picked = await showHubIconPickerSheet(
      context: context,
      selectedCodepoint: _iconCodepoint,
      fallbackIcon: widget.defaultIcon,
    );
    if (!mounted) return;
    setState(() => _iconCodepoint = picked);
  }

  void _setGridCell(int col, int row) {
    setState(() {
      _gridCol = col;
      _gridRow = row;
    });
  }

  void _clearPosition() {
    setState(() {
      _gridCol = null;
      _gridRow = null;
    });
  }

  void _reset() {
    setState(() {
      _labelCtrl.text = widget.defaultLabel;
      _subtitleCtrl.text = widget.defaultSubtitle;
      _sizeScale = 1.0;
      _backgroundColor = null;
      _textColor = null;
      _iconColor = null;
      _gridCol = null;
      _gridRow = null;
      _iconCodepoint = null;
      _fontFamilyKey = HubTileFonts.keyDefault;
      _titleFontSize = null;
      _iconFontSize = null;
    });
  }

  List<(String, String, String?)> get _fontOptions {
    if (!widget.futuristicMode) return HubTileFonts.options;
    return [
      (HubTileFonts.keyDefault, 'Orbitron (predefinito)', null),
      ('orbitron', 'Orbitron', null),
      ('exo2', 'Exo 2', null),
      ...HubTileFonts.options.skip(1),
    ];
  }

  static String? _labelOrNull(String typed, String fallback) {
    final t = typed.trim();
    if (t.isEmpty) return null;
    if (t == fallback.trim()) return null;
    return t;
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final style = widget.futuristicMode
        ? CronosFonts.orbitron(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.85),
          )
        : Theme.of(context).textTheme.titleSmall;
    return Text(text, style: style);
  }

  Widget _pxSizeSlider({
    required bool auto,
    required double? valuePx,
    required double autoPreviewPx,
    required ValueChanged<double?> onChanged,
  }) {
    const minPx = HubTileStyle.minIconFontSize;
    const maxPx = HubTileStyle.maxIconFontSize;
    final v = (valuePx ?? autoPreviewPx).clamp(minPx, maxPx);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatica'),
          subtitle: Text(auto ? 'Usa la misura predefinita' : 'Scegli da 1 a 50 px'),
          value: auto,
          onChanged: (on) {
            if (on) {
              onChanged(null);
            } else {
              onChanged(v.roundToDouble());
            }
          },
        ),
        if (!auto)
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: minPx,
                  max: maxPx,
                  divisions: 49,
                  value: v,
                  label: '${v.round()} px',
                  onChanged: (n) => onChanged(n.roundToDouble()),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${v.round()} px',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFormFields(BuildContext context, HubTileStyle preview) {
    final previewIconSize =
        preview.resolveIconSize(fillCell: false, scale: _sizeScale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, 'Nome e descrizione'),
        const SizedBox(height: 8),
        TextField(
          controller: _labelCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Nome visualizzato',
            helperText: 'Nome attuale del pulsante: puoi modificarlo qui.',
            border: const OutlineInputBorder(),
          ),
        ),
        if (!widget.pillButtonOnly) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _subtitleCtrl,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Descrizione sotto il titolo',
              helperText: widget.defaultSubtitle.trim().isEmpty
                  ? 'Vuota di default: scrivi un testo se vuoi una riga sotto il nome.'
                  : 'Descrizione attuale: puoi modificarla qui.',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle(
          context,
          widget.pillButtonOnly
              ? 'Dimensione testo e spaziatura'
              : 'Dimensione pulsante',
        ),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 0.75, label: Text('S')),
            ButtonSegment(value: 1.0, label: Text('M')),
            ButtonSegment(value: 1.25, label: Text('L')),
            ButtonSegment(value: 1.5, label: Text('XL')),
            ButtonSegment(value: 2.0, label: Text('XXL')),
          ],
          selected: {_sizeScale},
          onSelectionChanged: (values) {
            setState(() => _sizeScale = values.first);
          },
        ),
        if (widget.futuristicMode && !widget.pillButtonOnly) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Scala fine',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CronosFuturisticTheme.neonCyan
                          .withValues(alpha: 0.65),
                    ),
              ),
              Expanded(
                child: Slider(
                  value: _sizeScale.clamp(
                    HubTileStyle.minScale,
                    HubTileStyle.maxScale,
                  ),
                  min: HubTileStyle.minScale,
                  max: HubTileStyle.maxScale,
                  divisions: 14,
                  label: '${(_sizeScale * 100).round()}%',
                  onChanged: (v) => setState(() => _sizeScale = v),
                ),
              ),
              Text(
                '${(_sizeScale * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          Text(
            'Il pulsante occupa più spazio nella griglia (fino a ${HubTileGridConfig.spansForScale(_sizeScale).$1}×${HubTileGridConfig.spansForScale(_sizeScale).$2} celle).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle(context, 'Icona'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickIcon,
          icon: Icon(
            HubIconCatalog.iconFromCodepoint(
              _iconCodepoint,
              widget.defaultIcon,
            ),
            size: previewIconSize.clamp(18, 40),
          ),
          label: Text(
            _iconCodepoint == null
                ? 'Icona predefinita — tocca per cambiare'
                : (HubIconCatalog.byCodepoint(_iconCodepoint)?.labelIt ??
                    'Icona personalizzata'),
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle(context, 'Dimensione icona'),
        const SizedBox(height: 6),
        Text(
          _iconFontSize == null
              ? 'Automatica (${previewIconSize.round()} px con scala attuale)'
              : '${_iconFontSize!.round()} px',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        _pxSizeSlider(
          auto: _iconFontSize == null,
          valuePx: _iconFontSize,
          autoPreviewPx: previewIconSize,
          onChanged: (v) => setState(() => _iconFontSize = v),
        ),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Carattere titolo'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(_fontFamilyKey),
          initialValue: _fontFamilyKey ?? HubTileFonts.keyDefault,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Tipo carattere',
          ),
          items: [
            for (final o in _fontOptions)
              DropdownMenuItem(
                value: o.$1,
                child: Text(
                  o.$2,
                  style: TextStyle(fontFamily: o.$3),
                ),
              ),
          ],
          onChanged: (v) => setState(
            () => _fontFamilyKey = v ?? HubTileFonts.keyDefault,
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle(context, 'Dimensione testo'),
        const SizedBox(height: 6),
        Text(
          _titleFontSize == null
              ? 'Automatica: si riduce per entrare nel pulsante'
              : '${_titleFontSize!.round()} px',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        _pxSizeSlider(
          auto: _titleFontSize == null,
          valuePx: _titleFontSize,
          autoPreviewPx: 15 * _sizeScale,
          onChanged: (v) => setState(() => _titleFontSize = v),
        ),
        const SizedBox(height: 16),
        _ColorPickerRow(
          title: 'Colore sfondo',
          value: _backgroundColor,
          onChanged: (c) => setState(() => _backgroundColor = c),
          futuristic: widget.futuristicMode,
        ),
        const SizedBox(height: 12),
        _ColorPickerRow(
          title: 'Colore testo',
          value: _textColor,
          onChanged: (c) => setState(() => _textColor = c),
          futuristic: widget.futuristicMode,
        ),
        const SizedBox(height: 12),
        _ColorPickerRow(
          title: 'Colore icona',
          value: _iconColor,
          onChanged: (c) => setState(() => _iconColor = c),
          futuristic: widget.futuristicMode,
        ),
        if (!widget.pillButtonOnly && !widget.futuristicMode) ...[
          const SizedBox(height: 16),
          _sectionTitle(
            context,
            'Posizione griglia ${HubTileGridConfig.sizeLabel}',
          ),
          const SizedBox(height: 6),
          Text(
            'Tocca una cella. Tile grandi occupano più celle '
            '(${HubTileGridConfig.spansForScale(_sizeScale).$1}×'
            '${HubTileGridConfig.spansForScale(_sizeScale).$2} con scala attuale).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          _HubGridCellPicker(
            selectedCol: _gridCol,
            selectedRow: _gridRow,
            colSpan: HubTileGridConfig.spansForScale(_sizeScale).$1,
            rowSpan: HubTileGridConfig.spansForScale(_sizeScale).$2,
            onCellSelected: _setGridCell,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clearPosition,
            icon: const Icon(Icons.grid_off_outlined, size: 18),
            label: const Text('Posizione automatica'),
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle(context, 'Anteprima'),
        const SizedBox(height: 8),
        widget.pillButtonOnly
            ? _PillStylePreview(
                defaultLabel: widget.defaultLabel,
                style: preview,
                defaultIcon: widget.defaultIcon,
              )
            : widget.futuristicMode
                ? _FuturisticStylePreview(
                    defaultLabel: widget.defaultLabel,
                    defaultSubtitle: widget.defaultSubtitle,
                    style: preview,
                    defaultIcon: widget.defaultIcon,
                  )
                : _StylePreview(
                    defaultLabel: widget.defaultLabel,
                    defaultSubtitle: widget.defaultSubtitle,
                    style: preview,
                    defaultIcon: widget.defaultIcon,
                  ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildResult();
    final form = SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: _buildFormFields(context, preview),
      ),
    );

    if (!widget.futuristicMode) {
      return AlertDialog(
        title: const Text('Personalizza pulsante'),
        content: form,
        actions: [
          TextButton(onPressed: _reset, child: const Text('Ripristina default')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _buildResult()),
            child: const Text('Applica'),
          ),
        ],
      );
    }

    return Theme(
      data: CronosFuturisticTheme.themeData(Theme.of(context).textTheme).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0A1828),
          labelStyle: TextStyle(
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.7),
          ),
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.35),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.25),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: CronosFuturisticTheme.neonCyan,
              width: 1.5,
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF041018);
              }
              return Colors.white.withValues(alpha: 0.85);
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return CronosFuturisticTheme.neonCyan;
              }
              return const Color(0xFF0A1828);
            }),
          ),
        ),
      ),
      child: Dialog(
        backgroundColor: const Color(0xFF061020),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.45),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Personalizza modulo',
                        style: CronosFonts.orbitron(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.2),
              ),
              Flexible(child: Padding(padding: const EdgeInsets.all(16), child: form)),
              Divider(
                height: 1,
                color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.2),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _reset,
                      child: Text(
                        'Ripristina default',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Annulla',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: CronosFuturisticTheme.neonCyan,
                        foregroundColor: const Color(0xFF041018),
                      ),
                      onPressed: () => Navigator.pop(context, _buildResult()),
                      child: const Text('Applica'),
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

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.futuristic = false,
  });

  final String title;
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final bool futuristic;

  Future<void> _openCustomPicker(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _CustomColorPickerDialog(initial: value),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: futuristic
                    ? CronosFonts.orbitron(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.85),
                      )
                    : Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ColorSwatch(
                  color: value!,
                  selected: true,
                  onTap: () {},
                  size: 22,
                ),
              ),
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Default'),
            ),
          ],
        ),
        SizedBox(
          height: 132,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in HubTileColorPalette.swatches)
                    _ColorSwatch(
                      color: color,
                      selected: value != null &&
                          value!.toARGB32() == color.toARGB32(),
                      onTap: () => onChanged(color),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _openCustomPicker(context),
          icon: const Icon(Icons.palette_outlined, size: 18),
          label: const Text('Altro colore (sfumature)'),
        ),
      ],
    );
  }
}

/// Selettore HSV per colori non in tavolozza.
class _CustomColorPickerDialog extends StatefulWidget {
  const _CustomColorPickerDialog({this.initial});

  final Color? initial;

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial ?? Colors.blue);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('Scegli colore'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(height: 16),
            _slider(
              label: 'Tonalità',
              value: _hsv.hue,
              max: 360,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _slider(
              label: 'Saturazione',
              value: _hsv.saturation,
              max: 1,
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _slider(
              label: 'Luminosità',
              value: _hsv.value,
              max: 1,
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Usa questo colore'),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 26,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black26,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _PillStylePreview extends StatelessWidget {
  const _PillStylePreview({
    required this.defaultLabel,
    required this.style,
    required this.defaultIcon,
  });

  final String defaultLabel;
  final HubTileStyle style;
  final IconData defaultIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = style.sizeScale;
    final icon = style.effectiveIcon(defaultIcon);
    final iconColor = style.iconColor ?? theme.colorScheme.primary;
    final textColor = style.textColor ?? theme.colorScheme.primary;
    final bg = style.backgroundColor ?? const Color(0xFFECECEC);
    final titleStyle = style.titleTextStyle(
      base: theme.textTheme.labelLarge ?? const TextStyle(),
      color: textColor,
      fontWeight: FontWeight.w600,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: textColor,
          elevation: 4,
          shadowColor: const Color(0xFFBEBEBE),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 14 * scale,
            vertical: 12 * scale,
          ),
        ),
        icon: Icon(
          icon,
          color: iconColor,
          size: style.resolveIconSize(fillCell: false, scale: scale),
        ),
        label: Text(style.effectiveLabel(defaultLabel), style: titleStyle),
      ),
    );
  }
}

class _FuturisticStylePreview extends StatelessWidget {
  const _FuturisticStylePreview({
    required this.defaultLabel,
    required this.defaultSubtitle,
    required this.style,
    required this.defaultIcon,
  });

  final String defaultLabel;
  final String defaultSubtitle;
  final HubTileStyle style;
  final IconData defaultIcon;

  @override
  Widget build(BuildContext context) {
    final label = style.effectiveLabel(defaultLabel);
    final subtitle = style.effectiveSubtitle(defaultSubtitle);
    final icon = style.effectiveIcon(defaultIcon);
    final accent = style.iconColor ?? CronosFuturisticTheme.neonCyan;
    final previewStyle = style.copyWith(sizeScale: style.sizeScale.clamp(0.75, 1.5));
    final previewSize = 120.0 * previewStyle.sizeScale.clamp(0.75, 1.5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF04080F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CronosFuturisticTheme.neonCyan.withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: previewSize,
          height: previewSize,
          child: NeonCard(
            title: label,
            subtitle: subtitle.trim().isEmpty ? null : subtitle,
            icon: icon,
            color: accent,
            tileStyle: previewStyle,
          ),
        ),
      ),
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({
    required this.defaultLabel,
    required this.defaultSubtitle,
    required this.style,
    required this.defaultIcon,
  });

  final String defaultLabel;
  final String defaultSubtitle;
  final HubTileStyle style;
  final IconData defaultIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = style.sizeScale;
    final iconSize = style.resolveIconSize(fillCell: false, scale: scale);
    final iconColor = style.iconColor ?? theme.colorScheme.primary;
    final textColor = style.textColor ?? theme.colorScheme.onSurface;
    final icon = style.effectiveIcon(defaultIcon);
    final titleStyle = style.titleTextStyle(
      base: theme.textTheme.titleMedium ?? const TextStyle(),
      color: textColor,
    );
    final subtitle = style.effectiveSubtitle(defaultSubtitle);
    final subtitleColor = theme.colorScheme.onSurfaceVariant;
    final titleSize = titleStyle.fontSize ?? 15;
    return SizedBox(
      width: 168 * scale.clamp(0.75, 1.5),
      height: 126 * scale.clamp(0.75, 1.5),
      child: Cronos3dSurface(
        color: style.backgroundColor,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * scale,
            vertical: 10 * scale,
          ),
          child: Column(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(icon, size: iconSize, color: iconColor),
                ),
              ),
              SizedBox(height: 6 * scale),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: subtitle.trim().isNotEmpty ? 3 : 1,
                      child: HubTileAutoFitText(
                        text: style.effectiveLabel(defaultLabel),
                        maxLines: 3,
                        minFontSize: 6,
                        maxFontSize: titleSize.clamp(6.0, 50.0),
                        style: titleStyle.copyWith(height: 1.15),
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      SizedBox(height: 4 * scale),
                      Expanded(
                        flex: 2,
                        child: HubTileAutoFitText(
                          text: subtitle,
                          maxLines: 3,
                          minFontSize: 5,
                          maxFontSize: (titleSize * 0.78).clamp(5.0, titleSize),
                          style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.15,
                                color: subtitleColor,
                              ) ??
                              TextStyle(height: 1.15, color: subtitleColor),
                        ),
                      ),
                    ],
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

/// Pulsante modifica aspetto (modalità riordino).
class CronosHubTileStyleButton extends StatelessWidget {
  const CronosHubTileStyleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Personalizza aspetto',
        icon: const Icon(Icons.palette_outlined, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

/// Selettore visuale celle griglia hub.
class _HubGridCellPicker extends StatelessWidget {
  const _HubGridCellPicker({
    required this.selectedCol,
    required this.selectedRow,
    required this.colSpan,
    required this.rowSpan,
    required this.onCellSelected,
  });

  final int? selectedCol;
  final int? selectedRow;
  final int colSpan;
  final int rowSpan;
  final void Function(int col, int row) onCellSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const cols = HubTileGridConfig.columns;
    const rows = HubTileGridConfig.rows;

    return AspectRatio(
      aspectRatio: cols / rows * 0.85,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 3.0;
          final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
          final cellH = (constraints.maxHeight - gap * (rows - 1)) / rows;

          return Stack(
            children: [
              for (var r = 0; r < rows; r++)
                for (var c = 0; c < cols; c++)
                  Positioned(
                    left: c * (cellW + gap),
                    top: r * (cellH + gap),
                    width: cellW,
                    height: cellH,
                    child: Material(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          final col =
                              c.clamp(0, HubTileGridConfig.columns - colSpan);
                          final row =
                              r.clamp(0, HubTileGridConfig.rows - rowSpan);
                          onCellSelected(col, row);
                        },
                      ),
                    ),
                  ),
              if (selectedCol != null && selectedRow != null)
                Positioned(
                  left: selectedCol! * (cellW + gap),
                  top: selectedRow! * (cellH + gap),
                  width: colSpan * cellW + (colSpan - 1) * gap,
                  height: rowSpan * cellH + (rowSpan - 1) * gap,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.primary, width: 2),
                        color: scheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Calcola dimensioni tile in base allo stile.
class HubTileStyleMetrics {
  const HubTileStyleMetrics({
    required this.iconSize,
    required this.titleSize,
    required this.subtitleSize,
    required this.paddingH,
    required this.paddingV,
    required this.gapIconTitle,
    required this.gapTitleSubtitle,
    this.titleStyleBuilder,
  });

  final double iconSize;
  final double titleSize;
  final double subtitleSize;
  final double paddingH;
  final double paddingV;
  final double gapIconTitle;
  final double gapTitleSubtitle;
  final TextStyle Function(TextStyle base, Color? color)? titleStyleBuilder;

  TextStyle resolveTitleStyle(TextStyle base, Color? color) {
    if (titleStyleBuilder != null) {
      return titleStyleBuilder!(base, color);
    }
    return base.copyWith(
      fontSize: titleSize,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  factory HubTileStyleMetrics.fromStyle({
    required HubTileStyle? style,
    required bool fillCell,
    double cellScale = 1.0,
  }) {
    final scale = style?.sizeScale ?? 1.0;
    final spanScale = HubTileGridConfig.visualScaleForStyle(style, scale);
    final layoutScale = fillCell ? cellScale.clamp(0.75, 2.5) : 1.0;
    final baseTitle = fillCell ? 13.0 : 15.0;
    final explicitTitle = style?.titleFontSize;
    final titleSize = explicitTitle != null
        ? explicitTitle.clamp(
            HubTileStyle.minTitleFontSize,
            HubTileStyle.maxTitleFontSize,
          )
        : (baseTitle * scale * spanScale * layoutScale).clamp(
            HubTileStyle.minTitleFontSize,
            HubTileStyle.maxTitleFontSize,
          );
    final explicitIcon = style?.iconFontSize;
    final autoIcon = (fillCell ? 30.0 : 36.0) * scale * spanScale * layoutScale;
    final iconSize = explicitIcon != null
        ? explicitIcon.clamp(
            HubTileStyle.minIconFontSize,
            HubTileStyle.maxIconFontSize,
          )
        : autoIcon.clamp(
            HubTileStyle.minIconFontSize,
            HubTileStyle.maxIconFontSize,
          );
    return HubTileStyleMetrics(
      iconSize: iconSize,
      titleSize: titleSize,
      subtitleSize: (titleSize * 0.78).clamp(6.0, titleSize),
      paddingH: (fillCell ? 8.0 : 12.0) * scale * spanScale * layoutScale,
      paddingV: (fillCell ? 10.0 : 14.0) * scale * spanScale * layoutScale,
      gapIconTitle: (fillCell ? 6.0 : 8.0) * scale * layoutScale,
      gapTitleSubtitle: (fillCell ? 4.0 : 6.0) * scale * layoutScale,
      titleStyleBuilder: style == null
          ? null
          : (TextStyle base, Color? color) =>
              style.titleTextStyle(base: base, color: color),
    );
  }

  /// Scala icona/testo in base alle dimensioni reali della cella hub.
  static double cellScaleFromConstraints(BoxConstraints constraints) {
    const refCell = 100.0;
    final w = constraints.maxWidth;
    if (!w.isFinite || w <= 0) return 1.0;
    final h = constraints.maxHeight.isFinite ? constraints.maxHeight : w;
    return (w < h ? w : h) / refCell;
  }
}
