import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/logistica_officine_convenzionate_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/logistica_layout.dart';
import '../utils/mdo_gps_coords.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';

const _kBlue = kClassicAppBarColor;
const _kBlueDark = Color(0xFF0D47A1);
const _kBlueLight = Color(0xFF1976D2);
const _kAmber = Color(0xFFF59E0B);

class AdminLogisticaOfficineConvenzionatePage extends StatefulWidget {
  const AdminLogisticaOfficineConvenzionatePage({
    super.key,
    this.forceMobileLayout = false,
    this.readOnly = false,
  });

  final bool forceMobileLayout;
  /// Vista dipendente / anteprima: lista senza modifica.
  final bool readOnly;

  @override
  State<AdminLogisticaOfficineConvenzionatePage> createState() =>
      _AdminLogisticaOfficineConvenzionatePageState();
}

class _AdminLogisticaOfficineConvenzionatePageState
    extends State<AdminLogisticaOfficineConvenzionatePage> {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  String? _error;
  String _search = '';
  String _marchioFilter = 'tutti';
  String _tipoFilter = 'tutti';
  String _provinciaFilter = 'tutte';
  List<OfficinaConvenzionata> _rows = const [];

  bool get _canWrite {
    if (widget.readOnly) return false;
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) return false;
    final r = normalizeRole(role);
    if (r == 'dt' || r == 'assistente_dt') return false;
    return canMutateAsAdmin(role) || r == 'logistica';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await LogisticaOfficineConvenzionateService.list(_supa);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<OfficinaConvenzionata> get _filtered {
    final q = _search.trim().toLowerCase();
    return _rows.where((o) {
      if (_provinciaFilter != 'tutte' &&
          o.provincia.toUpperCase() != _provinciaFilter) {
        return false;
      }
      if (_marchioFilter != 'tutti' &&
          !o.brandKeys.contains(_marchioFilter)) {
        return false;
      }
      if (_tipoFilter != 'tutti' && !o.tipoKeys.contains(_tipoFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      final blob = [
        o.fornitore,
        o.marchio,
        o.tipologia,
        o.citta,
        o.via,
        o.provincia,
        o.telefono,
        o.note,
      ].join(' ').toLowerCase();
      return blob.contains(q);
    }).toList(growable: false);
  }

  static const _brandOrder = <String>[
    'FIAT',
    'FORD',
    'JEEP',
    'RENAULT',
    'GENERICO',
    'ALTRE',
  ];

  static const _tipoOrder = <String>[
    'TAGLIANDI',
    'PNEUMATICI',
    'CARROZZERIA',
    'CRISTALLI',
    'REVISIONI',
    'ELETTRAUTO',
    'MECCANICA',
    'CAMION',
  ];

  List<String> get _brandChipKeys {
    final present = <String>{};
    for (final o in _rows) {
      present.addAll(o.brandKeys);
    }
    final out = <String>[];
    for (final k in _brandOrder) {
      if (present.contains(k)) out.add(k);
    }
    final extra = present.where((k) => !_brandOrder.contains(k)).toList()
      ..sort();
    final altreIdx = out.indexOf('ALTRE');
    if (altreIdx >= 0) {
      out.insertAll(altreIdx, extra);
    } else {
      out.addAll(extra);
    }
    return out;
  }

  List<String> get _tipoChipKeys {
    final present = <String>{};
    for (final o in _rows) {
      present.addAll(o.tipoKeys);
    }
    final out = <String>[];
    for (final k in _tipoOrder) {
      if (present.contains(k)) out.add(k);
    }
    final extra = present.where((k) => !_tipoOrder.contains(k)).toList()
      ..sort();
    out.addAll(extra);
    return out;
  }

  List<_BrandGroup> _groupsFor(List<OfficinaConvenzionata> filtered) {
    if (_marchioFilter != 'tutti') {
      return <_BrandGroup>[
        _BrandGroup(
          key: _marchioFilter,
          label: _brandLabel(_marchioFilter),
          items: filtered,
        ),
      ];
    }
    final buckets = <String, List<OfficinaConvenzionata>>{};
    for (final o in filtered) {
      for (final brand in o.brandKeys) {
        buckets.putIfAbsent(brand, () => <OfficinaConvenzionata>[]).add(o);
      }
    }
    final keys = <String>[];
    for (final k in _brandOrder) {
      if (buckets.containsKey(k)) keys.add(k);
    }
    final extra = buckets.keys.where((k) => !_brandOrder.contains(k)).toList()
      ..sort();
    final altreIdx = keys.indexOf('ALTRE');
    if (altreIdx >= 0) {
      keys.insertAll(altreIdx, extra);
    } else {
      keys.addAll(extra);
    }
    return [
      for (final k in keys)
        _BrandGroup(key: k, label: _brandLabel(k), items: buckets[k]!),
    ];
  }

  List<String> get _province {
    final set = <String>{};
    for (final o in _rows) {
      if (o.provincia.isNotEmpty) set.add(o.provincia.toUpperCase());
    }
    final list = set.toList()..sort();
    return list;
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _search = v);
    });
  }

  bool _guardWrite() {
    if (_canWrite) return true;
    final role = ClassicNavSessionCache.current?.role ?? '';
    if (isAdminVistaRole(role)) {
      showAdminVistaReadOnlyDialog(context);
    } else {
      ModifyFeedback.hint(context, 'Solo consultazione');
    }
    return false;
  }

  Future<void> _openForm({OfficinaConvenzionata? existing}) async {
    if (!_guardWrite()) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfficinaFormDialog(existing: existing),
    );
    if (saved == true) unawaited(_load(showLoader: false));
  }

  Future<void> _delete(OfficinaConvenzionata o) async {
    if (!_guardWrite()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina officina'),
        content: Text('Eliminare «${o.fornitore}» da ${o.luogoLabel}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await LogisticaOfficineConvenzionateService.delete(_supa, o.id);
      if (!mounted) return;
      ModifyFeedback.success(context, 'Officina eliminata');
      unawaited(_load(showLoader: false));
    } catch (e) {
      if (!mounted) return;
      ModifyFeedback.error(context, '$e');
    }
  }

  Future<void> _call(OfficinaConvenzionata o) async {
    final href = _telHref(o.telefono);
    if (href == null) {
      ModifyFeedback.hint(context, 'Nessun numero da chiamare');
      return;
    }
    await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }

  Future<void> _openMaps(OfficinaConvenzionata o) async {
    Uri? uri;
    if (o.mapsUrl.isNotEmpty) {
      uri = Uri.tryParse(o.mapsUrl);
    } else if (o.latitudine != null && o.longitudine != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${o.latitudine},${o.longitudine}',
      );
    }
    if (uri == null) {
      ModifyFeedback.hint(context, 'Nessuna mappa disponibile');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final compact = isLogisticaCompactLayout(
      context,
      force: widget.forceMobileLayout,
    );
    final filtered = _filtered;
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Officine convenzionate'),
          actions: [
            IconButton(
              tooltip: 'Ricarica',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
            if (_canWrite)
              IconButton(
                tooltip: 'Nuova officina',
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
              ),
          ],
        ),
      ),
      floatingActionButton: (_canWrite && compact)
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi'),
            )
          : null,
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      _header(compact, filtered.length),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('Nessuna officina con questi filtri'),
                              )
                            : LayoutBuilder(
                                builder: (context, c) {
                                  final w = c.maxWidth;
                                  final cols = w >= 1180
                                      ? 3
                                      : w >= 740
                                          ? 2
                                          : 1;
                                  final groups = _groupsFor(filtered);
                                  return CustomScrollView(
                                    slivers: [
                                      for (final g in groups) ...[
                                        SliverToBoxAdapter(
                                          child: _brandSectionHeader(g),
                                        ),
                                        SliverPadding(
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            g.key == groups.last.key
                                                ? (compact ? 88 : 24)
                                                : 8,
                                          ),
                                          sliver: SliverGrid(
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: cols,
                                              crossAxisSpacing: 10,
                                              mainAxisSpacing: 10,
                                              mainAxisExtent: 186,
                                            ),
                                            delegate:
                                                SliverChildBuilderDelegate(
                                              (context, i) {
                                                final o = g.items[i];
                                                return _OfficinaCard(
                                                  officina: o,
                                                  canWrite: _canWrite,
                                                  onEdit: () =>
                                                      _openForm(existing: o),
                                                  onDelete: () => _delete(o),
                                                  onCall: () => _call(o),
                                                  onMaps: () => _openMaps(o),
                                                );
                                              },
                                              childCount: g.items.length,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _header(bool compact, int visible) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: EdgeInsets.fromLTRB(14, 10, 14, compact ? 8 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [_kBlueDark, _kBlue, _kBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _kBlue.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.garage_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rete officine per tagliandi',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$visible di ${_rows.length} convenzionate',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Cerca nome, città, marca, telefono…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip(
                label: 'Tutte',
                selected: _marchioFilter == 'tutti',
                onTap: () => setState(() => _marchioFilter = 'tutti'),
              ),
              for (final k in _brandChipKeys)
                _filterChip(
                  label: _brandLabel(k),
                  selected: _marchioFilter == k,
                  onTap: () => setState(() => _marchioFilter = k),
                ),
              SizedBox(
                width: compact ? double.infinity : 220,
                child: InputDecorator(
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _provinciaFilter,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Colors.white,
                      iconEnabledColor: Colors.white,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        const DropdownMenuItem(
                          value: 'tutte',
                          child: Text(
                            'Tutte le province',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                        ..._province.map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _provinciaFilter = v ?? 'tutte'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_tipoChipKeys.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterChip(
                  label: 'Tutti i servizi',
                  selected: _tipoFilter == 'tutti',
                  onTap: () => setState(() => _tipoFilter = 'tutti'),
                ),
                for (final k in _tipoChipKeys)
                  _filterChip(
                    label: _tipoLabel(k),
                    selected: _tipoFilter == k,
                    onTap: () => setState(() => _tipoFilter = k),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _kAmber : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kAmber : Colors.white.withValues(alpha: 0.55),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black87 : _kBlueDark,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandSectionHeader(_BrandGroup g) {
    final color = _brandColor(g.key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            g.label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${g.items.length}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficinaCard extends StatelessWidget {
  const _OfficinaCard({
    required this.officina,
    required this.canWrite,
    required this.onEdit,
    required this.onDelete,
    required this.onCall,
    required this.onMaps,
  });

  final OfficinaConvenzionata officina;
  final bool canWrite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCall;
  final VoidCallback onMaps;

  @override
  Widget build(BuildContext context) {
    final o = officina;
    final accent = _brandColor(o.brandKeys.first);
    return Material(
      color: CronosAppThemes.cardOf(context),
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canWrite ? onEdit : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CronosAppThemes.hairlineOf(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              o.fornitore,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (canWrite)
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onSelected: (v) {
                                if (v == 'edit') onEdit();
                                if (v == 'delete') onDelete();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Modifica'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Elimina'),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (o.luogoLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 13, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                o.luogoLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (o.via.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1, left: 17),
                          child: Text(
                            o.via,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final t in o.marchioTags)
                            _miniChip(t, _kBlueDark, filled: true),
                          for (final t in o.tipologiaTags)
                            _miniChip(t, _tipoColor(t)),
                          if (!o.attivo)
                            _miniChip('Non attiva', Colors.red.shade700),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (o.telefono.isNotEmpty)
                            Expanded(
                              child: TextButton.icon(
                                onPressed: onCall,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.phone_outlined, size: 16),
                                label: Text(
                                  o.telefono,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (o.hasMaps)
                            IconButton.filledTonal(
                              tooltip: 'Apri mappa',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: onMaps,
                              icon: const Icon(Icons.map_outlined, size: 18),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
          height: 1.2,
        ),
      ),
    );
  }
}

class _OfficinaFormDialog extends StatefulWidget {
  const _OfficinaFormDialog({this.existing});

  final OfficinaConvenzionata? existing;

  @override
  State<_OfficinaFormDialog> createState() => _OfficinaFormDialogState();
}

class _OfficinaFormDialogState extends State<_OfficinaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fornitore;
  late final TextEditingController _marchio;
  late final TextEditingController _tipologia;
  late final TextEditingController _citta;
  late final TextEditingController _via;
  late final TextEditingController _provincia;
  late final TextEditingController _telefono;
  late final TextEditingController _gps;
  late final TextEditingController _maps;
  late final TextEditingController _note;
  late bool _attivo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fornitore = TextEditingController(text: e?.fornitore ?? '');
    _marchio = TextEditingController(text: e?.marchio ?? '');
    _tipologia = TextEditingController(text: e?.tipologia ?? '');
    _citta = TextEditingController(text: e?.citta ?? '');
    _via = TextEditingController(text: e?.via ?? '');
    _provincia = TextEditingController(text: e?.provincia ?? '');
    _telefono = TextEditingController(text: e?.telefono ?? '');
    _gps = TextEditingController(
      text: (e?.latitudine != null && e?.longitudine != null)
          ? '${e!.latitudine}, ${e.longitudine}'
          : '',
    );
    _maps = TextEditingController(text: e?.mapsUrl ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _attivo = e?.attivo ?? true;
  }

  @override
  void dispose() {
    _fornitore.dispose();
    _marchio.dispose();
    _tipologia.dispose();
    _citta.dispose();
    _via.dispose();
    _provincia.dispose();
    _telefono.dispose();
    _gps.dispose();
    _maps.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final gps = mdoGpsCoordsFromText(_gps.text);
    setState(() => _saving = true);
    try {
      final row = OfficinaConvenzionata(
        id: widget.existing?.id ?? '',
        fornitore: _fornitore.text.trim(),
        marchio: _marchio.text.trim(),
        tipologia: _tipologia.text.trim(),
        citta: _citta.text.trim(),
        via: _via.text.trim(),
        provincia: _provincia.text.trim().toUpperCase(),
        telefono: _telefono.text.trim(),
        latitudine: gps?.$1,
        longitudine: gps?.$2,
        mapsUrl: _maps.text.trim(),
        note: _note.text.trim(),
        attivo: _attivo,
      );
      final supa = Supabase.instance.client;
      if (widget.existing == null) {
        await LogisticaOfficineConvenzionateService.insert(supa, row);
      } else {
        await LogisticaOfficineConvenzionateService.update(supa, row);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ModifyFeedback.error(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Nuova officina' : 'Modifica officina'),
      content: SizedBox(
        width: logisticaDialogWidth(context, desktop: 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_fornitore, 'Fornitore *', required: true),
                _field(_marchio, 'Marchio (FIAT, FORD, GENERICO…)'),
                _field(
                  _tipologia,
                  'Tipologia (tagliando, pneumatici, carrozzeria…)',
                ),
                Row(
                  children: [
                    Expanded(child: _field(_citta, 'Città')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_provincia, 'Provincia')),
                  ],
                ),
                _field(_via, 'Indirizzo'),
                _field(_telefono, 'Telefono', keyboard: TextInputType.phone),
                _field(_gps, 'Coordinate GPS (lat, lon)'),
                _field(_maps, 'Link Google Maps'),
                _field(_note, 'Note', maxLines: 3),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Officina attiva'),
                  value: _attivo,
                  onChanged: (v) => setState(() => _attivo = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isNew ? 'Aggiungi' : 'Salva'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        validator: required
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _BrandGroup {
  const _BrandGroup({
    required this.key,
    required this.label,
    required this.items,
  });

  final String key;
  final String label;
  final List<OfficinaConvenzionata> items;
}

String _brandLabel(String key) {
  switch (key) {
    case 'ALTRE':
      return 'Altre';
    case 'GENERICO':
      return 'Generico';
    default:
      return key;
  }
}

String _tipoLabel(String key) {
  switch (key) {
    case 'PNEUMATICI':
      return 'Gomme';
    case 'CARROZZERIA':
      return 'Carrozzeria';
    case 'TAGLIANDI':
      return 'Tagliandi';
    case 'CRISTALLI':
      return 'Cristalli';
    case 'REVISIONI':
      return 'Revisioni';
    case 'ELETTRAUTO':
      return 'Elettrauto';
    case 'MECCANICA':
      return 'Meccanica';
    case 'CAMION':
      return 'Camion';
    default:
      return key;
  }
}

Color _brandColor(String key) {
  switch (key.toUpperCase()) {
    case 'FIAT':
      return const Color(0xFF1E3A8A);
    case 'FORD':
      return const Color(0xFF1D4ED8);
    case 'JEEP':
      return const Color(0xFF166534);
    case 'RENAULT':
      return const Color(0xFFB45309);
    case 'GENERICO':
      return const Color(0xFF57534E);
    case 'ALTRE':
      return const Color(0xFF1565C0);
    default:
      return const Color(0xFF334155);
  }
}

Color _tipoColor(String raw) {
  final u = raw.toUpperCase();
  if (u.contains('PNEUMATIC')) return const Color(0xFF334155);
  if (u.contains('CARROZZ')) return const Color(0xFFC2410C);
  if (u.contains('CAMION')) return const Color(0xFF047857);
  if (u.contains('CRISTALL')) return const Color(0xFF0369A1);
  if (u.contains('REVISION')) return const Color(0xFF7C3AED);
  if (u.contains('TAGLIAND')) return const Color(0xFF1D4ED8);
  if (u.contains('MECCANIC')) return const Color(0xFF0F766E);
  return const Color(0xFF475569);
}

String? _telHref(String raw) {
  final m = RegExp(r'(\+?\d[\d\s./-]{5,}\d)').firstMatch(raw);
  if (m == null) return null;
  final digits = m.group(1)!.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.replaceAll('+', '').length < 6) return null;
  return 'tel:$digits';
}
