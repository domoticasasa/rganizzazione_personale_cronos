import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/neo_buttons.dart';
import '../utils/dt_user_list.dart';
import '../utils/travel_departure_guard.dart';
import '../utils/admin_vista_guard.dart';
import '../widgets/classic_app_bar_chrome.dart';

class RichiestaTrenoPage extends StatefulWidget {
  final int userId; // users.id (int)
  final String fullName;

  const RichiestaTrenoPage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<RichiestaTrenoPage> createState() => _RichiestaTrenoPageState();
}

class _RichiestaTrenoPageState extends State<RichiestaTrenoPage> {
  bool _busy = false;

  // miei identificativi
  String? _myPersonaleUuid;
  String? _myUserUuid; // users.id_uuid (uuid)

  // dizionari
  final List<String> _stazioni = [];
  final List<_DtUser> _dts = [];

  // form
  String? _stazionePartenza;
  String? _stazioneArrivo;
  String? _stazionePartenzaRitorno;
  String? _stazioneArrivoRitorno;
  DateTime _data = DateTime.now();
  String? _orarioHHmm;
  String _viaggioTipo = 'A'; // A | AR
  DateTime? _dataRitorno;
  String? _orarioRitornoHHmm;
  bool _ritornoDiverso = false;
  String? _selectedDtUuid;
  final _noteCtrl = TextEditingController();

  // controller visuali
  final _partenzaCtrl = TextEditingController();
  final _arrivoCtrl = TextEditingController();
  final _partenzaRitornoCtrl = TextEditingController();
  final _arrivoRitornoCtrl = TextEditingController();

  final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  bool _isUuid(String? v) => v != null && _uuidRe.hasMatch(v);

  int _compareTextAz(String a, String b) =>
      a.trim().toLowerCase().compareTo(b.trim().toLowerCase());

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _partenzaCtrl.dispose();
    _arrivoCtrl.dispose();
    _partenzaRitornoCtrl.dispose();
    _arrivoRitornoCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _busy = true);
    try {
      await _resolveMyUuids();
      await _loadStazioni();
      await _loadDTs();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveMyUuids() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    final authId = authUser.id;

    // users.id_uuid
    final u = await SupabaseService.client
        .from('users')
        .select('id_uuid')
        .eq('auth_id', authId)
        .maybeSingle();
    final uuid = (u?['id_uuid'] ?? '').toString().trim();
    if (_isUuid(uuid)) _myUserUuid = uuid;

    // personale.id_uuid collegato all'utente loggato
    final p1 = await SupabaseService.client
        .from('personale')
        .select('id_uuid, user_id')
        .eq('user_id', authId)
        .maybeSingle();
    if (p1 != null && (p1['id_uuid'] ?? '').toString().trim().isNotEmpty) {
      _myPersonaleUuid = (p1['id_uuid'] as String).trim();
      return;
    }

    // fallback: personale.user_id == users.id_uuid
    if (_myUserUuid != null) {
      final p2 = await SupabaseService.client
          .from('personale')
          .select('id_uuid')
          .eq('user_id', _myUserUuid!)
          .maybeSingle();
      if (p2 != null && (p2['id_uuid'] ?? '').toString().trim().isNotEmpty) {
        _myPersonaleUuid = (p2['id_uuid'] as String).trim();
      }
    }
  }

  Future<void> _loadStazioni() async {
    const pageSize = 1000;
    int from = 0;
    _stazioni.clear();
    while (true) {
      final page = await SupabaseService.client
          .from('stazioni')
          .select('nome, attiva')
          .eq('attiva', true)
          .order('nome', ascending: true)
          .range(from, from + pageSize - 1);
      final list = List<Map<String, dynamic>>.from(page as List);
      if (list.isEmpty) break;
      _stazioni.addAll(list.map((e) => (e['nome'] ?? '').toString()).where((s) => s.isNotEmpty));
      if (list.length < pageSize) break;
      from += pageSize;
    }
    _stazioni.sort(_compareTextAz);
  }

  Future<void> _loadDTs() async {
    final rows = await loadDtSelectableUserRows();
    _dts
      ..clear()
      ..addAll(rows.map((e) {
        final uuid = (e['id_uuid'] ?? '').toString();
        return _DtUser(
          uuid: uuid,
          label: dtUserDisplayLabel(e),
        );
      }).where((e) => _isUuid(e.uuid)))
      ..sort((a, b) => _compareTextAz(a.label, b.label));
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  String _isoDate(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _data = picked);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        _orarioHHmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickReturnDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataRitorno ?? _data,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _dataRitorno = picked);
  }

  Future<void> _pickReturnTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        _orarioRitornoHHmm =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  bool _validate() {
    if (!_isUuid(_myPersonaleUuid)) {
      _toast('Profilo non collegato a "personale".', error: true);
      return false;
    }
    if ((_stazionePartenza ?? '').trim().isEmpty ||
        (_stazioneArrivo ?? '').trim().isEmpty ||
        (_orarioHHmm ?? '').trim().isEmpty ||
        !_isUuid(_selectedDtUuid) ||
        !_isUuid(_myUserUuid)) {
      _toast('Compila tutti i campi obbligatori.', error: true);
      return false;
    }
    if (_stazionePartenza == _stazioneArrivo) {
      _toast('Partenza e arrivo devono essere diversi.', error: true);
      return false;
    }
    if (_viaggioTipo == 'AR') {
      if (_dataRitorno == null || (_orarioRitornoHHmm ?? '').trim().isEmpty) {
        _toast('Per A/R compila data e orario ritorno.', error: true);
        return false;
      }
      if ((_stazionePartenzaRitorno ?? '').trim().isEmpty ||
          (_stazioneArrivoRitorno ?? '').trim().isEmpty) {
        _toast('Compila anche stazioni di ritorno (Da/A).', error: true);
        return false;
      }
      if (_stazionePartenzaRitorno == _stazioneArrivoRitorno) {
        _toast('Stazioni di ritorno devono essere diverse.', error: true);
        return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (!await ensureCanPersist(context)) return;
    if (!_validate()) return;
    final pastMsg = pastTravelDepartureMessage(
      dataPartenza: _data,
      orarioPartenzaHHmm: _orarioHHmm!,
      dataRitorno: _dataRitorno,
      orarioRitornoHHmm: _orarioRitornoHHmm,
      andataRitorno: _viaggioTipo == 'AR',
      tipoViaggioLabel: 'biglietto treno',
    );
    if (pastMsg != null) {
      await showPastTravelDepartureDialog(context, pastMsg);
      return;
    }
    setState(() => _busy = true);
    try {
      final inserted = await SupabaseService.client.from('bookings_treno').insert({
        'personale_id': _myPersonaleUuid,
        'stazione_partenza': _stazionePartenza,
        'stazione_arrivo': _stazioneArrivo,
        'data': _isoDate(_data),
        'orario': _orarioHHmm,
        'viaggio_tipo': _viaggioTipo,
        'data_ritorno': _viaggioTipo == 'AR' ? _isoDate(_dataRitorno!) : null,
        'orario_ritorno': _viaggioTipo == 'AR' ? _orarioRitornoHHmm : null,
        // Ritorno: usa stazioni di ritorno selezionate (se vuote fallback inverso).
        'stazione_partenza_ritorno': _viaggioTipo == 'AR'
            ? (_stazionePartenzaRitorno ?? _stazioneArrivo)
            : null,
        'stazione_arrivo_ritorno': _viaggioTipo == 'AR'
            ? (_stazioneArrivoRitorno ?? _stazionePartenza)
            : null,
        // commessa la inserisce il DT in fase di conferma
        'commessa_id': null,
        'status': 'IN_ATTESA',
        // associare da subito al DT scelto (poi lui conferma/rifiuta)
        'dt_user_uuid': _selectedDtUuid,
        'assigned_dt_user_uuid': _selectedDtUuid,
        'requested_by_user_id': widget.userId,
        'workflow_status': 'INVIATA_AL_DT',
        'master_note': _noteCtrl.text.trim(),
        'updated_by': _myUserUuid, // creator = dipendente
      }).select('id').single();

      final newId = inserted['id'] != null ? int.tryParse(inserted['id'].toString()) : null;
      var successMsg = 'Richiesta treno inviata.';
      if (newId != null) {
        final dtRow = await SupabaseService.client
            .from('users')
            .select('id')
            .eq('id_uuid', _selectedDtUuid!)
            .maybeSingle();
        final dtId = dtRow?['id'] as int?;
        if (dtId != null) {
          try {
            final targets = await NotificationSender.targetsForRule(
              'request_to_dt',
              fallback: const ['selected_dt'],
            );
            final recipientIds = await NotificationSender.resolveRecipientsFromTargets(
              targets: targets,
              requesterUserId: widget.userId,
              selectedDtUuid: _selectedDtUuid,
              bookingId: newId,
              bookingType: 'treno',
            );
            var effectiveIds =
                recipientIds.isEmpty ? <int>[dtId] : List<int>.from(recipientIds);
            if (!effectiveIds.contains(dtId)) effectiveIds.add(dtId);
            await NotificationSender.sendToUserIds(
              userIds: effectiveIds,
              bookingId: newId,
              action: 'dt_approval_required',
              title: 'Richiesta treno',
              message:
                  '${widget.fullName} ha inviato una richiesta treno. Attende conferma DT.',
            );
            final who = await NotificationSender.recipientLabelsForUserIds(effectiveIds);
            successMsg = 'Richiesta treno inviata. Notifica inviata a: $who.';
          } catch (notifyErr) {
            // Non bloccare l'invio richiesta se fallisce solo la notifica push.
            // ignore: avoid_print
            print('>>> Notifica DT treno non inviata: $notifyErr');
            String? dtLabel;
            for (final e in _dts) {
              if (e.uuid == _selectedDtUuid) {
                dtLabel = e.label;
                break;
              }
            }
            final hint = (dtLabel ?? '').trim().isNotEmpty
                ? dtLabel!.trim()
                : 'il DT selezionato';
            successMsg =
                'Richiesta treno inviata. Notifica non recapitata (errore). Destinatari previsti: $hint.';
          }
        } else {
          successMsg =
              'Richiesta treno inviata. Utente DT non trovato: notifica non inviata.';
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(successMsg);
    } catch (e) {
      _toast('Errore invio richiesta: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        titleSpacing: 0,
        title: const ResponsiveAppBarTitle(
          title: 'Richiedi treno',
          desktopLogoSize: 36,
        ),
      )),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle('DT da scegliere'),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDtUuid,
                    items: _dts
                        .map((e) => DropdownMenuItem(value: e.uuid, child: Text(e.label)))
                        .toList(),
                    onChanged: _busy ? null : (v) => setState(() => _selectedDtUuid = v),
                    decoration: const InputDecoration(labelText: 'DT'),
                  ),
                  const SizedBox(height: 12),

                  _SectionTitle('Dati viaggio'),
                  _stationField(
                    label: 'Stazione di partenza',
                    controller: _partenzaCtrl,
                    onSelected: (s) => setState(() {
                      _stazionePartenza = s;
                      if (_viaggioTipo == 'AR' &&
                          (_stazionePartenzaRitorno ?? '').trim().isEmpty &&
                          (_stazioneArrivoRitorno ?? '').trim().isEmpty) {
                            _stazionePartenzaRitorno = _stazioneArrivo;
                            _stazioneArrivoRitorno = _stazionePartenza;
                            _partenzaRitornoCtrl.text =
                                _stazionePartenzaRitorno ?? '';
                            _arrivoRitornoCtrl.text =
                                _stazioneArrivoRitorno ?? '';
                          } else if (_viaggioTipo == 'AR') {
                            // Aggiorna sempre la partenza del ritorno (inverso).
                            _stazionePartenzaRitorno = _stazioneArrivo;
                            _partenzaRitornoCtrl.text =
                                _stazionePartenzaRitorno ?? '';
                            // Se il flag è OFF, aggiorna anche la destinazione di ritorno all'inverso.
                            if (!_ritornoDiverso) {
                              _stazioneArrivoRitorno = _stazionePartenza;
                              _arrivoRitornoCtrl.text =
                                  _stazioneArrivoRitorno ?? '';
                            }
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  _stationField(
                    label: 'Stazione di arrivo',
                    controller: _arrivoCtrl,
                    onSelected: (s) => setState(() {
                      _stazioneArrivo = s;
                      if (_viaggioTipo == 'AR' &&
                          (_stazionePartenzaRitorno ?? '').trim().isEmpty &&
                          (_stazioneArrivoRitorno ?? '').trim().isEmpty) {
                            _stazionePartenzaRitorno = _stazioneArrivo;
                            _stazioneArrivoRitorno = _stazionePartenza;
                            _partenzaRitornoCtrl.text =
                                _stazionePartenzaRitorno ?? '';
                            _arrivoRitornoCtrl.text =
                                _stazioneArrivoRitorno ?? '';
                          } else if (_viaggioTipo == 'AR') {
                            _stazionePartenzaRitorno = _stazioneArrivo;
                            _partenzaRitornoCtrl.text =
                                _stazionePartenzaRitorno ?? '';
                            if (!_ritornoDiverso) {
                              _stazioneArrivoRitorno = _stazionePartenza;
                              _arrivoRitornoCtrl.text =
                                  _stazioneArrivoRitorno ?? '';
                            }
                      }
                    }),
                  ),
                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Viaggio:'),
                        ChoiceChip(
                          label: const Text('A'),
                          selected: _viaggioTipo == 'A',
                          onSelected: (_) => setState(() {
                            _viaggioTipo = 'A';
                            _dataRitorno = null;
                            _orarioRitornoHHmm = null;
                            _ritornoDiverso = false;
                            _stazionePartenzaRitorno = null;
                            _stazioneArrivoRitorno = null;
                            _partenzaRitornoCtrl.text = '';
                            _arrivoRitornoCtrl.text = '';
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('A/R'),
                          selected: _viaggioTipo == 'AR',
                          onSelected: (_) => setState(() {
                            _viaggioTipo = 'AR';
                          _ritornoDiverso = false;
                            // Default ritorno = inverso andata
                            _stazionePartenzaRitorno ??= _stazioneArrivo;
                            _stazioneArrivoRitorno ??= _stazionePartenza;
                            _partenzaRitornoCtrl.text =
                                _stazionePartenzaRitorno ?? '';
                            _arrivoRitornoCtrl.text =
                                _stazioneArrivoRitorno ?? '';
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: NeoButton(
                          onTap: _busy ? null : _pickDate,
                          child: Text(
                            'Data: ${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeoButton(
                          onTap: _busy ? null : _pickTime,
                          child: Text(_orarioHHmm == null ? 'Orario andata' : 'Orario andata: $_orarioHHmm'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_viaggioTipo == 'AR') ...[
                    Row(
                      children: [
                        Expanded(
                          child: NeoButton(
                            onTap: _busy ? null : _pickReturnDate,
                            child: Text(
                              _dataRitorno == null
                                  ? 'Data ritorno'
                                  : 'Data ritorno: ${_dataRitorno!.day.toString().padLeft(2, '0')}/${_dataRitorno!.month.toString().padLeft(2, '0')}/${_dataRitorno!.year}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: NeoButton(
                            onTap: _busy ? null : _pickReturnTime,
                            child: Text(
                              _orarioRitornoHHmm == null
                                  ? 'Orario ritorno'
                                  : 'Orario ritorno: $_orarioRitornoHHmm',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      dense: true,
                      value: _ritornoDiverso,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _ritornoDiverso = v;
                                if (!_ritornoDiverso) {
                                  // Ripristina destinazione di ritorno all'inverso.
                                  _stazioneArrivoRitorno = _stazionePartenza;
                                  _arrivoRitornoCtrl.text =
                                      _stazioneArrivoRitorno ?? '';
                                  _stazionePartenzaRitorno = _stazioneArrivo;
                                  _partenzaRitornoCtrl.text =
                                      _stazionePartenzaRitorno ?? '';
                                }
                              }),
                      title: const Text('Ritorno diverso'),
                    ),
                    if (_ritornoDiverso) ...[
                      const SizedBox(height: 10),
                      _stationField(
                        label: 'Seleziona destinazione',
                        controller: _arrivoRitornoCtrl,
                        onSelected: (s) =>
                            setState(() => _stazioneArrivoRitorno = s),
                      ),
                    ],
                  ],

                  TextField(
                    controller: _noteCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Note (opzionale)'),
                  ),
                  const SizedBox(height: 16),

                  NeoAsyncFilledButton(
                    onTap: _busy ? null : _submit,
                    child: const Text('Invia richiesta'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dopo l’invio, la richiesta arriva solo al DT scelto. '
                    'Solo dopo conferma DT viene inoltrata agli admin treni/aerei.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.06),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stationField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onSelected,
  }) {
    TextEditingController? internalCtrlRef;
    return TypeAheadField<String>(
      suggestionsCallback: (pattern) {
        final p = pattern.trim().toLowerCase();
        if (p.isEmpty) return _stazioni.take(30).toList();
        return _stazioni
            .where((s) => s.toLowerCase().contains(p))
            .take(30)
            .toList();
      },
      builder: (context, internalCtrl, focusNode) {
        // sincronizziamo anche il controller interno (TypeAhead) quando selezioni un suggerimento
        internalCtrlRef = internalCtrl;
        if (controller.text.isNotEmpty && internalCtrl.text.isEmpty) {
          internalCtrl.text = controller.text;
        }
        return TextField(
          controller: internalCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) {
            controller.text = v;
            onSelected(v);
          },
        );
      },
      itemBuilder: (_, s) => ListTile(title: Text(s)),
      onSelected: (s) {
        controller.text = s;
        internalCtrlRef?.text = s;
        onSelected(s);
      },
    );
  }
}

class _DtUser {
  final String uuid;
  final String label;
  _DtUser({required this.uuid, required this.label});
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

