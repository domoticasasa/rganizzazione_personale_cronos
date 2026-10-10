import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/neo_buttons.dart';
import '../utils/dt_user_list.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/date_formatters.dart';
import '../utils/travel_departure_guard.dart';
import '../utils/admin_vista_guard.dart';
import '../widgets/classic_app_bar_chrome.dart';

class TrenoPage extends StatefulWidget {
  final String username;
  final int userId;
  final String role;
  final String fullName;

  const TrenoPage({
    super.key,
    required this.username,
    required this.userId,
    required this.role,
    required this.fullName,
  });

  @override
  State<TrenoPage> createState() => _TrenoPageState();
}

class _TrenoPageState extends State<TrenoPage> {
  static const String kTable = 'bookings_treno';

  bool get _isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';

  // Caricamenti
  bool loadingDicts = false;
  bool loadingRows = false;
  bool _insertInFlight = false;

  // Dizionari
  final List<Map<String, String>> _personale = []; // [{id, name}]
  final List<Map<String, String>> _commesse = [];  // [{id, nome}]
  final List<String> _stazioni = [];               // [nome]

  // Mappa id->label rapida per tabella
  Map<String, String> _personaleMap = {};
  Map<String, String> _commesseMap = {};

  // Selezioni form (UUID vincolati dove applicabile)
  Set<String> personaleIds = <String>{}; // uuid da personale (multi-select)
  String? commessaId;           // uuid da commesse
  String? stazionePartenza;     // nome stazione
  String? stazioneArrivo;       // nome stazione
  String? orarioHHmm;           // HH:mm
  String viaggioTipo = 'A';     // A | AR
  DateTime? dataRitorno;
  String? orarioRitornoHHmm;    // HH:mm
  // Se A/R e flag attivo, si permette di selezionare solo la destinazione del ritorno (arrivo ritorno).
  bool _ritornoDiverso = false;
  String? stazioneRitornoDest; // arrivo ritorno (destinazione)
  DateTime dataViaggio = DateTime.now();
  final noteCtrl = TextEditingController();

  // Controller testuali (DropdownMenu / TypeAhead)
  final _personaleCtrl = TextEditingController();
  final _commessaCtrl = TextEditingController();
  final _partenzaCtrl = TextEditingController();
  final _arrivoCtrl = TextEditingController();
  final _ritornoDestCtrl = TextEditingController();

  // DT corrente (users.id o users.id_uuid)
  String? _currentDtUuid;

  // Assistente DT: selezione DT supervisionato
  String? _selectedDtUuidForAssist;
  Map<String, String> _dtOptions = {}; // id_uuid -> label
  final _dtAssistantCtrl = TextEditingController();

  // Tabella
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _requestersMap = {}; // requested_by_user_id -> label
  int _rowsPerPage = 10;

  // Colonne chiave
  String _personaleIdCol = 'id_uuid';
  String _commesseIdCol = 'id_uuid';

  // UUID check
  final _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$');
  bool _isUuid(String? v) => v != null && _uuidRe.hasMatch(v);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    _personaleCtrl.dispose();
    _commessaCtrl.dispose();
    _partenzaCtrl.dispose();
    _arrivoCtrl.dispose();
    _ritornoDestCtrl.dispose();
    _dtAssistantCtrl.dispose();
    super.dispose();
  }

  // ===== Bootstrap =====
  Future<void> _bootstrap() async {
    await _fetchCurrentUserUuid();
    await _resolveKeyColumns();
    await _loadDizionari();
    _syncDropdownTexts();
    await _loadRows();
  }

  // DT: prova users.id (se UUID), altrimenti users.id_uuid
  Future<void> _fetchCurrentUserUuid() async {
    try {
      final r1 = await SupabaseService.client
          .from('users')
          .select('id, username')
          .eq('username', widget.username)
          .maybeSingle();
      final id = (r1?['id'])?.toString();
      if (_isUuid(id)) {
        _currentDtUuid = id;
        return;
      }
      final r2 = await SupabaseService.client
          .from('users')
          .select('id_uuid, username')
          .eq('username', widget.username)
          .maybeSingle();
      final uuid = (r2?['id_uuid'])?.toString();
      if (_isUuid(uuid)) {
        _currentDtUuid = uuid;
        return;
      }
      _msg('Attenzione: impossibile determinare dt_user_uuid.', isError: true);
    } catch (e) {
      _msg('Errore utente corrente: $e', isError: true);
    }
  }

  // Preferisci sempre id_uuid se disponibile
  Future<void> _resolveKeyColumns() async {
    try {
      await SupabaseService.client.from('personale').select('id_uuid').limit(1);
      _personaleIdCol = 'id_uuid';
    } catch (_) {
      _personaleIdCol = 'id';
    }
    try {
      await SupabaseService.client.from('commesse').select('id_uuid').limit(1);
      _commesseIdCol = 'id_uuid';
    } catch (_) {
      _commesseIdCol = 'id';
    }
  }

  // ---------- NUOVO: scarica TUTTE le stazioni a blocchi da 1000 ----------
  Future<List<String>> _fetchAllStazioni({bool soloAttive = true}) async {
    const pageSize = 1000;
    int from = 0;
    final List<String> acc = [];

    while (true) {
      final base = SupabaseService.client
          .from('stazioni')
          .select('nome, attiva');

      // filtro PRIMA di order/range
      final filtered = soloAttive ? base.eq('attiva', true) : base;

      final page = await filtered
          .order('nome', ascending: true)
          .range(from, from + pageSize - 1);

      final list = List<Map<String, dynamic>>.from(page as List);
      if (list.isEmpty) break;

      acc.addAll(list.map((e) => (e['nome'] ?? '').toString()));

      if (list.length < pageSize) break; // ultima pagina
      from += pageSize;
    }

    return acc;
  }

  // Dizionari
  Future<void> _loadDizionari() async {
    setState(() => loadingDicts = true);
    try {
      // Personale
      final p = await SupabaseService.client
          .from('personale')
          .select('$_personaleIdCol, full_name, active')
          .eq('active', true)
          .order('full_name');
      _personale
        ..clear()
        ..addAll((p as List).map<Map<String, String>>(
          (e) => {
            'id': (e[_personaleIdCol] ?? '').toString(),
            'name': (e['full_name'] ?? '').toString(),
          },
        ));
      _personaleMap = {for (final e in _personale) e['id']!: e['name']!};

      // Commesse
      final c = await SupabaseService.client
          .from('commesse')
          .select('$_commesseIdCol, nome, active')
          .eq('active', true)
          .order('nome');
      _commesse
        ..clear()
        ..addAll((c as List).map<Map<String, String>>(
          (e) => {
            'id': (e[_commesseIdCol] ?? '').toString(),
            'nome': (e['nome'] ?? '').toString(),
          },
        ));
      _commesseMap = {for (final e in _commesse) e['id']!: e['nome']!};

      // ---------- Sostituito: Stazioni (tutte, paginate) ----------
      final allStations = await _fetchAllStazioni(soloAttive: true);
      _stazioni
        ..clear()
        ..addAll(allStations);

      // Assistente DT: carica elenco DT supervisionabili
      if (_isAssistenteDt) {
        try {
          final permsRes = await SupabaseService.client
              .from('assistente_dt_permissions')
              .select('grantor_dt_user_uuid')
              .eq('assistant_user_id', widget.userId);

          final perms = permsRes as List;
          final allowedUuids = perms
              .map((e) => (e['grantor_dt_user_uuid'] ?? '').toString().trim())
              .where((u) => u.isNotEmpty)
              .toSet()
              .toList();

          if (allowedUuids.isEmpty) {
            _dtOptions = {};
          } else {
            final orExpr = allowedUuids
                .map((u) => 'id_uuid.eq.$u')
                .join(',');
            final dtRes = await SupabaseService.client
                .from('users')
                .select('id_uuid, full_name, username')
                .or(orExpr);

            _dtOptions = {
              for (final e in (dtRes as List))
                if ((e['id_uuid'] ?? '').toString().trim().isNotEmpty)
                  (e['id_uuid'] ?? '').toString().trim():
                      ((e['full_name'] ?? '').toString().trim().isNotEmpty
                              ? (e['full_name'] ?? '').toString().trim()
                              : (e['username'] ?? '').toString().trim())
            };
          }
        } catch (_) {
          _dtOptions = await loadDtOptionsByUuid();
        }

        if (_dtOptions.isNotEmpty) {
          // se la selezione corrente non è più consentita, riprendiamo la prima voce
          if (_selectedDtUuidForAssist == null ||
              !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
            _selectedDtUuidForAssist = _dtOptions.keys.first;
          }
        }
      }
    } catch (e) {
      _msg('Errore caricamento liste: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingDicts = false);
    }
  }

  // Prenotazioni del DT corrente (finestra recente + limite anti-timeout)
  Future<void> _loadRows() async {
    setState(() => loadingRows = true);
    try {
      final effectiveDtUuid =
          _isAssistenteDt ? _selectedDtUuidForAssist : _currentDtUuid;
      if (_isAssistenteDt) {
        if (effectiveDtUuid == null ||
            _selectedDtUuidForAssist == null ||
            !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
          _rows = [];
          return;
        }
      }

      final fromDate = DateTime.now()
          .subtract(const Duration(days: 120))
          .toIso8601String()
          .substring(0, 10);

      dynamic q = SupabaseService.client.from(kTable).select(
            'id,data,orario,data_ritorno,orario_ritorno,personale_id,'
            'stazione_partenza,stazione_arrivo,stazione_partenza_ritorno,'
            'stazione_arrivo_ritorno,commessa_id,status,master_note,'
            'requested_by_user_id,dt_user_uuid,viaggio_tipo,'
            'workflow_status,assigned_dt_user_uuid,cognome_nome,'
            'personale_fullname,commessa_nome',
          );

      if (_isUuid(effectiveDtUuid)) {
        q = q.eq('dt_user_uuid', effectiveDtUuid!);
      }

      final res = await q
          .gte('data', fromDate)
          .order('data', ascending: false)
          .limit(500);

      _rows = List<Map<String, dynamic>>.from(res as List);
      await _loadRequestersMap();
      setState(() {});
    } catch (e) {
      _msg('Errore caricamento prenotazioni: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingRows = false);
    }
  }

  Future<void> _loadRequestersMap() async {
    _requestersMap.clear();
    try {
      final ids = _rows
          .map((e) => e['requested_by_user_id'])
          .whereType<int>()
          .toSet()
          .toList();
      if (ids.isEmpty) return;

      final orExpr = ids.map((id) => 'id.eq.$id').join(',');
      final res = await SupabaseService.client
          .from('users')
          .select('id, full_name, username')
          .or(orExpr);

      _requestersMap = {
        for (final e in (res as List))
          (e['id'] ?? '').toString(): ((e['full_name'] ?? '').toString().trim().isNotEmpty
                  ? (e['full_name'] ?? '').toString().trim()
                  : (e['username'] ?? '').toString().trim())
      };
    } catch (_) {
      // Fallback: mappa vuota
    }
  }

  void _syncDropdownTexts() {
    if (personaleIds.isEmpty) {
      _personaleCtrl.text = '';
    } else if (personaleIds.length == 1) {
      final id = personaleIds.first;
      _personaleCtrl.text = _personaleMap[id] ?? '';
    } else {
      _personaleCtrl.text = '${personaleIds.length} selezionati';
    }
    _commessaCtrl.text =
        commessaId == null ? '' : (_commesseMap[commessaId!] ?? '');
    _partenzaCtrl.text = stazionePartenza ?? '';
    _arrivoCtrl.text = stazioneArrivo ?? '';
    _ritornoDestCtrl.text = stazioneRitornoDest ?? '';
  }

  // Inserimento
  bool _validate() {
    final effectiveDtUuid =
        _isAssistenteDt ? _selectedDtUuidForAssist : _currentDtUuid;

    if (personaleIds.isEmpty ||
        !_isUuid(commessaId) ||
        (stazionePartenza == null || stazionePartenza!.trim().isEmpty) ||
        (stazioneArrivo == null || stazioneArrivo!.trim().isEmpty) ||
        (orarioHHmm == null || orarioHHmm!.trim().isEmpty) ||
        !_isUuid(effectiveDtUuid) ||
        (_isAssistenteDt &&
            (_selectedDtUuidForAssist == null ||
                !_dtOptions.containsKey(_selectedDtUuidForAssist)))) {
      _msg(
        'Compila: Personale (uno o più), Stazione di partenza, Stazione di arrivo, Data, Orario e Commessa (selezionati dalla lista).',
        isError: true,
      );
      return false;
    }
    if (stazionePartenza == stazioneArrivo) {
      _msg('Partenza e arrivo devono essere diversi.', isError: true);
      return false;
    }
    if (viaggioTipo == 'AR') {
      if (dataRitorno == null || (orarioRitornoHHmm ?? '').trim().isEmpty) {
        _msg('Per A/R compila data e orario ritorno.', isError: true);
        return false;
      }
      if (_ritornoDiverso) {
        if (stazioneRitornoDest == null ||
            stazioneRitornoDest!.trim().isEmpty) {
          _msg('Per ritorno diverso seleziona anche la destinazione di ritorno.', isError: true);
          return false;
        }
        // Il ritorno parte dalla stazione di arrivo andata.
        if (stazioneRitornoDest!.trim() == stazioneArrivo) {
          _msg('La destinazione di ritorno deve essere diversa dalla stazione di arrivo (andata).', isError: true);
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _insert() async {
    if (_insertInFlight) return;
    if (!await ensureCanPersist(context)) return;
    if (!(_validate())) return;
    final pastMsg = pastTravelDepartureMessage(
      dataPartenza: dataViaggio,
      orarioPartenzaHHmm: orarioHHmm!,
      dataRitorno: dataRitorno,
      orarioRitornoHHmm: orarioRitornoHHmm,
      andataRitorno: viaggioTipo == 'AR',
      tipoViaggioLabel: 'biglietto treno',
    );
    if (pastMsg != null) {
      await showPastTravelDepartureDialog(context, pastMsg);
      return;
    }
    if (mounted) {
      setState(() => _insertInFlight = true);
    } else {
      _insertInFlight = true;
    }
    try {
      final effectiveDtUuid =
          _isAssistenteDt ? _selectedDtUuidForAssist : _currentDtUuid;

      final payload = personaleIds.map((pid) {
        return {
          'personale_id': pid,
          'stazione_partenza': stazionePartenza,
          'stazione_arrivo': stazioneArrivo,
          'data': _iso(dataViaggio),
          'orario': orarioHHmm,
          'viaggio_tipo': viaggioTipo,
          'data_ritorno': viaggioTipo == 'AR' ? _iso(dataRitorno!) : null,
          'orario_ritorno': viaggioTipo == 'AR' ? orarioRitornoHHmm : null,
          // Per default il ritorno torna dalla destinazione all'origine.
          'stazione_partenza_ritorno': viaggioTipo == 'AR' ? stazioneArrivo : null,
          'stazione_arrivo_ritorno': viaggioTipo == 'AR'
              ? (_ritornoDiverso ? stazioneRitornoDest : stazionePartenza)
              : null,
          'commessa_id': commessaId,
          'status': 'IN_ATTESA',
          'dt_user_uuid': effectiveDtUuid,
          'workflow_status': 'INVIATA_ADMIN',
          if (_isAssistenteDt) 'requested_by_user_id': widget.userId,
          'master_note': noteCtrl.text.trim(),
          if (_currentDtUuid != null && _currentDtUuid!.length >= 32)
            'updated_by': _currentDtUuid,
        };
      }).toList(growable: false);

      final res = await SupabaseService.client
          .from(kTable)
          .insert(payload)
          .select('id');

      final ids = (res as List)
          .map((e) => e['id'])
          .where((v) => v != null)
          .map((v) => int.tryParse(v.toString()))
          .whereType<int>()
          .toList();

      for (final newId in ids) {
        await NotificationSender.notifyUserForBooking(
          dtUserId: effectiveDtUuid!,
          bookingId: newId,
          action: 'create',
          title: 'Nuova prenotazione treno',
          bookingType: 'treno',
          message: 'Nuova prenotazione treno inserita.',
        );
      }

      // reset form
      setState(() {
        personaleIds = <String>{};
        commessaId = null;
        stazionePartenza = null;
        stazioneArrivo = null;
        stazioneRitornoDest = null;
        orarioHHmm = null;
        viaggioTipo = 'A';
        dataRitorno = null;
        orarioRitornoHHmm = null;
        _ritornoDiverso = false;
        _ritornoDestCtrl.clear();
        noteCtrl.clear();
        _personaleCtrl.clear();
        _commessaCtrl.clear();
        _partenzaCtrl.clear();
        _arrivoCtrl.clear();
      });

      await _loadRows();
      _msg(
        'Prenotazioni treno inserite correttamente (${payload.length}). '
        'Notifiche: admin treni/aereo; se sei DT anche al dipendente coinvolto, '
        'se sei Assistente DT anche al DT supervisore (vedi Regole notifiche).',
      );
    } catch (e) {
      _msg('Errore inserimento: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _insertInFlight = false);
      } else {
        _insertInFlight = false;
      }
    }
  }

  Future<void> _deleteRejectedBooking(Map<String, dynamic> row) async {
    if (!await ensureCanPersist(context)) return;
    final id = row['id'];
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (id == null) {
      _msg('Prenotazione non valida (id mancante).', isError: true);
      return;
    }
    if (status != 'RIFIUTATA') {
      _msg('Puoi cancellare solo richieste rifiutate.', isError: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancella richiesta rifiutata'),
        content: const Text('Vuoi cancellare definitivamente questa richiesta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancella')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.client.from(kTable).delete().eq('id', id);
      await _loadRows();
      _msg('Richiesta rifiutata cancellata.');
    } catch (e) {
      _msg('Errore cancellazione richiesta: $e', isError: true);
    }
  }

  Future<void> _pickPersonaleMulti() async {
    final selected = Set<String>.from(personaleIds);
    String q = '';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            final entries = _personaleMap.entries
                .where((e) {
                  if (q.trim().isEmpty) return true;
                  final needle = q.trim().toLowerCase();
                  return e.value.toLowerCase().contains(needle);
                })
                .toList(growable: false);
            return AlertDialog(
              title: const Text('Seleziona personale'),
              content: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Cerca',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setD(() => q = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final id = entries[i].key;
                          final name = entries[i].value;
                          final isOn = selected.contains(id);
                          return CheckboxListTile(
                            value: isOn,
                            title: Text(name),
                            onChanged: (v) {
                              setD(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setD(() => selected.clear());
                  },
                  child: const Text('Svuota'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      personaleIds = selected;
                      _syncDropdownTexts();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Conferma'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _multiPersonSelector() {
    final selected = personaleIds.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: selected.map((id) {
            final label = _personaleMap[id] ?? id;
            return Chip(
              label: Text(label),
              onDeleted: () {
                setState(() {
                  personaleIds.remove(id);
                  _syncDropdownTexts();
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Seleziona persone'),
            onPressed: _pickPersonaleMulti,
          ),
        ),
      ],
    );
  }

  Future<void> _pickTime() async {
    final t =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) {
      setState(() {
        orarioHHmm =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickReturnDate() async {
    final initial = dataRitorno ?? dataViaggio;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => dataRitorno = picked);
    }
  }

  Future<void> _pickReturnTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        orarioRitornoHHmm =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  // Helpers
  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);
  String _fmtDate(dynamic iso) {
    return formatDateDdMmYyyy(iso);
  }

  void _msg(String text, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green));
  }

  // Stato → colore (uguale alle prenotazioni)
  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN_ATTESA':
        return Colors.orange;
      case 'CONFERMATA':
        return Colors.green;
      case 'RIFIUTATA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // ====== UI building ======

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'Indietro',
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        },
      ),
      titleSpacing: 0,
      title: WelcomeAppBarTitle(
        fullName: widget.fullName,
        username: widget.username,
        avatarRadius: 16,
        onAvatarTap: () => openDipendenteView(
          context,
          userId: widget.userId,
          username: widget.username,
          fullName: widget.fullName,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Ricarica',
          icon: const Icon(Icons.refresh),
          onPressed: _loadRows,
        ),
      ],
    );
  }

  // DropdownMenu con ricerca (Material 3)
  DropdownMenu<String> _dropdownSearch({
    required String label,
    required TextEditingController textCtrl,
    required Map<String, String> sourceMap, // id_uuid -> label
    required String? value, // id_uuid selezionato
    required void Function(String?) onSelected,
    IconData? leading,
  }) {
    final entries = sourceMap.entries
        .map((e) => DropdownMenuEntry<String>(value: e.key, label: e.value))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return DropdownMenu<String>(
      controller: textCtrl,
      initialSelection: value,
      label: Text(label),
      enableFilter: true,
      requestFocusOnTap: true,
      leadingIcon: leading != null ? Icon(leading) : null,
      dropdownMenuEntries: entries,
      onSelected: onSelected,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: UnderlineInputBorder(),
      ),
      menuStyle: const MenuStyle(
        visualDensity: VisualDensity(horizontal: -1, vertical: -1),
      ),
    );
  }

  // ==== TypeAhead per STAZIONI (desktop friendly) ====
  Widget _stationTypeAheadField({
    required String label,
    required TextEditingController ctrl,
    required String? initialValue,
    required ValueChanged<String> onSelected,
  }) {
    // N.B. flutter_typeahead usa un proprio controller interno:
    // lo usiamo nel TextField e teniamo `ctrl` solo sincronizzato.

    const int kMax = 50; // massimo suggerimenti mostrati
    TextEditingController? internalCtrlRef;

    return TypeAheadField<String>(
      suggestionsCallback: (pattern) async {
        final query = pattern.trim().toLowerCase();

        // Campo vuoto -> prime 50 (l'elenco è già ordinato alfabeticamente)
        if (query.isEmpty) {
          return _stazioni.take(kMax).toList(growable: false);
        }

        // Filtra e limita (performance)
        final matches = _stazioni.where((s) => s.toLowerCase().contains(query));
        return matches.take(kMax).toList(growable: false);
      },

      builder: (context, internalCtrl, focusNode) {
        // Manteniamo un riferimento al controller interno così possiamo sincronizzarlo anche in onSelected.
        internalCtrlRef = internalCtrl;

        // inizializza il testo del controller interno una sola volta
        if ((initialValue ?? '').isNotEmpty && internalCtrl.text.isEmpty) {
          internalCtrl.text = initialValue!;
          ctrl.text = initialValue;
        }

        return TextField(
          controller: internalCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            ctrl.text = v;      // mantieni sincronizzato il controller esterno
            onSelected(v);
          },
        );
      },

      itemBuilder: (context, suggestion) => ListTile(
        dense: true,
        title: Text(suggestion),
      ),

      onSelected: (value) {
        ctrl.text = value;
        // In alcuni casi TypeAhead aggiorna la UI solo col controller interno:
        // sincronizziamo esplicitamente per evitare campi "non compilati".
        internalCtrlRef?.text = value;
        onSelected(value);
      },

      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Nessuna stazione trovata'),
      ),

      decorationBuilder: (context, child) {
        return Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Tema compatto come nella pagina prenotazioni
    final compactTheme = theme.copyWith(
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      textTheme: theme.textTheme.apply(fontSizeFactor: 0.95),
      dataTableTheme: const DataTableThemeData(
        dataRowMinHeight: 28,
        dataRowMaxHeight: 40,
        headingRowHeight: 34,
      ),
    );

    return Theme(
      data: compactTheme,
      child: Scaffold(
        appBar: wrapClassicAppBarChrome(context, _buildAppBar()),
        body: PageWithTopLogo(
          child: loadingDicts
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // ===== FORM + CALENDARIO (data singola) =====
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // SINISTRA: form
                            Expanded(
                              child: Column(
                                children: [
                                  if (_isAssistenteDt) ...[
                                    _dropdownSearch(
                                      label: 'DT supervisionato',
                                      textCtrl: _dtAssistantCtrl,
                                      sourceMap: _dtOptions,
                                      value: _selectedDtUuidForAssist,
                                      leading: Icons.approval,
                                      onSelected: (v) async {
                                        setState(() => _selectedDtUuidForAssist = v);
                                        await _loadRows();
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  // Personale (come pernottamenti: chip + pulsante selezione)
                                  _multiPersonSelector(),
                                  const SizedBox(height: 10),

                                  // Stazione Partenza (TypeAhead)
                                  _stationTypeAheadField(
                                    label: 'Stazione di partenza',
                                    ctrl: _partenzaCtrl,
                                    initialValue: stazionePartenza,
                                    onSelected: (v) => stazionePartenza = v,
                                  ),
                                  const SizedBox(height: 10),

                                  // Stazione Arrivo (TypeAhead)
                                  _stationTypeAheadField(
                                    label: 'Stazione di arrivo',
                                    ctrl: _arrivoCtrl,
                                    initialValue: stazioneArrivo,
                                    onSelected: (v) => stazioneArrivo = v,
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
                                          selected: viaggioTipo == 'A',
                                          onSelected: (_) => setState(() {
                                            viaggioTipo = 'A';
                                            dataRitorno = null;
                                            orarioRitornoHHmm = null;
                                          _ritornoDiverso = false;
                                          stazioneRitornoDest = null;
                                          _ritornoDestCtrl.clear();
                                          }),
                                        ),
                                        ChoiceChip(
                                          label: const Text('A/R'),
                                          selected: viaggioTipo == 'AR',
                                        onSelected: (_) => setState(() {
                                          viaggioTipo = 'AR';
                                          _ritornoDiverso = false;
                                          stazioneRitornoDest = null;
                                          _ritornoDestCtrl.clear();
                                        }),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Commessa
                                  _dropdownSearch(
                                    label: 'Commessa',
                                    textCtrl: _commessaCtrl,
                                    sourceMap: _commesseMap,
                                    value: commessaId,
                                    leading: Icons.work_outline,
                                    onSelected: (v) => setState(() => commessaId = v),
                                  ),
                                  const SizedBox(height: 10),

                                  // Orario andata
                                  Row(
                                    children: [
                                      Expanded(
                                          child: Text(
                                              'Orario andata: ${orarioHHmm ?? '--:--'}')),
                                      OutlinedButton(
                                          onPressed: _pickTime,
                                          child: const Text('Seleziona orario andata')),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  if (viaggioTipo == 'AR') ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Ritorno: ${dataRitorno == null ? '--' : _displayDate(dataRitorno!)}',
                                          ),
                                        ),
                                        OutlinedButton(
                                          onPressed: _pickReturnDate,
                                          child: const Text('Data ritorno'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                              'Orario ritorno: ${orarioRitornoHHmm ?? '--:--'}'),
                                        ),
                                        OutlinedButton(
                                          onPressed: _pickReturnTime,
                                          child: const Text('Orario ritorno'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SwitchListTile(
                                      dense: true,
                                      value: _ritornoDiverso,
                                      onChanged: (v) => setState(() {
                                        _ritornoDiverso = v;
                                        if (!_ritornoDiverso) {
                                          stazioneRitornoDest = null;
                                          _ritornoDestCtrl.clear();
                                        } else {
                                          stazioneRitornoDest ??= stazionePartenza;
                                          _ritornoDestCtrl.text =
                                              stazioneRitornoDest ?? '';
                                        }
                                      }),
                                      title: const Text('Ritorno diverso'),
                                    ),
                                    if (_ritornoDiverso) ...[
                                      const SizedBox(height: 6),
                                      _stationTypeAheadField(
                                        label: 'Seleziona destinazione',
                                        ctrl: _ritornoDestCtrl,
                                        initialValue: stazioneRitornoDest,
                                        onSelected: (v) => setState(() => stazioneRitornoDest = v),
                                      ),
                                    ],
                                  ],

                                  // Note
                                  TextField(
                                    controller: noteCtrl,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      labelText: 'Note opzionali...',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Inserisci
                                  SizedBox(
                                    width: double.infinity,
                                    child: NeoAsyncFilledButton(
                                      onTap: _insertInFlight ? null : _insert,
                                      child: const Center(
                                        child: Text('Inserisci prenotazione'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // DESTRA: Calendario (data singola)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Data: ${_displayDate(dataViaggio)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  CalendarDatePicker(
                                    initialDate: dataViaggio,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    onDateChanged: (d) =>
                                        setState(() => dataViaggio = d),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ===== LISTA PRENOTAZIONI =====
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Prenotazioni',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 6),

                    loadingRows
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: (MediaQuery.of(context).size.width)
                                  .clamp(1100, 1600),
                              child: PaginatedDataTable(
                                header: const Text(''),
                                rowsPerPage: _rowsPerPage,
                                columnSpacing: 22,
                                horizontalMargin: 8,
                                availableRowsPerPage: const [10, 25, 50],
                                onRowsPerPageChanged: (v) {
                                  if (v != null) setState(() => _rowsPerPage = v);
                                },
                                columns: const [
                                  DataColumn(label: Text('Persona')),
                                  DataColumn(label: Text('Data')),
                                  DataColumn(label: Text('Orario andata')),
                                  DataColumn(label: Text('Partenza')),
                                  DataColumn(label: Text('Arrivo')),
                                  DataColumn(label: Text('Data ritorno')),
                                  DataColumn(label: Text('Orario ritorno')),
                                  DataColumn(label: Text('Ritorno diverso')),
                                  DataColumn(label: Text('Commessa')),
                                  DataColumn(label: Text('Stato')),
                                  DataColumn(label: Text('Note')),
                                  DataColumn(label: Text('Azioni')),
                                ],
                                source: _TreniTableSource(
                                  rows: _rows,
                                  personale: _personaleMap, // id -> name
                                  commesse: _commesseMap,   // id -> nome
                                  requesters: _requestersMap,
                                  fmtDate: _fmtDate,
                                  statusColor: _statusColor, // badge color
                                  onDeleteRejected: _deleteRejectedBooking,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
          ),
      ),
    );
  }
}

// =================== DataTable Source ===================
class _TreniTableSource extends DataTableSource {
  final List<Map<String, dynamic>> rows;
  final Map<String, String> personale;
  final Map<String, String> commesse;
  final Map<String, String> requesters;
  final String Function(dynamic) fmtDate;
  final Color Function(String) statusColor;
  final void Function(Map<String, dynamic> row) onDeleteRejected;

  _TreniTableSource({
    required this.rows,
    required this.personale,
    required this.commesse,
    required this.requesters,
    required this.fmtDate,
    required this.statusColor,
    required this.onDeleteRejected,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];

    final persona = personale[(r['personale_id'] ?? '').toString()] ??
        (r['personale_id'] ?? '').toString();
    final commessa = commesse[(r['commessa_id'] ?? '').toString()] ??
        (r['commessa_id'] ?? '').toString();

    final rawStato = (r['status'] ?? '').toString().toUpperCase();
    String statoLabel;
    switch (rawStato) {
      case 'IN_ATTESA':
        statoLabel = 'Attesa';
        break;
      case 'CONFERMATA':
        statoLabel = 'Confermata';
        break;
      case 'RIFIUTATA':
        statoLabel = 'Rifiutata';
        break;
      default:
        statoLabel = (r['status'] ?? '').toString();
    }
    final sColor = statusColor(rawStato);
    final ritornoDiverso = (r['stazione_arrivo_ritorno'] ?? '')
                .toString()
                .trim()
                .isNotEmpty &&
            (r['stazione_arrivo_ritorno'] ?? '').toString().trim() !=
                (r['stazione_partenza'] ?? '').toString().trim();
    final ritornoDiversoVal = ritornoDiverso
        ? (r['stazione_arrivo_ritorno'] ?? '').toString().trim()
        : '';
    final insertedAtLabel = (() {
      final s = formatDateTimeItFromSupabase(r['created_at']);
      return s.isEmpty ? '—' : s;
    })();

    return DataRow(cells: [
      DataCell(Text(persona)),
      DataCell(Text(fmtDate(r['data']))),
      DataCell(Text((r['orario'] ?? '').toString())),
      DataCell(Text((r['stazione_partenza'] ?? '').toString())),
      DataCell(Text((r['stazione_arrivo'] ?? '').toString())),
      DataCell(Text(fmtDate(r['data_ritorno']))),
      DataCell(Text((r['orario_ritorno'] ?? '').toString())),
      DataCell(Text(ritornoDiversoVal)),
      DataCell(Text(commessa)),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: sColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statoLabel,
            style: TextStyle(color: sColor, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      DataCell(() {
        final reqId = (r['requested_by_user_id'] ?? '').toString().trim();
        final reqName =
            reqId.isNotEmpty ? (requesters[reqId] ?? reqId) : null;
        final note = (r['master_note'] ?? '').toString();
        if (reqName == null || reqName.isEmpty) return Text(note);
        if (note.trim().isEmpty) return Text('Richiedente: $reqName');
        return Text('Richiedente: $reqName\n$note');
      }()),
      DataCell(
        IconButton(
          tooltip: 'Cancella richiesta rifiutata',
          icon: const Icon(Icons.delete_outline),
          onPressed: rawStato == 'RIFIUTATA' ? () => onDeleteRejected(r) : null,
        ),
      ),
    ].map((c) => DataCell(
          Tooltip(
            message: 'Inserita il: $insertedAtLabel',
            waitDuration: const Duration(milliseconds: 220),
            child: c.child,
          ),
        )).toList());
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => rows.length;
  @override
  int get selectedRowCount => 0;
}