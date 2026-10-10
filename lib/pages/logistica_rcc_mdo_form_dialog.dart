import 'dart:async';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/logistica_assignee_at_date.dart';
import '../services/mdo_rifornimento_service.dart';
import '../services/mezzi_km_service.dart';
import '../services/qt_carburante_fatturazione_parser.dart';
import '../services/qt_multicard_storico_assignee.dart';
import '../utils/carburante_euro_litro_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/logistica_multicard_mezzo_sync.dart';
import '../utils/modify_feedback.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/pernottamento_commessa_suggest_dialog.dart';
import '../utils/dt_user_list.dart';
import '../utils/rcc_mdo_destinations.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';

const _tipiCarburanteMdo = ['Gasolio', 'HVO', 'Benzina', 'AdBlue'];

class MdoUserPick {
  final String uuid;
  final String label;
  const MdoUserPick({required this.uuid, required this.label});
}

class _DestEntry {
  final TextEditingController mezzoCtrl = TextEditingController();
  final TextEditingController litriCtrl = TextEditingController();

  void dispose() {
    mezzoCtrl.dispose();
    litriCtrl.dispose();
  }
}

/// Form «Nuovo / Modifica rifornimento MDO» (dipendente e logistica).
class MdoRccFormDialog extends StatefulWidget {
  final SupabaseClient supa;
  final bool dipendenteMode;
  final String myUserUuid;
  final String myDisplayName;
  final String myNameNorm;
  final List<MdoUserPick> userPicks;
  final String? lockDtUuid;
  final List<String> allowedDtUuids;
  final String? initialDtUuid;
  final bool viewOnly;
  final Map<String, dynamic>? existing;

  const MdoRccFormDialog({
    super.key,
    required this.supa,
    required this.dipendenteMode,
    required this.myUserUuid,
    required this.myDisplayName,
    required this.myNameNorm,
    required this.userPicks,
    this.lockDtUuid,
    this.allowedDtUuids = const <String>[],
    this.initialDtUuid,
    this.viewOnly = false,
    this.existing,
  });

  @override
  State<MdoRccFormDialog> createState() => _MdoRccFormDialogState();
}

class _MdoRccFormDialogState extends State<MdoRccFormDialog> {
  final _dataCtrl = TextEditingController();
  final _litriCtrl = TextEditingController();
  final _euroCtrl = TextEditingController();
  bool _saving = false;
  bool _loadingRefs = true;
  String? _selUserUuid;
  String? _selMulticard;
  String? _selCommessaUuid;
  String? _selDtUuid;
  String? _selTipoCarburante;
  final List<Map<String, dynamic>> _mdoFerroviari = <Map<String, dynamic>>[];
  final Map<String, String> _mdoLabelById = <String, String>{};
  final Map<String, String> _labelToMdoId = <String, String>{};
  final List<String> _mdoSuggestions = <String>[];
  final List<Map<String, dynamic>> _multicards = <Map<String, dynamic>>[];
  List<QtMulticardAssigneeProfile> _multicardProfiles =
      const <QtMulticardAssigneeProfile>[];
  final Map<String, String> _commesseByUuid = <String, String>{};
  final Map<String, String> _dtLabelsByUuid = <String, String>{};
  final List<_DestEntry> _destinations = <_DestEntry>[];
  String? _suggestedCommessaUuid;
  bool _loadingSuggestion = false;
  bool _suggestionDismissed = false;
  String? _suggestionDismissedForIso;

  bool get _isEdit => widget.existing != null;
  bool get _isAdmin => !widget.dipendenteMode;

  bool get _readOnly =>
      widget.viewOnly ||
      (widget.existing != null &&
          isMdoRifornimentoLockedForDipendente(
            widget.existing!,
            dipendenteMode: widget.dipendenteMode,
          ));

  bool get _lockedAsComplete =>
      !_isAdmin &&
      widget.existing != null &&
      isMdoRifornimentoLockedForDipendente(
        widget.existing!,
        dipendenteMode: widget.dipendenteMode,
      );

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _dataCtrl.text = formatDateDdMmYyyy(ex['data_rifornimento']);
      _litriCtrl.text = (ex['litri'] ?? '').toString();
      _euroCtrl.text = (ex['euro'] ?? '').toString();
      _selUserUuid = (ex['user_uuid'] ?? '').toString().trim();
      _selMulticard = (ex['n_carta_carburante'] ?? '').toString().trim();
      _selDtUuid = (ex['dt_user_uuid'] ?? '').toString().trim();
      final tipo = (ex['tipo_carburante'] ?? '').toString().trim();
      if (tipo.isNotEmpty && _tipiCarburanteMdo.contains(tipo)) {
        _selTipoCarburante = tipo;
      }
      final commUuid = (ex['commessa_uuid'] ?? '').toString().trim();
      if (commUuid.isNotEmpty) {
        _selCommessaUuid = commUuid;
      } else {
        final cantiere = (ex['cantiere'] ?? '').toString().trim();
        if (cantiere.isNotEmpty) _selCommessaUuid = cantiere;
      }
      for (final d in parseMdoDestinationsFromRow(ex)) {
        final e = _DestEntry();
        e.mezzoCtrl.text = d.mezzo;
        e.litriCtrl.text = _fmtNum(d.litri);
        _destinations.add(e);
      }
    } else {
      _dataCtrl.text = formatDateDdMmYyyyFromDate(DateTime.now());
      _selUserUuid = widget.myUserUuid;
      final lockedDt = (widget.lockDtUuid ?? '').trim();
      if (lockedDt.isNotEmpty) {
        _selDtUuid = lockedDt;
      } else {
        final initial = (widget.initialDtUuid ?? '').trim();
        if (initial.isNotEmpty) _selDtUuid = initial;
      }
      _addDestinationRow();
    }
    if (_destinations.isEmpty) _addDestinationRow();
    unawaited(_loadRefs());
  }

  @override
  void dispose() {
    _dataCtrl.dispose();
    _litriCtrl.dispose();
    _euroCtrl.dispose();
    for (final d in _destinations) {
      d.dispose();
    }
    super.dispose();
  }

  void _addDestinationRow() {
    setState(() => _destinations.add(_DestEntry()));
  }

  void _removeDestinationRow(int index) {
    if (_destinations.length <= 1) return;
    setState(() {
      _destinations[index].dispose();
      _destinations.removeAt(index);
    });
  }

  String _ownerUuid() =>
      widget.dipendenteMode ? widget.myUserUuid : (_selUserUuid ?? '').trim();

  Future<void> _loadRefs() async {
    try {
      final mdoRes = await widget.supa
          .from('logistica_mdo_ferroviari')
          .select(
              'id_uuid,codice_identificativo_targa_rfi,matricola_interna,descrizione_mezzo,active')
          .eq('active', true)
          .order('descrizione_mezzo', ascending: true);
      _mdoFerroviari
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(
            (mdoRes as List).map((e) => Map<String, dynamic>.from(e as Map))));
      _mdoLabelById.clear();
      _labelToMdoId.clear();
      _mdoSuggestions.clear();
      for (final m in _mdoFerroviari) {
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final short = mdoMatricolaFromRecord(m);
        final label = formatMdoFerroviarioLabel(m);
        _mdoLabelById[id] = short.isNotEmpty ? short : label;
        if (short.isNotEmpty) {
          _labelToMdoId[short.toLowerCase()] = id;
          if (!_mdoSuggestions.contains(short)) _mdoSuggestions.add(short);
        }
        _labelToMdoId[label.toLowerCase()] = id;
      }
      for (final d in _destinations) {
        final t = d.mezzoCtrl.text.trim();
        if (t.isEmpty) continue;
        final mdoId = _labelToMdoId[t.toLowerCase()];
        if (mdoId != null) {
          for (final m in _mdoFerroviari) {
            if ((m['id_uuid'] ?? '').toString().trim() == mdoId) {
              d.mezzoCtrl.text = mdoMatricolaFromRecord(m);
              break;
            }
          }
        } else {
          d.mezzoCtrl.text = mdoExtractMatricolaCode(t);
        }
      }

      final cardRes = await widget.supa
          .from('logistica_multicard')
          .select('id_uuid,multicard,assegnatario_attuale,assegnatario_user_uuid')
          .order('multicard', ascending: true);
      _multicards
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(
            (cardRes as List).map((e) => Map<String, dynamic>.from(e as Map))));
      _multicardProfiles =
          await QtMulticardStoricoAssigneeLoader.load(widget.supa);

      final commRes =
          await widget.supa.from('commesse').select('id_uuid,nome').order('nome', ascending: true);
      for (final e in (commRes as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id_uuid'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        _commesseByUuid[id] =
            (m['nome'] ?? '').toString().trim().isEmpty ? id : (m['nome'] ?? '').toString().trim();
      }
      final ex = widget.existing;
      if (ex != null) {
        final exComm = (ex['commessa_uuid'] ?? '').toString().trim();
        if (exComm.isNotEmpty && _commesseByUuid.containsKey(exComm)) {
          _selCommessaUuid = exComm;
        }
      }

      final allowed = widget.allowedDtUuids
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (allowed.isEmpty) {
        _dtLabelsByUuid.addAll(await loadDtOptionsByUuid());
      } else {
        final dtRes = await widget.supa
            .from('users')
            .select('id_uuid,full_name,username')
            .inFilter('id_uuid', allowed.toList());
        for (final e in (dtRes as List)) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = (m['id_uuid'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          final full = (m['full_name'] ?? '').toString().trim();
          final user = (m['username'] ?? '').toString().trim();
          _dtLabelsByUuid[id] =
              full.isNotEmpty ? full : (user.isNotEmpty ? user : id);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    final lockedDt = (widget.lockDtUuid ?? '').trim();
    if (lockedDt.isNotEmpty && _dtLabelsByUuid.containsKey(lockedDt)) {
      _selDtUuid = lockedDt;
    } else if ((_selDtUuid ?? '').trim().isEmpty && _dtLabelsByUuid.isNotEmpty) {
      final initial = (widget.initialDtUuid ?? '').trim();
      if (initial.isNotEmpty && _dtLabelsByUuid.containsKey(initial)) {
        _selDtUuid = initial;
      } else {
        _selDtUuid = _dtLabelsByUuid.keys.first;
      }
    } else if ((_selDtUuid ?? '').trim().isNotEmpty &&
        !_dtLabelsByUuid.containsKey(_selDtUuid)) {
      _selDtUuid = _dtLabelsByUuid.isEmpty ? null : _dtLabelsByUuid.keys.first;
    }
    setState(() => _loadingRefs = false);
    if (!_readOnly) unawaited(_loadCommessaSuggestion());
  }

  Future<void> _loadCommessaSuggestion() async {
    if (_readOnly) return;
    final iso = _isoDate();
    final owner = _ownerUuid();
    if ((iso ?? '').isEmpty || owner.isEmpty) {
      if (!mounted) return;
      setState(() => _suggestedCommessaUuid = null);
      return;
    }
    if (_suggestionDismissedForIso != iso) {
      _suggestionDismissed = false;
      _suggestionDismissedForIso = iso;
    }
    setState(() => _loadingSuggestion = true);
    final sug = await suggestCommessaUuidFromPernottamento(
      supa: widget.supa,
      compilatoreUserUuid: owner,
      isoRefuelDate: iso!,
    );
    if (!mounted) return;
    setState(() {
      _loadingSuggestion = false;
      _suggestedCommessaUuid = sug;
    });
    await _maybeShowCommessaSuggestDialog();
  }

  Future<void> _maybeShowCommessaSuggestDialog() async {
    final sug = (_suggestedCommessaUuid ?? '').trim();
    if (sug.isEmpty || _suggestionDismissed) return;
    if (sug == (_selCommessaUuid ?? '').trim()) return;
    if ((_selCommessaUuid ?? '').trim().isNotEmpty) return;

    final label = _commesseByUuid[sug] ?? sug;
    final yes = await showPernottamentoCommessaSuggestDialog(
      context: context,
      dateLabel: _dataCtrl.text.trim(),
      commessaLabel: label,
    );
    if (!mounted) return;
    setState(() => _suggestionDismissed = true);
    if (yes == true && _commesseByUuid.containsKey(sug)) {
      setState(() => _selCommessaUuid = sug);
    }
  }

  void _onRefuelDateChanged() {
    setState(() {
      final cards = _multicardsForOwner()
          .map((m) => (m['multicard'] ?? '').toString().trim())
          .where((x) => x.isNotEmpty)
          .toSet();
      if (_selMulticard != null && !cards.contains(_selMulticard)) {
        _selMulticard = null;
      }
    });
    unawaited(_loadCommessaSuggestion());
  }

  String _normNameFromUser(String userUuid) {
    final u = widget.userPicks.where((x) => x.uuid == userUuid).toList();
    if (u.isEmpty) return '';
    return MezziKmService.normalizePersonName(u.first.label);
  }

  List<Map<String, dynamic>> _multicardsForOwner() {
    final uuid = _ownerUuid();
    final norm = widget.dipendenteMode ? widget.myNameNorm : _normNameFromUser(_selUserUuid ?? '');
    final iso = _isoDate();
    final refuelDate = iso != null ? DateTime.tryParse(iso) : null;

    return _multicards.where((r) {
      final mc = (r['multicard'] ?? '').toString().trim();
      if (mc.isEmpty) return false;
      if (isMulticardMdoAssignment((r['mezzo_targa'] ?? '').toString())) {
        return true;
      }

      if (refuelDate != null && norm.isNotEmpty) {
        final profile = QtMulticardStoricoAssigneeLoader.findProfile(
          QtCarburanteTrxRow.normCarta(mc),
          _multicardProfiles,
        );
        if (LogisticaAssigneeAtDate.wasMulticardAssigneeAtDate(
          profile: profile,
          date: refuelDate,
          nameNorm: norm,
          userUuid: uuid,
          multicardRow: r,
        )) {
          return true;
        }
      }

      final au = (r['assegnatario_user_uuid'] ?? '').toString().trim();
      final an = MezziKmService.normalizePersonName((r['assegnatario_attuale'] ?? '').toString());
      if (uuid.isNotEmpty && au == uuid) return true;
      if (norm.isNotEmpty && an == norm) return true;
      return false;
    }).toList(growable: false);
  }

  String? _isoDate() => parseFlexibleDateToIsoDate(_dataCtrl.text.trim());

  double? _dec(String raw) {
    var t = raw.trim().replaceAll(' ', '');
    if (t.isEmpty) return null;
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  double get _litriTotValue => _dec(_litriCtrl.text) ?? 0;

  double get _litriRifornitiValue =>
      sumMdoDestinationLitri(_collectDestinations());

  double get _litriDaRifornire => _litriTotValue - _litriRifornitiValue;

  void _onDestinationsChanged() => setState(() {});

  /// Ogni riga form = una voce in JSON (stesso mezzo ripetuto conserva 10 L e 15 L separati).
  List<MdoRifornimentoDest> _collectDestinations() {
    final raw = <MdoRifornimentoDest>[];
    for (final d in _destinations) {
      final mezzoInput = d.mezzoCtrl.text.trim();
      final litri = _dec(d.litriCtrl.text);
      if (mezzoInput.isEmpty || litri == null || litri <= 0) continue;
      final mdoId = _labelToMdoId[mezzoInput.toLowerCase()];
      var mezzo = mdoExtractMatricolaCode(mezzoInput);
      if (mdoId != null) {
        for (final m in _mdoFerroviari) {
          if ((m['id_uuid'] ?? '').toString().trim() == mdoId) {
            final short = mdoMatricolaFromRecord(m);
            if (short.isNotEmpty) mezzo = short;
            break;
          }
        }
      }
      raw.add(MdoRifornimentoDest(
        mezzo: mezzo,
        litri: litri,
        mdoIdUuid: mdoId,
      ));
    }
    return raw;
  }

  Future<void> _save() async {
    if (_readOnly) {
      ModifyFeedback.error(
        context,
        'Rifornimento completo: non modificabile in modalità dipendente.',
      );
      return;
    }
    if (!await ensureCanPersist(context)) return;
    final iso = _isoDate();
    if ((iso ?? '').isEmpty) {
      ModifyFeedback.error(context, 'Data non valida.');
      return;
    }
    final owner = _ownerUuid();
    if (owner.isEmpty) {
      ModifyFeedback.error(context, 'Selezionare il compilatore.');
      return;
    }
    final card = (_selMulticard ?? '').trim();
    if (card.isEmpty) {
      ModifyFeedback.error(context, 'Selezionare la multicard assegnata.');
      return;
    }
    final cardsOk = _multicardsForOwner()
        .map((m) => (m['multicard'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet();
    if (!cardsOk.contains(card)) {
      ModifyFeedback.error(
        context,
        'La multicard non è assegnata al compilatore per la data del rifornimento.',
      );
      return;
    }
    final dt = (_selDtUuid ?? '').trim();
    if (dt.isEmpty || !_dtLabelsByUuid.containsKey(dt)) {
      ModifyFeedback.error(context, 'Selezionare il DT.');
      return;
    }
    final allowedDt = widget.allowedDtUuids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (allowedDt.isNotEmpty && !allowedDt.contains(dt)) {
      ModifyFeedback.error(context, 'DT non autorizzato per questo assistente.');
      return;
    }

    final entries = _collectDestinations();
    if (entries.isEmpty) {
      ModifyFeedback.error(context, 'Aggiungere almeno un mezzo rifornito con litri > 0.');
      return;
    }

    final litriTot = _dec(_litriCtrl.text);
    if (litriTot == null || litriTot <= 0) {
      ModifyFeedback.error(context, 'Inserire i litri totali prelevati.');
      return;
    }

    final riforniti = sumMdoDestinationLitri(entries);
    if (riforniti > litriTot + 0.001) {
      ModifyFeedback.error(
        context,
        'Eccesso rifornito: la somma mezzi (${_fmtNum(riforniti)} L) supera i litri totali (${_fmtNum(litriTot)} L).',
      );
      return;
    }

    final euro = _dec(_euroCtrl.text);
    final commessaUuid = (_selCommessaUuid ?? '').trim();
    if (commessaUuid.isEmpty || !_commesseByUuid.containsKey(commessaUuid)) {
      ModifyFeedback.error(context, 'Selezionare la commessa.');
      return;
    }
    final tipo = (_selTipoCarburante ?? '').trim();
    if (tipo.isEmpty) {
      ModifyFeedback.error(context, 'Selezionare il tipo carburante.');
      return;
    }

    final blocked = await CarburanteEuroLitroGuard.confirmBlockIfNeeded(
      context: context,
      tipoCarburante: tipo,
      litri: litriTot,
      euro: euro,
    );
    if (blocked) return;

    final cantiere = _commesseByUuid[commessaUuid];
    final completo = isMdoRifornimentoComplete(
      litriTotali: litriTot,
      litriRiforniti: riforniti,
    );

    final first = entries.first;
    var targa = '';
    if (first.mdoIdUuid != null) {
      for (final m in _mdoFerroviari) {
        if ((m['id_uuid'] ?? '').toString() == first.mdoIdUuid) {
          targa = (m['codice_identificativo_targa_rfi'] ?? '').toString().trim();
          break;
        }
      }
    }

    final compName = widget.dipendenteMode
        ? widget.myDisplayName
        : (widget.userPicks.where((u) => u.uuid == owner).isEmpty
            ? owner
            : widget.userPicks.firstWhere((u) => u.uuid == owner).label);

    final payload = <String, dynamic>{
      'user_uuid': owner,
      'data_rifornimento': iso,
      'n_carta_carburante': card,
      'litri': litriTot,
      'euro': euro,
      'tipo_carburante': tipo,
      'dt_user_uuid': dt,
      'nome_cognome': compName,
      'mezzi_riforniti_json': mdoDestinationsToJsonList(entries),
      'automezzo_mdo': first.mezzo,
      'targa_matricola': targa.isEmpty ? null : targa,
      'mezzo_stradale_id_uuid': null,
      'firma_compilatore': null,
      'commessa_uuid': commessaUuid,
      'cantiere': cantiere,
      'rifornimento_completo': completo,
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.supa
            .from('logistica_rcc_mdo_carburante')
            .update(payload)
            .eq('id_uuid', widget.existing!['id_uuid']);
      } else {
        await widget.supa.from('logistica_rcc_mdo_carburante').insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Salvataggio fallito: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildMezzoRow(int idx) {
    final d = _destinations[idx];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Autocomplete<String>(
              optionsBuilder: (text) {
                final q = text.text.trim().toLowerCase();
                if (q.isEmpty) return _mdoSuggestions.take(40);
                return _mdoSuggestions.where((o) => o.toLowerCase().contains(q)).take(40);
              },
              onSelected: _readOnly
                  ? null
                  : (v) {
                      d.mezzoCtrl.text = v;
                      _onDestinationsChanged();
                    },
              fieldViewBuilder: (context, textCtrl, focusNode, _) {
                if (textCtrl.text != d.mezzoCtrl.text) {
                  textCtrl.text = d.mezzoCtrl.text;
                }
                return TextField(
                  controller: textCtrl,
                  focusNode: focusNode,
                  readOnly: _readOnly,
                  onChanged: _readOnly
                      ? null
                      : (v) {
                          d.mezzoCtrl.text = v;
                          _onDestinationsChanged();
                        },
                  decoration: InputDecoration(
                    labelText: idx == 0 ? 'Mezzo (ferroviario o esterno)' : 'Mezzo',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: d.litriCtrl,
              readOnly: _readOnly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: _readOnly ? null : (_) => _onDestinationsChanged(),
              decoration: const InputDecoration(
                labelText: 'Litri',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Rimuovi mezzo',
            onPressed: _readOnly || _destinations.length <= 1
                ? null
                : () => _removeDestinationRow(idx),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBox() {
    final manca = _litriDaRifornire;
    final excess = manca < -0.001;
    final mancaLabel = excess ? 'Eccesso rifornito' : 'Manca da rifornire';
    final mancaValue = excess ? -manca : manca;
    final mancaColor = excess ? Colors.red.shade700 : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Totale rifornito: ${_fmtNum(_litriRifornitiValue)} L',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$mancaLabel: ${_fmtNum(mancaValue)} L',
            style: TextStyle(color: mancaColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = _multicardsForOwner()
        .map((m) => (m['multicard'] ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final dtIds = _dtLabelsByUuid.keys.toList()
      ..sort((a, b) => (_dtLabelsByUuid[a] ?? '').compareTo(_dtLabelsByUuid[b] ?? ''));

    return AlertDialog(
      title: Text(
        _lockedAsComplete
            ? 'Rifornimento MDO (sola lettura)'
            : widget.viewOnly
                ? 'Rifornimento MDO (visualizzazione)'
                : (_isEdit ? 'Modifica rifornimento MDO' : 'Nuovo rifornimento MDO'),
      ),
      content: SizedBox(
        width: 500,
        child: _loadingRefs
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_lockedAsComplete)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Rifornimento completo (manca da rifornire = 0). '
                          'Non è più modificabile; contattare la logistica per correzioni.',
                          style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600),
                        ),
                      )
                    else if (widget.viewOnly)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Sola lettura.',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (_isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownSearch<String>(
                          items: widget.userPicks.map((u) => u.uuid).toList(),
                          selectedItem: _selUserUuid,
                          itemAsString: (id) {
                            final x = widget.userPicks.where((u) => u.uuid == id).toList();
                            return x.isEmpty ? id : x.first.label;
                          },
                          popupProps: const PopupProps.menu(showSearchBox: true, fit: FlexFit.loose),
                          dropdownDecoratorProps: const DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              labelText: 'Compilatore',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          onChanged: _readOnly
                              ? null
                              : (v) {
                                    setState(() {
                                      _selUserUuid = v;
                                      _selMulticard = null;
                                    });
                                    unawaited(_loadCommessaSuggestion());
                                  },
                        ),
                      ),
                    TextField(
                      controller: _dataCtrl,
                      readOnly: true,
                      onTap: _readOnly
                          ? null
                          : () async {
                              final initial = DateTime.tryParse(_isoDate() ?? '') ?? DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: DateTime(2018),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                                locale: const Locale('it', 'IT'),
                              );
                              if (picked != null) {
                                setState(() {
                                  _dataCtrl.text = formatDateDdMmYyyyFromDate(picked);
                                });
                                _onRefuelDateChanged();
                              }
                            },
                      decoration: const InputDecoration(
                        labelText: 'Data rifornimento',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cards.contains(_selMulticard) ? _selMulticard : null,
                      items: cards
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: _readOnly ? null : (v) => setState(() => _selMulticard = v),
                      decoration: const InputDecoration(
                        labelText: 'Multicard assegnata',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: dtIds.contains(_selDtUuid) ? _selDtUuid : null,
                      items: dtIds
                          .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(_dtLabelsByUuid[id] ?? id),
                              ))
                          .toList(),
                      onChanged: (widget.lockDtUuid ?? '').trim().isNotEmpty
                          ? null
                          : (v) => setState(() => _selDtUuid = v),
                      decoration: const InputDecoration(
                        labelText: 'DT',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Mezzi riforniti',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _destinations.length; i++) _buildMezzoRow(i),
                    if (!_readOnly)
                      OutlinedButton.icon(
                        onPressed: _addDestinationRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Aggiungi mezzo'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _litriCtrl,
                      readOnly: _readOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: _readOnly ? null : (_) => _onDestinationsChanged(),
                      decoration: const InputDecoration(
                        labelText: 'Litri totali',
                        helperText: 'Allineato alla somma dei mezzi riforniti',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryBox(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _euroCtrl,
                      readOnly: _readOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Euro tot.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _tipiCarburanteMdo.contains(_selTipoCarburante)
                          ? _selTipoCarburante
                          : null,
                      items: _tipiCarburanteMdo
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: _readOnly
                          ? null
                          : (v) => setState(() => _selTipoCarburante = v),
                      decoration: const InputDecoration(
                        labelText: 'Tipo carburante',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (_loadingSuggestion)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    CommessaUuidAutocompleteField(
                      commesseByUuid: _commesseByUuid,
                      selectedUuid: _selCommessaUuid,
                      readOnly: _readOnly,
                      onSelected: (v) => setState(() => _selCommessaUuid = v),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        if (!_readOnly)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvataggio...' : 'Salva'),
          ),
      ],
    );
  }
}
