import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/data_cleanup_service.dart';
import '../utils/admin_vista_guard.dart';
import 'admin_formazione_dlgs_strutture_page.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/gps_coords_input_row.dart';
import '../utils/commesse_data_export.dart';
import '../utils/mdo_gps_coords.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminMasterDataPage extends StatefulWidget {
  const AdminMasterDataPage({
    super.key,
    this.initialTabIndex = 0,
    this.highlightStructureId,
  });

  /// Tab da aprire all'avvio (0=Commesse … 3=Strutture, 4=Strutture Form. 81).
  final int initialTabIndex;

  /// Se valorizzato, apre il tab Strutture evidenziando questa struttura.
  final String? highlightStructureId;

  @override
  State<AdminMasterDataPage> createState() => _AdminMasterDataPageState();
}

class _AdminMasterDataPageState extends State<AdminMasterDataPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 4),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // Elimina notifiche oltre gli ultimi 10 giorni
  // ---------------------------------------------------------------------------
  Future<void> _deleteOldNotifications() async {
    if (!await ensureCanPersist(context)) return;
    try {
      final deleted = await DataCleanupService.cleanupNotifications();
      final remaining = await DataCleanupService.countNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted > 0
                ? 'Notifiche: eliminate $deleted righe (>10 gg). Ne restano $remaining.'
                : 'Nessuna da eliminare. Su Supabase: $remaining notifiche '
                    '(ultimi ${DataCleanupService.notificationRetentionDays} giorni).',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on AdminVistaReadOnlyException {
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore pulizia notifiche su Supabase: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: "Gestione Dati (Admin)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: "Elimina notifiche >10 giorni",
            onPressed: _deleteOldNotifications,   // 👈 ECCO IL BTN A BARRE ROSSE
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: "Commesse"),
            Tab(text: "Stazioni"),
            Tab(text: "Aeroporti"),
            Tab(text: "Strutture"),
            Tab(text: "Strutture Form. 81"),
          ],
        ),
      )),
      body: PageWithTopLogo(
        child: TabBarView(
          controller: _tab,
          children: [
            const _CommessePage(),
            const _StazioniPage(),
            const _AeroportiPage(),
            _StrutturePage(highlightId: widget.highlightStructureId),
            const AdminFormazioneDlgsStrutturePage(embedded: true),
          ],
        ),
      ),
    );
  }
}

/* -----------------------------------------------------------
 * UTIL & COMMON
 * ----------------------------------------------------------*/

Future<bool> _confirm(BuildContext context, String msg) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma'),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Conferma')),
          ],
        ),
      ) ??
      false;
}

class _RowCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool hasActive;
  final bool activeValue;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onToggle;
  final Color? color;

  const _RowCard({
    super.key,
    required this.title,
    this.subtitle,
    this.hasActive = false,
    this.activeValue = false,
    this.onDelete,
    this.onEdit,
    this.onToggle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: color,
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: (subtitle == null || subtitle!.isEmpty) ? null : Text(subtitle!),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasActive) Switch(value: activeValue, onChanged: onToggle),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/* -----------------------------------------------------------
 * COMMESSE
 * ----------------------------------------------------------*/

class _CommessePage extends StatefulWidget {
  const _CommessePage();
  @override
  State<_CommessePage> createState() => _CommessePageState();
}

class _CommessePageState extends State<_CommessePage> {
  final supa = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];

  /// Opzioni DT suggerite (selezione ibrida + testo libero).
  List<String> _dtOptions = const <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _gpsDbFields(TextEditingController ctrl) {
    final coords = GpsCoordsInputRow.parseFromController(ctrl);
    return <String, dynamic>{
      'latitudine': coords?.$1,
      'longitudine': coords?.$2,
    };
  }

  void _fillGpsCtrl(TextEditingController ctrl, Map<String, dynamic> row) {
    final coords = mdoGpsCoordsFromRow(row);
    if (coords == null) {
      ctrl.clear();
      return;
    }
    ctrl.text = GpsCoordsInputRow.formatCoords(coords.$1, coords.$2);
  }

  String _gpsSubtitle(Map<String, dynamic> r) {
    final coords = mdoGpsCoordsFromRow(r);
    if (coords == null) return '';
    return '\nGPS: ${GpsCoordsInputRow.formatCoords(coords.$1, coords.$2)}';
  }

  Future<void> _load() async {
    final commesseRes = await supa.from('commesse').select('*').order('nome');
    final cigCupRes = await supa
        .from('commesse_cig_cup')
        .select(
          'id_uuid,commessa_code,commessa_id_uuid,cig,cig_derivato,cup,cliente,active',
        )
        .eq('active', true)
        .order('commessa_code');

    final commesse = (commesseRes as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final cigRows = (cigCupRes as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    final byCommessaId = <String, Map<String, dynamic>>{};
    final byCode = <String, Map<String, dynamic>>{};
    for (final r in cigRows) {
      final code = _s(r['commessa_code']).toUpperCase();
      final cid = _s(r['commessa_id_uuid']);
      if (code.isNotEmpty) byCode[code] = r;
      if (cid.isNotEmpty) byCommessaId[cid] = r;
    }

    final merged = <Map<String, dynamic>>[];
    for (final c in commesse) {
      final id = _s(c['id_uuid']);
      final code = _s(c['nome']).toUpperCase();
      final cc = byCommessaId[id] ?? byCode[code];
      merged.add(<String, dynamic>{
        ...c,
        'commessa_code': code,
        'cig': _s(cc?['cig']),
        'cig_derivato': _s(cc?['cig_derivato']),
        'cup': _s(cc?['cup']),
        'cliente': _s(cc?['cliente']),
      });
    }

    final opts = <String>{};
    for (final c in commesse) {
      final d1 = _s(c['dt']);
      final d2 = _s(c['dt2']);
      if (d1.isNotEmpty) opts.add(d1);
      if (d2.isNotEmpty) opts.add(d2);
    }
    final sortedOpts = opts.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      _items = merged;
      _dtOptions = sortedOpts;
    });
  }

  /// Campo DT ibrido: selezione da suggerimenti + testo libero.
  Widget _dtPicker(TextEditingController ctrl, String label) {
    return DropdownMenu<String>(
      controller: ctrl,
      enableFilter: true,
      requestFocusOnTap: true,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      dropdownMenuEntries: _dtOptions
          .map((o) => DropdownMenuEntry<String>(value: o, label: o))
          .toList(growable: false),
      onSelected: (v) {
        if (v != null) ctrl.text = v;
      },
    );
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _exportCsv() async {
    await exportCommesseDataCsv(context, commesseRows: _items);
  }

  Future<void> _upsertCigCupForCommessa({
    required String commessaIdUuid,
    required String commessaCode,
    required String cig,
    required String cigDerivato,
    required String cup,
    required String cliente,
    required bool active,
  }) async {
    final existing = await supa
        .from('commesse_cig_cup')
        .select('id_uuid')
        .eq('commessa_code', commessaCode)
        .maybeSingle();
    final payload = <String, dynamic>{
      'commessa_code': commessaCode,
      'commessa_id_uuid': commessaIdUuid,
      'cig': cig,
      'cig_derivato': cigDerivato,
      'cup': cup,
      'cliente': cliente,
      'active': active,
    };
    if (existing != null) {
      await supa
          .from('commesse_cig_cup')
          .update(payload)
          .eq('id_uuid', existing['id_uuid']);
    } else {
      await supa.from('commesse_cig_cup').insert(payload);
    }
  }

  Future<void> _syncMissingGpsFromLogisticaBox() async {
    final ok = await _confirm(
      context,
      'Importare le coordinate dalle righe BOX verso le commesse che non hanno ancora GPS?',
    );
    if (!ok) return;

    try {
      final commesseRes = await supa
          .from('commesse')
          .select('id_uuid,nome,latitudine,longitudine')
          .eq('active', true);
      final boxRes = await supa
          .from('logistica_box')
          .select(
            'id_uuid,numero_interno,commessa_id,posizione_gps,latitudine,longitudine,updated_at',
          )
          .eq('active', true)
          .not('commessa_id', 'is', null)
          .order('updated_at', ascending: false);

      final boxByCommessa = <String, Map<String, dynamic>>{};
      for (final raw in (boxRes as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final commessaId = _s(row['commessa_id']);
        if (commessaId.isEmpty) continue;
        final coords = mdoGpsCoordsFromRow(row);
        if (coords == null) continue;
        // Lista già ordinata per updated_at desc: primo box vince.
        boxByCommessa.putIfAbsent(commessaId, () => row);
      }

      var updated = 0;
      var skippedWithGps = 0;
      var skippedNoBoxGps = 0;

      for (final raw in (commesseRes as List)) {
        final c = Map<String, dynamic>.from(raw as Map);
        final commessaId = _s(c['id_uuid']);
        if (commessaId.isEmpty) continue;

        final hasGps = mdoGpsCoordsFromRow(c) != null;
        if (hasGps) {
          skippedWithGps++;
          continue;
        }

        final box = boxByCommessa[commessaId];
        if (box == null) {
          skippedNoBoxGps++;
          continue;
        }

        final coords = mdoGpsCoordsFromRow(box);
        if (coords == null) {
          skippedNoBoxGps++;
          continue;
        }

        await supa.from('commesse').update({
          'latitudine': coords.$1,
          'longitudine': coords.$2,
        }).eq('id_uuid', commessaId);
        updated++;
      }

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Coordinate importate su $updated commesse. '
            'Saltate: $skippedWithGps già valorizzate, $skippedNoBoxGps senza GPS BOX.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore import coordinate da BOX: $e')),
      );
    }
  }

  Future<void> _showCommessaDialog({Map<String, dynamic>? item}) async {
    final isEdit = item != null;
    final nomeCtrl = TextEditingController(text: isEdit ? _s(item['commessa_code']) : '');
    final cigCtrl = TextEditingController(text: isEdit ? _s(item['cig']) : '');
    final cigDerCtrl = TextEditingController(text: isEdit ? _s(item['cig_derivato']) : '');
    final cupCtrl = TextEditingController(text: isEdit ? _s(item['cup']) : '');
    final clienteCtrl = TextEditingController(text: isEdit ? _s(item['cliente']) : '');
    final pmCtrl = TextEditingController(text: isEdit ? _s(item['pm']) : '');
    final dtCtrl = TextEditingController(text: isEdit ? _s(item['dt']) : '');
    final dt2Ctrl = TextEditingController(text: isEdit ? _s(item['dt2']) : '');
    final gpsCtrl = TextEditingController();
    if (isEdit) _fillGpsCtrl(gpsCtrl, item);
    var active = isEdit ? ((item['active'] ?? true) == true) : true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(isEdit ? 'Modifica Commessa' : 'Nuova Commessa'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nomeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Nome commessa',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cigCtrl,
                        decoration: const InputDecoration(
                          labelText: 'CIG',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cigDerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'CIG derivato',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cupCtrl,
                        decoration: const InputDecoration(
                          labelText: 'CUP',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: clienteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cliente',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pmCtrl,
                        decoration: const InputDecoration(
                          labelText: 'PM',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dtPicker(dtCtrl, 'DT'),
                      const SizedBox(height: 12),
                      _dtPicker(dt2Ctrl, 'DT 2 (opzionale)'),
                      const SizedBox(height: 12),
                      GpsCoordsInputRow(controller: gpsCtrl, dense: true),
                      if (!isEdit) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Attiva'),
                          value: active,
                          onChanged: (v) => setLocal(() => active = v),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isEdit ? 'Salva' : 'Crea'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true && nomeCtrl.text.trim().isNotEmpty) {
      final code = nomeCtrl.text.trim().toUpperCase();
      try {
        if (isEdit) {
          final id = _s(item['id_uuid']);
          await supa.from('commesse').update({
            'nome': code,
            'pm': pmCtrl.text.trim().isEmpty ? null : pmCtrl.text.trim(),
            'dt': dtCtrl.text.trim().isEmpty ? null : dtCtrl.text.trim(),
            'dt2': dt2Ctrl.text.trim().isEmpty ? null : dt2Ctrl.text.trim(),
            ..._gpsDbFields(gpsCtrl),
          }).match({'id_uuid': id});
          await _upsertCigCupForCommessa(
            commessaIdUuid: id,
            commessaCode: code,
            cig: cigCtrl.text.trim(),
            cigDerivato: cigDerCtrl.text.trim(),
            cup: cupCtrl.text.trim(),
            cliente: clienteCtrl.text.trim(),
            active: (item['active'] ?? true) == true,
          );
        } else {
          final inserted = await supa
              .from('commesse')
              .insert({
                'nome': code,
                'active': active,
                'pm': pmCtrl.text.trim().isEmpty ? null : pmCtrl.text.trim(),
                'dt': dtCtrl.text.trim().isEmpty ? null : dtCtrl.text.trim(),
                'dt2': dt2Ctrl.text.trim().isEmpty ? null : dt2Ctrl.text.trim(),
                ..._gpsDbFields(gpsCtrl),
              })
              .select('id_uuid')
              .single();
          final id = _s(inserted['id_uuid']);
          if (id.isNotEmpty) {
            await _upsertCigCupForCommessa(
              commessaIdUuid: id,
              commessaCode: code,
              cig: cigCtrl.text.trim(),
              cigDerivato: cigDerCtrl.text.trim(),
              cup: cupCtrl.text.trim(),
              cliente: clienteCtrl.text.trim(),
              active: active,
            );
          }
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore salvataggio: $e')),
          );
        }
      }
    }

    nomeCtrl.dispose();
    cigCtrl.dispose();
    cigDerCtrl.dispose();
    cupCtrl.dispose();
    clienteCtrl.dispose();
    pmCtrl.dispose();
    dtCtrl.dispose();
    dt2Ctrl.dispose();
    gpsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final nome = (r['nome'] ?? '').toString().toLowerCase();
      return q.isEmpty || nome.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _showCommessaDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nuova Commessa'),
            ),
            OutlinedButton.icon(
              onPressed: _items.isEmpty ? null : _exportCsv,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _items.isEmpty ? null : _syncMissingGpsFromLogisticaBox,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('GPS da BOX'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cerca',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        const Divider(),
        for (final r in filtered)
          _RowCard(
            title: r['nome'] ?? '',
            subtitle:
                'CIG: ${_s(r['cig']).isEmpty ? '-' : _s(r['cig'])} | '
                'CIG derivato: ${_s(r['cig_derivato']).isEmpty ? '-' : _s(r['cig_derivato'])} | '
                'CUP: ${_s(r['cup']).isEmpty ? '-' : _s(r['cup'])} | '
                'Cliente: ${_s(r['cliente']).isEmpty ? '-' : _s(r['cliente'])}\n'
                'PM: ${_s(r['pm']).isEmpty ? '-' : _s(r['pm'])} | '
                'DT: ${_s(r['dt']).isEmpty ? '-' : _s(r['dt'])}'
                '${_s(r['dt2']).isEmpty ? '' : ' | DT 2: ${_s(r['dt2'])}'}'
                '${_gpsSubtitle(r)}',
            hasActive: true,
            activeValue: r['active'] ?? false,
            onEdit: () => _showCommessaDialog(item: r),
            onToggle: (v) async {
              final id = _s(r['id_uuid']);
              final code = _s(r['commessa_code']).toUpperCase();
              await supa.from('commesse').update({'active': v}).match({'id_uuid': id});
              await _upsertCigCupForCommessa(
                commessaIdUuid: id,
                commessaCode: code,
                cig: _s(r['cig']),
                cigDerivato: _s(r['cig_derivato']),
                cup: _s(r['cup']),
                cliente: _s(r['cliente']),
                active: v,
              );
              await _load();
            },
            onDelete: () async {
              if (await _confirm(context, "Eliminare?")) {
                final id = _s(r['id_uuid']);
                final code = _s(r['commessa_code']).toUpperCase();
                await supa
                    .from('commesse_cig_cup')
                    .delete()
                    .or('commessa_id_uuid.eq.$id,commessa_code.eq.$code');
                await supa.from('commesse').delete().match({'id_uuid': id});
                await _load();
              }
            },
          ),
      ],
    );
  }
}

/* -----------------------------------------------------------
 * STAZIONI
 * ----------------------------------------------------------*/

class _StazioniPage extends StatefulWidget {
  const _StazioniPage();
  @override
  State<_StazioniPage> createState() => _StazioniPageState();
}

class _StazioniPageState extends State<_StazioniPage> {
  final supa = Supabase.instance.client;
  final _nome = TextEditingController();
  final _search = TextEditingController();
  bool _attiva = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nome.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await supa.from('stazioni').select('*').order('nome');
    setState(() => _items = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['nome']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifica Stazione"),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: "Nome stazione")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annulla")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salva")),
        ],
      ),
    );
    if (ok == true && controller.text.isNotEmpty) {
      await supa.from('stazioni').update({'nome': controller.text}).match({'id': item['id']});
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final nome = (r['nome'] ?? '').toString().toLowerCase();
      return q.isEmpty || nome.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nuova Stazione')),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cerca',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: [
            const Text('Attiva'),
            Switch(value: _attiva, onChanged: (v) => setState(() => _attiva = v)),
            const Spacer(),
            AsyncFilledButton(
                onPressed: () async {
                  await supa.from('stazioni').insert({'nome': _nome.text, 'attiva': _attiva});
                  _nome.clear();
                  _load();
                },
                child: const Text('SALVA')),
          ],
        ),
        const Divider(),
        for (final r in filtered)
          _RowCard(
            title: r['nome'] ?? '',
            hasActive: true,
            activeValue: r['attiva'] ?? false,
            onEdit: () => _showEditDialog(r),
            onToggle: (v) async {
              await supa.from('stazioni').update({'attiva': v}).match({'id': r['id']});
              _load();
            },
            onDelete: () async {
              if (await _confirm(context, "Eliminare?")) {
                await supa.from('stazioni').delete().match({'id': r['id']});
                _load();
              }
            },
          ),
      ],
    );
  }
}

/* -----------------------------------------------------------
 * AEROPORTI
 * ----------------------------------------------------------*/

class _AeroportiPage extends StatefulWidget {
  const _AeroportiPage();
  @override
  State<_AeroportiPage> createState() => _AeroportiPageState();
}

class _AeroportiPageState extends State<_AeroportiPage> {
  final supa = Supabase.instance.client;
  final _nome = TextEditingController();
  final _search = TextEditingController();
  bool _attiva = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nome.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await supa.from('aeroporti').select('*').order('nome');
    setState(() => _items = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['nome']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifica Aeroporto"),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: "Nome aeroporto")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annulla")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salva")),
        ],
      ),
    );
    if (ok == true && controller.text.isNotEmpty) {
      await supa.from('aeroporti').update({'nome': controller.text}).match({'id': item['id']});
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final nome = (r['nome'] ?? '').toString().toLowerCase();
      return q.isEmpty || nome.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nuovo Aeroporto')),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cerca',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: [
            const Text('Attiva'),
            Switch(value: _attiva, onChanged: (v) => setState(() => _attiva = v)),
            const Spacer(),
            AsyncFilledButton(
                onPressed: () async {
                  await supa.from('aeroporti').insert({'nome': _nome.text, 'attiva': _attiva});
                  _nome.clear();
                  _load();
                },
                child: const Text('SALVA')),
          ],
        ),
        const Divider(),
        for (final r in filtered)
          _RowCard(
            title: r['nome'] ?? '',
            hasActive: true,
            activeValue: r['attiva'] ?? false,
            onEdit: () => _showEditDialog(r),
            onToggle: (v) async {
              await supa.from('aeroporti').update({'attiva': v}).match({'id': r['id']});
              _load();
            },
            onDelete: () async {
              if (await _confirm(context, "Eliminare?")) {
                await supa.from('aeroporti').delete().match({'id': r['id']});
                _load();
              }
            },
          ),
      ],
    );
  }
}

/* -----------------------------------------------------------
 * STRUTTURE
 * ----------------------------------------------------------*/

class _StrutturePage extends StatefulWidget {
  const _StrutturePage({this.highlightId});

  /// id_uuid della struttura da evidenziare (apertura da mappa).
  final String? highlightId;

  @override
  State<_StrutturePage> createState() => _StrutturePageState();
}

class _StrutturePageState extends State<_StrutturePage> {
  final supa = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];

  final GlobalKey _highlightKey = GlobalKey();
  String? _highlightId;
  bool _blinkOn = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _highlightId = (widget.highlightId ?? '').trim().isEmpty
        ? null
        : widget.highlightId!.trim();
    _load().then((_) {
      if (_highlightId != null) _focusHighlight();
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await supa.from('structures').select('*').order('name');
    if (!mounted) return;
    setState(() => _items = List<Map<String, dynamic>>.from(res));
  }

  /// Scorre fino alla struttura evidenziata e la fa lampeggiare in giallo 5 volte.
  /// La riga può non essere ancora "montata" (lista lazy): riprova alcune volte.
  void _focusHighlight() {
    var attempts = 0;
    void tryScroll() {
      if (!mounted) return;
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          alignment: 0.3,
        );
        _startBlink();
        return;
      }
      attempts++;
      if (attempts <= 10) {
        Future.delayed(const Duration(milliseconds: 200), tryScroll);
      } else {
        _startBlink();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
  }

  void _startBlink() {
    _blinkTimer?.cancel();
    var ticks = 0;
    const totalTicks = 10; // 5 lampeggi (on/off)
    setState(() => _blinkOn = true);
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 350), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      ticks++;
      setState(() => _blinkOn = !_blinkOn);
      if (ticks >= totalTicks) {
        t.cancel();
        if (mounted) setState(() => _blinkOn = false);
      }
    });
  }

  Future<void> _showStrutturaDialog({Map<String, dynamic>? item}) async {
    final isEdit = item != null;
    final cName = TextEditingController(text: isEdit ? (item['name'] ?? '').toString() : '');
    final cAddr = TextEditingController(text: isEdit ? (item['address'] ?? '').toString() : '');
    final cMaps = TextEditingController(text: isEdit ? (item['maps_link'] ?? '').toString() : '');
    final cEmail = TextEditingController(text: isEdit ? (item['email'] ?? '').toString() : '');
    final cGps = TextEditingController(text: isEdit ? (item['posizione_gps'] ?? '').toString() : '');
    var isHotel = isEdit ? item['is_hotel'] == true : false;
    var isRistorante = isEdit ? item['is_ristorante'] == true : false;
    var active = isEdit ? ((item['active'] ?? false) == true) : true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isEdit ? 'Modifica Struttura' : 'Nuova Struttura'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: cName,
                    decoration: const InputDecoration(
                      labelText: 'Nome struttura',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cAddr,
                    decoration: const InputDecoration(
                      labelText: 'Indirizzo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cMaps,
                    decoration: const InputDecoration(
                      labelText: 'Link Maps',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cGps,
                    decoration: const InputDecoration(
                      labelText: 'Coordinate GPS (lat, lon)',
                      hintText: 'es. 41.902782, 12.496366',
                      helperText: 'Se compilate, hanno priorità sul Link Maps',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email struttura (Outlook)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tipologia struttura',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('HOTEL'),
                        selected: isHotel,
                        onSelected: (v) => setLocal(() => isHotel = v),
                      ),
                      FilterChip(
                        label: const Text('RISTORANTE'),
                        selected: isRistorante,
                        onSelected: (v) => setLocal(() => isRistorante = v),
                      ),
                    ],
                  ),
                  if (!isEdit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Attiva'),
                      value: active,
                      onChanged: (v) => setLocal(() => active = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isEdit ? 'Salva' : 'Crea'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || cName.text.trim().isEmpty) return;

    final payload = <String, dynamic>{
      'name': cName.text.trim(),
      'address': cAddr.text.trim(),
      'maps_link': cMaps.text.trim(),
      'posizione_gps': _normalizeGpsInput(cGps.text),
      'email': cEmail.text.trim(),
      'is_hotel': isHotel,
      'is_ristorante': isRistorante,
    };
    if (!isEdit) payload['active'] = active;

    try {
      if (isEdit) {
        await supa.from('structures').update(payload).match({'id_uuid': item['id_uuid']});
      } else {
        await supa.from('structures').insert(payload);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio struttura: $e')),
      );
    } finally {
      cName.dispose();
      cAddr.dispose();
      cMaps.dispose();
      cEmail.dispose();
      cGps.dispose();
    }
  }

  /// Etichetta tipologia struttura in base ai flag HOTEL / RISTORANTE.
  String _tipologiaLabel(Map<String, dynamic> r) {
    final parts = <String>[
      if (r['is_hotel'] == true) 'HOTEL',
      if (r['is_ristorante'] == true) 'RISTORANTE',
    ];
    return parts.join(' · ');
  }

  /// Normalizza l'input GPS a "lat, lon" se riconosciuto, altrimenti lo lascia
  /// così com'è (vuoto -> null).
  String? _normalizeGpsInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final coords = mdoGpsCoordsFromMapsLink(text);
    if (coords != null) return formatGpsCoordsText(coords.$1, coords.$2);
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final address = (r['address'] ?? '').toString().toLowerCase();
      final email = (r['email'] ?? '').toString().toLowerCase();
      return q.isEmpty || name.contains(q) || address.contains(q) || email.contains(q);
    }).toList();

    return ListView(
      // ignore: deprecated_member_use
      cacheExtent: _highlightId != null ? 100000 : null,
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _showStrutturaDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nuova Struttura'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cerca',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        const Divider(),
        for (final r in filtered)
          () {
            final isHi = _highlightId != null &&
                (r['id_uuid'] ?? '').toString().trim() == _highlightId;
            return _RowCard(
            key: isHi ? _highlightKey : null,
            color: isHi && _blinkOn ? Colors.yellow.shade600 : null,
            title: r['name'] ?? '',
            subtitle: [
              if (_tipologiaLabel(r).isNotEmpty) _tipologiaLabel(r),
              if ((r['address'] ?? '').toString().trim().isNotEmpty)
                (r['address'] ?? '').toString(),
              if (r['email'] != null && r['email'].toString().trim().isNotEmpty)
                r['email'].toString(),
            ].join('\n'),
            hasActive: true,
            activeValue: r['active'] ?? false,
            onEdit: () => _showStrutturaDialog(item: r),
            onToggle: (v) async {
              await supa.from('structures').update({'active': v}).match({'id_uuid': r['id_uuid']});
              _load();
            },
            onDelete: () async {
              if (await _confirm(context, "Eliminare?")) {
                await supa.from('structures').delete().match({'id_uuid': r['id_uuid']});
                _load();
              }
            },
          );
          }(),
      ],
    );
  }
}