import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/confirm_sound_service.dart';
import '../services/vestiario_fabbisogno_service.dart';
import '../services/vestiario_magazzino_service.dart';
import '../utils/excel_export_helper.dart';
import '../utils/gestopro_data_palette.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../utils/responsive.dart';
import '../utils/vestiario_catalog.dart';
import '../widgets/app_logo.dart';
import '../widgets/cronos_app_background.dart';
import '../widgets/classic_app_bar_chrome.dart';

class _RigaUnificata {
  final String articolo;
  final String taglia;
  final VestiarioInventarioRiga? stock;
  final int fabbisognoEstivo;
  final int fabbisognoInvernale;

  const _RigaUnificata({
    required this.articolo,
    required this.taglia,
    this.stock,
    this.fabbisognoEstivo = 0,
    this.fabbisognoInvernale = 0,
  });

  int get fabbisognoTotale => VestiarioCatalog.isArticoloModelloUnico(articolo)
      ? VestiarioCatalog.fabbisognoModelloUnico(fabbisognoEstivo, fabbisognoInvernale)
      : fabbisognoEstivo + fabbisognoInvernale;

  int get daOrdinareTotale {
    final mag = stock?.magazzino ?? 0;
    final diff = fabbisognoTotale - mag;
    return diff > 0 ? diff : 0;
  }
}

class _RiepilogoTipologia {
  final String articolo;
  final int fabbisogno;
  final int magazzino;
  final int ordinato;
  final int daOrdinare;

  const _RiepilogoTipologia({
    required this.articolo,
    required this.fabbisogno,
    required this.magazzino,
    required this.ordinato,
    required this.daOrdinare,
  });
}

class AdminVestiarioInventarioPage extends StatefulWidget {
  const AdminVestiarioInventarioPage({super.key});

  @override
  State<AdminVestiarioInventarioPage> createState() =>
      _AdminVestiarioInventarioPageState();
}

class _AdminVestiarioInventarioPageState extends State<AdminVestiarioInventarioPage>
    with RouteAware {
  late GestoproDataPalette _palette;
  bool _loading = true;
  bool _saving = false;
  VestiarioSeasonMultipliers _multipliers = VestiarioSeasonMultipliers(
    estivo: VestiarioFabbisognoService.defaultMultipliersEstivo(),
    invernale: VestiarioFabbisognoService.defaultMultipliersInvernale(),
  );
  List<VestiarioFabbisognoRow> _fabbisognoRows = const [];
  final Map<String, TextEditingController> _magControllers = <String, TextEditingController>{};
  final Map<String, TextEditingController> _ordControllers = <String, TextEditingController>{};
  final Map<String, TextEditingController> _arrControllers = <String, TextEditingController>{};
  final Map<String, TextEditingController> _marcaControllers = <String, TextEditingController>{};
  List<VestiarioInventarioRiga> _righeEstivo = const [];
  List<VestiarioInventarioRiga> _righeInvernale = const [];
  List<VestiarioInventarioRiga> _righeStock = const [];

  String? _articoloSelezionato;
  final Set<String> _dpiRigheDaEliminare = <String>{};
  Timer? _sidebarRefreshDebounce;
  bool _syncingStockControllers = false;
  bool _riepilogoExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      logoLightSweepRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _load();
  }

  @override
  void dispose() {
    logoLightSweepRouteObserver.unsubscribe(this);
    _sidebarRefreshDebounce?.cancel();
    for (final c in _magControllers.values) {
      c.dispose();
    }
    for (final c in _ordControllers.values) {
      c.dispose();
    }
    for (final c in _arrControllers.values) {
      c.dispose();
    }
    for (final c in _marcaControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _narrowLayout =>
      useMobileUi(context) || useCompactPageLayout(context);

  void _scheduleSidebarRefresh() {
    if (_syncingStockControllers) return;
    _sidebarRefreshDebounce?.cancel();
    _sidebarRefreshDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  String _stockKey(String articolo, String taglia) => '$articolo|$taglia';
  String _baseKey(VestiarioInventarioRiga r) => _stockKey(r.articolo, r.taglia);
  String _ordKey(VestiarioInventarioRiga r) => '${_baseKey(r)}|ord';
  String _arrKey(VestiarioInventarioRiga r) => '${_baseKey(r)}|arr';
  String _marcaKey(VestiarioInventarioRiga r) => '${_baseKey(r)}|marca';

  void _disposeKeysNotIn(Set<String> baseKeys) {
    for (final k in _magControllers.keys.toList()) {
      if (!baseKeys.contains(k)) _magControllers.remove(k)?.dispose();
    }
    for (final k in _ordControllers.keys.toList()) {
      final base = k.endsWith('|ord') ? k.substring(0, k.length - 4) : k;
      if (!baseKeys.contains(base)) _ordControllers.remove(k)?.dispose();
    }
    for (final k in _arrControllers.keys.toList()) {
      final base = k.endsWith('|arr') ? k.substring(0, k.length - 4) : k;
      if (!baseKeys.contains(base)) _arrControllers.remove(k)?.dispose();
    }
    for (final k in _marcaControllers.keys.toList()) {
      final base = k.endsWith('|marca') ? k.substring(0, k.length - 6) : k;
      if (!baseKeys.contains(base)) _marcaControllers.remove(k)?.dispose();
    }
  }

  TextEditingController _marcaCtrl(VestiarioInventarioRiga r) {
    final key = _marcaKey(r);
    return _marcaControllers.putIfAbsent(key, () => TextEditingController(text: r.marca));
  }

  TextEditingController _arrivoCtrl(VestiarioInventarioRiga r) {
    final key = _arrKey(r);
    return _arrControllers.putIfAbsent(key, () => TextEditingController(text: '0'));
  }

  void _clearArrivoControllers() {
    for (final c in _arrControllers.values) {
      if (c.text != '0') c.text = '0';
    }
  }

  List<({String stagione, String articolo, String taglia, int quantita})> _arriviPendenti() {
    final out = <({String stagione, String articolo, String taglia, int quantita})>[];
    for (final r in _righeStock) {
      final q = _parseCtrl(_arrControllers[_arrKey(r)], 0);
      if (q > 0) {
        out.add((
          stagione: VestiarioCatalog.magazzinoStagioneEffettiva(r.articolo, r.stagione),
          articolo: r.articolo,
          taglia: r.taglia,
          quantita: q,
        ));
      }
    }
    return out;
  }

  Future<void> _showStoricoArrivi(String articolo) async {
    try {
      final rows = await VestiarioMagazzinoService.loadStoricoArrivi(articolo: articolo, limit: 100);
      if (!mounted) return;
      final fmt = DateFormat('dd/MM/yyyy HH:mm');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Consegnati · ${VestiarioCatalog.label(articolo)}'),
          content: SizedBox(
            width: 420,
            child: rows.isEmpty
                ? const Text('Nessuna consegna registrata per questo articolo.')
                : SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.1),
                        1: FlexColumnWidth(0.7),
                        2: FlexColumnWidth(1.4),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        const TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text('Taglia', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text('Qtà', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text('Data/ora', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        ...rows.map(
                          (r) => TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(r.taglia),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text('${r.quantita}', textAlign: TextAlign.right),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(fmt.format(r.arrivatoAt)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
          ],
        ),
      );
    } catch (e) {
      _snack('Storico consegnati non disponibile: $e', error: true);
    }
  }

  void _syncControllers(Iterable<VestiarioInventarioRiga> righe) {
    _syncingStockControllers = true;
    try {
      final baseKeys = righe.map(_baseKey).toSet();
      _disposeKeysNotIn(baseKeys);
      for (final r in righe) {
        _upsertCtrl(_magControllers, _baseKey(r), '${r.magazzino}');
        _upsertCtrl(_ordControllers, _ordKey(r), '${r.ordinato}');
        if (VestiarioCatalog.isArticoloDpiMagazzino(r.articolo)) {
          _upsertCtrl(_marcaControllers, _marcaKey(r), r.marca);
        }
      }
    } finally {
      _syncingStockControllers = false;
    }
  }

  void _upsertCtrl(
    Map<String, TextEditingController> map,
    String key,
    String text, {
    bool resetIfExists = true,
  }) {
    final existing = map[key];
    if (existing == null) {
      map[key] = TextEditingController(text: text);
    } else if (resetIfExists && existing.text != text) {
      existing.text = text;
    }
  }

  List<_RigaUnificata> get _righeUnificate {
    final keys = <String>{};
    for (final r in _righeStock) {
      keys.add(_stockKey(r.articolo, r.taglia));
    }
    for (final r in [..._righeEstivo, ..._righeInvernale]) {
      keys.add(_stockKey(r.articolo, r.taglia));
    }
    final stockByKey = <String, VestiarioInventarioRiga>{
      for (final r in _righeStock) _stockKey(r.articolo, r.taglia): r,
    };
    final fabbEst = <String, int>{};
    final fabbInv = <String, int>{};
    for (final r in _righeEstivo) {
      final k = _stockKey(r.articolo, r.taglia);
      fabbEst[k] = (fabbEst[k] ?? 0) + r.fabbisogno;
    }
    for (final r in _righeInvernale) {
      final k = _stockKey(r.articolo, r.taglia);
      fabbInv[k] = (fabbInv[k] ?? 0) + r.fabbisogno;
    }
    final out = <_RigaUnificata>[];
    for (final key in keys) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      out.add(
        _RigaUnificata(
          articolo: parts[0],
          taglia: parts[1],
          stock: stockByKey[key],
          fabbisognoEstivo: fabbEst[key] ?? 0,
          fabbisognoInvernale: fabbInv[key] ?? 0,
        ),
      );
    }
    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.articolo).compareTo(VestiarioCatalog.label(b.articolo));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.taglia, b.taglia);
    });
    return out;
  }

  Map<String, List<_RigaUnificata>> get _righePerArticolo {
    final map = <String, List<_RigaUnificata>>{};
    for (final r in _righeUnificate) {
      map.putIfAbsent(r.articolo, () => <_RigaUnificata>[]).add(r);
    }
    return map;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final multipliers = await VestiarioFabbisognoService.loadMultipliers();
      final aggregations = await VestiarioFabbisognoService.loadAggregations();
      final records = await VestiarioMagazzinoService.loadRecordsMap();
      var estivo = await VestiarioMagazzinoService.buildInventario(
        stagione: 'estivo',
        fabbisognoRows: aggregations,
        multiplierByItem: multipliers.estivo,
        recordsMap: records,
      );
      var invernale = await VestiarioMagazzinoService.buildInventario(
        stagione: 'invernale',
        fabbisognoRows: aggregations,
        multiplierByItem: multipliers.invernale,
        recordsMap: records,
      );
      estivo = VestiarioMagazzinoService.espandiGrigliaTaglie(righe: estivo, stagione: 'estivo');
      invernale =
          VestiarioMagazzinoService.espandiGrigliaTaglie(righe: invernale, stagione: 'invernale');
      if (!mounted) return;
      var stock = VestiarioMagazzinoService.mergeStockUnificato(
        estivo: estivo,
        invernale: invernale,
      );
      stock = _completaRigheStock(stock, estivo, invernale);
      setState(() {
        _multipliers = multipliers;
        _fabbisognoRows = aggregations;
        _righeEstivo = estivo;
        _righeInvernale = invernale;
        _righeStock = stock;
        _dpiRigheDaEliminare.clear();
        final entries = _articoliEntriesOrdinati(_righePerArticolo);
        if (entries.isEmpty) {
          _articoloSelezionato = null;
        } else if (_articoloSelezionato == null ||
            !entries.any((e) => e.key == _articoloSelezionato)) {
          _articoloSelezionato = entries.first.key;
        }
      });
      _syncControllers(stock);
    } catch (e) {
      _snack('Errore caricamento inventario: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _parseCtrl(TextEditingController? ctrl, int fallback) {
    final parsed = int.tryParse((ctrl?.text ?? '').trim());
    if (parsed == null) return fallback;
    return parsed < 0 ? 0 : parsed;
  }

  VestiarioInventarioRiga _edited(VestiarioInventarioRiga r) {
    return VestiarioInventarioRiga(
      stagione: r.stagione,
      articolo: r.articolo,
      taglia: r.taglia,
      magazzino: _parseCtrl(_magControllers[_baseKey(r)], r.magazzino),
      fabbisogno: r.fabbisogno,
      ordinato: _parseCtrl(_ordControllers[_ordKey(r)], r.ordinato),
      arrivatoTotale: r.arrivatoTotale,
      marca: VestiarioCatalog.isArticoloDpiMagazzino(r.articolo)
          ? (_marcaControllers[_marcaKey(r)]?.text ?? r.marca).trim()
          : r.marca,
    );
  }

  List<VestiarioInventarioRiga> _righeEdited(List<VestiarioInventarioRiga> source) =>
      source.map(_edited).toList(growable: false);

  List<VestiarioInventarioRiga> _completaRigheStock(
    List<VestiarioInventarioRiga> stock,
    List<VestiarioInventarioRiga> estivo,
    List<VestiarioInventarioRiga> invernale,
  ) {
    final byKey = <String, VestiarioInventarioRiga>{
      for (final r in stock) _stockKey(r.articolo, r.taglia): r,
    };
    for (final articolo in VestiarioCatalog.articoliMagazzino) {
      if (VestiarioCatalog.isArticoloDpiMagazzino(articolo)) {
        final hasAny = byKey.keys.any((k) => k.startsWith('$articolo|'));
        if (!hasAny) {
          final k = _stockKey(articolo, VestiarioCatalog.tagliaInventarioUnitaria);
          byKey[k] = VestiarioInventarioRiga(
            stagione: VestiarioCatalog.stagioneRegistrazioneMagazzino(articolo),
            articolo: articolo,
            taglia: VestiarioCatalog.tagliaInventarioUnitaria,
            magazzino: 0,
            fabbisogno: 0,
          );
        }
        continue;
      }
      for (final taglia in VestiarioCatalog.tagliePerArticolo(articolo)) {
        final k = _stockKey(articolo, taglia);
        byKey.putIfAbsent(
          k,
          () => VestiarioInventarioRiga(
            stagione: VestiarioCatalog.stagioneRegistrazioneMagazzino(articolo),
            articolo: articolo,
            taglia: taglia,
            magazzino: 0,
            fabbisogno: 0,
          ),
        );
      }
    }
    for (final r in [...estivo, ...invernale]) {
      final k = _stockKey(r.articolo, r.taglia);
      final existing = byKey[k];
      if (existing == null) {
        byKey[k] = VestiarioInventarioRiga(
          stagione: VestiarioCatalog.stagioneRegistrazioneMagazzino(r.articolo),
          articolo: r.articolo,
          taglia: r.taglia,
          magazzino: 0,
          fabbisogno: 0,
        );
      }
    }
    final out = byKey.values.toList(growable: false);
    out.sort((a, b) {
      final c = VestiarioCatalog.label(a.articolo).compareTo(VestiarioCatalog.label(b.articolo));
      if (c != 0) return c;
      return VestiarioCatalog.compareSizes(a.taglia, b.taglia);
    });
    return out;
  }

  List<_RiepilogoTipologia> _riepilogoFabbisogno(List<VestiarioInventarioRiga> righe) {
    final acc = <String, int>{};
    for (final r in righe) {
      acc[r.articolo] = (acc[r.articolo] ?? 0) + r.fabbisogno;
    }
    final out = <_RiepilogoTipologia>[];
    for (final key in VestiarioCatalog.articoliMagazzino) {
      final fabb = acc[key];
      if (fabb == null || fabb <= 0) continue;
      out.add(
        _RiepilogoTipologia(
          articolo: key,
          fabbisogno: fabb,
          magazzino: 0,
          ordinato: 0,
          daOrdinare: 0,
        ),
      );
    }
    for (final entry in acc.entries) {
      if (VestiarioCatalog.articoliMagazzino.contains(entry.key)) continue;
      if (entry.value <= 0) continue;
      out.add(
        _RiepilogoTipologia(
          articolo: entry.key,
          fabbisogno: entry.value,
          magazzino: 0,
          ordinato: 0,
          daOrdinare: 0,
        ),
      );
    }
    return out;
  }

  List<_RiepilogoTipologia> _riepilogoMagazzinoUnificato() {
    final acc = <String, _RiepilogoTipologia>{};
    for (final r in _righeEdited(_righeStock)) {
      final prev = acc[r.articolo];
      if (prev == null) {
        acc[r.articolo] = _RiepilogoTipologia(
          articolo: r.articolo,
          fabbisogno: 0,
          magazzino: r.magazzino,
          ordinato: r.ordinato,
          daOrdinare: 0,
        );
      } else {
        acc[r.articolo] = _RiepilogoTipologia(
          articolo: r.articolo,
          fabbisogno: 0,
          magazzino: prev.magazzino + r.magazzino,
          ordinato: prev.ordinato + r.ordinato,
          daOrdinare: 0,
        );
      }
    }
    final out = <_RiepilogoTipologia>[];
    for (final key in VestiarioCatalog.articoliMagazzino) {
      final t = acc[key];
      if (t == null) continue;
      if (t.magazzino <= 0 && t.ordinato <= 0) continue;
      out.add(t);
    }
    for (final entry in acc.entries) {
      if (VestiarioCatalog.articoliMagazzino.contains(entry.key)) continue;
      out.add(entry.value);
    }
    return out;
  }

  List<VestiarioInventarioRiga> _righeDpiDaSalvare(List<VestiarioInventarioRiga> righe) {
    final out = <VestiarioInventarioRiga>[];
    final marchePerArticolo = <String, Set<String>>{};
    for (final r in righe) {
      if (!VestiarioCatalog.isArticoloDpiMagazzino(r.articolo)) {
        out.add(r);
        continue;
      }
      final marca = r.marca.trim();
      final hasDati = marca.isNotEmpty ||
          r.magazzino > 0 ||
          r.ordinato > 0 ||
          r.arrivatoTotale > 0;
      if (!hasDati) continue;
      if (marca.isEmpty) {
        throw StateError(
          'Inserisci Marca/modello per ${VestiarioCatalog.label(r.articolo)} '
          '(riga con giacenza o ordini).',
        );
      }
      final key = marca.toLowerCase();
      final set = marchePerArticolo.putIfAbsent(r.articolo, () => <String>{});
      if (!set.add(key)) {
        throw StateError(
          'Marca/modello duplicata per ${VestiarioCatalog.label(r.articolo)}: $marca',
        );
      }
      out.add(r);
    }
    return out;
  }

  void _aggiungiVarianteDpi(String articolo) {
    final taglia = VestiarioCatalog.nuovaTagliaDpiVariante();
    final riga = VestiarioInventarioRiga(
      stagione: VestiarioCatalog.stagioneRegistrazioneMagazzino(articolo),
      articolo: articolo,
      taglia: taglia,
      magazzino: 0,
      fabbisogno: 0,
    );
    setState(() {
      _righeStock = [..._righeStock, riga];
      _syncControllers(_righeStock);
    });
  }

  Future<void> _rimuoviVarianteDpi(VestiarioInventarioRiga r) async {
    final righeArticolo =
        _righeStock.where((x) => x.articolo == r.articolo).length;
    if (righeArticolo <= 1) {
      _snack('Serve almeno una riga Marca/modello.', error: true);
      return;
    }
    final edited = _edited(r);
    final hasDati = edited.magazzino > 0 ||
        edited.ordinato > 0 ||
        edited.arrivatoTotale > 0 ||
        edited.marca.trim().isNotEmpty;
    if (hasDati) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rimuovi riga'),
          content: Text(
            'Eliminare la variante '
            '${edited.marca.trim().isEmpty ? '(senza nome)' : edited.marca} '
            'di ${VestiarioCatalog.label(r.articolo)}?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rimuovi')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _dpiRigheDaEliminare.add(_baseKey(r));
    }
    final base = _baseKey(r);
    setState(() {
      _righeStock = _righeStock.where((x) => _baseKey(x) != base).toList();
    });
    _magControllers.remove(base)?.dispose();
    _ordControllers.remove(_ordKey(r))?.dispose();
    _arrControllers.remove(_arrKey(r))?.dispose();
    _marcaControllers.remove(_marcaKey(r))?.dispose();
  }

  int _conteggioModelliDpi(String articolo) =>
      _righeStock.where((r) => r.articolo == articolo).length;

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      var righe = _righeDpiDaSalvare(_righeEdited(_righeStock));
      final arrivi = _arriviPendenti();
      for (final key in _dpiRigheDaEliminare) {
        final parts = key.split('|');
        if (parts.length == 2) {
          await VestiarioMagazzinoService.deleteRiga(
            articolo: parts[0],
            taglia: parts[1],
          );
        }
      }
      _dpiRigheDaEliminare.clear();
      await VestiarioMagazzinoService.saveRighe(righe);
      final nArrivi = arrivi.isEmpty
          ? 0
          : await VestiarioMagazzinoService.registraArrivi(arrivi);
      _clearArrivoControllers();
      await _load();
      if (!mounted) return;
      if (nArrivi > 0) {
        _snack('Salvato · $nArrivi ${nArrivi == 1 ? 'consegna registrata' : 'consegne registrate'}');
      } else {
        _snack('Dati salvati');
      }
    } catch (e) {
      _snack('Salvataggio non riuscito: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportExcel() async {
    try {
      final stock = _righeEdited(_righeStock);
      final excel = Excel.createExcel();
      // Su web excel.rename/delete fallisce (liste interne non modificabili).
      final sheet = excel['Sheet1'];
      sheet.appendRow(<String>[
        'Articolo',
        'Taglia',
        'In magazzino',
        'Ordinato',
        'Fabbisogno estivo',
        'Fabbisogno invernale',
        'Fabbisogno totale',
        'Da ordinare (totale)',
      ]);
      final fabbEst = <String, int>{};
      final fabbInv = <String, int>{};
      for (final r in _righeEstivo) {
        final k = _stockKey(r.articolo, r.taglia);
        fabbEst[k] = (fabbEst[k] ?? 0) + r.fabbisogno;
      }
      for (final r in _righeInvernale) {
        final k = _stockKey(r.articolo, r.taglia);
        fabbInv[k] = (fabbInv[k] ?? 0) + r.fabbisogno;
      }
      for (final r in stock) {
        final k = _stockKey(r.articolo, r.taglia);
        final fe = fabbEst[k] ?? 0;
        final fi = fabbInv[k] ?? 0;
        final fabbTot = VestiarioCatalog.isArticoloModelloUnico(r.articolo)
            ? VestiarioCatalog.fabbisognoModelloUnico(fe, fi)
            : fe + fi;
        final daOrd = (fabbTot - r.magazzino) > 0 ? fabbTot - r.magazzino : 0;
        sheet.appendRow(<dynamic>[
          VestiarioCatalog.label(r.articolo),
          r.taglia,
          r.magazzino,
          r.ordinato,
          fe,
          fi,
          fabbTot,
          daOrd,
        ]);
      }
      final encoded = excel.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Impossibile generare file Excel');
      }
      await ExcelExportHelper.saveAndReveal(
        pageName: 'inventario_vestiario',
        bytes: Uint8List.fromList(encoded),
        openFile: true,
      );
      if (!mounted) return;
      _snack('Export Excel completato');
    } catch (e) {
      _snack('Export Excel non riuscito: $e', error: true);
    }
  }

  Widget _riepilogoNumCell(
    int n, {
    TextAlign align = TextAlign.right,
    Color? color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        '$n',
        textAlign: align,
        style: TextStyle(
          fontSize: GestoproDataPalette.fsBody,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color ?? _palette.textPrimary,
        ),
      ),
    );
  }

  Widget _riepilogoPanel() {
    final estivoMap = {
      for (final t in _riepilogoFabbisogno(_righeEstivo)) t.articolo: t.fabbisogno,
    };
    final invMap = {
      for (final t in _riepilogoFabbisogno(_righeInvernale)) t.articolo: t.fabbisogno,
    };
    final magMap = {
      for (final t in _riepilogoMagazzinoUnificato()) t.articolo: t,
    };

    final articoli = <String>[
      ...VestiarioCatalog.articoliMagazzino,
      ...estivoMap.keys.where((k) => !VestiarioCatalog.articoliMagazzino.contains(k)),
      ...invMap.keys.where((k) => !VestiarioCatalog.articoliMagazzino.contains(k)),
      ...magMap.keys.where((k) => !VestiarioCatalog.articoliMagazzino.contains(k)),
    ];

    final rows = <String>[];
    for (final a in articoli) {
      if (rows.contains(a)) continue;
      final e = estivoMap[a] ?? 0;
      final i = invMap[a] ?? 0;
      final m = magMap[a];
      final mag = m?.magazzino ?? 0;
      final ord = m?.ordinato ?? 0;
      if (e == 0 && i == 0 && mag == 0 && ord == 0) continue;
      rows.add(a);
    }

    final totEst = estivoMap.values.fold<int>(0, (a, b) => a + b);
    final totInv = invMap.values.fold<int>(0, (a, b) => a + b);
    final totMag = magMap.values.fold<int>(0, (a, t) => a + t.magazzino);
    final totOrd = magMap.values.fold<int>(0, (a, t) => a + t.ordinato);

    Widget hdr(String t, {Color? bg, Color? fg, TextAlign align = TextAlign.left}) {
      return Container(
        color: bg ?? _palette.canvas,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Text(
          t,
          textAlign: align,
          style: TextStyle(
            fontSize: GestoproDataPalette.fsLabel,
            fontWeight: FontWeight.w700,
            color: fg ?? _palette.headerMuted,
          ),
        ),
      );
    }

    final table = Table(
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(0.9),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(0.85),
        4: FlexColumnWidth(0.85),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: _articoloTableBorder,
      children: [
        TableRow(
          children: [
            hdr('Tipologia'),
            hdr('Est.', bg: _palette.estivoBg, fg: _palette.estivo, align: TextAlign.right),
            hdr('Inv.', bg: _palette.invernaleBg, fg: _palette.invernale, align: TextAlign.right),
            hdr('Mag.', align: TextAlign.right),
            hdr('Ord.', align: TextAlign.right),
          ],
        ),
        ...rows.map((articolo) {
          var e = estivoMap[articolo] ?? 0;
          var i = invMap[articolo] ?? 0;
          if (VestiarioCatalog.isArticoloModelloUnico(articolo)) {
            e = VestiarioCatalog.fabbisognoModelloUnico(e, i);
            i = 0;
          }
          final m = magMap[articolo];
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  VestiarioCatalog.label(articolo),
                  style: TextStyle(
                    fontSize: GestoproDataPalette.fsBody,
                    fontWeight: FontWeight.w600,
                    color: _palette.textPrimary,
                  ),
                ),
              ),
              _riepilogoNumCell(e, color: _palette.estivo),
              _riepilogoNumCell(i, color: _palette.invernale),
              _riepilogoNumCell(m?.magazzino ?? 0),
              _riepilogoNumCell(m?.ordinato ?? 0),
            ],
          );
        }),
      ],
    );

    final subtitle = 'Tot. E $totEst · I $totInv · mag. $totMag · ord. $totOrd';
    final tableBody = rows.isEmpty
        ? Text(
            'Nessun dato da mostrare.',
            style: TextStyle(
              fontSize: GestoproDataPalette.fsBody,
              color: _palette.textMuted,
            ),
          )
        : _narrowLayout
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 420),
                  child: table,
                ),
              )
            : table;

    return Container(
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(_palette.radius),
        border: Border.all(color: _palette.border),
        boxShadow: _palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _riepilogoExpanded = !_riepilogoExpanded),
              borderRadius: BorderRadius.circular(_palette.radius),
              child: Padding(
                padding: GestoproDataPalette.padCard,
                child: Row(
                  children: [
                    Icon(
                      Icons.summarize_outlined,
                      size: 14,
                      color: _palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Riepilogo',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: GestoproDataPalette.fsTitle,
                              color: _palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: GestoproDataPalette.fsLabel,
                              color: _palette.textMuted,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _riepilogoExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _palette.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_riepilogoExpanded) ...[
            Divider(height: 1, color: _palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _narrowLayout
                  ? tableBody
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: tableBody,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _moltiplicatoriLine(Map<String, int> map) {
    final parts = <String>[];
    for (final k in map.keys) {
      final q = map[k] ?? 0;
      if (q <= 0) continue;
      parts.add('${VestiarioCatalog.label(k)} $q/a');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  TableBorder get _articoloTableBorder => TableBorder.all(
        color: _palette.border,
        width: 1,
      );

  int _daOrdinare(_RigaUnificata u) {
    final s = u.stock;
    if (s == null) return 0;
    final mag = _edited(s).magazzino;
    final diff = u.fabbisognoTotale - mag;
    return diff > 0 ? diff : 0;
  }

  int _daOrdinareArticolo(String articolo) {
    final righe = _righePerArticolo[articolo] ?? const [];
    return righe.fold(0, (sum, u) => sum + _daOrdinare(u));
  }

  List<MapEntry<String, List<_RigaUnificata>>> _articoliEntriesOrdinati(
    Map<String, List<_RigaUnificata>> gruppi,
  ) {
    final out = <MapEntry<String, List<_RigaUnificata>>>[];
    for (final a in VestiarioCatalog.articoliMagazzino) {
      final righe = gruppi[a];
      if (righe != null && righe.isNotEmpty) {
        out.add(MapEntry(a, righe));
      }
    }
    final extra = gruppi.entries
        .where((e) => !VestiarioCatalog.articoliMagazzino.contains(e.key))
        .toList(growable: false)
      ..sort((a, b) => VestiarioCatalog.label(a.key).compareTo(VestiarioCatalog.label(b.key)));
    out.addAll(extra);
    return out;
  }

  Widget _listaArticoli(
    List<MapEntry<String, List<_RigaUnificata>>> entries,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return Material(
      color: _palette.surface,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final e = entries[i];
          final id = e.key;
          final label = VestiarioCatalog.label(id);
          final daOrd = _daOrdinareArticolo(id);
          final isSel = id == selected;
          return ListTile(
            dense: true,
            selected: isSel,
            selectedTileColor: _palette.selectedTile,
            title: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: GestoproDataPalette.fsBody,
                color: _palette.textPrimary,
              ),
            ),
            subtitle: Text(
              VestiarioCatalog.isArticoloDpiMagazzino(id)
                  ? 'DPI · ${_conteggioModelliDpi(id)} '
                      '${_conteggioModelliDpi(id) == 1 ? 'modello' : 'modelli'}'
                  : '${e.value.length} taglie · da ord. $daOrd',
              style: TextStyle(fontSize: GestoproDataPalette.fsTiny, color: daOrd > 0 ? _palette.estivo : _palette.textMuted),
            ),
            onTap: () => onSelect(id),
          );
        },
      ),
    );
  }

  Widget _pannelloDettaglio(List<_RigaUnificata> righe, {bool shrinkWrap = false}) {
    if (_articoloSelezionato == null) {
      return Center(child: Text('Seleziona un articolo', style: TextStyle(color: _palette.textMuted)));
    }
    final label = VestiarioCatalog.label(_articoloSelezionato!);
    final daOrdTot = righe.fold<int>(0, (s, u) => s + _daOrdinare(u));

    final editor = _ArticoloInventarioEditor(
      key: ValueKey('${_articoloSelezionato}_${righe.length}'),
      palette: _palette,
      articolo: _articoloSelezionato!,
      righe: righe,
      magControllers: _magControllers,
      ordControllers: _ordControllers,
      arrivoControllerFor: _arrivoCtrl,
      marcaControllerFor: _marcaCtrl,
      baseKey: _baseKey,
      ordKey: _ordKey,
      daOrdinare: _daOrdinare,
      onStockChanged: _scheduleSidebarRefresh,
      onAggiungiVarianteDpi: _aggiungiVarianteDpi,
      onRimuoviVarianteDpi: _rimuoviVarianteDpi,
      shrinkWrap: shrinkWrap,
      minTableWidth: VestiarioCatalog.isArticoloDpiMagazzino(_articoloSelezionato!)
          ? 520
          : (shrinkWrap
              ? (VestiarioCatalog.isArticoloModelloUnico(_articoloSelezionato!) ? 560 : 640)
              : null),
    );

    final tableArea = shrinkWrap
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: editor,
          )
        : Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: editor,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          color: _palette.panelHeader,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _palette.textPrimary,
                  ),
                ),
              ),
              if (!VestiarioCatalog.isArticoloDpiMagazzino(_articoloSelezionato!)) ...[
                _chipInfo('${righe.length} taglie'),
                const SizedBox(width: 6),
                _chipInfo('Da ord. $daOrdTot', highlight: daOrdTot > 0),
              ] else ...[
                _chipInfo(
                  '${righe.length} ${righe.length == 1 ? 'modello' : 'modelli'}',
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => _aggiungiVarianteDpi(_articoloSelezionato!),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Altra marca/modello'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: GestoproDataPalette.fsTiny),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _showStoricoArrivi(_articoloSelezionato!),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Storico consegnati'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: GestoproDataPalette.fsTiny),
                ),
              ),
            ],
          ),
        ),
        tableArea,
      ],
    );
  }

  Widget _chipInfo(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? _palette.estivoBg : _palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: GestoproDataPalette.fsTiny,
          fontWeight: FontWeight.w600,
          color: highlight ? _palette.estivo : _palette.textMuted,
        ),
      ),
    );
  }

  Widget _workspaceInventario() {
    final gruppi = _righePerArticolo;
    final entries = _articoliEntriesOrdinati(gruppi);
    if (entries.isEmpty) {
      return Center(
        child: Text('Nessun dato inventario.', style: TextStyle(color: _palette.textMuted)),
      );
    }

    final selected = _articoloSelezionato;
    final righe = selected != null ? (gruppi[selected] ?? const []) : const <_RigaUnificata>[];
    if (_narrowLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Articolo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(VestiarioCatalog.label(e.key))))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _articoloSelezionato = v);
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _palette.surface,
              border: Border.all(color: _palette.border),
              borderRadius: BorderRadius.circular(_palette.radius),
            ),
            child: _pannelloDettaglio(righe, shrinkWrap: true),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _palette.surface,
              border: Border(right: BorderSide(color: _palette.border)),
            ),
            child: _listaArticoli(entries, selected, (id) => setState(() => _articoloSelezionato = id)),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: _palette.surface),
            child: _pannelloDettaglio(righe),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Material(
      elevation: _palette.futuristic ? 0 : 8,
      color: _palette.surface,
      child: DecoratedBox(
        decoration: _palette.futuristic
            ? BoxDecoration(
                border: Border(
                  top: BorderSide(color: _palette.border),
                ),
              )
            : const BoxDecoration(),
        child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _arriviPendenti().isEmpty
                      ? 'Salva per confermare magazzino e ordinato.'
                      : 'Salva: ${_arriviPendenti().length} consegne da aggiungere al magazzino.',
                  style: TextStyle(
                    color: _palette.textMuted,
                    fontSize: GestoproDataPalette.fsLabel,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _saveAll,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: GestoproDataPalette.fsBody),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? '...' : 'Salva'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildMainContent() {
    final warning = _fabbisognoRows.isEmpty
        ? Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _palette.alertBg,
              borderRadius: BorderRadius.circular(_palette.radius),
              border: Border.all(color: _palette.alertBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined, size: 16, color: _palette.alertIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fabbisogno non calcolabile: verifica le taglie del personale attivo.',
                    style: TextStyle(
                      fontSize: GestoproDataPalette.fsBody,
                      color: _palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    final workspaceCard = ClipRRect(
      borderRadius: BorderRadius.circular(_palette.radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _palette.surface,
          border: Border.all(color: _palette.border),
          boxShadow: _palette.cardShadow,
        ),
        child: _workspaceInventario(),
      ),
    );

    if (_narrowLayout) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?warning,
            _riepilogoPanel(),
            const SizedBox(height: 10),
            _workspaceInventario(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?warning,
          _riepilogoPanel(),
          const SizedBox(height: 10),
          Expanded(child: workspaceCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _palette = GestoproDataPalette.of(context);
    final compactAppBar = useMobileUi(context) || _narrowLayout;
    final pageTitle = compactAppBar ? 'Inventario' : 'Inventario Vestiario';
    final toolbarActions = <Widget>[
      if (compactAppBar)
        IconButton(
          tooltip: 'Esporta Excel',
          onPressed: _loading ? null : _exportExcel,
          icon: const Icon(Icons.file_download_outlined),
        )
      else
        TextButton.icon(
          onPressed: _loading ? null : _exportExcel,
          icon: const Icon(Icons.file_download_outlined, size: 20),
          label: const Text('Excel'),
        ),
      IconButton(
        tooltip: 'Guida',
        onPressed: _loading
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Guida inventario'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('E: ${_moltiplicatoriLine(_multipliers.estivo)}', style: TextStyle(color: _palette.estivo, fontSize: 12)),
                          Text('I: ${_moltiplicatoriLine(_multipliers.invernale)}', style: TextStyle(color: _palette.invernale, fontSize: 12)),
                          const SizedBox(height: 10),
                          const Text(
                            'Modifica Mag., Ord. e Consegnati per la taglia selezionata. '
                            'T-shirt, scarpe, gilet e guanti (pelle/tessuto) hanno un solo fabbisogno (stesso articolo tutto l\'anno). '
                            'Da ord. = fabbisogno − magazzino.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
                    ],
                  ),
                ),
        icon: const Icon(Icons.help_outline),
      ),
      IconButton(
        tooltip: 'Ricarica',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      const SizedBox(width: 4),
    ];

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(child: _buildMainContent()),
              _bottomBar(),
            ],
          );

    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      toolbarActions: toolbarActions,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: Text(pageTitle),
        elevation: 0,
        actions: toolbarActions,
      )),
      wrapClassicBody: (ctx, child) => Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: CronosAppBackground()),
          ColoredBox(
            color: _palette.canvas.withValues(alpha: 0.92),
            child: child,
          ),
        ],
      ),
      body: content,
    );
  }
}

/// Editor isolato: un solo articolo montato → niente centinaia di TextField e glitch mouse_tracker.
class _ArticoloInventarioEditor extends StatefulWidget {
  const _ArticoloInventarioEditor({
    super.key,
    required this.palette,
    required this.articolo,
    required this.righe,
    required this.magControllers,
    required this.ordControllers,
    required this.arrivoControllerFor,
    required this.marcaControllerFor,
    required this.baseKey,
    required this.ordKey,
    required this.daOrdinare,
    this.onStockChanged,
    this.onAggiungiVarianteDpi,
    this.onRimuoviVarianteDpi,
    this.shrinkWrap = false,
    this.minTableWidth,
  });

  final GestoproDataPalette palette;
  final String articolo;
  final List<_RigaUnificata> righe;
  final Map<String, TextEditingController> magControllers;
  final Map<String, TextEditingController> ordControllers;
  final TextEditingController Function(VestiarioInventarioRiga) arrivoControllerFor;
  final TextEditingController Function(VestiarioInventarioRiga) marcaControllerFor;
  final String Function(VestiarioInventarioRiga) baseKey;
  final String Function(VestiarioInventarioRiga) ordKey;
  final int Function(_RigaUnificata) daOrdinare;
  final VoidCallback? onStockChanged;
  final void Function(String articolo)? onAggiungiVarianteDpi;
  final Future<void> Function(VestiarioInventarioRiga riga)? onRimuoviVarianteDpi;
  final bool shrinkWrap;
  final double? minTableWidth;

  @override
  State<_ArticoloInventarioEditor> createState() => _ArticoloInventarioEditorState();
}

class _ArticoloInventarioEditorState extends State<_ArticoloInventarioEditor> {
  GestoproDataPalette get _palette => widget.palette;

  TableBorder get _border =>
      TableBorder.all(color: _palette.border, width: 1);

  void _onFieldChanged() {
    setState(() {});
    widget.onStockChanged?.call();
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: _palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: _palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
    );
  }

  Widget _marcaInput(VestiarioInventarioRiga s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        controller: widget.marcaControllerFor(s),
        textAlign: TextAlign.left,
        style: const TextStyle(fontSize: GestoproDataPalette.fsBody),
        decoration: _fieldDecoration('Marca/modello'),
        onChanged: (_) => _onFieldChanged(),
      ),
    );
  }

  Widget _buildDpiUnitarioTable() {
    final righe = widget.righe
        .map((u) => u.stock)
        .whereType<VestiarioInventarioRiga>()
        .toList(growable: false)
      ..sort((a, b) => VestiarioCatalog.compareDpiVarianti(
            widget.marcaControllerFor(a).text,
            widget.marcaControllerFor(b).text,
          ));
    final puoRimuovere = righe.length > 1 && widget.onRimuoviVarianteDpi != null;
    return Table(
      columnWidths: {
        0: const FlexColumnWidth(1.45),
        1: const FlexColumnWidth(0.85),
        2: const FlexColumnWidth(0.85),
        3: const FlexColumnWidth(1),
        if (puoRimuovere) 4: const FixedColumnWidth(40),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: _border,
      children: [
        TableRow(
          children: [
            _th('Marca/modello', align: TextAlign.left),
            _th('Magazzino'),
            _th('Ordinato'),
            _th(
              'Consegnati',
              color: _palette.consegnati,
              bg: _palette.consegnatiBg,
            ),
            if (puoRimuovere) const SizedBox.shrink(),
          ],
        ),
        ...righe.asMap().entries.map((entry) {
          final s = entry.value;
          final stripe = entry.key.isOdd
              ? _palette.canvas.withValues(alpha: 0.3)
              : null;
          return TableRow(
            decoration: stripe != null ? BoxDecoration(color: stripe) : null,
            children: [
              _marcaInput(s),
              _input(widget.magControllers[widget.baseKey(s)]!, '0'),
              _input(widget.ordControllers[widget.ordKey(s)]!, '0'),
              _consegnatiCell(s),
              if (puoRimuovere)
                IconButton(
                  tooltip: 'Rimuovi riga',
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onRimuoviVarianteDpi!(s),
                ),
            ],
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (VestiarioCatalog.isArticoloDpiMagazzino(widget.articolo)) {
      final table = _buildDpiUnitarioTable();
      final minW = widget.minTableWidth ?? 520.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minW),
          child: table,
        ),
      );
    }

    final modelloUnico = VestiarioCatalog.isArticoloModelloUnico(widget.articolo);
    final table = Table(
      columnWidths: modelloUnico
          ? const {
              0: FixedColumnWidth(48),
              1: FlexColumnWidth(1.1),
              2: FlexColumnWidth(1.05),
              3: FlexColumnWidth(1.05),
              4: FlexColumnWidth(1.05),
              5: FlexColumnWidth(1.1),
            }
          : const {
              0: FixedColumnWidth(48),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1.05),
              4: FlexColumnWidth(1.05),
              5: FlexColumnWidth(1.05),
              6: FlexColumnWidth(1.1),
            },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: _border,
      children: [
        TableRow(
          children: [
            _th('Taglia', align: TextAlign.left),
            if (modelloUnico)
              _th('Fabbisogno', color: _palette.textMuted)
            else ...[
              _th('Estivo', color: _palette.estivo, bg: _palette.estivoBg),
              _th('Invernale', color: _palette.invernale, bg: _palette.invernaleBg),
            ],
            _th('Magazzino'),
            _th('Ordinato'),
            _th(
              'Consegnati',
              color: _palette.consegnati,
              bg: _palette.consegnatiBg,
            ),
            _th('Da ordinare', color: _palette.estivo, bg: _palette.estivoBg.withValues(alpha: 0.35)),
          ],
        ),
        ...List.generate(widget.righe.length, (i) {
          final u = widget.righe[i];
          final s = u.stock;
          final stripe = i.isOdd ? _palette.canvas.withValues(alpha: 0.3) : null;
          final daOrd = widget.daOrdinare(u);
          return TableRow(
            decoration: stripe != null ? BoxDecoration(color: stripe) : null,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(u.taglia, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: GestoproDataPalette.fsNum)),
              ),
              if (modelloUnico)
                _num(u.fabbisognoTotale)
              else ...[
                _num(u.fabbisognoEstivo, color: _palette.estivo),
                _num(u.fabbisognoInvernale, color: _palette.invernale),
              ],
              s == null ? _empty() : _input(widget.magControllers[widget.baseKey(s)]!, '0'),
              s == null ? _empty() : _input(widget.ordControllers[widget.ordKey(s)]!, '0'),
              s == null ? _empty() : _consegnatiCell(s),
              _num(daOrd, color: daOrd > 0 ? _palette.estivo : _palette.textMuted, bold: daOrd > 0),
            ],
          );
        }),
      ],
    );

    final minW = widget.minTableWidth;
    if (minW == null) return table;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minW),
        child: table,
      ),
    );
  }

  Widget _th(String label, {Color? color, Color? bg, TextAlign align = TextAlign.center}) {
    return Container(
      color: bg ?? _palette.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(fontSize: GestoproDataPalette.fsLabel, fontWeight: FontWeight.w700, color: color ?? _palette.tableHeader),
      ),
    );
  }

  Widget _num(int n, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        '$n',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: GestoproDataPalette.fsNum,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color ?? _palette.textPrimary,
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text('—', textAlign: TextAlign.center, style: TextStyle(color: _palette.textMuted)),
    );
  }

  Widget _consegnatiCell(VestiarioInventarioRiga s) {
    final tot = s.arrivatoTotale;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.arrivoControllerFor(s),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: GestoproDataPalette.fsNum,
              color: _palette.consegnati,
              fontWeight: FontWeight.w600,
            ),
            decoration: _fieldDecoration('0'),
            onChanged: (_) => _onFieldChanged(),
          ),
          if (tot > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'tot. $tot',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: GestoproDataPalette.fsTiny,
                  color: _palette.consegnati,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, String hint, {Color? hintColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: GestoproDataPalette.fsNum,
          color: hintColor,
          fontWeight: hintColor != null ? FontWeight.w600 : null,
        ),
        decoration: _fieldDecoration(hint),
        onChanged: (_) => _onFieldChanged(),
      ),
    );
  }
}
