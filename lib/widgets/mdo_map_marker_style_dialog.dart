import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../models/mdo_map_marker_style.dart';
import 'mdo_map_marker_painter.dart';

Future<MdoMapMarkerStyle?> showMdoMapMarkerStyleDialog(
  BuildContext context, {
  required MdoMapMarkerStyle initial,
}) {
  return showDialog<MdoMapMarkerStyle>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => PointerInterceptor(
      intercepting: true,
      child: _MarkerStyleDialog(initial: initial),
    ),
  );
}

class _MarkerStyleDialog extends StatefulWidget {
  const _MarkerStyleDialog({required this.initial});

  final MdoMapMarkerStyle initial;

  @override
  State<_MarkerStyleDialog> createState() => _MarkerStyleDialogState();
}

class _MarkerStyleDialogState extends State<_MarkerStyleDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late double _mapSize = widget.initial.mapSizeScale;
  late MdoMapMarkerKindStyle _commessa = widget.initial.commessa;
  late MdoMapMarkerKindStyle _mdo = widget.initial.mdo;
  late MdoMapMarkerKindStyle _box = widget.initial.box;
  late MdoMapMarkerKindStyle _estintore = widget.initial.estintore;
  late MdoMapMarkerKindStyle _casettaPs = widget.initial.casettaPs;
  late MdoMapMarkerKindStyle _struttura = widget.initial.struttura;
  late MdoMapMarkerKindStyle _officina = widget.initial.officina;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: kMdoMapMarkerTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  MdoMapMarkerStyle get _draft => MdoMapMarkerStyle(
        mapSizeScale: _mapSize,
        commessa: _commessa,
        mdo: _mdo,
        box: _box,
        estintore: _estintore,
        casettaPs: _casettaPs,
        struttura: _struttura,
        officina: _officina,
      );

  MdoMapMarkerKindTab get _tab => kMdoMapMarkerTabs[_tabs.index];

  MdoMapMarkerKindStyle get _current => switch (_tab.id) {
        'commessa' => _commessa,
        'box' => _box,
        'estintore' => _estintore,
        'casetta_ps' => _casettaPs,
        'struttura' => _struttura,
        'officina' => _officina,
        _ => _mdo,
      };

  void _setCurrent(MdoMapMarkerKindStyle v) {
    setState(() {
      switch (_tab.id) {
        case 'commessa':
          _commessa = v;
        case 'box':
          _box = v;
        case 'estintore':
          _estintore = v;
        case 'casetta_ps':
          _casettaPs = v;
        case 'struttura':
          _struttura = v;
        case 'officina':
          _officina = v;
        default:
          _mdo = v;
      }
    });
  }

  void _resetCurrentTab() => _setCurrent(_tab.defaultStyle);

  void _resetAll() {
    setState(() {
      final d = MdoMapMarkerStyle.defaults;
      _mapSize = d.mapSizeScale;
      _commessa = d.commessa;
      _mdo = d.mdo;
      _box = d.box;
      _estintore = d.estintore;
      _casettaPs = d.casettaPs;
      _struttura = d.struttura;
      _officina = d.officina;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = _draft.resolveForKind(_tab.id);

    return AlertDialog(
      title: const Text('Aspetto marker'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'Imposta forma, colore e icona per Commesse, MDO, BOX, Estintori, Cassette P.S., Strutture e Officine.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (_) => setState(() {}),
              tabs: kMdoMapMarkerTabs
                  .map(
                    (t) => Tab(
                      icon: Icon(t.tabIcon, size: 20),
                      text: t.title,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SizedBox(
                    width: 96,
                    height: 108,
                    child: CustomPaint(
                      painter: MdoMapMarkerPainter(
                        label: _tab.sampleLabel,
                        look: look,
                        large: _tab.id == 'commessa',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Dimensione ${_tab.title}',
                          style: theme.textTheme.labelLarge),
                      Slider(
                        value: _current.sizeScale,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: '${(_current.sizeScale * 100).round()}%',
                        onChanged: (v) =>
                            _setCurrent(_current.copyWith(sizeScale: v)),
                      ),
                      Text('Colore', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      _ColorRow(
                        selected: _current.colorArgb,
                        onPick: (c) =>
                            _setCurrent(_current.copyWith(colorArgb: c)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Forma', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final shapes = <MdoMapMarkerShape>[
                  ...mdoMapMarkerPickerShapesFor(_tab.id),
                ];
                if (!shapes.contains(_current.shape)) {
                  shapes.insert(0, _current.shape);
                }
                return SizedBox(
                  height: 168,
                  child: GridView.builder(
                    key: ValueKey('shape_grid_${_tab.id}_${_current.shape.name}'),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: shapes.length,
                    itemBuilder: (context, i) {
                      final shape = shapes[i];
                      final selected = _current.shape == shape;
                      final previewLook = ResolvedMapMarkerLook(
                        color: _current.color,
                        shape: shape,
                        icon: MdoMapMarkerIcon.none,
                        sizeScale: 1,
                      );
                      return Material(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              _setCurrent(_current.copyWith(shape: shape)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.dividerColor,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 52,
                                  height: 56,
                                  child: CustomPaint(
                                    painter: MdoMapMarkerPainter(
                                      label: 'A1',
                                      look: previewLook,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  shape.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<MdoMapMarkerIcon>(
              key: ValueKey('icon_${_tab.id}'),
              initialValue: _current.icon,
              decoration: const InputDecoration(
                labelText: 'Icona',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: MdoMapMarkerIcon.values
                  .map(
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Icon(i.iconData, size: 18),
                          const SizedBox(width: 8),
                          Text(i.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) _setCurrent(_current.copyWith(icon: v));
              },
            ),
            const SizedBox(height: 14),
            Text('Zoom generale mappa',
                style: theme.textTheme.labelLarge),
            Slider(
              value: _mapSize,
              min: 0.6,
              max: 2.0,
              divisions: 14,
              label: '${(_mapSize * 100).round()}%',
              onChanged: (v) => setState(() => _mapSize = v),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kMdoMapMarkerTabs.map((t) {
                final l = _draft.resolveForKind(t.id);
                return SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.tabIcon, size: 16, color: Colors.black54),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 64,
                        height: 72,
                        child: CustomPaint(
                          painter: MdoMapMarkerPainter(
                            label: t.sampleLabel,
                            look: l,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: _resetCurrentTab, child: const Text('Ripristina tab')),
        TextButton(onPressed: _resetAll, child: const Text('Ripristina tutto')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _draft),
          child: const Text('Applica'),
        ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kMdoMapMarkerPalette.map((c) {
        final argb = c.toARGB32();
        final on = argb == selected;
        return InkWell(
          onTap: () => onPick(argb),
          customBorder: const CircleBorder(),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: on ? Colors.black : Colors.grey.shade400,
                width: on ? 2.5 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
