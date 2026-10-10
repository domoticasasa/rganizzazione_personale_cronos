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

class RichiestaAereoPage extends StatefulWidget {
  final int userId; // users.id (int)
  final String fullName;

  const RichiestaAereoPage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<RichiestaAereoPage> createState() => _RichiestaAereoPageState();
}

class _RichiestaAereoPageState extends State<RichiestaAereoPage> {
  bool _busy = false;

  String? _myPersonaleUuid;
  String? _myUserUuid; // users.id_uuid

  final List<String> _aeroporti = [];
  final List<_DtUser> _dts = [];

  String? _aeroportoPartenza;
  String? _aeroportoArrivo;
  String? _aeroportoPartenzaRitorno;
  String? _aeroportoArrivoRitorno;
  DateTime _data = DateTime.now();
  String? _orarioHHmm;
  String _viaggioTipo = 'A'; // A | AR
  DateTime? _dataRitorno;
  String? _orarioRitornoHHmm;
  bool _ritornoDiverso = false;
  String? bagaglio;
  bool parcheggio = false;
  final _targaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedDtUuid;

  final _partCtrl = TextEditingController();
  final _arrCtrl = TextEditingController();
  final _partCtrlRitorno = TextEditingController();
  final _arrCtrlRitorno = TextEditingController();

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
    _targaCtrl.dispose();
    _noteCtrl.dispose();
    _partCtrl.dispose();
    _arrCtrl.dispose();
    _partCtrlRitorno.dispose();
    _arrCtrlRitorno.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _busy = true);
    try {
      await _resolveMyUuids();
      await _loadAeroporti();
      await _loadDTs();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveMyUuids() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    final authId = authUser.id;

    final u = await SupabaseService.client
        .from('users')
        .select('id_uuid')
        .eq('auth_id', authId)
        .maybeSingle();
    final uuid = (u?['id_uuid'] ?? '').toString().trim();
    if (_isUuid(uuid)) _myUserUuid = uuid;

    final p1 = await SupabaseService.client
        .from('personale')
        .select('id_uuid, user_id')
        .eq('user_id', authId)
        .maybeSingle();
    if (p1 != null && (p1['id_uuid'] ?? '').toString().trim().isNotEmpty) {
      _myPersonaleUuid = (p1['id_uuid'] as String).trim();
      return;
    }

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

  Future<void> _loadAeroporti() async {
    const pageSize = 1000;
    int from = 0;
    _aeroporti.clear();
    while (true) {
      final page = await SupabaseService.client
          .from('aeroporti')
          .select('nome, attiva')
          .eq('attiva', true)
          .order('nome', ascending: true)
          .range(from, from + pageSize - 1);
      final list = List<Map<String, dynamic>>.from(page as List);
      if (list.isEmpty) break;
      _aeroporti.addAll(list.map((e) => (e['nome'] ?? '').toString()).where((s) => s.isNotEmpty));
      if (list.length < pageSize) break;
      from += pageSize;
    }
    _aeroporti.sort(_compareTextAz);
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
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
    if ((_aeroportoPartenza ?? '').trim().isEmpty ||
        (_aeroportoArrivo ?? '').trim().isEmpty ||
        (_orarioHHmm ?? '').trim().isEmpty ||
        !_isUuid(_selectedDtUuid) ||
        !_isUuid(_myUserUuid)) {
      _toast('Compila tutti i campi obbligatori.', error: true);
      return false;
    }
    if (bagaglio == null || bagaglio!.trim().isEmpty) {
      _toast('Seleziona il tipo di bagaglio.', error: true);
      return false;
    }
    if (_aeroportoPartenza == _aeroportoArrivo) {
      _toast('Partenza e arrivo devono essere diversi.', error: true);
      return false;
    }
    if (parcheggio && _targaCtrl.text.trim().isEmpty) {
      _toast('Inserisci la targa se hai selezionato parcheggio.', error: true);
      return false;
    }
    if (_viaggioTipo == 'AR') {
      if (_dataRitorno == null || (_orarioRitornoHHmm ?? '').trim().isEmpty) {
        _toast('Per A/R compila data e orario ritorno.', error: true);
        return false;
      }
      if ((_aeroportoPartenzaRitorno ?? '').trim().isEmpty ||
          (_aeroportoArrivoRitorno ?? '').trim().isEmpty) {
        _toast('Compila anche aeroporti di ritorno (Da/A).', error: true);
        return false;
      }
      if (_aeroportoPartenzaRitorno == _aeroportoArrivoRitorno) {
        _toast('Aeroporti di ritorno devono essere diversi.', error: true);
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
      tipoViaggioLabel: 'biglietto aereo',
    );
    if (pastMsg != null) {
      await showPastTravelDepartureDialog(context, pastMsg);
      return;
    }
    setState(() => _busy = true);
    try {
      final inserted = await SupabaseService.client.from('bookings_aereo').insert({
        'personale_id': _myPersonaleUuid,
        'aeroporto_partenza': _aeroportoPartenza,
        'aeroporto_arrivo': _aeroportoArrivo,
        'data': _isoDate(_data),
        'orario': _orarioHHmm,
        'viaggio_tipo': _viaggioTipo,
        'data_ritorno': _viaggioTipo == 'AR' ? _isoDate(_dataRitorno!) : null,
        'orario_ritorno': _viaggioTipo == 'AR' ? _orarioRitornoHHmm : null,
        // Ritorno: usa aeroporti selezionati (se vuoti fallback inverso).
        'aeroporto_partenza_ritorno': _viaggioTipo == 'AR'
            ? (_aeroportoPartenzaRitorno ?? _aeroportoArrivo)
            : null,
        'aeroporto_arrivo_ritorno': _viaggioTipo == 'AR'
            ? (_aeroportoArrivoRitorno ?? _aeroportoPartenza)
            : null,
        // commessa la inserisce il DT in fase di conferma
        'commessa_id': null,
        'status': 'IN_ATTESA',
        'dt_user_uuid': _selectedDtUuid,
        'assigned_dt_user_uuid': _selectedDtUuid,
        'requested_by_user_id': widget.userId,
        'workflow_status': 'INVIATA_AL_DT',
        'bagaglio': bagaglio,
        'parcheggio': parcheggio,
        'targa_veicolo': _targaCtrl.text.trim(),
        'master_note': _noteCtrl.text.trim(),
        'updated_by': _myUserUuid,
      }).select('id').single();

      final newId = inserted['id'] != null ? int.tryParse(inserted['id'].toString()) : null;
      var successMsg = 'Richiesta aereo inviata.';
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
              bookingType: 'aereo',
            );
            var effectiveIds =
                recipientIds.isEmpty ? <int>[dtId] : List<int>.from(recipientIds);
            if (!effectiveIds.contains(dtId)) effectiveIds.add(dtId);
            await NotificationSender.sendToUserIds(
              userIds: effectiveIds,
              bookingId: newId,
              action: 'dt_approval_required',
              title: 'Richiesta aereo',
              message:
                  '${widget.fullName} ha inviato una richiesta aereo. Attende conferma DT.',
            );
            final who = await NotificationSender.recipientLabelsForUserIds(effectiveIds);
            successMsg = 'Richiesta aereo inviata. Notifica inviata a: $who.';
          } catch (notifyErr) {
            // Non bloccare l'invio richiesta se fallisce solo la notifica push.
            // ignore: avoid_print
            print('>>> Notifica DT aereo non inviata: $notifyErr');
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
                'Richiesta aereo inviata. Notifica non recapitata (errore). Destinatari previsti: $hint.';
          }
        } else {
          successMsg =
              'Richiesta aereo inviata. Utente DT non trovato: notifica non inviata.';
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
          title: 'Richiedi aereo',
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

                  _SectionTitle('Dati volo'),
                  _suggestField(
                    label: 'Aeroporto di partenza',
                    controller: _partCtrl,
                    source: _aeroporti,
                    onSelected: (s) => setState(() {
                      _aeroportoPartenza = s;
                      if (_viaggioTipo == 'AR' &&
                          (_aeroportoPartenzaRitorno ?? '').trim().isEmpty &&
                          (_aeroportoArrivoRitorno ?? '').trim().isEmpty) {
                        _aeroportoPartenzaRitorno = _aeroportoArrivo;
                        _aeroportoArrivoRitorno = _aeroportoPartenza;
                        _partCtrlRitorno.text =
                            _aeroportoPartenzaRitorno ?? '';
                        _arrCtrlRitorno.text =
                            _aeroportoArrivoRitorno ?? '';
                      } else if (_viaggioTipo == 'AR') {
                        // Ritorno di default = inverso: aggiorna sempre la partenza di ritorno.
                        _aeroportoPartenzaRitorno = _aeroportoArrivo;
                        _partCtrlRitorno.text =
                            _aeroportoPartenzaRitorno ?? '';
                        // Se il flag è OFF, aggiorna anche la destinazione di ritorno all'inverso.
                        if (!_ritornoDiverso) {
                          _aeroportoArrivoRitorno = _aeroportoPartenza;
                          _arrCtrlRitorno.text =
                              _aeroportoArrivoRitorno ?? '';
                        }
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  _suggestField(
                    label: 'Aeroporto di arrivo',
                    controller: _arrCtrl,
                    source: _aeroporti,
                    onSelected: (s) => setState(() {
                      _aeroportoArrivo = s;
                      if (_viaggioTipo == 'AR' &&
                          (_aeroportoPartenzaRitorno ?? '').trim().isEmpty &&
                          (_aeroportoArrivoRitorno ?? '').trim().isEmpty) {
                        _aeroportoPartenzaRitorno = _aeroportoArrivo;
                        _aeroportoArrivoRitorno = _aeroportoPartenza;
                        _partCtrlRitorno.text =
                            _aeroportoPartenzaRitorno ?? '';
                        _arrCtrlRitorno.text =
                            _aeroportoArrivoRitorno ?? '';
                      } else if (_viaggioTipo == 'AR') {
                        _aeroportoPartenzaRitorno = _aeroportoArrivo;
                        _partCtrlRitorno.text =
                            _aeroportoPartenzaRitorno ?? '';
                        if (!_ritornoDiverso) {
                          _aeroportoArrivoRitorno = _aeroportoPartenza;
                          _arrCtrlRitorno.text =
                              _aeroportoArrivoRitorno ?? '';
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
                            _aeroportoPartenzaRitorno = null;
                            _aeroportoArrivoRitorno = null;
                            _partCtrlRitorno.text = '';
                            _arrCtrlRitorno.text = '';
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('A/R'),
                          selected: _viaggioTipo == 'AR',
                          onSelected: (_) => setState(() {
                            _viaggioTipo = 'AR';
                            _ritornoDiverso = false;
                            _aeroportoPartenzaRitorno ??= _aeroportoArrivo;
                            _aeroportoArrivoRitorno ??= _aeroportoPartenza;
                            _partCtrlRitorno.text =
                                _aeroportoPartenzaRitorno ?? '';
                            _arrCtrlRitorno.text =
                                _aeroportoArrivoRitorno ?? '';
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
                                  _aeroportoArrivoRitorno = _aeroportoPartenza;
                                  _arrCtrlRitorno.text =
                                      _aeroportoArrivoRitorno ?? '';
                                }
                              }),
                      title: const Text('Ritorno diverso'),
                    ),
                    if (_ritornoDiverso) ...[
                      _suggestField(
                        label: 'Seleziona destinazione',
                        controller: _arrCtrlRitorno,
                        source: _aeroporti,
                        onSelected: (s) =>
                            setState(() => _aeroportoArrivoRitorno = s),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],

                  DropdownButtonFormField<String>(
                    initialValue: bagaglio,
                    hint: const Text('Seleziona bagaglio'),
                    onChanged: _busy ? null : (v) => setState(() => bagaglio = v),
                    items: const [
                      DropdownMenuItem(value: 'mano', child: Text('Bagaglio a mano')),
                      DropdownMenuItem(value: 'stiva', child: Text('Bagaglio in stiva')),
                    ],
                    decoration: const InputDecoration(labelText: 'Bagaglio *'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: parcheggio,
                    onChanged: _busy ? null : (v) => setState(() => parcheggio = v),
                    title: const Text('Parcheggio'),
                  ),
                  if (parcheggio) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _targaCtrl,
                      decoration: const InputDecoration(labelText: 'Targa veicolo'),
                    ),
                  ],
                  const SizedBox(height: 10),
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

  Widget _suggestField({
    required String label,
    required TextEditingController controller,
    required List<String> source,
    required ValueChanged<String> onSelected,
  }) {
    TextEditingController? internalCtrlRef;
    return TypeAheadField<String>(
      suggestionsCallback: (pattern) {
        final p = pattern.trim().toLowerCase();
        if (p.isEmpty) return source.take(30).toList();
        return source.where((s) => s.toLowerCase().contains(p)).take(30).toList();
      },
      builder: (context, internalCtrl, focusNode) {
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

