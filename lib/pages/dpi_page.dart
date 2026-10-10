import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';
import '../services/supabase_service.dart';
import '../utils/device.dart';
import '../widgets/classic_app_bar_chrome.dart';

class DpiPage extends StatefulWidget {
  final String fullName;
  final String personaleUuid;

  const DpiPage({
    super.key,
    required this.fullName,
    required this.personaleUuid,
  });

  @override
  State<DpiPage> createState() => _DpiPageState();
}

class _DpiPageState extends State<DpiPage> {
  /// Stesse categorie salvate dal modulo «DPI III categoria» (admin).
  static const List<String> _categories = [
    'Elmetto',
    'Imbracatura',
    'Cordino Singolo con Dissipatore',
    'Cordino di Posizionamento',
    'Cordino Shock Absorber Doppio',
  ];

  /// Vecchia etichetta generica non più usata nel modulo III.
  static String _canonicalCategoryForFilter(String c) {
    final t = c.trim();
    if (t == 'Cordino') return 'Cordino Singolo con Dissipatore';
    return t;
  }

  final List<_DpiItem> _items = [];
  bool _loading = true;
  String? _error;

  String _selectedCategory = _categories.first;

  String _toDdMmYyyy(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    final d = DateTime.tryParse(v);
    if (d == null) return v;
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year.toString().padLeft(4, '0')}';
  }

  String _displayDate(String raw) {
    final f = _toDdMmYyyy(raw);
    return f.isEmpty ? '—' : f;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.client
          .from('dpi_dotazioni')
          .select(
              'categoria, quantita_assegnata, marca, data_produzione, data_consegna, data_revisione, matricola, modello, created_at')
          .eq('personale_id', widget.personaleUuid)
          .order('categoria')
          .order('created_at');
      final all = (rows as List)
          .map((e) => _DpiItem.fromRow(Map<String, dynamic>.from(e)))
          .toList();
      final latestByCategory = <String, _DpiItem>{};
      for (final it in all) {
        final key = it.categoria.trim().toLowerCase();
        if (key.isEmpty) continue;
        final curr = latestByCategory[key];
        if (curr == null || it.createdAt.isAfter(curr.createdAt)) {
          latestByCategory[key] = it;
        }
      }
      _items
        ..clear()
        ..addAll(latestByCategory.values);
    } catch (e) {
      _error = 'Errore caricamento DPI: $e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Elmetto':
        return Icons.construction_rounded;
      case 'Imbracatura':
        return Icons.shield_outlined;
      case 'Cordino Singolo con Dissipatore':
        return Icons.link_rounded;
      case 'Cordino di Posizionamento':
        return Icons.straighten_rounded;
      case 'Cordino Shock Absorber Doppio':
        return Icons.bolt_rounded;
      default:
        return Icons.shield_outlined;
    }
  }

  /// Pittogrammi vettoriali (elmetto / imbracatura) come la cintura, senza asset.
  Widget _categoryGlyph(
    BuildContext context,
    String category,
    double size,
    Color color,
  ) {
    if (category == 'Elmetto') {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HelmetSymbolPainter(color: color),
        ),
      );
    }
    if (category == 'Imbracatura') {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HarnessSymbolPainter(color: color),
        ),
      );
    }
    return Icon(
      _iconForCategory(category),
      size: size,
      color: color,
    );
  }

  Widget _categoryPicker(bool mobile) {
    if (mobile) {
      final cs = Theme.of(context).colorScheme;
      return Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Tipo di dotazione',
            labelStyle: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.fromLTRB(16, 12, 8, 12),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategory,
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.expand_more_rounded, color: cs.primary),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              selectedItemBuilder: (ctx) => _categories
                  .map(
                    (c) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Row(
                        children: [
                          _categoryGlyph(ctx, c, 22, cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              items: _categories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          _categoryGlyph(context, c, 22, cs.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text(c)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategory = v);
              },
            ),
          ),
        ),
      );
    }
    final csDesk = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories
          .map(
            (c) => ChoiceChip(
              avatar: _categoryGlyph(context, c, 20, csDesk.primary),
              label: Text(c),
              selected: _selectedCategory == c,
              onSelected: (_) => setState(() => _selectedCategory = c),
            ),
          )
          .toList(),
    );
  }

  Widget _fieldChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final display = value.trim().isEmpty ? '—' : value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  display,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow2(
    BuildContext context,
    Widget a,
    Widget b,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    );
  }

  Widget _dpiCard(BuildContext context, _DpiItem e, {required bool mobile}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final catLabel = _canonicalCategoryForFilter(e.categoria);

    final qty = _fieldChip(
      context,
      icon: Icons.numbers_rounded,
      label: 'Quantità',
      value: '${e.quantitaAssegnata}',
    );
    final marca = _fieldChip(
      context,
      icon: Icons.branding_watermark_outlined,
      label: 'Marca',
      value: e.marca,
    );
    final dProd = _fieldChip(
      context,
      icon: Icons.factory_outlined,
      label: 'Produzione',
      value: _displayDate(e.dataProduzione),
    );
    final dCons = _fieldChip(
      context,
      icon: Icons.handshake_outlined,
      label: 'Consegna',
      value: _displayDate(e.dataConsegna),
    );
    final dRev = _fieldChip(
      context,
      icon: Icons.event_repeat_rounded,
      label: 'Revisione',
      value: _displayDate(e.dataRevisione),
    );
    final matr = _fieldChip(
      context,
      icon: Icons.qr_code_2_outlined,
      label: 'Matricola',
      value: e.matricola,
    );
    final mod = _fieldChip(
      context,
      icon: Icons.view_in_ar_outlined,
      label: 'Modello',
      value: e.modello,
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldRow2(context, qty, marca),
        const SizedBox(height: 10),
        _fieldRow2(context, dProd, dCons),
        const SizedBox(height: 10),
        dRev,
        const SizedBox(height: 10),
        _fieldRow2(context, matr, mod),
      ],
    );

    return Material(
      elevation: mobile ? 3 : 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      color: cs.surface,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.85),
                    cs.tertiaryContainer.withValues(alpha: 0.45),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(21),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child:
                        _categoryGlyph(context, catLabel, 32, cs.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          catLabel,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 16,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Registrato a tuo nome',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dettagli tecnici',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  details,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.6),
                    cs.surfaceContainerHigh,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                size: 44,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Nessuna dotazione qui',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Per questa categoria non risulta nulla a tuo nome. Scegli un altro tipo sopra oppure contatta l’ufficio se ti aspettavi un aggiornamento.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _refreshableBody(bool mobile, List<_DpiItem> items) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _errorState(context),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(context),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final card = _dpiCard(ctx, items[i], mobile: mobile);
                    final block = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        card,
                        if (i < items.length - 1) const SizedBox(height: 16),
                      ],
                    );
                    if (mobile) return block;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: block,
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = isMobileDevice();
    final items = _items
        .where((e) =>
            _canonicalCategoryForFilter(e.categoria) == _selectedCategory)
        .toList(growable: false);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: mobile
            ? const Text('Le tue dotazioni DPI')
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 40),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DPI — ${widget.fullName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      )),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 16 : 12, 12, mobile ? 16 : 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mobile) ...[
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHigh
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.person_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.fullName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Solo consultazione: i dati sono gestiti dall’ufficio. Per errori o modifiche, contatta il referente.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          height: 1.4,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _categoryPicker(mobile),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _refreshableBody(mobile, items),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Elmetto in profilo: calotta, visiera, cresta e sottogola a Y (stile pittogramma), senza asset.
class _HelmetSymbolPainter extends CustomPainter {
  _HelmetSymbolPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = size.shortestSide;
    final sw = s * 0.065;
    final p = Paint()
      ..color = color
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shell = Path()
      ..moveTo(w * 0.18, h * 0.52)
      ..cubicTo(
        w * 0.08,
        h * 0.42,
        w * 0.10,
        h * 0.22,
        w * 0.36,
        h * 0.13,
      )
      ..cubicTo(
        w * 0.52,
        h * 0.07,
        w * 0.82,
        h * 0.12,
        w * 0.88,
        h * 0.28,
      )
      ..lineTo(w * 0.95, h * 0.38)
      ..lineTo(w * 0.76, h * 0.42)
      ..cubicTo(
        w * 0.52,
        h * 0.49,
        w * 0.32,
        h * 0.52,
        w * 0.18,
        h * 0.52,
      );
    canvas.drawPath(shell, p);

    final ridge = Path()
      ..moveTo(w * 0.40, h * 0.15)
      ..quadraticBezierTo(w * 0.50, h * 0.09, w * 0.60, h * 0.15);
    canvas.drawPath(ridge, p);

    final chin = Offset(w * 0.30, h * 0.70);
    canvas.drawLine(Offset(w * 0.36, h * 0.47), chin, p);
    canvas.drawLine(Offset(w * 0.22, h * 0.49), chin, p);
  }

  @override
  bool shouldRepaint(covariant _HelmetSymbolPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Triangolo + figura con imbracatura e linea vita (stile cartello), senza asset.
class _HarnessSymbolPainter extends CustomPainter {
  _HarnessSymbolPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = size.shortestSide;
    final sw = s * 0.065;
    final p = Paint()
      ..color = color
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final m = s * 0.05;
    final apex = Offset(w * 0.5, m + sw);
    final left = Offset(m, h - m);
    final right = Offset(w - m, h - m);
    final tri = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(tri, p);

    final dorsal = Offset(w * 0.52, h * 0.33);
    final lineTop = Offset(w * 0.52, apex.dy + sw * 0.4);
    final pLine = Paint()
      ..color = color
      ..strokeWidth = sw * 1.15
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(dorsal, lineTop, pLine);

    final head = Offset(w * 0.48, h * 0.36);
    canvas.drawCircle(head, s * 0.052, p);

    final hip = Offset(w * 0.48, h * 0.54);
    canvas.drawLine(Offset(head.dx, head.dy + s * 0.06), hip, p);

    final shoulderL = Offset(w * 0.34, h * 0.42);
    final shoulderR = Offset(w * 0.62, h * 0.42);
    canvas.drawLine(shoulderL, shoulderR, p);
    canvas.drawLine(shoulderL, hip, p);
    canvas.drawLine(shoulderR, hip, p);

    canvas.drawLine(hip, Offset(w * 0.36, h * 0.78), p);
    canvas.drawLine(hip, Offset(w * 0.58, h * 0.72), p);
  }

  @override
  bool shouldRepaint(covariant _HarnessSymbolPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DpiItem {
  final String categoria;
  final int quantitaAssegnata;
  final String marca;
  final String dataProduzione;
  final String dataConsegna;
  final String dataRevisione;
  final String matricola;
  final String modello;
  final DateTime createdAt;

  const _DpiItem({
    required this.categoria,
    required this.quantitaAssegnata,
    required this.marca,
    required this.dataProduzione,
    required this.dataConsegna,
    required this.dataRevisione,
    required this.matricola,
    required this.modello,
    required this.createdAt,
  });

  factory _DpiItem.fromRow(Map<String, dynamic> r) => _DpiItem(
        categoria: (r['categoria'] ?? '').toString(),
        quantitaAssegnata: (r['quantita_assegnata'] is int)
            ? (r['quantita_assegnata'] as int)
            : int.tryParse((r['quantita_assegnata'] ?? '0').toString()) ?? 0,
        marca: (r['marca'] ?? '').toString(),
        dataProduzione: (r['data_produzione'] ?? '').toString(),
        dataConsegna: (r['data_consegna'] ?? '').toString(),
        dataRevisione: (r['data_revisione'] ?? '').toString(),
        matricola: (r['matricola'] ?? '').toString(),
        modello: (r['modello'] ?? '').toString(),
        createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
