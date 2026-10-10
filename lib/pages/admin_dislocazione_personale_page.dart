import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/dislocazione_impegno_excel_export.dart';
import '../services/dislocazione_personale_service.dart';
import '../services/dislocazione_pos_verifica_service.dart';
import '../utils/dislocazione_period_utils.dart';
import '../utils/excel_export_helper.dart';
import '../utils/futuristic_navigation.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import 'admin_dislocazione_mdo_per_commessa_page.dart';
import 'admin_dislocazione_riepilogo_page.dart';

/// Stati non-commessa (come Excel).
const List<String> kDislocazioneStati = <String>[
  'FERIE',
  'MALATTIA',
  'RIPOSO',
  'PERMESSO',
  'INFORTUNIO',
  'ASPETTATIVA',
  'SEDE',
  'CANTIERE',
  'CORSO',
  'MAGAZZINO',
  'LOGISTICA',
  'AMMINISTRAZIONE',
  'DIREZIONE',
  'QSA',
  'ACQUISTI',
  'ASSENTE',
  'ALTRO',
  'CESSATO',
];

/// Tipi attività tipici (Excel Maestranze).
const List<String> kDislocazioneAttivitaSuggerite = <String>[
  'LFM',
  'IS',
  'TE',
  'OP. CIVILI',
  'PM',
  'DT',
];

enum _OrdineDislocazioneRighe { nominativo, commessa }

enum _FillAsse { orizzontale, verticale }

class _CellSnapshot {
  const _CellSnapshot({
    required this.nominativo,
    required this.abilitazioni,
    this.attivita,
    required this.giorno,
    this.previous,
  });

  final String nominativo;
  final String? abilitazioni;
  final String? attivita;
  final DateTime giorno;
  final DislocazioneGiornoValore? previous;
}

class _UndoEntry {
  const _UndoEntry(this.cells);
  final List<_CellSnapshot> cells;
}

class AdminDislocazionePersonalePage extends StatefulWidget {
  final bool readOnly;

  const AdminDislocazionePersonalePage({super.key, this.readOnly = false});

  @override
  State<AdminDislocazionePersonalePage> createState() => _AdminDislocazionePersonalePageState();
}

class _AdminDislocazionePersonalePageState extends State<AdminDislocazionePersonalePage> {
  final _service = DislocazionePersonaleService();
  final _dateFmt = DateFormat('dd/MM');

  bool _loading = true;
  bool _caricamentoFinestra = false;
  bool _exportExcelInCorso = false;
  bool _importExcelInCorso = false;
  bool _vistaEstesa = false;
  final bool _mostraTabellaPeriodi = false;
  String _search = '';
  DateTime _pivotDate = dateOnly(DateTime.now());
  final _OrdineDislocazioneRighe _ordineRighe = _OrdineDislocazioneRighe.nominativo;

  Map<String, String> _commesse = <String, String>{};
  List<PersonaRiga> _persone = <PersonaRiga>[];
  List<Map<String, dynamic>> _righePeriodo = <Map<String, dynamic>>[];
  final Map<String, Map<DateTime, DislocazioneGiornoValore>> _cacheGiorni =
      <String, Map<DateTime, DislocazioneGiornoValore>>{};
  /// Track Formazione RFI per nominativo (solo elenco, senza date in griglia).
  Map<String, List<FormazioneRfiTrackInfo>> _rfiByNom =
      <String, List<FormazioneRfiTrackInfo>>{};
  /// Colonna FORMAZIONI RFI allargata per leggere tutto il testo.
  bool _formazioniRfiColEspansa = false;

  final Set<String> _savingNominativi = <String>{};
  String? _messaggioSalvataggio;

  /// Riempimento tipo Excel (maniglia in basso a destra della cella).
  String? _fillNominativo;
  int? _fillStartCol;
  int? _fillEndCol;
  int? _fillStartRow;
  int? _fillEndRow;
  _FillAsse? _fillAsse;
  DislocazioneGiornoValore? _fillValore;
  bool _fillDragging = false;
  int? _fillPointerId;
  double _fillDragAccumDx = 0;
  double _fillDragAccumDy = 0;
  PersonaRiga? _fillPersona;
  List<DateTime>? _fillGiorniRef;
  List<PersonaRiga>? _fillPersoneRef;

  /// Selezione rettangolo (click, trascina, Shift+click); Ctrl+C / Ctrl+V / Delete.
  int? _selAnchorRow;
  int? _selAnchorCol;
  int? _selEndRow;
  int? _selEndCol;
  bool _selDragActive = false;
  int? _selDragPointerId;
  List<List<DislocazioneGiornoValore?>>? _clipboardMatrix;
  ({int r0, int r1, int c0, int c1})? _clipboardSourceRect;
  final GlobalKey _gridAreaKey = GlobalKey();
  int _selGridRowCount = 0;
  int _selGridColCount = 0;
  double _selCellW = 76;
  double _selRowH = 36;
  static const double _selHeaderH = 44;

  final FocusNode _gridFocusNode = FocusNode();
  final FocusNode _filtroFocusNode = FocusNode();
  final TextEditingController _filtroCtrl = TextEditingController();
  final ScrollController _vScrollNomini = ScrollController();
  final ScrollController _vScrollGriglia = ScrollController();
  final ScrollController _hScrollGriglia = ScrollController();
  bool _syncingScrollVert = false;
  bool _fillRepaintScheduled = false;
  final Map<String, String> _labelCache = <String, String>{};
  static final DateFormat _weekdayFmt = DateFormat('E', 'it_IT');
  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  static const int _maxUndo = 40;

  bool get _canEdit => !widget.readOnly;
  bool get _puoUndo => _canEdit && _undoStack.isNotEmpty && _savingNominativi.isEmpty;

  /// Scorciatoie griglia (Canc, Ctrl+C, …) solo se il focus non è in un campo testo.
  bool get _scorciatoieGrigliaAttive {
    if (_filtroFocusNode.hasFocus) return false;
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    return true;
  }

  Set<String> get _nominativiNotiKeys {
    final keys = <String>{};
    for (final p in _personeOrdinate) {
      keys.add(p.nominativo.trim().toUpperCase());
    }
    for (final k in _cacheGiorni.keys) {
      keys.add(k.trim().toUpperCase());
    }
    return keys;
  }

  bool _isNominativoNoto(String testo) {
    final key = testo.replaceAll('\u00a0', ' ').trim().toUpperCase();
    return key.isNotEmpty && _nominativiNotiKeys.contains(key);
  }

  /// In vista estesa (molte colonne) le barre restano visibili su desktop/web.
  bool get _scrollbarSempreVisibili => _vistaEstesa;

  String _labelKey(String nominativo, DateTime giorno) =>
      '${nominativo.trim().toUpperCase()}|${dateOnly(giorno).millisecondsSinceEpoch}';

  String _labelCella(String nominativo, DateTime giorno) {
    final cached = _labelCache[_labelKey(nominativo, giorno)];
    if (cached != null && cached.isNotEmpty) return cached;
    final val = _valoreCella(nominativo, giorno);
    if (val == null || val.isEmpty) return '';
    return etichettaBreve(valore: val, commesse: _commesse, maxLen: 12);
  }

  void _rebuildLabelCache() {
    _labelCache.clear();
    for (final entry in _cacheGiorni.entries) {
      for (final g in entry.value.entries) {
        if (g.value.isEmpty) continue;
        _labelCache[_labelKey(entry.key, g.key)] = etichettaBreve(
          valore: g.value,
          commesse: _commesse,
          maxLen: 12,
        );
      }
    }
  }

  void _aggiornaLabelCacheIntervallo(
    String nominativo,
    DateTime dal,
    DateTime al,
    DislocazioneGiornoValore valore,
  ) {
    var d = dateOnly(dal.isBefore(al) ? dal : al);
    final end = dateOnly(dal.isBefore(al) ? al : dal);
    while (!d.isAfter(end)) {
      final key = _labelKey(nominativo, d);
      if (valore.isEmpty) {
        _labelCache.remove(key);
      } else {
        _labelCache[key] = etichettaBreve(valore: valore, commesse: _commesse, maxLen: 12);
      }
      d = d.add(const Duration(days: 1));
    }
  }

  DislocazioneGiornoValore? _cloneValore(DislocazioneGiornoValore? v) {
    if (v == null || v.isEmpty) return null;
    return DislocazioneGiornoValore(commessaId: v.commessaId, stato: v.stato);
  }

  List<_CellSnapshot> _catturaSnapshotsIntervallo({
    required String nominativo,
    required String? abilitazioni,
    String? attivita,
    required DateTime dal,
    required DateTime al,
  }) {
    final start = dateOnly(dal.isBefore(al) ? dal : al);
    final end = dateOnly(dal.isBefore(al) ? al : dal);
    final map = _cacheGiorni[nominativo];
    final out = <_CellSnapshot>[];
    var d = start;
    while (!d.isAfter(end)) {
      out.add(
        _CellSnapshot(
          nominativo: nominativo,
          abilitazioni: abilitazioni,
          attivita: attivita,
          giorno: d,
          previous: _cloneValore(map?[d]),
        ),
      );
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  void _registraUndo(List<_CellSnapshot> snapshots) {
    if (!_canEdit || snapshots.isEmpty) return;
    _undoStack.add(_UndoEntry(snapshots));
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  void _ripristinaLabelGiorno(String nominativo, DateTime giorno, DislocazioneGiornoValore? valore) {
    final key = _labelKey(nominativo, giorno);
    if (valore == null || valore.isEmpty) {
      _labelCache.remove(key);
    } else {
      _labelCache[key] = etichettaBreve(valore: valore, commesse: _commesse, maxLen: 12);
    }
  }

  Future<void> _eseguiUndo() async {
    if (!_puoUndo) return;
    final entry = _undoStack.removeLast();
    final byNom = <String, List<_CellSnapshot>>{};
    for (final s in entry.cells) {
      byNom.putIfAbsent(s.nominativo, () => <_CellSnapshot>[]).add(s);
    }

    setState(() => _messaggioSalvataggio = 'Annullamento…');

    try {
      for (final snaps in byNom.values) {
        if (snaps.isEmpty) continue;
        final nom = snaps.first.nominativo;
        final abilitazioni = snaps.first.abilitazioni;
        final attivita = snaps.first.attivita;
        final map = Map<DateTime, DislocazioneGiornoValore>.from(
          _cacheGiorni[nom] ?? <DateTime, DislocazioneGiornoValore>{},
        );
        final modifiche = <DateTime, DislocazioneGiornoValore?>{};
        for (final s in snaps) {
          final d = dateOnly(s.giorno);
          modifiche[d] = s.previous;
          if (s.previous == null || s.previous!.isEmpty) {
            map.remove(d);
          } else {
            map[d] = s.previous!;
          }
          _ripristinaLabelGiorno(nom, d, s.previous);
        }
        _cacheGiorni[nom] = map;
        _savingNominativi.add(nom);
        await _service.applicaModificheGiorni(
          nominativo: nom,
          abilitazioni: abilitazioni,
          attivita: attivita,
          modifiche: modifiche,
        );
        if (!mounted) return;
        setState(() => _savingNominativi.remove(nom));
      }
      if (!mounted) return;
      setState(() => _messaggioSalvataggio = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifica annullata'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingNominativi.clear();
        _messaggioSalvataggio = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Annullamento non riuscito: $e'), backgroundColor: Colors.red.shade800),
      );
      await _caricaFinestra();
      if (mounted) setState(() {});
    }
  }

  void _scheduleFillRepaint() {
    if (_fillRepaintScheduled) return;
    _fillRepaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillRepaintScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _onNominiScroll() {
    if (_syncingScrollVert || !_vScrollGriglia.hasClients) return;
    _syncingScrollVert = true;
    _vScrollGriglia.jumpTo(_vScrollNomini.offset);
    _syncingScrollVert = false;
  }

  void _onGrigliaScroll() {
    if (_syncingScrollVert || !_vScrollNomini.hasClients) return;
    _syncingScrollVert = true;
    _vScrollNomini.jumpTo(_vScrollGriglia.offset);
    _syncingScrollVert = false;
  }

  static const int _giorniPrima = 7;
  static const int _giorniDopo = 14;

  DateTime get _windowStart =>
      _vistaEstesa ? _rangeEstesoStart : _pivotDate.subtract(const Duration(days: _giorniPrima));

  DateTime get _windowEnd =>
      _vistaEstesa ? _rangeEstesoEnd : _pivotDate.add(const Duration(days: _giorniDopo));

  DateTime _rangeEstesoStart = dateOnly(DateTime.now());
  DateTime _rangeEstesoEnd = dateOnly(DateTime.now());

  List<DateTime> get _giorniColonne {
    final out = <DateTime>[];
    var d = _windowStart;
    while (!d.isAfter(_windowEnd)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  List<PersonaRiga> get _personeFiltrate {
    final k = _search.trim().toLowerCase();
    if (k.isEmpty) return _persone;
    return _persone
        .where(
          (p) =>
              p.nominativo.toLowerCase().contains(k) ||
              (p.abilitazioni ?? '').toLowerCase().contains(k) ||
              (p.attivita ?? '').toLowerCase().contains(k) ||
              _etichettaOrdineCommessa(p).toLowerCase().contains(k),
        )
        .toList(growable: false);
  }

  String _etichettaOrdineCommessa(PersonaRiga p) {
    final v = _valoreCella(p.nominativo, _pivotDate);
    if (v == null || v.isEmpty) return '';
    return etichettaBreve(valore: v, commesse: _commesse, maxLen: 48);
  }

  List<PersonaRiga> get _personeOrdinate {
    final list = List<PersonaRiga>.from(_personeFiltrate);
    if (_ordineRighe == _OrdineDislocazioneRighe.commessa) {
      list.sort((a, b) {
        final ka = _etichettaOrdineCommessa(a);
        final kb = _etichettaOrdineCommessa(b);
        if (ka.isEmpty && kb.isNotEmpty) return 1;
        if (ka.isNotEmpty && kb.isEmpty) return -1;
        final c = ka.toLowerCase().compareTo(kb.toLowerCase());
        if (c != 0) return c;
        return a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase());
      });
    } else {
      list.sort(
        (a, b) => a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase()),
      );
    }
    return list;
  }

  Future<void> _shiftSettimana(int deltaSettimane) async {
    if (_vistaEstesa || _caricamentoFinestra) return;
    setState(() {
      _pivotDate = dateOnly(_pivotDate.add(Duration(days: 7 * deltaSettimane)));
      _caricamentoFinestra = true;
    });
    await _caricaFinestra();
    if (mounted) setState(() => _caricamentoFinestra = false);
  }

  @override
  void initState() {
    super.initState();
    _vScrollNomini.addListener(_onNominiScroll);
    _vScrollGriglia.addListener(_onGrigliaScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    if (_selDragPointerId != null) {
      GestureBinding.instance.pointerRouter.removeRoute(
        _selDragPointerId!,
        _onSelezionePointerRoute,
      );
    }
    _vScrollNomini.removeListener(_onNominiScroll);
    _vScrollGriglia.removeListener(_onGrigliaScroll);
    _gridFocusNode.dispose();
    _filtroFocusNode.dispose();
    _filtroCtrl.dispose();
    _vScrollNomini.dispose();
    _vScrollGriglia.dispose();
    _hScrollGriglia.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      _commesse = await _service.loadCommesseAttive();
      _persone = await _service.loadPersone();
      await Future.wait([
        _caricaFinestra(),
        _caricaFormazioniRfi(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ricaricaAnagraficaEFinestra() async {
    _persone = await _service.loadPersone();
    await Future.wait([
      _caricaFinestra(),
      _caricaFormazioniRfi(),
    ]);
  }

  Future<void> _caricaFormazioniRfi() async {
    try {
      final map = await _service.loadFormazioniRfiTracksPerNominativi(
        _persone.map((p) => p.nominativo),
      );
      if (!mounted) return;
      setState(() => _rfiByNom = map);
      // Riscalda cache hover RFI.
      for (final e in map.entries) {
        _NominativoConHoverRfiState.warmCache(e.key, e.value);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _rfiByNom = <String, List<FormazioneRfiTrackInfo>>{});
    }
  }

  String _testoFormazioniRfi(String nominativo) {
    final list = _rfiByNom[nominativo] ?? const <FormazioneRfiTrackInfo>[];
    if (list.isEmpty) return '—';
    return list.map((e) => e.track).join(' · ');
  }

  /// Solo per «Mostra tutto il periodo»: 2 query min/max, non tutte le righe.
  Future<void> _ricalcolaRangeEsteso() async {
    final bounds = await _service.loadPeriodBounds();
    _rangeEstesoStart = dateOnly(
      bounds.min ?? _pivotDate.subtract(const Duration(days: 60)),
    );
    _rangeEstesoEnd = dateOnly(
      bounds.max ?? _pivotDate.add(const Duration(days: 60)),
    );
  }

  Future<void> _caricaFinestra() async {
    final righe = await _service.loadRigheNelPeriodo(
      dal: _windowStart,
      al: _windowEnd,
    );
    _righePeriodo = righe;
    _cacheGiorni.clear();
    _undoStack.clear();
    final byNom = <String, List<Map<String, dynamic>>>{};
    for (final r in righe) {
      final n = (r['nominativo'] ?? '').toString();
      byNom.putIfAbsent(n, () => <Map<String, dynamic>>[]).add(r);
    }
    for (final entry in byNom.entries) {
      _cacheGiorni[entry.key] = espandiPeriodi(entry.value);
    }
    _allineaCacheAiNominativiAnagrafica();
    await _service.overlayAssenzeSuCache(
      cache: _cacheGiorni,
      dal: _windowStart,
      al: _windowEnd,
      nominativiCanoni: _persone.map((p) => p.nominativo).toList(growable: false),
    );
    _rebuildLabelCache();
  }

  /// I dati in DB possono avere il nome in maiuscolo: allinea alla riga in pagina.
  void _allineaCacheAiNominativiAnagrafica() {
    if (_persone.isEmpty || _cacheGiorni.isEmpty) return;
    final canon = <String, String>{
      for (final p in _persone) p.nominativo.trim().toUpperCase(): p.nominativo,
    };
    final remapped = <String, Map<DateTime, DislocazioneGiornoValore>>{};
    for (final e in _cacheGiorni.entries) {
      final nome = canon[e.key.trim().toUpperCase()] ?? e.key;
      remapped
          .putIfAbsent(nome, () => <DateTime, DislocazioneGiornoValore>{})
          .addAll(e.value);
    }
    _cacheGiorni
      ..clear()
      ..addAll(remapped);
  }

  DislocazioneGiornoValore? _valoreCella(String nominativo, DateTime giorno) {
    final d = dateOnly(giorno);
    final direct = _cacheGiorni[nominativo]?[d];
    if (direct != null && !direct.isEmpty) return direct;
    final key = nominativo.trim().toUpperCase();
    for (final entry in _cacheGiorni.entries) {
      if (entry.key.trim().toUpperCase() != key) continue;
      final v = entry.value[d];
      if (v != null && !v.isEmpty) return v;
    }
    return null;
  }

  bool _matriceHaValori(List<List<DislocazioneGiornoValore?>>? matrix) {
    if (matrix == null || matrix.isEmpty) return false;
    for (final row in matrix) {
      for (final cell in row) {
        if (cell != null && !cell.isEmpty) return true;
      }
    }
    return false;
  }

  int _conteggiaValoriMatrice(List<List<DislocazioneGiornoValore?>> matrix) {
    var n = 0;
    for (final row in matrix) {
      for (final cell in row) {
        if (cell != null && !cell.isEmpty) n++;
      }
    }
    return n;
  }

  /// Se la sorgente è una sola cella, riempie tutto il rettangolo di destinazione (come Excel).
  List<List<DislocazioneGiornoValore?>> _espandiMatricePerIncolla(
    List<List<DislocazioneGiornoValore?>> src,
    ({int r0, int r1, int c0, int c1}) dest,
  ) {
    final srcRows = src.length;
    final srcCols = src.fold<int>(0, (m, r) => math.max(m, r.length));
    if (srcRows != 1 || srcCols != 1) return src;
    final v = src[0].isNotEmpty ? src[0][0] : null;
    if (v == null || v.isEmpty) return src;
    final destRows = dest.r1 - dest.r0 + 1;
    final destCols = dest.c1 - dest.c0 + 1;
    if (destRows <= 1 && destCols <= 1) return src;
    return List.generate(
      destRows,
      (_) => List.generate(destCols, (_) => _cloneValore(v)),
    );
  }

  /// Allinea righe incolla: evita di applicare la riga sbagliata (es. nominativo da Excel sopra).
  List<List<DislocazioneGiornoValore?>> _allineaMatriceIncolla(
    List<List<DislocazioneGiornoValore?>> matrix,
    ({int r0, int r1, int c0, int c1}) destRect,
  ) {
    if (matrix.length <= 1) return matrix;
    final destRows = destRect.r1 - destRect.r0 + 1;
    if (destRows == 1) {
      final src = _clipboardSourceRect;
      if (src != null) {
        final off = destRect.r0 - src.r0;
        if (off >= 0 && off < matrix.length) {
          return [matrix[off]];
        }
      }
      return [_rigaMatriceConPiuValori(matrix)];
    }
    if (destRows == matrix.length) return matrix;
    return matrix;
  }

  List<DislocazioneGiornoValore?> _rigaMatriceConPiuValori(
    List<List<DislocazioneGiornoValore?>> matrix,
  ) {
    var best = matrix.first;
    var bestN = _conteggiaValoriMatrice([best]);
    for (final row in matrix.skip(1)) {
      final n = _conteggiaValoriMatrice([row]);
      if (n > bestN) {
        best = row;
        bestN = n;
      }
    }
    return best;
  }

  Future<List<List<DislocazioneGiornoValore?>>?> _leggiMatriceIncolla() async {
    final fromInternal = _clipboardMatrix;
    List<List<DislocazioneGiornoValore?>>? fromSys;
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text?.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim() ?? '';
      if (text.isNotEmpty) {
        fromSys = _matriceDaTsv(text);
      }
    } catch (_) {
      // Web: lettura appunti può fallire senza permesso.
    }
    if (_matriceHaValori(fromInternal)) return fromInternal;
    if (_matriceHaValori(fromSys)) {
      _clipboardMatrix = fromSys;
      _clipboardSourceRect = null;
      return fromSys;
    }
    return null;
  }

  Future<void> _scegliPivotDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pivotDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      locale: const Locale('it', 'IT'),
    );
    if (picked == null) return;
    setState(() => _pivotDate = dateOnly(picked));
    if (!_vistaEstesa) {
      setState(() => _caricamentoFinestra = true);
      await _caricaFinestra();
      if (mounted) setState(() => _caricamentoFinestra = false);
    }
  }

  // ignore: unused_element
  Future<void> _toggleVistaEstesa() async {
    final attivaVistaEstesa = !_vistaEstesa;
    setState(() {
      _vistaEstesa = attivaVistaEstesa;
      _loading = true;
    });
    if (attivaVistaEstesa) {
      await _ricalcolaRangeEsteso();
    }
    await _caricaFinestra();
    if (mounted) setState(() => _loading = false);
  }

  void _impostaSelezioneCella({
    required int rowIndex,
    required int colIndex,
    required bool estendi,
  }) {
    setState(() {
      if (!estendi || _selAnchorRow == null || _selAnchorCol == null) {
        _selAnchorRow = rowIndex;
        _selAnchorCol = colIndex;
        _selEndRow = rowIndex;
        _selEndCol = colIndex;
      } else {
        _selEndRow = rowIndex;
        _selEndCol = colIndex;
      }
    });
  }

  /// Rettangolo selezione griglia (righe/colonne indice), da fill-drag o da click.
  ({int r0, int r1, int c0, int c1})? _rettangoloSelezioneGriglia() {
    if (_fillDragging &&
        _fillAsse != null &&
        _fillStartCol != null &&
        _fillStartRow != null) {
      if (_fillAsse == _FillAsse.orizzontale) {
        final c0 = math.min(_fillStartCol!, _fillEndCol ?? _fillStartCol!);
        final c1 = math.max(_fillStartCol!, _fillEndCol ?? _fillStartCol!);
        return (r0: _fillStartRow!, r1: _fillStartRow!, c0: c0, c1: c1);
      }
      final r0 = math.min(_fillStartRow!, _fillEndRow ?? _fillStartRow!);
      final r1 = math.max(_fillStartRow!, _fillEndRow ?? _fillStartRow!);
      return (r0: r0, r1: r1, c0: _fillStartCol!, c1: _fillStartCol!);
    }
    if (_selAnchorRow == null || _selAnchorCol == null) return null;
    final r0 = math.min(_selAnchorRow!, _selEndRow ?? _selAnchorRow!);
    final r1 = math.max(_selAnchorRow!, _selEndRow ?? _selAnchorRow!);
    final c0 = math.min(_selAnchorCol!, _selEndCol ?? _selAnchorCol!);
    final c1 = math.max(_selAnchorCol!, _selEndCol ?? _selAnchorCol!);
    return (r0: r0, r1: r1, c0: c0, c1: c1);
  }

  bool _cellaInSelezioneTastiera(int rowIndex, int colIndex) {
    if (_fillDragging) return false;
    final rect = _rettangoloSelezioneGriglia();
    if (rect == null) return false;
    return rowIndex >= rect.r0 &&
        rowIndex <= rect.r1 &&
        colIndex >= rect.c0 &&
        colIndex <= rect.c1;
  }

  bool _cellaIsAngoloSelezione(int rowIndex, int colIndex) {
    final rect = _rettangoloSelezioneGriglia();
    if (rect == null || _fillDragging) return false;
    final er = _selEndRow ?? _selAnchorRow ?? rect.r0;
    final ec = _selEndCol ?? _selAnchorCol ?? rect.c0;
    return rowIndex == er && colIndex == ec;
  }

  (int row, int col)? _indiciCellaDaPosizioneGlobale(Offset global) {
    final ctx = _gridAreaKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    if (local.dy < _selHeaderH) return null;
    if (_selGridRowCount <= 0 || _selGridColCount <= 0) return null;
    final row = ((local.dy - _selHeaderH) + _vScrollGriglia.offset) / _selRowH;
    final col = (local.dx + _hScrollGriglia.offset) / _selCellW;
    return (
      row.floor().clamp(0, _selGridRowCount - 1),
      col.floor().clamp(0, _selGridColCount - 1),
    );
  }

  void _onSelezionePointerRoute(PointerEvent event) {
    if (!_selDragActive || event.pointer != _selDragPointerId) return;
    if (event is PointerMoveEvent) {
      final idx = _indiciCellaDaPosizioneGlobale(event.position);
      if (idx == null) return;
      if (_selEndRow == idx.$1 && _selEndCol == idx.$2) return;
      setState(() {
        _selEndRow = idx.$1;
        _selEndCol = idx.$2;
      });
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      GestureBinding.instance.pointerRouter.removeRoute(
        event.pointer,
        _onSelezionePointerRoute,
      );
      _terminaSelezioneDrag(event);
    }
  }

  void _muoviSelezioneTastiera(int deltaRow, int deltaCol, {required bool estendi}) {
    final maxR = _personeOrdinate.length;
    final maxC = _giorniColonne.length;
    if (maxR == 0 || maxC == 0) return;
    setState(() {
      if (_selAnchorRow == null || _selAnchorCol == null) {
        _selAnchorRow = 0;
        _selAnchorCol = 0;
        _selEndRow = 0;
        _selEndCol = 0;
      }
      if (estendi) {
        final er = (_selEndRow ?? _selAnchorRow!) + deltaRow;
        final ec = (_selEndCol ?? _selAnchorCol!) + deltaCol;
        _selEndRow = er.clamp(0, maxR - 1);
        _selEndCol = ec.clamp(0, maxC - 1);
      } else {
        final ar = (_selAnchorRow ?? 0) + deltaRow;
        final ac = (_selAnchorCol ?? 0) + deltaCol;
        final nr = ar.clamp(0, maxR - 1);
        final nc = ac.clamp(0, maxC - 1);
        _selAnchorRow = nr;
        _selAnchorCol = nc;
        _selEndRow = nr;
        _selEndCol = nc;
      }
    });
  }

  String _testoDaValore(DislocazioneGiornoValore? valore) {
    if (valore == null || valore.isEmpty) return '';
    if (valore.commessaId != null && valore.commessaId!.isNotEmpty) {
      final nome = (_commesse[valore.commessaId!] ?? '').trim();
      if (nome.isEmpty) return valore.commessaId!;
      final sp = nome.indexOf(' ');
      return sp > 0 ? nome.substring(0, sp) : nome;
    }
    return valore.stato ?? '';
  }

  DislocazioneGiornoValore? _valoreDaTesto(String raw) {
    final t = raw.replaceAll('\u00a0', ' ').trim();
    if (t.isEmpty) return null;
    if (_isNominativoNoto(t)) return null;
    return parseDislocazioneTesto(
      raw,
      statiCatalogo: kDislocazioneStati,
      commesse: _commesse,
    );
  }

  List<List<DislocazioneGiornoValore?>>? _matriceSelezioneCorrente() {
    final rect = _rettangoloSelezioneGriglia();
    if (rect == null) return null;
    final persone = _personeOrdinate;
    final giorni = _giorniColonne;
    final rows = <List<DislocazioneGiornoValore?>>[];
    for (var r = rect.r0; r <= rect.r1; r++) {
      if (r < 0 || r >= persone.length) continue;
      final nom = persone[r].nominativo;
      final line = <DislocazioneGiornoValore?>[];
      for (var c = rect.c0; c <= rect.c1; c++) {
        if (c < 0 || c >= giorni.length) continue;
        final v = _valoreCella(nom, giorni[c]);
        line.add(v == null || v.isEmpty ? null : _cloneValore(v));
      }
      if (line.isNotEmpty) rows.add(line);
    }
    return rows.isEmpty ? null : rows;
  }

  String _matriceVersoTsv(List<List<DislocazioneGiornoValore?>> matrix) {
    return matrix
        .map(
          (row) => row.map((v) => _testoDaValore(v)).join('\t'),
        )
        .join('\n');
  }

  List<List<DislocazioneGiornoValore?>>? _matriceDaTsv(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return null;
    final lines = text.split('\n');
    final matrix = <List<DislocazioneGiornoValore?>>[];
    for (final line in lines) {
      final parts = line.contains('\t')
          ? line.split('\t')
          : (line.contains(';') ? line.split(';') : <String>[line]);
      var from = 0;
      if (parts.isNotEmpty && _isNominativoNoto(parts[0])) {
        from = 1;
      }
      matrix.add([
        for (var i = from; i < parts.length; i++) _valoreDaTesto(parts[i]),
      ]);
    }
    return matrix.isEmpty ? null : matrix;
  }

  Future<void> _eseguiCopia() async {
    final matrix = _matriceSelezioneCorrente();
    if (matrix == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Seleziona una o più celle: click, trascina sulla griglia, oppure Shift+click / frecce.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final valCount = _conteggiaValoriMatrice(matrix);
    if (valCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nessun valore nella selezione: seleziona prima le celle con contenuto (es. ASSENTE), poi Ctrl+C.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    _clipboardMatrix = matrix;
    _clipboardSourceRect = _rettangoloSelezioneGriglia();
    final tsv = _matriceVersoTsv(matrix);
    await Clipboard.setData(ClipboardData(text: tsv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copiati $valCount valori negli appunti'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _salvaModificheGriglia({
    required Map<String, Map<DateTime, DislocazioneGiornoValore?>> perNom,
    required Map<String, String?> abilitaPerNom,
    required Map<String, String?> attivitaPerNom,
    required List<_CellSnapshot> snapshots,
    required String messaggioProgresso,
    required String messaggioOk,
  }) async {
    if (snapshots.isEmpty) return;

    _registraUndo(snapshots);
    setState(() {
      for (final entry in perNom.entries) {
        final nom = entry.key;
        final map = Map<DateTime, DislocazioneGiornoValore>.from(
          _cacheGiorni[nom] ?? <DateTime, DislocazioneGiornoValore>{},
        );
        for (final mod in entry.value.entries) {
          final d = dateOnly(mod.key);
          final v = mod.value;
          if (v == null || v.isEmpty) {
            map.remove(d);
            _ripristinaLabelGiorno(nom, d, null);
          } else {
            map[d] = v;
            _ripristinaLabelGiorno(nom, d, v);
          }
        }
        _cacheGiorni[nom] = map;
        _savingNominativi.add(nom);
      }
      _messaggioSalvataggio = messaggioProgresso;
    });

    try {
      for (final entry in perNom.entries) {
        final nom = entry.key;
        await _service.applicaModificheGiorni(
          nominativo: nom,
          abilitazioni: abilitaPerNom[nom],
          attivita: attivitaPerNom[nom],
          modifiche: entry.value,
          giorniAttuali: _cacheGiorni[nom],
        );
        if (!mounted) return;
        setState(() => _savingNominativi.remove(nom));
      }
      if (!mounted) return;
      setState(() => _messaggioSalvataggio = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messaggioOk), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingNominativi.clear();
        _messaggioSalvataggio = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $e'), backgroundColor: Colors.red.shade800),
      );
      await _caricaFinestra();
      if (mounted) setState(() {});
    }
  }

  void _cancellaFiltroNominativo() {
    _filtroCtrl.clear();
    setState(() => _search = '');
    _filtroFocusNode.requestFocus();
  }

  Future<void> _eseguiCancellaSelezione() async {
    if (!_canEdit) return;
    final rect = _rettangoloSelezioneGriglia();
    if (rect == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleziona una o più celle da cancellare.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final persone = _personeOrdinate;
    final giorni = _giorniColonne;
    final snapshots = <_CellSnapshot>[];
    final perNom = <String, Map<DateTime, DislocazioneGiornoValore?>>{};
    final abilitaPerNom = <String, String?>{};
    final attivitaPerNom = <String, String?>{};

    for (var r = rect.r0; r <= rect.r1; r++) {
      if (r < 0 || r >= persone.length) continue;
      final persona = persone[r];
      abilitaPerNom[persona.nominativo] = persona.abilitazioni;
      attivitaPerNom[persona.nominativo] = persona.attivita;
      for (var c = rect.c0; c <= rect.c1; c++) {
        if (c < 0 || c >= giorni.length) continue;
        final giorno = giorni[c];
        final attuale = _valoreCella(persona.nominativo, giorno);
        if (attuale == null || attuale.isEmpty) continue;
        snapshots.add(
          _CellSnapshot(
            nominativo: persona.nominativo,
            abilitazioni: persona.abilitazioni,
            attivita: persona.attivita,
            giorno: giorno,
            previous: _cloneValore(attuale),
          ),
        );
        perNom
            .putIfAbsent(persona.nominativo, () => <DateTime, DislocazioneGiornoValore?>{})
            [dateOnly(giorno)] = null;
      }
    }

    if (snapshots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun contenuto da cancellare nella selezione.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    await _salvaModificheGriglia(
      perNom: perNom,
      abilitaPerNom: abilitaPerNom,
      attivitaPerNom: attivitaPerNom,
      snapshots: snapshots,
      messaggioProgresso: 'Cancellazione…',
      messaggioOk: 'Cancellate ${snapshots.length} celle',
    );
  }

  Future<void> _eseguiIncolla() async {
    if (!_canEdit) return;
    final rect = _rettangoloSelezioneGriglia();
    if (rect == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleziona la cella in alto a sinistra dove incollare.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    List<List<DislocazioneGiornoValore?>>? matrix = await _leggiMatriceIncolla();
    if (matrix == null || matrix.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nessun dato da incollare: seleziona le celle con ASSENTE (o altro valore) e premi Ctrl+C, poi incolla.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    matrix = _allineaMatriceIncolla(matrix, rect);
    matrix = _espandiMatricePerIncolla(matrix, rect);
    final dati = matrix;

    final persone = _personeOrdinate;
    final giorni = _giorniColonne;
    final anchorR = rect.r0;
    final anchorC = rect.c0;
    final snapshots = <_CellSnapshot>[];
    final perNom = <String, Map<DateTime, DislocazioneGiornoValore?>>{};
    final abilitaPerNom = <String, String?>{};
    final attivitaPerNom = <String, String?>{};
    var celleConValore = 0;

    for (var dr = 0; dr < dati.length; dr++) {
      final row = dati[dr];
      final pr = anchorR + dr;
      if (pr < 0 || pr >= persone.length) continue;
      final persona = persone[pr];
      abilitaPerNom[persona.nominativo] = persona.abilitazioni;
      attivitaPerNom[persona.nominativo] = persona.attivita;
      for (var dc = 0; dc < row.length; dc++) {
        final pc = anchorC + dc;
        if (pc < 0 || pc >= giorni.length) continue;
        final giorno = giorni[pc];
        final nuovo = row[dc];
        final precedente = _valoreCella(persona.nominativo, giorno);
        if (nuovo != null && !nuovo.isEmpty) celleConValore++;

        final uguale = (nuovo == null || nuovo.isEmpty)
            ? (precedente == null || precedente.isEmpty)
            : precedente != null &&
                !precedente.isEmpty &&
                precedente.cacheKey() == nuovo.cacheKey();
        if (uguale) continue;

        snapshots.add(
          _CellSnapshot(
            nominativo: persona.nominativo,
            abilitazioni: persona.abilitazioni,
            attivita: persona.attivita,
            giorno: giorno,
            previous: _cloneValore(precedente),
          ),
        );
        perNom
            .putIfAbsent(persona.nominativo, () => <DateTime, DislocazioneGiornoValore?>{})
            [dateOnly(giorno)] = nuovo == null || nuovo.isEmpty ? null : nuovo;
      }
    }

    if (snapshots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              celleConValore == 0
                  ? 'Nessun valore da incollare: copia di nuovo le celle con contenuto (Ctrl+C).'
                  : 'Nessuna modifica: le celle selezionate hanno già questi valori.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _selAnchorRow = anchorR;
      _selAnchorCol = anchorC;
      _selEndRow = anchorR + dati.length - 1;
      _selEndCol = anchorC + dati.first.length - 1;
    });

    await _salvaModificheGriglia(
      perNom: perNom,
      abilitaPerNom: abilitaPerNom,
      attivitaPerNom: attivitaPerNom,
      snapshots: snapshots,
      messaggioProgresso: 'Incollaggio…',
      messaggioOk: 'Incollate ${snapshots.length} celle',
    );
  }

  void _selezionaCellaGriglia({
    required int rowIndex,
    required int colIndex,
  }) {
    _gridFocusNode.requestFocus();
    final estendi = HardwareKeyboard.instance.isShiftPressed;
    _impostaSelezioneCella(rowIndex: rowIndex, colIndex: colIndex, estendi: estendi);
  }

  void _iniziaSelezioneDrag({
    required PointerDownEvent event,
    required int rowIndex,
    required int colIndex,
  }) {
    if (event.buttons != 1) return;
    if (_fillDragging) _annullaFillExcel();
    _gridFocusNode.requestFocus();
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift) {
      _impostaSelezioneCella(
        rowIndex: rowIndex,
        colIndex: colIndex,
        estendi: true,
      );
      return;
    }
    setState(() {
      _selDragActive = true;
      _selDragPointerId = event.pointer;
      _selAnchorRow = rowIndex;
      _selAnchorCol = colIndex;
      _selEndRow = rowIndex;
      _selEndCol = colIndex;
    });
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      _onSelezionePointerRoute,
    );
  }

  void _terminaSelezioneDrag(PointerEvent event) {
    if (_selDragPointerId != null && _selDragPointerId != event.pointer) return;
    GestureBinding.instance.pointerRouter.removeRoute(
      event.pointer,
      _onSelezionePointerRoute,
    );
    setState(() {
      _selDragActive = false;
      _selDragPointerId = null;
    });
  }

  Future<void> _modificaCella({
    required PersonaRiga persona,
    required DateTime giorno,
    required int rowIndex,
    required int colIndex,
  }) async {
    _selezionaCellaGriglia(rowIndex: rowIndex, colIndex: colIndex);
    if (!_canEdit) return;
    final attuale = _valoreCella(persona.nominativo, giorno);
    final scelta = await showDialog<DislocazioneGiornoValore?>(
      context: context,
      builder: (ctx) => _SelezioneAssegnazioneDialog(
        commesse: _commesse,
        valoreIniziale: attuale,
        nominativo: persona.nominativo,
        giorno: giorno,
      ),
    );
    if (scelta == null) return;
    if (scelta.cacheKey() == (attuale?.cacheKey() ?? '')) return;
    await _applicaValoriIntervallo(
      persona: persona,
      dal: giorno,
      al: giorno,
      valore: scelta,
    );
  }

  bool _cellaInSelezioneFill(
    String nominativo,
    int colIndex,
    int rowIndex,
  ) {
    if (!_fillDragging || _fillStartCol == null || _fillStartRow == null) return false;
    if (_fillAsse == null) {
      return _fillNominativo == nominativo &&
          _fillStartCol == colIndex &&
          _fillStartRow == rowIndex;
    }
    if (_fillAsse == _FillAsse.orizzontale) {
      if (_fillNominativo != nominativo || _fillStartRow != rowIndex) return false;
      final end = _fillEndCol ?? _fillStartCol!;
      final a = math.min(_fillStartCol!, end);
      final b = math.max(_fillStartCol!, end);
      return colIndex >= a && colIndex <= b;
    }
    if (_fillStartCol != colIndex || _fillStartRow == null) return false;
    final endRow = _fillEndRow ?? _fillStartRow!;
    final a = math.min(_fillStartRow!, endRow);
    final b = math.max(_fillStartRow!, endRow);
    return rowIndex >= a && rowIndex <= b;
  }

  void _resetFillState() {
    _fillDragging = false;
    _fillPointerId = null;
    _fillDragAccumDx = 0;
    _fillDragAccumDy = 0;
    _fillAsse = null;
    _fillNominativo = null;
    _fillStartCol = null;
    _fillEndCol = null;
    _fillStartRow = null;
    _fillEndRow = null;
    _fillValore = null;
    _fillPersona = null;
    _fillGiorniRef = null;
    _fillPersoneRef = null;
  }

  bool _cellaHaManigliaFill(String nominativo, int colIndex, int rowIndex) {
    if (!_canEdit || !_fillDragging) return false;
    if (_fillAsse == null) {
      return _fillNominativo == nominativo &&
          _fillStartCol == colIndex &&
          _fillStartRow == rowIndex;
    }
    if (_fillAsse == _FillAsse.orizzontale) {
      if (_fillNominativo != nominativo || _fillStartRow != rowIndex) return false;
      final end = _fillEndCol ?? _fillStartCol!;
      return colIndex == math.max(_fillStartCol!, end);
    }
    if (_fillStartCol != colIndex) return false;
    final endRow = _fillEndRow ?? _fillStartRow!;
    return rowIndex == math.max(_fillStartRow!, endRow);
  }

  void _iniziaFillExcel({
    required PersonaRiga persona,
    required int rowIndex,
    required int colIndex,
    required DislocazioneGiornoValore valore,
    required List<DateTime> giorni,
    required List<PersonaRiga> persone,
  }) {
    setState(() {
      _fillNominativo = persona.nominativo;
      _fillPersona = persona;
      _fillGiorniRef = List<DateTime>.from(giorni);
      _fillPersoneRef = List<PersonaRiga>.from(persone);
      _fillStartCol = colIndex;
      _fillEndCol = colIndex;
      _fillStartRow = rowIndex;
      _fillEndRow = rowIndex;
      _fillValore = valore;
      _fillDragging = true;
      _fillAsse = null;
      _fillDragAccumDx = 0;
      _fillDragAccumDy = 0;
      _selAnchorRow = rowIndex;
      _selAnchorCol = colIndex;
      _selEndRow = rowIndex;
      _selEndCol = colIndex;
    });
    _gridFocusNode.requestFocus();
  }

  void _aggiornaFillTrascinamento({
    required double deltaDx,
    required double deltaDy,
    required double cellW,
    required double rowH,
    required List<DateTime> giorni,
    required List<PersonaRiga> persone,
  }) {
    if (!_fillDragging || _fillStartCol == null || _fillStartRow == null) return;
    _fillDragAccumDx += deltaDx;
    _fillDragAccumDy += deltaDy;

    if (_fillAsse == null) {
      if (_fillDragAccumDx.abs() < 4 && _fillDragAccumDy.abs() < 4) return;
      setState(() {
        _fillAsse = _fillDragAccumDx.abs() >= _fillDragAccumDy.abs()
            ? _FillAsse.orizzontale
            : _FillAsse.verticale;
      });
      return;
    }

    if (_fillAsse == _FillAsse.orizzontale) {
      final offset = (_fillDragAccumDx / cellW).round();
      final idx = (_fillStartCol! + offset).clamp(0, giorni.length - 1);
      if (idx == _fillEndCol) return;
      _fillEndCol = idx;
      _scheduleFillRepaint();
    } else {
      final offset = (_fillDragAccumDy / rowH).round();
      final idx = (_fillStartRow! + offset).clamp(0, persone.length - 1);
      if (idx == _fillEndRow) return;
      _fillEndRow = idx;
      _scheduleFillRepaint();
    }
  }

  Future<void> _finaleFillDrag() async {
    if (!_fillDragging || _fillPersona == null || _fillStartCol == null || _fillStartRow == null) {
      if (mounted && _fillDragging) setState(_resetFillState);
      return;
    }
    final asse = _fillAsse;
    final giorni = _fillGiorniRef ?? _giorniColonne;
    final persone = _fillPersoneRef ?? _personeOrdinate;
    final persona = _fillPersona!;
    final col = _fillStartCol!;
    final startRow = _fillStartRow!;

    var valore = _fillValore ?? const DislocazioneGiornoValore();
    if (valore.isEmpty && col < giorni.length) {
      // Recupera solo se la cella sorgente ha un valore (copia persa durante il drag).
      final sorgente = _valoreCella(persona.nominativo, giorni[col]);
      if (sorgente != null && !sorgente.isEmpty) {
        valore = sorgente;
      }
    }

    if (asse == null) {
      if (mounted) setState(_resetFillState);
      return;
    }

    if (asse == _FillAsse.orizzontale) {
      final end = _fillEndCol ?? col;
      final a = math.min(col, end);
      final b = math.max(col, end);
      if (mounted) setState(_resetFillState);
      if (a == b) return;
      if (b >= giorni.length) return;
      await _applicaValoriIntervallo(
        persona: persona,
        dal: giorni[a],
        al: giorni[b],
        valore: valore,
      );
      return;
    }

    final endRow = _fillEndRow ?? startRow;
    final ra = math.min(startRow, endRow);
    final rb = math.max(startRow, endRow);
    final giorno = giorni[col];
    if (mounted) setState(_resetFillState);
    if (ra == rb) return;
    final target = <PersonaRiga>[
      for (var r = ra; r <= rb; r++)
        if (r >= 0 && r < persone.length) persone[r],
    ];
    if (target.isEmpty) return;
    await _applicaStessoGiornoMultipli(
      persone: target,
      giorno: giorno,
      valore: valore,
    );
  }

  void _annullaFillExcel() {
    if (!_fillDragging) return;
    if (mounted) setState(_resetFillState);
  }

  Future<void> _applicaValoriIntervallo({
    required PersonaRiga persona,
    required DateTime dal,
    required DateTime al,
    required DislocazioneGiornoValore valore,
  }) async {
    final start = dateOnly(dal.isBefore(al) ? dal : al);
    final end = dateOnly(dal.isBefore(al) ? al : dal);
    _registraUndo(
      _catturaSnapshotsIntervallo(
        nominativo: persona.nominativo,
        abilitazioni: persona.abilitazioni,
        attivita: persona.attivita,
        dal: start,
        al: end,
      ),
    );
    setState(() {
      final map = Map<DateTime, DislocazioneGiornoValore>.from(
        _cacheGiorni[persona.nominativo] ?? <DateTime, DislocazioneGiornoValore>{},
      );
      var d = start;
      while (!d.isAfter(end)) {
        if (valore.isEmpty) {
          map.remove(d);
        } else {
          map[d] = valore;
        }
        d = d.add(const Duration(days: 1));
      }
      _cacheGiorni[persona.nominativo] = map;
      _aggiornaLabelCacheIntervallo(persona.nominativo, start, end, valore);
      _savingNominativi.add(persona.nominativo);
      _messaggioSalvataggio = 'Salvataggio ${persona.nominativo}…';
    });

    try {
      await _service.salvaIntervalloGiorni(
        nominativo: persona.nominativo,
        abilitazioni: persona.abilitazioni,
        attivita: persona.attivita,
        dal: start,
        al: end,
        valore: valore,
        giorniAttuali: _cacheGiorni[persona.nominativo],
      );
      if (!mounted) return;
      setState(() {
        _savingNominativi.remove(persona.nominativo);
        _messaggioSalvataggio = _savingNominativi.isEmpty ? null : 'Salvataggio in corso…';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingNominativi.remove(persona.nominativo);
        _messaggioSalvataggio = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e'), backgroundColor: Colors.red.shade800),
      );
      await _caricaFinestra();
      setState(() {});
    }
  }

  Future<void> _applicaStessoGiornoMultipli({
    required List<PersonaRiga> persone,
    required DateTime giorno,
    required DislocazioneGiornoValore valore,
  }) async {
    if (persone.isEmpty) return;
    final d = dateOnly(giorno);
    final snapshots = <_CellSnapshot>[
      for (final persona in persone)
        _CellSnapshot(
          nominativo: persona.nominativo,
          abilitazioni: persona.abilitazioni,
          attivita: persona.attivita,
          giorno: d,
          previous: _cloneValore(_cacheGiorni[persona.nominativo]?[d]),
        ),
    ];
    _registraUndo(snapshots);
    setState(() {
      for (final persona in persone) {
        final map = Map<DateTime, DislocazioneGiornoValore>.from(
          _cacheGiorni[persona.nominativo] ?? <DateTime, DislocazioneGiornoValore>{},
        );
        if (valore.isEmpty) {
          map.remove(d);
        } else {
          map[d] = valore;
        }
        _cacheGiorni[persona.nominativo] = map;
        _aggiornaLabelCacheIntervallo(persona.nominativo, d, d, valore);
        _savingNominativi.add(persona.nominativo);
      }
      _messaggioSalvataggio = 'Salvataggio ${persone.length} nominativi…';
    });

    try {
      await Future.wait(
        persone.map(
          (persona) => _service.salvaGiorno(
            nominativo: persona.nominativo,
            abilitazioni: persona.abilitazioni,
            attivita: persona.attivita,
            giorno: d,
            valore: valore,
            giorniAttuali: _cacheGiorni[persona.nominativo],
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        for (final persona in persone) {
          _savingNominativi.remove(persona.nominativo);
        }
        _messaggioSalvataggio = _savingNominativi.isEmpty ? null : 'Salvataggio in corso…';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (final persona in persone) {
          _savingNominativi.remove(persona.nominativo);
        }
        _messaggioSalvataggio = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e'), backgroundColor: Colors.red.shade800),
      );
      await _caricaFinestra();
      if (mounted) setState(() {});
    }
  }

  Future<void> _verificaPos() async {
    if (_loading) return;
    final giorni = _giorniColonne;
    if (giorni.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Verifica POS: dipendenti, mezzi e MDO…')),
          ],
        ),
      ),
    );

    try {
      final risultato = await DislocazionePosVerificaService.verificaNelPeriodo(
        cacheGiorni: _cacheGiorni,
        giorniFinestra: giorni,
        commesse: _commesse,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await _mostraDialogVerificaPos(risultato);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verifica POS non riuscita: $e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<void> _mostraDialogVerificaPos(DislocazionePosVerificaRisultato risultato) async {
    final dal = risultato.periodoDal;
    final al = risultato.periodoAl;
    final periodo = (dal != null && al != null)
        ? '${_dateFmt.format(dal)} – ${_dateFmt.format(al)}'
        : '';
    final hasAnomalie = !risultato.tuttoOk;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final maxH = MediaQuery.sizeOf(ctx).height * 0.6;
        return AlertDialog(
          title: const Text('Verifica POS — dipendenti, mezzi e MDO'),
          content: SizedBox(
            width: 620,
            height: hasAnomalie ? maxH.clamp(300.0, 560.0) : null,
            child: risultato.commesseVerificate.isEmpty &&
                    risultato.mdoMancanti.isEmpty
                ? Text(
                    periodo.isEmpty
                        ? 'Nessuna assegnazione a commessa nel periodo visibile e nessun MDO con commessa.'
                        : 'Nessuna assegnazione a commessa nel periodo $periodo e nessun MDO con commessa.',
                  )
                : risultato.tuttoOk
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (periodo.isNotEmpty)
                            Text('Periodo: $periodo', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Text(
                            'Tutto allineato: dipendenti, mezzi stradali e MDO ferroviari '
                            'risultano presenti nelle rispettive liste POS (QSA).',
                            style: TextStyle(color: Colors.green.shade800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Commesse controllate: ${risultato.commesseVerificate.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (periodo.isNotEmpty)
                            Text('Periodo: $periodo', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Text(
                            '${risultato.anomalieTotali} anomalie '
                            '(${risultato.mancanti.length} dipendenti, '
                            '${risultato.mezziMancanti.length} mezzi stradali, '
                            '${risultato.mdoMancanti.length} MDO) '
                            'su ${risultato.commesseVerificate.length} commesse',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (risultato.mancanti.isNotEmpty) ...[
                                    Text(
                                      'Dipendenti',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.blueGrey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _buildListaAnomaliePos(risultato.mancanti),
                                    const SizedBox(height: 16),
                                  ],
                                  if (risultato.mezziMancanti.isNotEmpty) ...[
                                    Text(
                                      'Mezzi stradali',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.blueGrey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _buildListaAnomaliePosMezzi(risultato.mezziMancanti),
                                    const SizedBox(height: 16),
                                  ],
                                  if (risultato.mdoMancanti.isNotEmpty) ...[
                                    Text(
                                      'MDO ferroviari (lista POS QSA)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.blueGrey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _buildListaAnomaliePosMdo(risultato.mdoMancanti),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
          actions: [
            if (risultato.commesseVerificate.isNotEmpty ||
                risultato.mdoMancanti.isNotEmpty)
              TextButton.icon(
                onPressed: () => unawaited(_exportVerificaPosExcel(risultato)),
                icon: const Icon(Icons.download),
                label: const Text('Export Excel'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportProgrammaImpegnoExcel() async {
    if (_loading || _exportExcelInCorso) return;
    setState(() => _exportExcelInCorso = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final righe = await _service.loadRigheNelPeriodo(
        dal: DislocazioneImpegnoExcelExport.templatePeriodStart,
        al: DislocazioneImpegnoExcelExport.templatePeriodEnd,
      );
      final cache = DislocazioneImpegnoExcelExport.cacheDaRighe(righe);
      await _service.overlayAssenzeSuCache(
        cache: cache,
        dal: DislocazioneImpegnoExcelExport.templatePeriodStart,
        al: DislocazioneImpegnoExcelExport.templatePeriodEnd,
        nominativiCanoni: _persone.map((p) => p.nominativo).toList(growable: false),
      );
      final bytes = await DislocazioneImpegnoExcelExport.build(
        persone: _persone,
        cacheGiorni: cache,
        commesse: _commesse,
      );
      if (!mounted) return;
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Programma_impegno_personale',
        bytes: bytes,
      );
      if (!mounted) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      final count = _persone.length;
      final msg = saved
          ? (kIsWeb
              ? 'Download avviato: ${path.isNotEmpty ? path : 'Programma_impegno_personale.xlsx'} ($count nominativi)'
              : (path.isEmpty
                  ? 'Programma impegno personale esportato ($count nominativi).'
                  : 'Esportato: $path ($count nominativi)'))
          : 'Export annullato.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel non riuscito: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportExcelInCorso = false);
    }
  }

  Future<void> _importaProgrammaImpegnoExcel() async {
    if (!_canEdit || _loading || _exportExcelInCorso || _importExcelInCorso) {
      return;
    }
    const group = XTypeGroup(label: 'Excel', extensions: ['xlsx', 'xls']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa Programma impegno'),
        content: const Text(
          'Sostituisce le assegnazioni (commesse/stati) con il file Excel.\n\n'
          'Copia anche la colonna Attività (LFM, IS, TE, OP. CIVILI, PM, DT, …) '
          'solo se in app è ancora vuota: DT/PM già impostati non vengono cancellati.\n\n'
          'I nominativi restano quelli di Gestione Dipendenti: non vengono '
          'aggiunti né rinominati. Le righe Excel senza anagrafica vengono saltate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _importExcelInCorso = true;
      _loading = true;
      _messaggioSalvataggio = 'Import Excel…';
    });
    try {
      final bytes = await file.readAsBytes();
      final esito = await _service.importaProgrammaImpegnoSostituendo(
        bytes: bytes,
        esistenti: _persone,
        commesse: _commesse,
        statiCatalogo: kDislocazioneStati,
      );
      await _ricaricaAnagraficaEFinestra();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importato: ${esito.importati} nominativi, ${esito.periodi} periodi'
            '${esito.attivitaImportate > 0 ? ', ${esito.attivitaImportate} attività' : ''}'
            '${esito.saltatiExcel > 0 ? '. Saltate ${esito.saltatiExcel} righe Excel senza anagrafica' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import Excel non riuscito: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importExcelInCorso = false;
          _loading = false;
          _messaggioSalvataggio = null;
        });
      }
    }
  }

  Future<void> _exportVerificaPosExcel(DislocazionePosVerificaRisultato risultato) async {
    try {
      final bytes = DislocazionePosVerificaService.buildExcelBytes(
        risultato,
        dateFmt: _dateFmt,
      );
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'Verifica_POS',
        bytes: bytes,
      );
      if (!mounted) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? (path.isEmpty ? 'Export Excel completato.' : 'Export Excel: $path')
                : 'Export Excel annullato.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel non riuscito: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Widget _buildListaAnomaliePos(List<DislocazionePosVerificaMancante> mancanti) {
    final byCommessa = <String, List<DislocazionePosVerificaMancante>>{};
    for (final m in mancanti) {
      byCommessa.putIfAbsent(m.commessaNome, () => []).add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byCommessa.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              DislocazionePosVerificaService.codiceCommessa(entry.key).isEmpty
                  ? entry.key
                  : DislocazionePosVerificaService.codiceCommessa(entry.key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          ...entry.value.map((m) {
            final motivo = DislocazionePosVerificaService.motivoLabel(m.motivo);
            final giorniLabel = m.giorni.isEmpty
                ? ''
                : m.giorni.length <= 5
                    ? m.giorni.map((d) => _dateFmt.format(d)).join(', ')
                    : '${_dateFmt.format(m.giorni.first)} … ${_dateFmt.format(m.giorni.last)} (${m.giorni.length} gg)';
            final nome = (m.personaleFullName ?? m.nominativo).trim();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 22),
              title: Text(nome, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (m.personaleFullName != null && m.personaleFullName != m.nominativo)
                    'Dislocazione: ${m.nominativo}',
                  motivo,
                  if (giorniLabel.isNotEmpty) 'Giorni: $giorniLabel',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildListaAnomaliePosMezzi(
    List<DislocazionePosVerificaMezzoMancante> mancanti,
  ) {
    final byCommessa = <String, List<DislocazionePosVerificaMezzoMancante>>{};
    for (final m in mancanti) {
      byCommessa.putIfAbsent(m.commessaNome, () => []).add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byCommessa.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              DislocazionePosVerificaService.codiceCommessa(entry.key).isEmpty
                  ? entry.key
                  : DislocazionePosVerificaService.codiceCommessa(entry.key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          ...entry.value.map((m) {
            final motivo = DislocazionePosVerificaService.motivoMezzoLabel(m.motivo);
            final giorniLabel = m.giorni.isEmpty
                ? ''
                : m.giorni.length <= 5
                    ? m.giorni.map((d) => _dateFmt.format(d)).join(', ')
                    : '${_dateFmt.format(m.giorni.first)} … ${_dateFmt.format(m.giorni.last)} (${m.giorni.length} gg)';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.local_shipping_outlined,
                color: Colors.amber.shade900,
                size: 22,
              ),
              title: Text(m.label, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  'Assegnatario: ${m.assegnatario}',
                  if (m.tipologia.isNotEmpty) m.tipologia,
                  motivo,
                  if (giorniLabel.isNotEmpty) 'Giorni: $giorniLabel',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildListaAnomaliePosMdo(
    List<DislocazionePosVerificaMdoMancante> mancanti,
  ) {
    final byCommessa = <String, List<DislocazionePosVerificaMdoMancante>>{};
    for (final m in mancanti) {
      byCommessa.putIfAbsent(m.commessaNome, () => []).add(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byCommessa.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              DislocazionePosVerificaService.codiceCommessa(entry.key).isEmpty
                  ? entry.key
                  : DislocazionePosVerificaService.codiceCommessa(entry.key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          ...entry.value.map((m) {
            final motivo = DislocazionePosVerificaService.motivoMdoLabel(m.motivo);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.train_outlined,
                color: Colors.blue.shade800,
                size: 22,
              ),
              title: Text(m.label, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (m.cantiere.isNotEmpty) 'Cantiere: ${m.cantiere}',
                  motivo,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
        ],
      ],
    );
  }

  String _chiaveNominativo(String nome) => nome.trim().toUpperCase();

  // ignore: unused_element
  Future<void> _unificaNominativiDuplicati() async {
    setState(() => _loading = true);
    try {
      final personale = await _service.loadPersonaleNomiPerChiave();
      final daDislocazione = await _service.loadNominativiDislocazioneDistinti();
      final tutti = <String>{
        ...daDislocazione,
        ..._persone.map((p) => p.nominativo),
        ...personale.values,
      }.toList();
      final coppie = _service.trovaCoppieUnioneNominativi(
        tuttiNominativi: tutti,
        personalePerChiave: personale,
      );
      if (!mounted) return;
      if (coppie.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun nominativo incompleto da unire.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final righeAnteprima = <({NominativoMergeCoppia c, int giorni})>[];
      for (final c in coppie) {
        final g = await _service.contaGiorniDaUnire(
          incompleto: c.incompleto,
          completo: c.completo,
        );
        righeAnteprima.add((c: c, giorni: g));
      }
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('Unifica nominativi duplicati'),
            content: SizedBox(
              width: 560,
              height: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'I dati del nome incompleto vengono spostati sul nome completo '
                    '(priorità anagrafica dipendenti); il nome incompleto viene eliminato.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: righeAnteprima.length,
                      separatorBuilder: (_, _) => const Divider(height: 12),
                      itemBuilder: (context, i) {
                        final r = righeAnteprima[i];
                        final target =
                            personale[_chiaveNominativo(r.c.completo)] ?? r.c.completo;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.c.incompleto,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const Icon(Icons.arrow_downward, size: 16),
                            Text(
                              target,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (r.giorni > 0)
                              Text(
                                '${r.giorni} giorni da copiare',
                                style: theme.textTheme.bodySmall,
                              )
                            else
                              Text(
                                'Nessun giorno da copiare (solo rimozione duplicato)',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Unisci ${coppie.length} coppie'),
              ),
            ],
          );
        },
      );
      if (ok != true || !mounted) return;

      setState(() => _loading = true);
      final res = await _service.unificaTuttiNominativiDuplicati();
      if (!mounted) return;
      await _ricaricaAnagraficaEFinestra();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unite ${res.unite} coppie · ${res.giorniCopiati} giorni copiati',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unione non riuscita: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apriRiepilogo() {
    final giorni = _giorniColonne;
    final dal = giorni.isEmpty ? dateOnly(_pivotDate) : giorni.first;
    final al = giorni.isEmpty ? dateOnly(_pivotDate) : giorni.last;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminDislocazioneRiepilogoPage(
          persone: List<PersonaRiga>.from(_persone),
          cacheGiorni: {
            for (final e in _cacheGiorni.entries)
              e.key: Map<DateTime, DislocazioneGiornoValore>.from(e.value),
          },
          commesse: Map<String, String>.from(_commesse),
          dal: dal,
          al: al,
        ),
      ),
    );
  }

  void _apriMdoPerCommessa() {
    FuturisticNavigation.pushPage(
      context,
      page: AdminDislocazioneMdoPerCommessaPage(readOnly: !_canEdit),
      title: 'MDO per commessa',
    );
  }

  Future<void> _modificaNominativo(PersonaRiga persona) async {
    final nomeCtrl = TextEditingController(text: persona.nominativo);
    final abCtrl = TextEditingController(text: persona.abilitazioni ?? '');
    final atCtrl = TextEditingController(text: persona.attivita ?? '');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Modifica nominativo'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nominativo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: atCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Attività (es. LFM, IS, TE, PM, DT)',
                    border: OutlineInputBorder(),
                    helperText: 'Suggeriti: LFM, IS, TE, OP. CIVILI, PM, DT',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: abCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Abilitazioni (opzionale)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_canEdit)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx, false);
                  await _eliminaNominativoDaLista(persona);
                },
                child: Text(
                  'Rimuovi',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final nuovoNome = nomeCtrl.text.trim();
      if (nuovoNome.isEmpty) return;

      final stessoNome =
          _chiaveNominativo(nuovoNome) == _chiaveNominativo(persona.nominativo) &&
              nuovoNome == persona.nominativo;
      final nuovaAbilita = abCtrl.text.trim();
      final nuovaAttivita = atCtrl.text.trim();
      final abCambiata = nuovaAbilita != (persona.abilitazioni ?? '').trim();
      final atCambiata = nuovaAttivita != (persona.attivita ?? '').trim();

      if (stessoNome && !abCambiata && !atCambiata) return;

      if (!stessoNome &&
          _persone.any(
            (p) =>
                p.nominativo != persona.nominativo &&
                _chiaveNominativo(p.nominativo) == _chiaveNominativo(nuovoNome),
          )) {
        final conferma = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Nominativo già presente'),
            content: Text(
              'Esiste già «$nuovoNome» in elenco.\n\n'
              'I giorni di dislocazione verranno uniti (priorità ai dati già presenti sul nome di destinazione).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Unisci e rinomina'),
              ),
            ],
          ),
        );
        if (conferma != true || !mounted) return;
      }

      setState(() => _loading = true);
      try {
        var needBootstrap = false;

        if (!stessoNome) {
          await _service.rinominaNominativo(
            vecchio: persona.nominativo,
            nuovo: nuovoNome,
          );
          needBootstrap = true;
        }

        final target = stessoNome ? persona.nominativo : nuovoNome;
        if (abCambiata || atCambiata) {
          final salvato = await _service.aggiornaMetaPersona(
            nominativo: target,
            abilitazioni: nuovaAbilita.isEmpty ? null : nuovaAbilita,
            attivita: nuovaAttivita.isEmpty ? null : nuovaAttivita,
            updateAbilitazioni: abCambiata,
            updateAttivita: atCambiata,
          );
          if (salvato) {
            needBootstrap = true;
          } else if (mounted) {
            setState(() {
              final i = _persone.indexWhere(
                (p) =>
                    _chiaveNominativo(p.nominativo) ==
                    _chiaveNominativo(target),
              );
              if (i >= 0) {
                _persone[i] = PersonaRiga(
                  nominativo: _persone[i].nominativo,
                  abilitazioni: abCambiata
                      ? (nuovaAbilita.isEmpty ? null : nuovaAbilita)
                      : _persone[i].abilitazioni,
                  attivita: atCambiata
                      ? (nuovaAttivita.isEmpty ? null : nuovaAttivita)
                      : _persone[i].attivita,
                );
              }
            });
          }
        }

        if (needBootstrap && mounted) {
          setState(() => _loading = true);
          await _ricaricaAnagraficaEFinestra();
          if (mounted) setState(() => _loading = false);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              stessoNome
                  ? 'Dati aggiornati per $nuovoNome'
                  : 'Nominativo aggiornato: $nuovoNome',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Modifica non riuscita: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } finally {
      nomeCtrl.dispose();
      abCtrl.dispose();
      atCtrl.dispose();
    }
  }

  Future<void> _modificaAttivitaVeloce(PersonaRiga persona) async {
    if (!_canEdit) return;
    final atCtrl = TextEditingController(text: persona.attivita ?? '');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Attività — ${persona.nominativo}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: atCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo attività',
                    border: OutlineInputBorder(),
                    helperText: 'Es. LFM, IS, TE, OP. CIVILI, PM, DT',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in kDislocazioneAttivitaSuggerite)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => atCtrl.text = s,
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final nuova = atCtrl.text.trim();
      if (nuova == (persona.attivita ?? '').trim()) return;
      setState(() => _loading = true);
      try {
        final salvato = await _service.aggiornaAttivita(
          nominativo: persona.nominativo,
          attivita: nuova.isEmpty ? null : nuova,
        );
        if (!mounted) return;
        if (salvato) {
          await _ricaricaAnagraficaEFinestra();
        } else {
          setState(() {
            final i = _persone.indexWhere(
              (p) =>
                  _chiaveNominativo(p.nominativo) ==
                  _chiaveNominativo(persona.nominativo),
            );
            if (i >= 0) {
              _persone[i] = PersonaRiga(
                nominativo: _persone[i].nominativo,
                abilitazioni: _persone[i].abilitazioni,
                attivita: nuova.isEmpty ? null : nuova,
              );
            }
          });
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } finally {
      atCtrl.dispose();
    }
  }

  Future<void> _eliminaNominativoDaLista(PersonaRiga persona) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi nominativo'),
        content: Text(
          'Rimuovere «${persona.nominativo}» dalla lista Dislocazione?\n\n'
          'Verranno eliminate tutte le assegnazioni salvate per questo nome. '
          'Il dipendente non comparirà più in elenco (anche se è in anagrafica) '
          'finché non lo aggiungi di nuovo con «Nuovo nominativo».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = _chiaveNominativo(persona.nominativo);
    setState(() => _loading = true);
    try {
      await _service.rimuoviNominativoDallaLista(persona.nominativo);
      if (!mounted) return;
      setState(() {
        _persone.removeWhere((p) => _chiaveNominativo(p.nominativo) == key);
        _cacheGiorni.remove(persona.nominativo);
        _savingNominativi.remove(persona.nominativo);
        _selAnchorRow = null;
        _selAnchorCol = null;
        _selEndRow = null;
        _selEndCol = null;
        _fillDragging = false;
        _fillNominativo = null;
      });
      await _caricaFinestra();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rimosso ${persona.nominativo}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rimozione non riuscita: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _aggiungiPersona() async {
    final nomeCtrl = TextEditingController();
    final abCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nuovo nominativo'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nominativo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: abCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Abilitazioni (opzionale)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aggiungi')),
          ],
        ),
      );
      if (ok != true) return;
      final nome = nomeCtrl.text.trim();
      final abilita = abCtrl.text.trim();
      if (nome.isEmpty) return;
      if (_persone.any((p) => p.nominativo.toLowerCase() == nome.toLowerCase())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nominativo già presente.')),
          );
        }
        return;
      }
      await _service.rimuoviEsclusioneNominativo(nome);
      setState(() {
        _persone = [
          ..._persone,
          PersonaRiga(
            nominativo: nome,
            abilitazioni: abilita.isEmpty ? null : abilita,
          ),
        ]..sort((a, b) => a.nominativo.toLowerCase().compareTo(b.nominativo.toLowerCase()));
        _cacheGiorni[nome] = <DateTime, DislocazioneGiornoValore>{};
      });
    } finally {
      nomeCtrl.dispose();
      abCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final giorni = _giorniColonne;
    final persone = _personeOrdinate;
    final oggi = dateOnly(DateTime.now());

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _AnnullaFillIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): const _CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): const _CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _ClearCellsIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _SelUpIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _SelDownIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const _SelLeftIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): const _SelRightIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): const _SelUpIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): const _SelDownIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): const _SelLeftIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): const _SelRightIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _AnnullaFillIntent: CallbackAction<_AnnullaFillIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              _annullaFillExcel();
              return null;
            },
          ),
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              unawaited(_eseguiUndo());
              return null;
            },
          ),
          _CopyIntent: CallbackAction<_CopyIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              unawaited(_eseguiCopia());
              return null;
            },
          ),
          _PasteIntent: CallbackAction<_PasteIntent>(
            onInvoke: (_) {
              if (!_canEdit || !_scorciatoieGrigliaAttive) return null;
              unawaited(_eseguiIncolla());
              return null;
            },
          ),
          _ClearCellsIntent: CallbackAction<_ClearCellsIntent>(
            onInvoke: (_) {
              if (!_canEdit || !_scorciatoieGrigliaAttive) return null;
              unawaited(_eseguiCancellaSelezione());
              return null;
            },
          ),
          _SelUpIntent: CallbackAction<_SelUpIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              _muoviSelezioneTastiera(
                -1,
                0,
                estendi: HardwareKeyboard.instance.isShiftPressed,
              );
              return null;
            },
          ),
          _SelDownIntent: CallbackAction<_SelDownIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              _muoviSelezioneTastiera(
                1,
                0,
                estendi: HardwareKeyboard.instance.isShiftPressed,
              );
              return null;
            },
          ),
          _SelLeftIntent: CallbackAction<_SelLeftIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              _muoviSelezioneTastiera(
                0,
                -1,
                estendi: HardwareKeyboard.instance.isShiftPressed,
              );
              return null;
            },
          ),
          _SelRightIntent: CallbackAction<_SelRightIntent>(
            onInvoke: (_) {
              if (!_scorciatoieGrigliaAttive) return null;
              _muoviSelezioneTastiera(
                0,
                1,
                estendi: HardwareKeyboard.instance.isShiftPressed,
              );
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _gridFocusNode,
          autofocus: true,
          child: Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Dislocazione Personale'),
        actions: [
          if (_messaggioSalvataggio != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  _messaggioSalvataggio!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Annulla ultima modifica (Ctrl+Z)',
              onPressed: _puoUndo ? () => unawaited(_eseguiUndo()) : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Nuovo nominativo',
              onPressed: _aggiungiPersona,
              icon: const Icon(Icons.person_add_alt),
            ),
          ],
          IconButton(
            tooltip: 'Export Excel (Programma impegno personale)',
            onPressed: (_loading || _exportExcelInCorso)
                ? null
                : () => unawaited(_exportProgrammaImpegnoExcel()),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _exportExcelInCorso ? null : _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      )),
      body: PageWithTopLogo(
        child: Stack(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildToolbar(),
                      if (_mostraTabellaPeriodi)
                        Expanded(flex: 2, child: _buildTabellaPeriodi())
                      else
                        Expanded(child: _buildGriglia(giorni, persone, oggi)),
                    ],
                  ),
            if (_exportExcelInCorso)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Generazione Excel in corso…',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Il template viene compilato in background.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_caricamentoFinestra)
            const LinearProgressIndicator(minHeight: 2),
          Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.delete):
                    DoNothingAndStopPropagationTextIntent(),
              },
              child: TextField(
                controller: _filtroCtrl,
                focusNode: _filtroFocusNode,
                decoration: InputDecoration(
                  labelText: 'Filtra nominativo',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella filtro',
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: _cancellaFiltroNominativo,
                        ),
                ),
                onChanged: (v) => setState(() => _search = v),
                onSubmitted: (_) => _gridFocusNode.requestFocus(),
              ),
            ),
          ),
          if (!_vistaEstesa) ...[
            IconButton(
              tooltip: 'Settimana precedente',
              onPressed: (_loading || _caricamentoFinestra) ? null : () => _shiftSettimana(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Settimana successiva',
              onPressed: (_loading || _caricamentoFinestra) ? null : () => _shiftSettimana(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
          OutlinedButton.icon(
            onPressed: _scegliPivotDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('Data: ${_dateFmt.format(_pivotDate)}'),
          ),
          if (_fillDragging)
            FilledButton.icon(
              onPressed: _annullaFillExcel,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Annulla copia'),
            ),
          if (_canEdit)
            FilledButton.tonalIcon(
              onPressed: (_loading || _exportExcelInCorso || _importExcelInCorso)
                  ? null
                  : () => unawaited(_importaProgrammaImpegnoExcel()),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Importa Excel'),
            ),
          FilledButton.tonalIcon(
            onPressed: (_loading || _exportExcelInCorso)
                ? null
                : () => unawaited(_exportProgrammaImpegnoExcel()),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export Excel'),
          ),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : () => unawaited(_verificaPos()),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Verifica POS'),
          ),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _apriRiepilogo,
            icon: const Icon(Icons.summarize_outlined, size: 18),
            label: const Text('Riepilogo'),
          ),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _apriMdoPerCommessa,
            icon: const Icon(Icons.train_outlined, size: 18),
            label: const Text('MDO per commessa'),
          ),
        ],
      ),
        ],
      ),
    );
  }

  Widget _buildGriglia(List<DateTime> giorni, List<PersonaRiga> persone, DateTime oggi) {
    if (persone.isEmpty) {
      return const Center(child: Text('Nessun nominativo. Aggiungine uno o importa i dati.'));
    }

    final nomeW = 200.0;
    final rfiW = _formazioniRfiColEspansa ? 420.0 : 150.0;
    const attivitaW = 88.0;
    const cellW = 76.0;
    const headerH = 44.0;
    const rowH = 36.0;
    final frozenW = nomeW + rfiW + attivitaW;
    final gridW = giorni.length * cellW;
    _selGridRowCount = persone.length;
    _selGridColCount = giorni.length;
    _selCellW = cellW;
    _selRowH = rowH;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final listH = math.max(0.0, box.maxHeight - headerH);
              final visibili = math.max(1, (listH / rowH).floor());
              // Almeno una riga vuota dopo l'ultimo nominativo;
              // se la lista è corta, riempie il resto della griglia.
              final vuote =
                  persone.length < visibili ? visibili - persone.length : 1;
              final rowCount = persone.length + vuote;
              return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerUp: (e) {
              if (_selDragActive && _selDragPointerId == e.pointer) {
                _terminaSelezioneDrag(e);
                return;
              }
              if (!_fillDragging || _fillPointerId != e.pointer) return;
              unawaited(_finaleFillDrag());
            },
            onPointerCancel: (e) {
              if (_selDragPointerId == e.pointer) _terminaSelezioneDrag(e);
              if (_fillPointerId == e.pointer) _annullaFillExcel();
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: frozenW,
                  child: Column(
                    children: [
                      SizedBox(
                        height: headerH,
                        child: Row(
                          children: [
                            SizedBox(
                              width: nomeW,
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: Colors.grey.shade300),
                                    bottom: BorderSide(color: Colors.grey.shade400),
                                  ),
                                ),
                                child: Text('NOMINATIVO', style: _headerStyle()),
                              ),
                            ),
                            SizedBox(
                              width: rfiW,
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.only(left: 4, right: 2),
                                decoration: BoxDecoration(
                                  color: _formazioniRfiColEspansa
                                      ? Colors.teal.shade50
                                      : null,
                                  border: Border(
                                    right: BorderSide(color: Colors.grey.shade300),
                                    bottom: BorderSide(color: Colors.grey.shade400),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'FORMAZIONI RFI',
                                        style: _headerStyle(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                      ),
                                    ),
                                    Tooltip(
                                      message: _formazioniRfiColEspansa
                                          ? 'Restringi colonna'
                                          : 'Espandi colonna',
                                      child: InkWell(
                                        onTap: () => setState(
                                          () => _formazioniRfiColEspansa =
                                              !_formazioniRfiColEspansa,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: Icon(
                                            _formazioniRfiColEspansa
                                                ? Icons.chevron_left
                                                : Icons.chevron_right,
                                            size: 18,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: attivitaW,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.grey.shade400,
                                      width: 1.5,
                                    ),
                                    bottom: BorderSide(color: Colors.grey.shade400),
                                  ),
                                ),
                                child: Text('ATTIVITÀ', style: _headerStyle()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _vScrollNomini,
                          thumbVisibility: _scrollbarSempreVisibili,
                          child: ListView.builder(
                            controller: _vScrollNomini,
                            padding: EdgeInsets.zero,
                            itemExtent: rowH,
                            itemCount: rowCount,
                            itemBuilder: (context, r) {
                              if (r >= persone.length) {
                                return Row(
                                  children: [
                                    SizedBox(width: nomeW, child: _rigaNominativoVuota(rowH)),
                                    SizedBox(
                                      width: rfiW,
                                      height: rowH,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(color: Colors.grey.shade300),
                                            right: BorderSide(color: Colors.grey.shade300),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: attivitaW,
                                      height: rowH,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(color: Colors.grey.shade300),
                                            right: BorderSide(
                                              color: Colors.grey.shade400,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                              final p = persone[r];
                              final saving = _savingNominativi.contains(p.nominativo);
                              final rfiTxt = _testoFormazioniRfi(p.nominativo);
                              return Row(
                                children: [
                                  SizedBox(
                                    width: nomeW,
                                    height: rowH,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: Colors.grey.shade300),
                                          right: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        color: saving ? Colors.amber.shade50 : null,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      alignment: Alignment.centerLeft,
                                      child: _NominativoConHoverRfi(
                                        nominativo: p.nominativo,
                                        canEdit: _canEdit,
                                        busy: _savingNominativi.isNotEmpty,
                                        loadTracks: _service.loadFormazioniRfiTracksPerNominativo,
                                        onEdit: () => unawaited(_modificaNominativo(p)),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: rfiW,
                                    height: rowH,
                                    child: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: saving ? Colors.amber.shade50 : null,
                                        border: Border(
                                          bottom: BorderSide(color: Colors.grey.shade300),
                                          right: BorderSide(color: Colors.grey.shade300),
                                        ),
                                      ),
                                      child: Tooltip(
                                        message: rfiTxt == '—' ? '' : rfiTxt,
                                        waitDuration: const Duration(milliseconds: 400),
                                        child: Text(
                                          rfiTxt,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: rfiTxt == '—'
                                                ? Colors.grey.shade500
                                                : Colors.teal.shade900,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: attivitaW,
                                    height: rowH,
                                    child: Material(
                                      color: saving ? Colors.amber.shade50 : Colors.white,
                                      child: InkWell(
                                        onTap: _canEdit && _savingNominativi.isEmpty
                                            ? () => unawaited(_modificaAttivitaVeloce(p))
                                            : null,
                                        onDoubleTap: _canEdit && _savingNominativi.isEmpty
                                            ? () => unawaited(_modificaAttivitaVeloce(p))
                                            : null,
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(color: Colors.grey.shade300),
                                              right: BorderSide(
                                                color: Colors.grey.shade400,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 2),
                                          child: Text(
                                            (p.attivita ?? '').trim().isEmpty
                                                ? '—'
                                                : p.attivita!.trim(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: (p.attivita ?? '').trim().isEmpty
                                                  ? Colors.grey.shade500
                                                  : Colors.indigo.shade900,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Scrollbar(
                        controller: _hScrollGriglia,
                        thumbVisibility: _scrollbarSempreVisibili,
                        interactive: true,
                        child: SingleChildScrollView(
                          controller: _hScrollGriglia,
                          scrollDirection: Axis.horizontal,
                          physics: (_fillDragging || _selDragActive)
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          child: SizedBox(
                            key: _gridAreaKey,
                            width: gridW,
                            height: constraints.maxHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: headerH,
                                  child: Row(
                                    children: [
                                      for (final g in giorni)
                                        _headerGiorno(g, cellW, oggi),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _vScrollGriglia,
                                    thumbVisibility: _scrollbarSempreVisibili,
                                    child: ListView.builder(
                                      controller: _vScrollGriglia,
                                      padding: EdgeInsets.zero,
                                      itemExtent: rowH,
                                      itemCount: rowCount,
                                      itemBuilder: (context, r) {
                                        if (r >= persone.length) {
                                          return _rigaCelleVuote(
                                            giorni: giorni,
                                            cellW: cellW,
                                            rowH: rowH,
                                            oggi: oggi,
                                          );
                                        }
                                        final persona = persone[r];
                                        return RepaintBoundary(
                                          child: Row(
                                            children: [
                                              for (var i = 0; i < giorni.length; i++)
                                                _buildCellaGriglia(
                                                  persona: persona,
                                                  giorno: giorni[i],
                                                  colIndex: i,
                                                  rowIndex: r,
                                                  persone: persone,
                                                  giorni: giorni,
                                                  cellW: cellW,
                                                  rowH: rowH,
                                                  oggi: oggi,
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _canEdit
                ? 'Trascina o Shift+click/frecce per selezionare più celle · Ctrl+C / Ctrl+V · Delete cancella · doppio click = modifica · Ctrl+Z annulla.'
                : 'Sola lettura · Ctrl+C copia la selezione.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Color get _coloreRigaVuota => Colors.white.withValues(alpha: 0.92);

  Widget _rigaNominativoVuota(double rowH) {
    return Container(
      height: rowH,
      decoration: BoxDecoration(
        color: _coloreRigaVuota,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
          right: BorderSide(color: Colors.grey.shade400, width: 1.5),
        ),
      ),
    );
  }

  Widget _rigaCelleVuote({
    required List<DateTime> giorni,
    required double cellW,
    required double rowH,
    required DateTime oggi,
  }) {
    return Row(
      children: [
        for (final g in giorni)
          Container(
            width: cellW,
            height: rowH,
            decoration: BoxDecoration(
              color: dateOnly(g) == _pivotDate
                  ? Colors.blue.shade50
                  : dateOnly(g) == oggi
                      ? Colors.green.shade50
                      : _coloreRigaVuota,
              border: Border(
                right: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCellaGriglia({
    required PersonaRiga persona,
    required DateTime giorno,
    required int colIndex,
    required int rowIndex,
    required List<PersonaRiga> persone,
    required List<DateTime> giorni,
    required double cellW,
    required double rowH,
    required DateTime oggi,
  }) {
    final val = _valoreCella(persona.nominativo, giorno);
    final label = _labelCella(persona.nominativo, giorno);
    final isStato = val != null && !val.isEmpty && (val.commessaId ?? '').isEmpty;
    final isPivot = dateOnly(giorno) == _pivotDate;
    final isOggi = dateOnly(giorno) == oggi;
    final inFill = _cellaInSelezioneFill(persona.nominativo, colIndex, rowIndex);
    final inSelezione = _cellaInSelezioneTastiera(rowIndex, colIndex);
    final isAngoloSelezione = _cellaIsAngoloSelezione(rowIndex, colIndex);
    final showFillHandle =
        _cellaHaManigliaFill(persona.nominativo, colIndex, rowIndex);
    final valoreFill = (val != null && !val.isEmpty) ? val : const DislocazioneGiornoValore();
    final fillCancella = val == null || val.isEmpty;

    return _GrigliaDislocazioneCella(
      width: cellW,
      height: rowH,
      label: label,
      isStato: isStato,
      isPivot: isPivot,
      isOggi: isOggi,
      inFill: inFill,
      inSelezione: inSelezione,
      isAngoloSelezione: isAngoloSelezione,
      showFillHandle: showFillHandle,
      fillCancella: fillCancella,
      canEdit: _canEdit,
      onCellPointerDown: (e) => _iniziaSelezioneDrag(
        event: e,
        rowIndex: rowIndex,
        colIndex: colIndex,
      ),
      onDoubleTap: _canEdit
          ? () => unawaited(
                _modificaCella(
                  persona: persona,
                  giorno: giorno,
                  rowIndex: rowIndex,
                  colIndex: colIndex,
                ),
              )
          : null,
      onFillPointerDown: !_canEdit
          ? null
          : (e) {
              _fillPointerId = e.pointer;
              _iniziaFillExcel(
                persona: persona,
                rowIndex: rowIndex,
                colIndex: colIndex,
                valore: valoreFill,
                giorni: giorni,
                persone: persone,
              );
            },
      onFillPointerMove: !_canEdit
          ? null
          : (e) {
              if (_fillPointerId != e.pointer) return;
              _aggiornaFillTrascinamento(
                deltaDx: e.delta.dx,
                deltaDy: e.delta.dy,
                cellW: cellW,
                rowH: rowH,
                giorni: _fillGiorniRef ?? giorni,
                persone: _fillPersoneRef ?? persone,
              );
            },
      onFillPointerUp: !_canEdit
          ? null
          : (e) {
              if (_fillPointerId != e.pointer) return;
              unawaited(_finaleFillDrag());
            },
      onFillPointerCancel: !_canEdit
          ? null
          : (e) {
              if (_fillPointerId == e.pointer) _annullaFillExcel();
            },
    );
  }

  TextStyle _headerStyle() => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      );

  Widget _headerGiorno(DateTime g, double w, DateTime oggi) {
    final isPivot = dateOnly(g) == _pivotDate;
    final isOggi = dateOnly(g) == oggi;
    final bg = isPivot
        ? Colors.blue.shade100
        : isOggi
            ? Colors.green.shade50
            : Colors.grey.shade200;
    return Container(
      width: w,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _dateFmt.format(g),
            style: TextStyle(
              fontSize: 11,
              fontWeight: isPivot || isOggi ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          Text(
            _weekdayFmt.format(g).substring(0, 2).toUpperCase(),
            style: const TextStyle(fontSize: 9, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildTabellaPeriodi() {
    final rows = _righePeriodo.where((r) {
      final n = (r['nominativo'] ?? '').toString();
      if (_search.trim().isEmpty) return true;
      return n.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          final dal = parseIsoDate(r['data_inizio']);
          final al = parseIsoDate(r['data_fine']);
          final val = DislocazioneGiornoValore.fromRow(r);
          return ListTile(
            dense: true,
            title: Text((r['nominativo'] ?? '').toString()),
            subtitle: Text(
              '${etichettaBreve(valore: val, commesse: _commesse, maxLen: 40)} · '
              '${dal != null ? _dateFmt.format(dal) : '?'} – ${al != null ? _dateFmt.format(al) : '?'}',
            ),
          );
        },
      ),
    );
  }
}

/// Cella griglia leggera: maniglia fill solo al passaggio del mouse.
class _GrigliaDislocazioneCella extends StatefulWidget {
  const _GrigliaDislocazioneCella({
    required this.width,
    required this.height,
    required this.label,
    required this.isStato,
    required this.isPivot,
    required this.isOggi,
    required this.inFill,
    required this.inSelezione,
    this.isAngoloSelezione = false,
    required this.showFillHandle,
    required this.fillCancella,
    required this.canEdit,
    this.onCellPointerDown,
    this.onDoubleTap,
    this.onFillPointerDown,
    this.onFillPointerMove,
    this.onFillPointerUp,
    this.onFillPointerCancel,
  });

  final double width;
  final double height;
  final String label;
  final bool isStato;
  final bool isPivot;
  final bool isOggi;
  final bool inFill;
  final bool inSelezione;
  final bool isAngoloSelezione;
  final bool showFillHandle;
  final bool fillCancella;
  final bool canEdit;
  final void Function(PointerDownEvent event)? onCellPointerDown;
  final VoidCallback? onDoubleTap;
  final void Function(PointerDownEvent event)? onFillPointerDown;
  final void Function(PointerMoveEvent event)? onFillPointerMove;
  final void Function(PointerUpEvent event)? onFillPointerUp;
  final void Function(PointerCancelEvent event)? onFillPointerCancel;

  @override
  State<_GrigliaDislocazioneCella> createState() => _GrigliaDislocazioneCellaState();
}

class _GrigliaDislocazioneCellaState extends State<_GrigliaDislocazioneCella> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    if (widget.inFill) {
      bg = Colors.green.shade50;
    } else if (widget.inSelezione) {
      bg = Colors.blue.shade50;
    } else if (widget.isPivot) {
      bg = Colors.blue.shade50;
    } else if (widget.isOggi) {
      bg = Colors.green.shade50;
    } else if (widget.isStato) {
      bg = Colors.orange.shade50;
    }

    final border = widget.inFill
        ? Border.all(color: Colors.green.shade700, width: 1.5)
        : widget.inSelezione
            ? Border.all(
                color: widget.isAngoloSelezione
                    ? Colors.blue.shade900
                    : Colors.blue.shade700,
                width: widget.isAngoloSelezione ? 2.5 : 1.5,
              )
            : Border(
                right: BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade300),
              );

    final showHandle = widget.canEdit && (widget.showFillHandle || _hovered);
    final handleColor =
        widget.fillCancella ? Colors.grey.shade600 : Colors.green.shade700;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: MouseRegion(
        onEnter: widget.canEdit ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.canEdit ? (_) => setState(() => _hovered = false) : null,
        child: Material(
          color: bg ?? Colors.white,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.onCellPointerDown,
                  child: GestureDetector(
                    onDoubleTap: widget.onDoubleTap,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: border),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: widget.isStato
                              ? Colors.red.shade800
                              : Colors.blue.shade900,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              if (showHandle)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: widget.onFillPointerDown,
                    onPointerMove: widget.onFillPointerMove,
                    onPointerUp: widget.onFillPointerUp,
                    onPointerCancel: widget.onFillPointerCancel,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: handleColor,
                        border: Border.all(color: Colors.white, width: 1),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Popup compatto: commessa o stato, salvataggio alla selezione.
class _SelezioneAssegnazioneDialog extends StatefulWidget {
  const _SelezioneAssegnazioneDialog({
    required this.commesse,
    required this.valoreIniziale,
    required this.nominativo,
    required this.giorno,
  });

  final Map<String, String> commesse;
  final DislocazioneGiornoValore? valoreIniziale;
  final String nominativo;
  final DateTime giorno;

  @override
  State<_SelezioneAssegnazioneDialog> createState() =>
      _SelezioneAssegnazioneDialogState();
}

class _SelezioneAssegnazioneDialogState extends State<_SelezioneAssegnazioneDialog> {
  final _filterCtrl = TextEditingController();
  final _liberoCtrl = TextEditingController();
  String _tab = 'commesse';
  static const double _listH = 220;

  @override
  void initState() {
    super.initState();
    final ini = widget.valoreIniziale;
    if (ini != null &&
        !ini.isEmpty &&
        (ini.commessaId == null || ini.commessaId!.isEmpty)) {
      final st = ini.stato?.trim() ?? '';
      if (st.isNotEmpty && !kDislocazioneStati.contains(st.toUpperCase())) {
        _liberoCtrl.text = st;
        _tab = 'libero';
      }
    }
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _liberoCtrl.dispose();
    super.dispose();
  }

  void _confermaTesto(String raw) {
    final val = parseDislocazioneTesto(
      raw,
      statiCatalogo: kDislocazioneStati,
      commesse: widget.commesse,
    );
    if (val == null) return;
    Navigator.pop(context, val);
  }

  List<MapEntry<String, String>> get _commesseFiltrate {
    final k = _filterCtrl.text.trim().toLowerCase();
    final items = widget.commesse.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    if (k.isEmpty) return items.take(80).toList(growable: false);
    return items.where((e) => e.value.toLowerCase().contains(k)).take(80).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd/MM/yyyy').format(widget.giorno);
    final nome = widget.nominativo.length > 28
        ? '${widget.nominativo.substring(0, 26)}…'
        : widget.nominativo;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      title: Text(
        '$nome · $dateLabel',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _filterCtrl,
              autofocus: _tab != 'libero',
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: _tab == 'libero'
                    ? 'Cerca commessa o stato…'
                    : 'Cerca… (Invio = testo libero)',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _tab == 'libero' ? null : _confermaTesto,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Commesse', style: TextStyle(fontSize: 12)),
                  selected: _tab == 'commesse',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _tab = 'commesse'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Stati', style: TextStyle(fontSize: 12)),
                  selected: _tab == 'stati',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _tab = 'stati'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Libero', style: TextStyle(fontSize: 12)),
                  selected: _tab == 'libero',
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _tab = 'libero'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: _listH,
              child: switch (_tab) {
                'commesse' => _listaCommesse(),
                'stati' => _listaStati(),
                _ => _libero(),
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const DislocazioneGiornoValore()),
          child: const Text('Svuota', style: TextStyle(fontSize: 13)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _listaCommesse() {
    final items = _commesseFiltrate;
    if (items.isEmpty) {
      return const Center(child: Text('Nessun risultato', style: TextStyle(fontSize: 12)));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        final sel = widget.valoreIniziale?.commessaId == e.key;
        return Material(
          color: sel ? Colors.blue.shade50 : null,
          child: InkWell(
            onTap: () => Navigator.pop(
              context,
              DislocazioneGiornoValore(commessaId: e.key),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _listaStati() {
    final k = _filterCtrl.text.trim().toUpperCase();
    final stati = kDislocazioneStati
        .where((s) => k.isEmpty || s.contains(k))
        .toList(growable: false);
    return ListView.builder(
      itemCount: stati.length,
      itemBuilder: (context, i) {
        final s = stati[i];
        final sel = widget.valoreIniziale?.stato == s;
        return Material(
          color: sel ? Colors.orange.shade50 : null,
          child: InkWell(
            onTap: () => Navigator.pop(
              context,
              DislocazioneGiornoValore(stato: s),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                s,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _libero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _liberoCtrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Es. ASSENTE, note, codice custom…',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(),
          ),
          onSubmitted: _confermaTesto,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _confermaTesto(_liberoCtrl.text),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Applica testo libero', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 6),
        Text(
          'Qualsiasi testo non commessa/stato catalogo viene salvato in maiuscolo.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _AnnullaFillIntent extends Intent {
  const _AnnullaFillIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _ClearCellsIntent extends Intent {
  const _ClearCellsIntent();
}

class _SelUpIntent extends Intent {
  const _SelUpIntent();
}

class _SelDownIntent extends Intent {
  const _SelDownIntent();
}

class _SelLeftIntent extends Intent {
  const _SelLeftIntent();
}

class _SelRightIntent extends Intent {
  const _SelRightIntent();
}

/// Nome con hover: popup Formazione RFI; doppio click / long press: modifica.
class _NominativoConHoverRfi extends StatefulWidget {
  const _NominativoConHoverRfi({
    required this.nominativo,
    required this.canEdit,
    required this.busy,
    required this.loadTracks,
    required this.onEdit,
  });

  final String nominativo;
  final bool canEdit;
  final bool busy;
  final Future<List<FormazioneRfiTrackInfo>> Function(String nominativo)
      loadTracks;
  final VoidCallback onEdit;

  @override
  State<_NominativoConHoverRfi> createState() => _NominativoConHoverRfiState();
}

class _NominativoConHoverRfiState extends State<_NominativoConHoverRfi> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _loading = false;
  List<FormazioneRfiTrackInfo>? _tracks;
  static final Map<String, List<FormazioneRfiTrackInfo>> _cache =
      <String, List<FormazioneRfiTrackInfo>>{};
  static final DateFormat _scadFmt = DateFormat('dd/MM/yyyy');

  static void warmCache(String nominativo, List<FormazioneRfiTrackInfo> tracks) {
    _cache[nominativo] = tracks;
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _scheduleShow() {
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_mostra());
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _removeOverlay();
    });
  }

  Color _coloreScadenza(DateTime? dt) {
    if (dt == null) return Colors.grey.shade700;
    final today = DateTime.now();
    final ref = DateTime(today.year, today.month, today.day);
    final days = dt.difference(ref).inDays;
    if (days < 0) return Colors.red.shade800;
    if (days <= 45) return Colors.red.shade700;
    if (days <= 60) return Colors.orange.shade800;
    return Colors.green.shade800;
  }

  Widget _rigaTrack(FormazioneRfiTrackInfo info) {
    final scad = info.scadenza;
    final rinn = info.rinnovo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ${info.track}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          if (scad != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 1),
              child: Text(
                'Scadenza: ${_scadFmt.format(scad)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _coloreScadenza(scad),
                ),
              ),
            ),
          if (rinn != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 1),
              child: Text(
                'Rinnovo: ${_scadFmt.format(rinn)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _coloreScadenza(rinn),
                ),
              ),
            ),
          if (scad == null && rinn == null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 1),
              child: Text(
                'Scadenza: non impostata',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _mostra() async {
    if (!mounted) return;
    final cached = _cache[widget.nominativo];
    if (cached != null) {
      _tracks = cached;
    } else {
      setState(() => _loading = true);
      try {
        final list = await widget.loadTracks(widget.nominativo);
        _cache[widget.nominativo] = list;
        _tracks = list;
      } catch (_) {
        _tracks = const <FormazioneRfiTrackInfo>[];
      }
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (ctx) {
        final tracks = _tracks ?? const <FormazioneRfiTrackInfo>[];
        return Positioned(
          width: 340,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: const Offset(0, 28),
            child: MouseRegion(
              onEnter: (_) => _hideTimer?.cancel(),
              onExit: (_) => _scheduleHide(),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Formazione RFI',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            Text(
                              widget.nominativo,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (tracks.isEmpty)
                              Text(
                                'Nessuna formazione RFI registrata',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: tracks.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (_, i) => _rigaTrack(tracks[i]),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _scheduleShow(),
        onExit: (_) => _scheduleHide(),
        child: GestureDetector(
          onDoubleTap: widget.canEdit && !widget.busy ? widget.onEdit : null,
          onLongPress: widget.canEdit && !widget.busy ? widget.onEdit : null,
          child: Tooltip(
            message: widget.canEdit
                ? 'Hover: Formazione RFI · Doppio click: modifica'
                : 'Hover: Formazione RFI',
            waitDuration: const Duration(milliseconds: 900),
            child: Text(
              widget.nominativo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
