import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../Mobile/admin_misc_mobile_pages.dart';
import '../services/deadline_nav_highlight.dart';
import '../services/dislocazione_mdo_per_commessa_service.dart';
import '../services/dislocazione_pos_verifica_service.dart';
import '../services/notification_sender.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/dt_view_role.dart';
import '../utils/excel_export_helper.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/responsive.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../theme/cronos_app_themes.dart';
import 'admin_logistica_mdo_ferroviari_page.dart';

/// Elenco MDO ferroviari per commessa, con trasferimenti programmati e conferma arrivo.
class AdminDislocazioneMdoPerCommessaPage extends StatefulWidget {
  const AdminDislocazioneMdoPerCommessaPage({
    super.key,
    this.readOnly = false,
    this.forceMobileLayout = false,
    this.initialMainTab = 0,
  });

  final bool readOnly;
  final bool forceMobileLayout;
  /// 0 = mezzi per commessa · 1 = trasferimenti in corso
  final int initialMainTab;

  @override
  State<AdminDislocazioneMdoPerCommessaPage> createState() =>
      _AdminDislocazioneMdoPerCommessaPageState();
}

class _AdminDislocazioneMdoPerCommessaPageState
    extends State<AdminDislocazioneMdoPerCommessaPage> {
  final _cercaCommessaCtrl = TextEditingController();
  final _cercaMezzoCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  bool _busy = false;
  bool _exportExcelInCorso = false;
  String? _error;
  int _mainTab = 0; // 0 mezzi · 1 trasferimenti
  /// Su mobile: dopo aver scelto la commessa mostra l'elenco mezzi a pieno schermo.
  bool _mobileShowMezzi = false;

  Map<String, String> _commesseById = {};
  List<MdoFerroviarioRiga> _mezzi = const [];
  List<MdoCommessaGroup> _gruppi = const [];
  List<MdoTrasferimento> _trasferimenti = const [];
  String? _selectedKey;
  final Set<String> _selectedMezzoIds = <String>{};

  String _filtroCommessa = '';
  String _filtroMezzo = '';

  /// Admin / logistica possono trasferire; DT e admin vista solo consultano.
  bool _canEdit(BuildContext context) {
    if (widget.readOnly) return false;
    final session = currentSessionRole() ?? '';
    final role = DtViewRoleScope.resolveForPage(context, session);
    final effective = role.isNotEmpty ? role : normalizeRole(session);
    if (effective.isEmpty) return true;
    return canEditMdoPerCommessa(effective);
  }

  bool _isCompact(BuildContext context) =>
      widget.forceMobileLayout || useMobileUi(context);

  Set<String> get _mdoInTrasferimentoIds =>
      _trasferimenti.map((e) => e.mdoId).toSet();

  bool _mezzoMatchQuery(MdoFerroviarioRiga m, String q) {
    if (q.isEmpty) return true;
    final hay = [
      m.matricolaInterna,
      m.targaRfi,
      m.descrizione,
      m.modello,
      m.dtNome,
      m.cantiereAttuale,
      m.commessa,
      m.titolo,
      m.sottotitolo,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  bool _gruppoMatchQuery(MdoCommessaGroup g, String q) {
    if (q.isEmpty) return true;
    if (g.label.toLowerCase().contains(q)) return true;
    if (g.commessaKey.contains(q)) return true;
    return g.mezzi.any((m) => _mezzoMatchQuery(m, q));
  }

  @override
  void initState() {
    super.initState();
    _mainTab = widget.initialMainTab == 1 ? 1 : 0;
    _cercaCommessaCtrl.addListener(() {
      final q = _cercaCommessaCtrl.text.trim().toLowerCase();
      setState(() {
        _filtroCommessa = q;
        final filtrati = _gruppi
            .where((g) => _gruppoMatchQuery(g, q))
            .toList(growable: false);
        if (filtrati.isEmpty) return;
        final stillOk = filtrati.any((g) => g.commessaKey == _selectedKey);
        if (!stillOk) {
          _selectedKey = filtrati.first.commessaKey;
          _selectedMezzoIds.clear();
        }
      });
    });
    _cercaMezzoCtrl.addListener(() {
      setState(() => _filtroMezzo = _cercaMezzoCtrl.text.trim().toLowerCase());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _cercaCommessaCtrl.dispose();
    _cercaMezzoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DislocazioneMdoPerCommessaService.loadMezziAttivi(),
        DislocazioneMdoPerCommessaService.loadCommesseAttive(),
        DislocazioneMdoPerCommessaService.loadTrasferimentiInCorso(),
      ]);
      final mezzi = results[0] as List<MdoFerroviarioRiga>;
      final commesse = results[1] as Map<String, String>;
      final trasferimenti = results[2] as List<MdoTrasferimento>;
      final gruppi = DislocazioneMdoPerCommessaService.groupByCommessa(mezzi);
      if (!mounted) return;
      setState(() {
        _mezzi = mezzi;
        _commesseById = commesse;
        _gruppi = gruppi;
        _trasferimenti = trasferimenti;
        _loading = false;
        if (_selectedKey == null ||
            !gruppi.any((g) => g.commessaKey == _selectedKey)) {
          _selectedKey = gruppi.isEmpty ? null : gruppi.first.commessaKey;
        }
        final ids = mezzi.map((e) => e.id).toSet();
        final busy = trasferimenti.map((e) => e.mdoId).toSet();
        _selectedMezzoIds.removeWhere((id) => !ids.contains(id) || busy.contains(id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<MdoCommessaGroup> get _gruppiFiltrati {
    if (_filtroCommessa.isEmpty) return _gruppi;
    return _gruppi
        .where((g) => _gruppoMatchQuery(g, _filtroCommessa))
        .toList(growable: false);
  }

  MdoCommessaGroup? get _gruppoSelezionato {
    final key = _selectedKey;
    if (key == null) return null;
    for (final g in _gruppi) {
      if (g.commessaKey == key) return g;
    }
    return null;
  }

  List<MdoFerroviarioRiga> get _mezziVisibili {
    final g = _gruppoSelezionato;
    if (g == null) return const [];
    var list = g.mezzi;
    if (_filtroMezzo.isNotEmpty) {
      return list.where((m) => _mezzoMatchQuery(m, _filtroMezzo)).toList(growable: false);
    }
    // Se la ricerca a sinistra ha trovato per mezzo/targa, filtra anche l'elenco.
    if (_filtroCommessa.isNotEmpty &&
        list.any((m) => _mezzoMatchQuery(m, _filtroCommessa))) {
      return list
          .where((m) => _mezzoMatchQuery(m, _filtroCommessa))
          .toList(growable: false);
    }
    return list;
  }

  void _selezionaCommessa(String key) {
    setState(() {
      _selectedKey = key;
      _selectedMezzoIds.clear();
      _cercaMezzoCtrl.clear();
      _filtroMezzo = '';
      _mobileShowMezzi = true;
    });
  }

  void _tornaAlleCommesseMobile() {
    setState(() {
      _mobileShowMezzi = false;
      _selectedMezzoIds.clear();
    });
  }

  void _toggleMezzo(String id) {
    if (_mdoInTrasferimentoIds.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Questo mezzo ha già un trasferimento in corso. '
            'Gestiscilo dalla scheda Trasferimenti.',
          ),
        ),
      );
      setState(() => _mainTab = 1);
      return;
    }
    setState(() {
      if (!_selectedMezzoIds.add(id)) {
        _selectedMezzoIds.remove(id);
      }
    });
  }

  void _selezionaTuttiVisibili(bool select) {
    final ids = _mezziVisibili
        .where((m) => !_mdoInTrasferimentoIds.contains(m.id))
        .map((e) => e.id);
    setState(() {
      if (select) {
        _selectedMezzoIds.addAll(ids);
      } else {
        _selectedMezzoIds.removeAll(_mezziVisibili.map((e) => e.id));
      }
    });
  }

  void _apriMezzoInLogistica(MdoFerroviarioRiga mezzo) {
    final id = mezzo.id.trim();
    if (id.isEmpty) return;
    DeadlineNavHighlight.armUuid(id, flashCycles: 10);
    final page = useMobileUi(context)
        ? const AdminLogisticaMdoFerroviariMobilePage()
        : const AdminLogisticaMdoFerroviariPage();
    FuturisticNavigation.pushPage(
      context,
      page: page,
      title: 'MDO ferroviari',
    );
  }

  Future<void> _apriTrasferimento({List<MdoFerroviarioRiga>? mezziForzati}) async {
    if (!_canEdit(context)) return;
    final fromSelection = mezziForzati == null;
    if (fromSelection && _selectedMezzoIds.isEmpty) return;
    if (!await ensureCanPersist(context)) return;
    if (!mounted) return;

    final selezionati = (mezziForzati ??
            _mezzi
                .where((m) => _selectedMezzoIds.contains(m.id))
                .toList(growable: false))
        .where((m) => !_mdoInTrasferimentoIds.contains(m.id))
        .toList(growable: false);
    if (selezionati.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessun mezzo selezionato disponibile al trasferimento.'),
        ),
      );
      return;
    }

    String origineLabel;
    if (mezziForzati != null) {
      final keys = selezionati.map((e) => e.commessa).toSet();
      origineLabel = keys.length == 1
          ? (selezionati.first.commessa.isEmpty
              ? 'Senza commessa'
              : selezionati.first.commessa)
          : 'Più commesse';
    } else {
      origineLabel = _gruppoSelezionato?.label ?? '';
    }

    final dest = await showDialog<_TrasferimentoFormEsito>(
      context: context,
      builder: (ctx) => _TrasferimentoFormDialog(
        title: 'Nuovo trasferimento',
        confirmLabel: 'Avvia trasferimento',
        mezziLabels: selezionati.map((e) => e.titolo).toList(),
        commesseNomi: _commesseById.values.toList()..sort(),
        commessaOrigine: origineLabel,
        initialCantiere: selezionati.length == 1
            ? selezionati.first.cantiereAttuale
            : '',
      ),
    );
    if (dest == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final n = await DislocazioneMdoPerCommessaService.creaTrasferimenti(
        mezzi: selezionati,
        nuovaCommessa: dest.commessa,
        nuovoCantiere: dest.cantiere,
        aggiornaCantiere: dest.aggiornaCantiere,
        periodoTipo: dest.periodoTipo,
        dataRiferimento: dest.dataRiferimento,
        note: dest.note,
        trasportatore: dest.trasportatore,
        referenteCaricoPersonaleUuid: dest.referenteCaricoPersonaleUuid,
        referenteCaricoNome: dest.referenteCaricoNome,
        referenteCaricoTelefono: dest.referenteCaricoTelefono,
        referenteScaricoPersonaleUuid: dest.referenteScaricoPersonaleUuid,
        referenteScaricoNome: dest.referenteScaricoNome,
        referenteScaricoTelefono: dest.referenteScaricoTelefono,
        luogoCarico: dest.luogoCarico,
        luogoScarico: dest.luogoScarico,
        modalitaCarico: dest.modalitaCarico,
        modalitaScarico: dest.modalitaScarico,
      );
      unawaited(
        _notifyReferentiTrasferimento(
          action: 'create',
          mezziLabels: selezionati.map((e) => e.titolo).toList(),
          commessaOrigine: origineLabel,
          dest: dest,
        ),
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _mainTab = 1;
        _selectedMezzoIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1
                ? '1 trasferimento avviato verso «${dest.commessa}». '
                    'Conferma l’arrivo quando il mezzo è a destinazione.'
                : '$n trasferimenti avviati verso «${dest.commessa}». '
                    'Conferma l’arrivo quando i mezzi sono a destinazione.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trasferimento non avviato: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apriNuovoTrasferimentoDaTab() async {
    if (!_canEdit(context) || _busy) return;
    final disponibili = _mezzi
        .where((m) => !_mdoInTrasferimentoIds.contains(m.id))
        .toList(growable: false)
      ..sort((a, b) => a.titolo.toLowerCase().compareTo(b.titolo.toLowerCase()));
    if (disponibili.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nessun mezzo disponibile: tutti sono già in trasferimento.',
          ),
        ),
      );
      return;
    }

    final scelti = await showDialog<List<MdoFerroviarioRiga>>(
      context: context,
      builder: (ctx) => _SelezionaMezziTrasferimentoDialog(mezzi: disponibili),
    );
    if (scelti == null || scelti.isEmpty || !mounted) return;
    await _apriTrasferimento(mezziForzati: scelti);
  }

  Future<void> _exportExcel() async {
    if (_exportExcelInCorso || _loading) return;
    setState(() => _exportExcelInCorso = true);
    try {
      final excel = Excel.createExcel();
      final def = excel.getDefaultSheet();
      if (def != null) excel.delete(def);

      final sheetTr = excel['Trasferimenti in corso'];
      sheetTr.appendRow([
        'Mezzo',
        'Matricola',
        'Targa RFI',
        'Commessa origine',
        'Commessa destinazione',
        'Periodo',
        'Cantiere origine',
        'Cantiere destinazione',
        'Aggiorna cantiere',
        'Referente carico',
        'Tel. carico',
        'Referente scarico',
        'Tel. scarico',
        'Trasportatore',
        'Note',
        'Stato',
      ]);
      for (final t in _trasferimenti) {
        sheetTr.appendRow([
          t.mdoLabel.isEmpty ? t.matricolaInterna : t.mdoLabel,
          t.matricolaInterna,
          t.targaRfi,
          t.commessaOrigine.isEmpty ? 'Senza commessa' : t.commessaOrigine,
          t.commessaDestinazione,
          t.periodoLabel(_dateFmt),
          t.cantiereOrigine,
          t.cantiereDestinazione ?? '',
          t.aggiornaCantiere ? 'SI' : 'NO',
          t.referenteCaricoNome ?? '',
          t.referenteCaricoTelefono ?? '',
          t.referenteScaricoNome ?? '',
          t.referenteScaricoTelefono ?? '',
          t.trasportatore ?? '',
          t.note ?? '',
          t.stato == 'in_corso' ? 'In corso' : t.stato,
        ]);
      }

      final sheetMezzi = excel['Mezzi per commessa'];
      sheetMezzi.appendRow([
        'Commessa',
        'Mezzo',
        'Matricola',
        'Targa RFI',
        'Descrizione',
        'Modello',
        'Cantiere',
        'DT',
        'In trasferimento',
      ]);
      final mezziOrd = List<MdoFerroviarioRiga>.from(_mezzi)
        ..sort((a, b) {
          final c = a.commessa.toLowerCase().compareTo(b.commessa.toLowerCase());
          if (c != 0) return c;
          return a.titolo.toLowerCase().compareTo(b.titolo.toLowerCase());
        });
      for (final m in mezziOrd) {
        sheetMezzi.appendRow([
          m.commessa.isEmpty ? 'Senza commessa' : m.commessa,
          m.titolo,
          m.matricolaInterna,
          m.targaRfi,
          m.descrizione,
          m.modello,
          m.cantiereAttuale,
          m.dtNome,
          _mdoInTrasferimentoIds.contains(m.id) ? 'SI' : 'NO',
        ]);
      }

      final bytes = Uint8List.fromList(excel.encode()!);
      final saved = await ExcelExportHelper.saveAndReveal(
        pageName: 'mdo_per_commessa',
        bytes: bytes,
      );
      if (!mounted) return;
      if (saved) {
        final p = ExcelExportHelper.lastSavedPath ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              p.isEmpty
                  ? 'Export Excel completato.'
                  : 'Export Excel completato: $p',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore export Excel: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportExcelInCorso = false);
    }
  }

  Future<void> _modificaTrasferimento(MdoTrasferimento t) async {
    if (!_canEdit(context)) return;
    if (!await ensureCanPersist(context)) return;
    if (!mounted) return;

    final dest = await showDialog<_TrasferimentoFormEsito>(
      context: context,
      builder: (ctx) => _TrasferimentoFormDialog(
        title: 'Modifica trasferimento',
        confirmLabel: 'Salva modifiche',
        mezziLabels: [t.mdoLabel.isEmpty ? t.matricolaInterna : t.mdoLabel],
        commesseNomi: _commesseById.values.toList()..sort(),
        commessaOrigine: t.commessaOrigine,
        initialCommessa: t.commessaDestinazione,
        initialCantiere: t.cantiereDestinazione ?? '',
        initialAggiornaCantiere: t.aggiornaCantiere,
        initialPeriodoTipo: t.periodoTipo,
        initialData: t.dataInizio,
        initialNote: t.note ?? '',
        initialTrasportatore: t.trasportatore ?? '',
        initialReferenteCaricoUuid: t.referenteCaricoPersonaleUuid,
        initialReferenteCaricoNome: t.referenteCaricoNome,
        initialReferenteCaricoTelefono: t.referenteCaricoTelefono,
        initialReferenteScaricoUuid: t.referenteScaricoPersonaleUuid,
        initialReferenteScaricoNome: t.referenteScaricoNome,
        initialReferenteScaricoTelefono: t.referenteScaricoTelefono,
        initialLuogoCarico: t.luogoCarico ?? '',
        initialLuogoScarico: t.luogoScarico ?? '',
        initialModalitaCarico: t.modalitaCarico,
        initialModalitaScarico: t.modalitaScarico,
      ),
    );
    if (dest == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await DislocazioneMdoPerCommessaService.aggiornaTrasferimento(
        trasferimentoId: t.id,
        nuovaCommessa: dest.commessa,
        nuovoCantiere: dest.cantiere,
        aggiornaCantiere: dest.aggiornaCantiere,
        periodoTipo: dest.periodoTipo,
        dataRiferimento: dest.dataRiferimento,
        note: dest.note,
        trasportatore: dest.trasportatore,
        referenteCaricoPersonaleUuid: dest.referenteCaricoPersonaleUuid,
        referenteCaricoNome: dest.referenteCaricoNome,
        referenteCaricoTelefono: dest.referenteCaricoTelefono,
        referenteScaricoPersonaleUuid: dest.referenteScaricoPersonaleUuid,
        referenteScaricoNome: dest.referenteScaricoNome,
        referenteScaricoTelefono: dest.referenteScaricoTelefono,
        luogoCarico: dest.luogoCarico,
        luogoScarico: dest.luogoScarico,
        modalitaCarico: dest.modalitaCarico,
        modalitaScarico: dest.modalitaScarico,
      );
      unawaited(
        _notifyReferentiTrasferimento(
          action: 'update',
          mezziLabels: [
            t.mdoLabel.isEmpty ? t.matricolaInterna : t.mdoLabel,
          ],
          commessaOrigine: t.commessaOrigine,
          dest: dest,
        ),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trasferimento aggiornato.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modifica non riuscita: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyReferentiTrasferimento({
    required String action,
    required List<String> mezziLabels,
    required String commessaOrigine,
    required _TrasferimentoFormEsito dest,
  }) async {
    try {
      final period = DislocazioneMdoPerCommessaService.resolvePeriodo(
        periodoTipo: dest.periodoTipo,
        riferimento: dest.dataRiferimento,
      );
      final periodoLabel = dest.periodoTipo == 'settimana'
          ? '${_dateFmt.format(period.inizio)} – ${_dateFmt.format(period.fine)}'
          : _dateFmt.format(period.inizio);
      await NotificationSender.notifyMdoTrasferimentoReferenti(
        action: action,
        mezziLabels: mezziLabels,
        commessaOrigine: commessaOrigine,
        commessaDestinazione: dest.commessa,
        periodoLabel: periodoLabel,
        trasportatore: dest.trasportatore,
        referenteCaricoPersonaleUuid: dest.referenteCaricoPersonaleUuid,
        referenteCaricoNome: dest.referenteCaricoNome,
        referenteScaricoPersonaleUuid: dest.referenteScaricoPersonaleUuid,
        referenteScaricoNome: dest.referenteScaricoNome,
        luogoCarico: dest.luogoCarico,
        luogoScarico: dest.luogoScarico,
      );
    } catch (e) {
      // ignore: avoid_print
      print('>>> notify referenti trasferimento: $e');
    }
  }

  Future<void> _annullaTrasferimento(MdoTrasferimento t) async {
    if (!_canEdit(context)) return;
    if (!await ensureCanPersist(context)) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Annulla trasferimento'),
        content: Text(
          'Annullare il trasferimento di «${t.mdoLabel}» verso '
          '«${t.commessaDestinazione}»?\n\n'
          'La dislocazione del mezzo non verrà modificata.',
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Indietro'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await DislocazioneMdoPerCommessaService.annullaTrasferimento(t.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trasferimento annullato.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Annullamento non riuscito: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verificaListaPosTrasferimenti() async {
    if (!mounted) return;
    if (_trasferimenti.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun trasferimento in corso.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 14),
                  Text('Verifica lista POS…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    List<DislocazionePosVerificaMdoTrasferimentoEsito>? esiti;
    Object? err;
    try {
      esiti = await DislocazionePosVerificaService
          .verificaTrasferimentiSuPosCommessaDestinazione(
        trasferimenti: _trasferimenti
            .map(
              (t) => (
                mdoId: t.mdoId,
                mdoLabel: t.mdoLabel.trim().isEmpty
                    ? t.matricolaInterna
                    : t.mdoLabel.trim(),
                commessaDestinazione: t.commessaDestinazione,
              ),
            )
            .toList(),
        commesseById: _commesseById,
      );
    } catch (e) {
      err = e;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (err != null || esiti == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verifica POS non riuscita: $err'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    final risultati = esiti;
    final okCount = risultati.where((e) => e.ok).length;
    final koCount = risultati.length - okCount;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.65;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Row(
            children: [
              Icon(
                koCount == 0
                    ? Icons.check_circle_outline
                    : Icons.fact_check_outlined,
                color: koCount == 0
                    ? Colors.green.shade700
                    : Colors.deepPurple.shade700,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Verifica lista POS')),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  koCount == 0
                      ? 'Tutti i ${risultati.length} mezzi in trasferimento '
                          'sono in lista POS della destinazione.'
                      : '$okCount ok · $koCount da verificare '
                          '(su ${risultati.length} trasferimenti).',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: koCount == 0
                        ? Colors.green.shade700
                        : CronosAppThemes.onSurfaceOf(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: risultati.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final e = risultati[i];
                      final color = e.ok
                          ? Colors.green
                          : (e.esito == 'errore' ||
                                  e.esito == 'commessa_non_risolta'
                              ? Colors.orange
                              : Colors.red);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: color.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              e.ok
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              size: 18,
                              color: color.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.mdoLabel.isEmpty ? e.mdoId : e.mdoLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: color.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '→ ${e.commessaDestinazione.isEmpty ? '—' : e.commessaDestinazione}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: CronosAppThemes.onSurfaceOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.ok ||
                                            e.esito == 'errore' ||
                                            e.esito == 'commessa_non_risolta'
                                        ? e.messaggio
                                        : DislocazionePosVerificaService
                                            .motivoMdoLabel(e.esito),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.25,
                                      color: CronosAppThemes.mutedOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confermaArrivo(MdoTrasferimento t) async {
    if (!_canEdit(context)) return;
    if (!await ensureCanPersist(context)) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Conferma arrivo'),
        content: Text(
          'Confermare l’arrivo di «${t.mdoLabel}» su '
          '«${t.commessaDestinazione}»?\n\n'
          'Verrà aggiornata automaticamente la dislocazione '
          '(commessa${t.aggiornaCantiere ? ' e cantiere' : ''}) in anagrafica MDO.',
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Indietro'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await DislocazioneMdoPerCommessaService.confermaArrivo(
        t: t,
        commesseById: _commesseById,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Arrivo confermato: dislocazione aggiornata su «${t.commessaDestinazione}».',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conferma non riuscita: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = _isCompact(context);
    final wide = !compact && MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: CronosAppThemes.canvasOf(context),
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'MDO per commessa'),
          actions: [
            IconButton(
              tooltip: 'Export Excel',
              onPressed: _loading || _exportExcelInCorso
                  ? null
                  : () => unawaited(_exportExcel()),
              icon: _exportExcelInCorso
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading || _busy ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heroBanner(theme, compact: compact),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 16,
                        0,
                        compact ? 10 : 16,
                        compact ? 6 : 8,
                      ),
                      child: SegmentedButton<int>(
                        style: compact
                            ? const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              )
                            : null,
                        segments: [
                          ButtonSegment(
                            value: 0,
                            icon: const Icon(Icons.train_outlined, size: 18),
                            label: Text(compact ? 'Mezzi' : 'Mezzi per commessa'),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(
                              _trasferimenti.isEmpty
                                  ? (compact ? 'Trasferimenti' : 'Trasferimenti in corso')
                                  : (compact
                                      ? 'Trasf. (${_trasferimenti.length})'
                                      : 'Trasferimenti (${_trasferimenti.length})'),
                            ),
                          ),
                        ],
                        selected: {_mainTab},
                        onSelectionChanged: (s) => setState(() {
                          _mainTab = s.first;
                          if (_mainTab == 1) _mobileShowMezzi = false;
                        }),
                      ),
                    ),
                    Expanded(
                      child: _mainTab == 1
                          ? _panelTrasferimenti(theme, compact: compact)
                          : wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 340,
                                      child: _panelCommesse(theme, compact: false),
                                    ),
                                    Expanded(
                                      child: _panelDettaglio(theme, compact: false),
                                    ),
                                  ],
                                )
                              : compact
                                  ? (_mobileShowMezzi
                                      ? _panelDettaglio(theme, compact: true)
                                      : _panelCommesse(theme, compact: true))
                                  : Column(
                                      children: [
                                        SizedBox(
                                          height: 220,
                                          child: _panelCommesse(theme, compact: false),
                                        ),
                                        Expanded(
                                          child: _panelDettaglio(theme, compact: false),
                                        ),
                                      ],
                                    ),
                    ),
                  ],
                ),
    );
  }

  Widget _heroBanner(ThemeData theme, {required bool compact}) {
    final totale = _mezzi.length;
    final nCommesse = _gruppi.where((g) => g.commessaKey.isNotEmpty).length;
    final nTr = _trasferimenti.length;
    return Container(
      margin: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 8 : 16,
        compact ? 10 : 16,
        compact ? 4 : 8,
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 12 : 18,
        compact ? 12 : 20,
        compact ? 12 : 18,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF0277BD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade900.withValues(alpha: 0.22),
            blurRadius: compact ? 10 : 18,
            offset: Offset(0, compact ? 4 : 8),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.train_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'MDO per commessa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statChip('$totale', 'mezzi', compact: true),
                    _statChip('$nCommesse', 'commesse', compact: true),
                    if (nTr > 0) _statChip('$nTr', 'in corso', compact: true),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.train_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mezzi ferroviari MDO per commessa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Avvia un trasferimento con date, poi conferma l’arrivo '
                        'per aggiornare la dislocazione del mezzo.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _statChip('$totale', 'mezzi'),
                const SizedBox(width: 8),
                _statChip('$nCommesse', 'commesse'),
                if (nTr > 0) ...[
                  const SizedBox(width: 8),
                  _statChip('$nTr', 'in corso'),
                ],
              ],
            ),
    );
  }

  Widget _statChip(String value, String label, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 15 : 18,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            const SizedBox(height: 12),
            Text('Errore caricamento: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelCommesse(ThemeData theme, {required bool compact}) {
    final gruppi = _gruppiFiltrati;
    return Container(
      margin: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 4 : 8,
        compact ? 10 : 8,
        compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: CronosAppThemes.cardOf(context),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: CronosAppThemes.hairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 12 : 14, compact ? 12 : 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Scegli la commessa',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: CronosAppThemes.onSurfaceOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _cercaCommessaCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cerca commessa, matricola, targa, DT…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: gruppi.isEmpty
                ? const Center(child: Text('Nessuna commessa trovata.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: gruppi.length,
                    itemBuilder: (context, i) {
                      final g = gruppi[i];
                      final selected = g.commessaKey == _selectedKey;
                      final emptyCommessa = g.commessaKey.isEmpty;
                      return InkWell(
                        onTap: () => _selezionaCommessa(g.commessaKey),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: compact ? 10 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? CronosAppThemes.selectedFillOf(context)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? CronosAppThemes.selectedBorderOf(context)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                emptyCommessa
                                    ? Icons.help_outline
                                    : Icons.construction_outlined,
                                size: 20,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : CronosAppThemes.mutedOf(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  g.label,
                                  style: TextStyle(
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: 13,
                                    color: emptyCommessa
                                        ? Colors.orange.shade700
                                        : CronosAppThemes.onSurfaceOf(context),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.blue.shade700
                                      : CronosAppThemes.cardMutedOf(context),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${g.count}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: selected
                                        ? Colors.white
                                        : CronosAppThemes.onSurfaceOf(context),
                                  ),
                                ),
                              ),
                              if (compact) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  color: CronosAppThemes.mutedOf(context),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelDettaglio(ThemeData theme, {required bool compact}) {
    final g = _gruppoSelezionato;
    final mezzi = _mezziVisibili;
    final selectable = mezzi.where((m) => !_mdoInTrasferimentoIds.contains(m.id));
    final allVisibleSelected = selectable.isNotEmpty &&
        selectable.every((m) => _selectedMezzoIds.contains(m.id));

    return Container(
      margin: EdgeInsets.fromLTRB(
        compact ? 10 : 8,
        compact ? 4 : 8,
        compact ? 10 : 16,
        compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: CronosAppThemes.cardOf(context),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: CronosAppThemes.hairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: g == null
          ? const Center(child: Text('Seleziona una commessa a sinistra.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 18,
                    compact ? 12 : 16,
                    compact ? 12 : 18,
                    compact ? 10 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: CronosAppThemes.cardMutedOf(context),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(compact ? 12 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            onPressed: _tornaAlleCommesseMobile,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Colors.blue.shade800,
                            ),
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Commesse'),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '2. Mezzi sulla commessa',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: CronosAppThemes.mutedOf(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  g.label,
                                  style: TextStyle(
                                    fontSize: compact ? 17 : 20,
                                    fontWeight: FontWeight.w900,
                                    color: CronosAppThemes.onSurfaceOf(context),
                                  ),
                                ),
                                Text(
                                  '${mezzi.length} ${mezzi.length == 1 ? 'mezzo' : 'mezzi'}'
                                  '${_filtroCommessa.isNotEmpty || _filtroMezzo.isNotEmpty ? ' filtrati' : ''}'
                                  ' · ${g.count} in anagrafica',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CronosAppThemes.mutedOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_canEdit(context))
                            FilledButton.icon(
                              onPressed: _selectedMezzoIds.isEmpty || _busy
                                  ? null
                                  : () => unawaited(_apriTrasferimento()),
                              style: compact
                                  ? FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    )
                                  : null,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.swap_horiz, size: 18),
                              label: Text(
                                _selectedMezzoIds.isEmpty
                                    ? 'Trasferisci'
                                    : 'Trasferisci (${_selectedMezzoIds.length})',
                                style: TextStyle(fontSize: compact ? 12 : 14),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cercaMezzoCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Filtra mezzo (matricola, targa, DT…)',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: CronosAppThemes.cardOf(context),
                        ),
                      ),
                      if (_canEdit(context)) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: Text(
                              allVisibleSelected ? 'Deseleziona' : 'Seleziona tutti',
                            ),
                            selected: allVisibleSelected,
                            onSelected: mezzi.isEmpty
                                ? null
                                : (v) => _selezionaTuttiVisibili(v),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: mezzi.isEmpty
                      ? const Center(child: Text('Nessun mezzo su questa commessa.'))
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 8 : 12,
                            8,
                            compact ? 8 : 12,
                            compact ? 10 : 16,
                          ),
                          itemCount: mezzi.length,
                          itemBuilder: (context, i) {
                            final m = mezzi[i];
                            final inTr = _mdoInTrasferimentoIds.contains(m.id);
                            return _MezzoCard(
                              mezzo: m,
                              selected: _selectedMezzoIds.contains(m.id),
                              canSelect: _canEdit(context) && !inTr,
                              inTrasferimento: inTr,
                              compact: compact,
                              onToggle: () => _toggleMezzo(m.id),
                              onApriInLogistica: () => _apriMezzoInLogistica(m),
                              onApriTrasferimenti: inTr
                                  ? () => setState(() {
                                        _mainTab = 1;
                                        _mobileShowMezzi = false;
                                      })
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _panelTrasferimenti(ThemeData theme, {required bool compact}) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 4 : 6,
        compact ? 10 : 16,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: CronosAppThemes.cardOf(context),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: CronosAppThemes.hairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 14,
              compact ? 8 : 10,
              compact ? 12 : 14,
              compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: CronosAppThemes.warnFillOf(context),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(compact ? 12 : 14),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: compact ? 18 : 20,
                  color: Colors.orange.shade900,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trasferimenti in corso',
                    style: TextStyle(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w800,
                      color: CronosAppThemes.onSurfaceOf(context),
                    ),
                  ),
                ),
                Text(
                  '${_trasferimenti.length}',
                  style: TextStyle(
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Export Excel',
                  visualDensity: VisualDensity.compact,
                  onPressed: _exportExcelInCorso
                      ? null
                      : () => unawaited(_exportExcel()),
                  icon: Icon(
                    Icons.file_download_outlined,
                    size: 20,
                    color: Colors.orange.shade900,
                  ),
                ),
                if (_trasferimenti.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_verificaListaPosTrasferimenti()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 10,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(
                      compact ? 'Verifica POS' : 'Verifica lista POS',
                      style: TextStyle(fontSize: compact ? 12 : 13),
                    ),
                  ),
                ],
                if (_canEdit(context)) ...[
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_apriNuovoTrasferimentoDaTab()),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      compact ? 'Nuovo' : 'Nuovo trasferimento',
                      style: TextStyle(fontSize: compact ? 12 : 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _trasferimenti.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Nessun trasferimento in corso.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: CronosAppThemes.mutedOf(context),
                          ),
                        ),
                        if (_canEdit(context)) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => unawaited(_apriNuovoTrasferimentoDaTab()),
                            icon: const Icon(Icons.add),
                            label: const Text('Nuovo trasferimento'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 10,
                      8,
                      compact ? 8 : 10,
                      10,
                    ),
                    itemCount: _trasferimenti.length,
                    itemBuilder: (context, i) {
                      final t = _trasferimenti[i];
                      return _TrasferimentoCard(
                        t: t,
                        dateFmt: _dateFmt,
                        canEdit: _canEdit(context) && !_busy,
                        compact: compact,
                        onModifica: () => unawaited(_modificaTrasferimento(t)),
                        onAnnulla: () => unawaited(_annullaTrasferimento(t)),
                        onConferma: () => unawaited(_confermaArrivo(t)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelezionaMezziTrasferimentoDialog extends StatefulWidget {
  const _SelezionaMezziTrasferimentoDialog({required this.mezzi});

  final List<MdoFerroviarioRiga> mezzi;

  @override
  State<_SelezionaMezziTrasferimentoDialog> createState() =>
      _SelezionaMezziTrasferimentoDialogState();
}

class _SelezionaMezziTrasferimentoDialogState
    extends State<_SelezionaMezziTrasferimentoDialog> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = <String>{};
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MdoFerroviarioRiga> get _filtered {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.mezzi;
    return widget.mezzi.where((m) {
      final hay = [
        m.titolo,
        m.matricolaInterna,
        m.targaRfi,
        m.commessa,
        m.cantiereAttuale,
        m.dtNome,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width;
    final dialogW = maxW < 640 ? maxW - 32 : 560.0;
    final filtered = _filtered;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Seleziona mezzi da trasferire'),
      content: SizedBox(
        width: dialogW,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cerca matricola, targa, commessa, DT…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_selected.length} selezionati · ${filtered.length} visibili',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CronosAppThemes.mutedOf(context),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: filtered.isEmpty
                      ? null
                      : () => setState(() {
                            for (final m in filtered) {
                              _selected.add(m.id);
                            }
                          }),
                  child: const Text('Tutti visibili'),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('Azzera'),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Nessun mezzo trovato'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        final sel = _selected.contains(m.id);
                        return CheckboxListTile(
                          dense: true,
                          value: sel,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(m.id);
                            } else {
                              _selected.remove(m.id);
                            }
                          }),
                          title: Text(
                            m.titolo,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (m.commessa.isNotEmpty) m.commessa,
                              if (m.cantiereAttuale.isNotEmpty) m.cantiereAttuale,
                              if (m.dtNome.isNotEmpty) 'DT: ${m.dtNome}',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
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
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final out = widget.mezzi
                      .where((m) => _selected.contains(m.id))
                      .toList(growable: false);
                  Navigator.pop(context, out);
                },
          child: Text(
            _selected.isEmpty
                ? 'Continua'
                : 'Continua (${_selected.length})',
          ),
        ),
      ],
    );
  }
}

class _MezzoCard extends StatelessWidget {
  const _MezzoCard({
    required this.mezzo,
    required this.selected,
    required this.canSelect,
    required this.inTrasferimento,
    required this.onToggle,
    required this.onApriInLogistica,
    this.onApriTrasferimenti,
    this.compact = false,
  });

  final MdoFerroviarioRiga mezzo;
  final bool selected;
  final bool canSelect;
  final bool inTrasferimento;
  final VoidCallback onToggle;
  final VoidCallback onApriInLogistica;
  final VoidCallback? onApriTrasferimenti;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
      elevation: 0,
      color: inTrasferimento
          ? CronosAppThemes.warnFillOf(context)
          : selected
              ? CronosAppThemes.selectedFillOf(context)
              : CronosAppThemes.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: inTrasferimento
              ? Colors.orange.shade200.withValues(
                  alpha: CronosAppThemes.isDarkOf(context) ? 0.45 : 1,
                )
              : selected
                  ? CronosAppThemes.selectedBorderOf(context)
                  : CronosAppThemes.hairlineOf(context),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canSelect ? onToggle : onApriTrasferimenti,
        onDoubleTap: onApriInLogistica,
        child: Tooltip(
          message: 'Doppio click: apri in Logistica MDO',
          waitDuration: const Duration(milliseconds: 700),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 6 : 8,
              compact ? 8 : 10,
              compact ? 10 : 12,
              compact ? 8 : 10,
            ),
            child: Row(
              children: [
                if (canSelect)
                  Checkbox(
                    value: selected,
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    onChanged: (_) => onToggle(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.local_shipping,
                      color: Colors.orange.shade800,
                      size: 20,
                    ),
                  ),
                Container(
                  width: compact ? 38 : 44,
                  height: compact ? 38 : 44,
                  decoration: BoxDecoration(
                    color: CronosAppThemes.selectedFillOf(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.train,
                    color: Colors.blue.shade800,
                    size: compact ? 20 : 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mezzo.titolo,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 13 : 14,
                        ),
                      ),
                      if (mezzo.sottotitolo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          mezzo.sottotitolo,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 11 : 12,
                            color: CronosAppThemes.mutedOf(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (mezzo.matricolaInterna.isNotEmpty)
                            _chip(mezzo.matricolaInterna, Colors.indigo),
                          if (mezzo.cantiereAttuale.isNotEmpty)
                            _chip(
                              'Cantiere: ${mezzo.cantiereAttuale}',
                              Colors.teal,
                            ),
                          if (mezzo.posizioneGps != null)
                            _chip('GPS', Colors.deepOrange),
                          if (inTrasferimento)
                            _chip('In trasferimento', Colors.orange),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color.shade900,
        ),
      ),
    );
  }
}

class _TrasferimentoCard extends StatelessWidget {
  const _TrasferimentoCard({
    required this.t,
    required this.dateFmt,
    required this.canEdit,
    required this.onModifica,
    required this.onAnnulla,
    required this.onConferma,
    this.compact = false,
  });

  final MdoTrasferimento t;
  final DateFormat dateFmt;
  final bool canEdit;
  final VoidCallback onModifica;
  final VoidCallback onAnnulla;
  final VoidCallback onConferma;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final note = (t.note ?? '').trim();
    final trasportatore = (t.trasportatore ?? '').trim();
    final refCarico = (t.referenteCaricoNome ?? '').trim();
    final telCarico = (t.referenteCaricoTelefono ?? '').trim();
    final refScarico = (t.referenteScaricoNome ?? '').trim();
    final telScarico = (t.referenteScaricoTelefono ?? '').trim();
    return Card(
      margin: EdgeInsets.only(bottom: compact ? 6 : 6),
      elevation: 0,
      color: CronosAppThemes.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.orange.shade200.withValues(
            alpha: CronosAppThemes.isDarkOf(context) ? 0.45 : 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 10,
          compact ? 8 : 8,
          compact ? 8 : 10,
          compact ? 8 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 30 : 34,
                  height: compact ? 30 : 34,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    size: compact ? 16 : 18,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.mdoLabel.isEmpty ? t.matricolaInterna : t.mdoLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 12.5 : 13,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${t.commessaOrigine.isEmpty ? 'Senza commessa' : t.commessaOrigine}'
                        '  →  ${t.commessaDestinazione}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: CronosAppThemes.onSurfaceOf(context),
                          fontSize: compact ? 11 : 12,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _infoChip(Icons.event, t.periodoLabel(dateFmt), Colors.indigo),
                          if (t.cantiereDestinazione != null &&
                              t.cantiereDestinazione!.isNotEmpty)
                            _infoChip(
                              Icons.place_outlined,
                              'Cantiere dest.: ${t.cantiereDestinazione}',
                              Colors.teal,
                            ),
                          if (t.cantiereOrigine.isNotEmpty)
                            _infoChip(
                              Icons.home_work_outlined,
                              'Da cantiere: ${t.cantiereOrigine}',
                              Colors.blueGrey,
                            ),
                          if (refCarico.isNotEmpty)
                            _infoChip(
                              Icons.person_outline,
                              telCarico.isEmpty
                                  ? 'Ref. carico: $refCarico'
                                  : 'Ref. carico: $refCarico · $telCarico',
                              Colors.deepPurple,
                            ),
                          if (refScarico.isNotEmpty)
                            _infoChip(
                              Icons.person_pin_outlined,
                              telScarico.isEmpty
                                  ? 'Ref. scarico: $refScarico'
                                  : 'Ref. scarico: $refScarico · $telScarico',
                              Colors.purple,
                            ),
                        ],
                      ),
                      if (trasportatore.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: CronosAppThemes.warnFillOf(context),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.local_shipping_outlined,
                                size: 14,
                                color: Colors.orange.shade900,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'TRASPORTATORE $trasportatore',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.sticky_note_2_outlined,
                                size: 14,
                                color: Colors.amber.shade900,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.brown.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onModifica,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Modifica', style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAnnulla,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Annulla', style: TextStyle(fontSize: 12)),
                  ),
                  FilledButton.icon(
                    onPressed: onConferma,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      compact ? 'Conferma' : 'Conferma arrivo',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.shade800),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrasferimentoFormEsito {
  const _TrasferimentoFormEsito({
    required this.commessa,
    required this.cantiere,
    required this.aggiornaCantiere,
    required this.periodoTipo,
    required this.dataRiferimento,
    this.note,
    this.trasportatore,
    this.referenteCaricoPersonaleUuid,
    this.referenteCaricoNome,
    this.referenteCaricoTelefono,
    this.referenteScaricoPersonaleUuid,
    this.referenteScaricoNome,
    this.referenteScaricoTelefono,
    this.luogoCarico,
    this.luogoScarico,
    this.modalitaCarico,
    this.modalitaScarico,
  });

  final String commessa;
  final String cantiere;
  final bool aggiornaCantiere;
  /// `giorno` | `settimana`
  final String periodoTipo;
  final DateTime dataRiferimento;
  final String? note;
  final String? trasportatore;
  final String? referenteCaricoPersonaleUuid;
  final String? referenteCaricoNome;
  final String? referenteCaricoTelefono;
  final String? referenteScaricoPersonaleUuid;
  final String? referenteScaricoNome;
  final String? referenteScaricoTelefono;
  final String? luogoCarico;
  final String? luogoScarico;
  final String? modalitaCarico;
  final String? modalitaScarico;
}

class _TrasferimentoFormDialog extends StatefulWidget {
  const _TrasferimentoFormDialog({
    required this.title,
    required this.confirmLabel,
    required this.mezziLabels,
    required this.commesseNomi,
    required this.commessaOrigine,
    this.initialCommessa = '',
    this.initialCantiere = '',
    this.initialAggiornaCantiere = true,
    this.initialPeriodoTipo = 'giorno',
    this.initialData,
    this.initialNote = '',
    this.initialTrasportatore = '',
    this.initialReferenteCaricoUuid,
    this.initialReferenteCaricoNome,
    this.initialReferenteCaricoTelefono,
    this.initialReferenteScaricoUuid,
    this.initialReferenteScaricoNome,
    this.initialReferenteScaricoTelefono,
    this.initialLuogoCarico = '',
    this.initialLuogoScarico = '',
    this.initialModalitaCarico,
    this.initialModalitaScarico,
  });

  final String title;
  final String confirmLabel;
  final List<String> mezziLabels;
  final List<String> commesseNomi;
  final String commessaOrigine;
  final String initialCommessa;
  final String initialCantiere;
  final bool initialAggiornaCantiere;
  final String initialPeriodoTipo;
  final DateTime? initialData;
  final String initialNote;
  final String initialTrasportatore;
  final String? initialReferenteCaricoUuid;
  final String? initialReferenteCaricoNome;
  final String? initialReferenteCaricoTelefono;
  final String? initialReferenteScaricoUuid;
  final String? initialReferenteScaricoNome;
  final String? initialReferenteScaricoTelefono;
  final String initialLuogoCarico;
  final String initialLuogoScarico;
  final String? initialModalitaCarico;
  final String? initialModalitaScarico;

  @override
  State<_TrasferimentoFormDialog> createState() =>
      _TrasferimentoFormDialogState();
}

class _TrasferimentoFormDialogState extends State<_TrasferimentoFormDialog> {
  late final TextEditingController _commessaCtrl;
  late final TextEditingController _cantiereCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _trasportatoreCtrl;
  late final TextEditingController _luogoCaricoCtrl;
  late final TextEditingController _luogoScaricoCtrl;
  late final TextEditingController _nomeCaricoCtrl;
  late final TextEditingController _nomeScaricoCtrl;
  late final TextEditingController _telCaricoCtrl;
  late final TextEditingController _telScaricoCtrl;
  late bool _aggiornaCantiere;
  late String _periodoTipo;
  late DateTime _dataRif;
  final _dateFmt = DateFormat('dd/MM/yyyy');

  List<PersonaleReferentePick> _personale = const [];
  bool _loadingPersonale = true;
  String? _refCaricoUuid;
  String? _refScaricoUuid;
  String? _modalitaCarico;
  String? _modalitaScarico;

  static const _modalitaItems = <({String value, String label})>[
    (value: 'piano_a_raso', label: 'Piano a raso'),
    (value: 'gru', label: 'Gru'),
  ];

  @override
  void initState() {
    super.initState();
    _commessaCtrl = TextEditingController(text: widget.initialCommessa);
    _cantiereCtrl = TextEditingController(text: widget.initialCantiere);
    _noteCtrl = TextEditingController(text: widget.initialNote);
    _trasportatoreCtrl =
        TextEditingController(text: widget.initialTrasportatore);
    _luogoCaricoCtrl = TextEditingController(text: widget.initialLuogoCarico);
    _luogoScaricoCtrl = TextEditingController(text: widget.initialLuogoScarico);
    _nomeCaricoCtrl =
        TextEditingController(text: widget.initialReferenteCaricoNome ?? '');
    _nomeScaricoCtrl =
        TextEditingController(text: widget.initialReferenteScaricoNome ?? '');
    _telCaricoCtrl =
        TextEditingController(text: widget.initialReferenteCaricoTelefono ?? '');
    _telScaricoCtrl = TextEditingController(
      text: widget.initialReferenteScaricoTelefono ?? '',
    );
    _aggiornaCantiere = widget.initialAggiornaCantiere;
    _periodoTipo =
        widget.initialPeriodoTipo == 'settimana' ? 'settimana' : 'giorno';
    _dataRif = DislocazioneMdoPerCommessaService.dateOnly(
      widget.initialData ?? DateTime.now(),
    );
    _refCaricoUuid = widget.initialReferenteCaricoUuid;
    _refScaricoUuid = widget.initialReferenteScaricoUuid;
    _modalitaCarico = widget.initialModalitaCarico;
    _modalitaScarico = widget.initialModalitaScarico;
    unawaited(_loadPersonale());
  }

  Future<void> _loadPersonale() async {
    try {
      final list =
          await DislocazioneMdoPerCommessaService.loadPersonaleReferenti();
      if (!mounted) return;
      PersonaleReferentePick? findByUuid(String? id) {
        final k = (id ?? '').trim();
        if (k.isEmpty) return null;
        for (final p in list) {
          if (p.idUuid == k) return p;
        }
        return null;
      }

      PersonaleReferentePick? findByName(String? name) {
        final n = (name ?? '').trim().toLowerCase();
        if (n.isEmpty) return null;
        for (final p in list) {
          if (p.fullName.trim().toLowerCase() == n) return p;
        }
        return null;
      }

      setState(() {
        _personale = list;
        final carico = findByUuid(widget.initialReferenteCaricoUuid) ??
            findByName(widget.initialReferenteCaricoNome);
        final scarico = findByUuid(widget.initialReferenteScaricoUuid) ??
            findByName(widget.initialReferenteScaricoNome);
        if (carico != null) {
          _refCaricoUuid = carico.idUuid;
          if (_nomeCaricoCtrl.text.trim().isEmpty) {
            _nomeCaricoCtrl.text = carico.fullName;
          }
          if (_telCaricoCtrl.text.trim().isEmpty) {
            _telCaricoCtrl.text = carico.telefono;
          }
        }
        if (scarico != null) {
          _refScaricoUuid = scarico.idUuid;
          if (_nomeScaricoCtrl.text.trim().isEmpty) {
            _nomeScaricoCtrl.text = scarico.fullName;
          }
          if (_telScaricoCtrl.text.trim().isEmpty) {
            _telScaricoCtrl.text = scarico.telefono;
          }
        }
        _loadingPersonale = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPersonale = false);
    }
  }

  @override
  void dispose() {
    _commessaCtrl.dispose();
    _cantiereCtrl.dispose();
    _noteCtrl.dispose();
    _trasportatoreCtrl.dispose();
    _luogoCaricoCtrl.dispose();
    _luogoScaricoCtrl.dispose();
    _nomeCaricoCtrl.dispose();
    _nomeScaricoCtrl.dispose();
    _telCaricoCtrl.dispose();
    _telScaricoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataRif,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: _periodoTipo == 'settimana'
          ? 'Scegli un giorno della settimana di trasferimento'
          : 'Giorno di trasferimento',
    );
    if (picked == null) return;
    setState(() {
      _dataRif = DislocazioneMdoPerCommessaService.dateOnly(picked);
    });
  }

  String get _periodoPreview {
    final p = DislocazioneMdoPerCommessaService.resolvePeriodo(
      periodoTipo: _periodoTipo,
      riferimento: _dataRif,
    );
    if (_periodoTipo == 'settimana') {
      return 'Settimana ${_dateFmt.format(p.inizio)} – ${_dateFmt.format(p.fine)}';
    }
    return 'Giorno ${_dateFmt.format(p.inizio)}';
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: CronosAppThemes.onSurfaceOf(context),
          ),
        ),
      );

  Widget _referenteField({
    required String label,
    required TextEditingController nomeCtrl,
    required String? selectedUuid,
    required ValueChanged<String?> onUuidChanged,
    required ValueChanged<String> onPhoneFromPick,
  }) {
    return Autocomplete<PersonaleReferentePick>(
      initialValue: TextEditingValue(text: nomeCtrl.text),
      displayStringForOption: (p) => p.label,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return _personale.take(40);
        return _personale.where((p) {
          return p.fullName.toLowerCase().contains(q) ||
              p.telefono.contains(q);
        }).take(40);
      },
      onSelected: (p) {
        nomeCtrl.text = p.fullName;
        onUuidChanged(p.idUuid);
        onPhoneFromPick(p.telefono);
      },
      fieldViewBuilder: (context, textCtrl, focus, onSubmit) {
        return TextField(
          controller: textCtrl,
          focusNode: focus,
          onChanged: (v) {
            nomeCtrl.text = v;
            PersonaleReferentePick? match;
            final key = v.trim().toLowerCase();
            if (key.isNotEmpty) {
              for (final p in _personale) {
                if (p.fullName.trim().toLowerCase() == key) {
                  match = p;
                  break;
                }
              }
            }
            onUuidChanged(match?.idUuid);
            if (match != null && match.telefono.isNotEmpty) {
              onPhoneFromPick(match.telefono);
            }
          },
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Cerca in elenco o digita un nome…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: Icon(
              selectedUuid != null
                  ? Icons.badge_outlined
                  : Icons.edit_outlined,
              size: 20,
              color: selectedUuid != null
                  ? Colors.teal.shade700
                  : CronosAppThemes.mutedOf(context),
            ),
          ),
        );
      },
    );
  }

  Widget _modalitaDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = value == 'piano_a_raso' || value == 'gru' ? value : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label|$selected'),
      initialValue: selected,
      items: [
        for (final m in _modalitaItems)
          DropdownMenuItem(value: m.value, child: Text(m.label)),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width;
    final dialogW = maxW < 560 ? maxW - 32 : 520.0;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Da: ${widget.commessaOrigine.isEmpty ? 'Senza commessa' : widget.commessaOrigine}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: CronosAppThemes.onSurfaceOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.mezziLabels.length} '
                '${widget.mezziLabels.length == 1 ? 'mezzo' : 'mezzi'}:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CronosAppThemes.cardMutedOf(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final label in widget.mezziLabels)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $label', style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              _sectionTitle('Periodo trasferimento'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'giorno',
                    label: Text('Giorno singolo'),
                    icon: Icon(Icons.today, size: 16),
                  ),
                  ButtonSegment(
                    value: 'settimana',
                    label: Text('Intera settimana'),
                    icon: Icon(Icons.date_range, size: 16),
                  ),
                ],
                selected: {_periodoTipo},
                onSelectionChanged: (s) => setState(() => _periodoTipo = s.first),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(_periodoPreview),
              ),
              _sectionTitle('Destinazione'),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _commessaCtrl.text),
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  if (q.isEmpty) return widget.commesseNomi;
                  return widget.commesseNomi
                      .where((e) => e.toLowerCase().contains(q));
                },
                onSelected: (v) => _commessaCtrl.text = v,
                fieldViewBuilder: (context, textCtrl, focus, onSubmit) {
                  return TextField(
                    controller: textCtrl,
                    focusNode: focus,
                    onChanged: (v) => _commessaCtrl.text = v,
                    onSubmitted: (_) => onSubmit(),
                    decoration: const InputDecoration(
                      labelText: 'Nuova commessa *',
                      hintText: 'Es. TE-10-28 …',
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aggiorna anche cantiere attuale'),
                value: _aggiornaCantiere,
                onChanged: (v) => setState(() => _aggiornaCantiere = v),
              ),
              if (_aggiornaCantiere)
                TextField(
                  controller: _cantiereCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nuovo cantiere',
                    border: OutlineInputBorder(),
                  ),
                ),
              _sectionTitle('Carico / scarico'),
              if (_loadingPersonale)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _referenteField(
                  label: 'Referente carico',
                  nomeCtrl: _nomeCaricoCtrl,
                  selectedUuid: _refCaricoUuid,
                  onUuidChanged: (id) => setState(() => _refCaricoUuid = id),
                  onPhoneFromPick: (tel) =>
                      setState(() => _telCaricoCtrl.text = tel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _telCaricoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono referente carico',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _luogoCaricoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Luogo di carico',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                _modalitaDropdown(
                  label: 'Modalità di carico',
                  value: _modalitaCarico,
                  onChanged: (v) => setState(() => _modalitaCarico = v),
                ),
                const SizedBox(height: 14),
                _referenteField(
                  label: 'Referente scarico',
                  nomeCtrl: _nomeScaricoCtrl,
                  selectedUuid: _refScaricoUuid,
                  onUuidChanged: (id) => setState(() => _refScaricoUuid = id),
                  onPhoneFromPick: (tel) =>
                      setState(() => _telScaricoCtrl.text = tel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _telScaricoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono referente scarico',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _luogoScaricoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Luogo di scarico',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                _modalitaDropdown(
                  label: 'Modalità di scarico',
                  value: _modalitaScarico,
                  onChanged: (v) => setState(() => _modalitaScarico = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _trasportatoreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Trasportatore',
                  hintText: 'Es. GEOTRASPORTI, GRUBER…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (opzionale)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La dislocazione del mezzo si aggiorna solo dopo «Conferma arrivo».',
                style: TextStyle(fontSize: 12, color: CronosAppThemes.mutedOf(context)),
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
        FilledButton.icon(
          onPressed: () {
            final dest = _commessaCtrl.text.trim();
            if (dest.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Indica la commessa di destinazione.')),
              );
              return;
            }
            Navigator.pop(
              context,
              _TrasferimentoFormEsito(
                commessa: dest,
                cantiere: _cantiereCtrl.text.trim(),
                aggiornaCantiere: _aggiornaCantiere,
                periodoTipo: _periodoTipo,
                dataRiferimento: _dataRif,
                note: _noteCtrl.text.trim(),
                trasportatore: _trasportatoreCtrl.text.trim(),
                referenteCaricoPersonaleUuid: _refCaricoUuid,
                referenteCaricoNome: _nomeCaricoCtrl.text.trim(),
                referenteCaricoTelefono: _telCaricoCtrl.text.trim(),
                referenteScaricoPersonaleUuid: _refScaricoUuid,
                referenteScaricoNome: _nomeScaricoCtrl.text.trim(),
                referenteScaricoTelefono: _telScaricoCtrl.text.trim(),
                luogoCarico: _luogoCaricoCtrl.text.trim(),
                luogoScarico: _luogoScaricoCtrl.text.trim(),
                modalitaCarico: _modalitaCarico,
                modalitaScarico: _modalitaScarico,
              ),
            );
          },
          icon: const Icon(Icons.swap_horiz),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
