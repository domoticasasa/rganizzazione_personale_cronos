import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../utils/dt_user_list.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/date_formatters.dart';
import '../utils/travel_departure_guard.dart';
import '../utils/admin_vista_guard.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AereoPage extends StatefulWidget {
  final String username;
  final int userId; 
  final String role;
  final String fullName;

  const AereoPage({
    super.key,
    required this.username,
    required this.userId,
    required this.role,
    required this.fullName,
  });

  @override
  State<AereoPage> createState() => _AereoPageState();
}

class _AereoPageState extends State<AereoPage> {
  static const String kTable = 'bookings_aereo';

  bool get _isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';

  // Dizionari display (UUID -> label)
  final Map<String, String> _personale = {}; 
  final Map<String, String> _aeroporti = {}; 
  final Map<String, String> _commesse = {};  

  // Scelte form
  Set<String> personaleIds = <String>{}; // multi-select
  String? aeroportoPartenza;
  String? aeroportoArrivo;
  String? commessaId;      
  DateTime dataVolo = DateTime.now();
  String? orarioPartenza;  
  String viaggioTipo = 'A';   // A | AR
  DateTime? dataRitorno;
  String? orarioRitorno;
  // Se A/R e flag attivo, si permette la selezione solo della destinazione di ritorno (arrivo ritorno).
  bool _ritornoDiverso = false;
  String? aeroportoRitornoDest; // arrivo ritorno (destinazione)
  String? bagaglio;
  bool parcheggio = false;
  final targaCtrl = TextEditingController();
  final noteCtrl  = TextEditingController();

  // Controller testuali per DropdownMenu
  final _personaleCtrl = TextEditingController();
  final _partenzaCtrl  = TextEditingController();
  final _arrivoCtrl    = TextEditingController();
  final _commessaCtrl  = TextEditingController();
  final _aeroportoRitornoDestCtrl = TextEditingController();

  // DT corrente (UUID)
  String? _currentDtUuid;

  // Assistente DT: DT supervisionato
  String? _selectedDtUuidForAssist;
  Map<String, String> _dtOptions = {}; // id_uuid -> label
  final _dtAssistantCtrl = TextEditingController();

  // Assistente DT: requested_by_user_id -> label
  Map<String, String> _requestersMap = {};

  // Stato/caricamento
  bool loadingDicts = false;
  bool loadingRows  = false;
  bool _insertInFlight = false;
  List<Map<String, dynamic>> _rows = [];
  int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    targaCtrl.dispose();
    noteCtrl.dispose();
    _personaleCtrl.dispose();
    _partenzaCtrl.dispose();
    _arrivoCtrl.dispose();
    _commessaCtrl.dispose();
    _aeroportoRitornoDestCtrl.dispose();
    _dtAssistantCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _fetchCurrentUserUuid();
    await _loadDizionari();
    _syncDropdownTexts();
    await _loadRows();
  }

  void _syncDropdownTexts() {
    if (personaleIds.isEmpty) {
      _personaleCtrl.text = '';
    } else if (personaleIds.length == 1) {
      final id = personaleIds.first;
      _personaleCtrl.text = _personale[id] ?? '';
    } else {
      _personaleCtrl.text = '${personaleIds.length} selezionati';
    }
    _partenzaCtrl.text  = aeroportoPartenza ?? '';
    _arrivoCtrl.text    = aeroportoArrivo ?? '';
    _commessaCtrl.text  = commessaId == null ? '' : (_commesse[commessaId!] ?? '');
    _aeroportoRitornoDestCtrl.text = aeroportoRitornoDest ?? '';
  }

  Future<void> _fetchCurrentUserUuid() async {
    try {
      final r1 = await SupabaseService.client
          .from('users')
          .select('id, username')
          .eq('username', widget.username)
          .maybeSingle();
      if (r1 != null && r1['id'] is String && (r1['id'] as String).length >= 32) {
        _currentDtUuid = r1['id'] as String;
        return;
      }
      final r2 = await SupabaseService.client
          .from('users')
          .select('id_uuid, username')
          .eq('username', widget.username)
          .maybeSingle();
      if (r2 != null && r2['id_uuid'] is String && (r2['id_uuid'] as String).length >= 32) {
        _currentDtUuid = r2['id_uuid'] as String;
        return;
      }
      _msg('Attenzione: impossibile determinare dt_user_uuid.', isError: true);
    } catch (e) {
      _msg('Errore utente corrente: $e', isError: true);
    }
  }

  Future<void> _loadDizionari() async {
    setState(() => loadingDicts = true);
    try {
      final p = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, active')
          .eq('active', true)
          .order('full_name');

      _personale
        ..clear()
        ..addEntries(
          ((p as List)
                .map((e) => MapEntry(
                      (e['id_uuid'] ?? '').toString(),
                      (e['full_name'] ?? '').toString(),
                    ))
                .toList()
              ..sort((a, b) => a.value
                  .toLowerCase()
                  .trim()
                  .compareTo(b.value.toLowerCase().trim()))),
        );

      final a = await SupabaseService.client
          .from('aeroporti')
          .select('nome, attiva')
          .order('nome');

      _aeroporti
        ..clear()
        ..addEntries(
          ((a as List)
                .where((e) => (e['attiva'] ?? false) == true)
                .map((e) {
                  final nome = (e['nome'] ?? '').toString();
                  return MapEntry(nome, nome);
                })
                .toList()
              ..sort((x, y) => x.value
                  .toLowerCase()
                  .trim()
                  .compareTo(y.value.toLowerCase().trim()))),
        );

      final c = await SupabaseService.client
          .from('commesse')
          .select('id_uuid, nome, active')
          .eq('active', true)
          .order('nome');

      _commesse
        ..clear()
        ..addEntries(
          ((c as List)
                .map((e) => MapEntry(
                      (e['id_uuid'] ?? '').toString(),
                      (e['nome'] ?? '').toString(),
                    ))
                .toList()
              ..sort((a, b) => a.value
                  .toLowerCase()
                  .trim()
                  .compareTo(b.value.toLowerCase().trim()))),
        );

      // Assistente DT: carica elenco DT
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
            final orExpr = allowedUuids.map((u) => 'id_uuid.eq.$u').join(',');
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
          if (_selectedDtUuidForAssist == null ||
              !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
            _selectedDtUuidForAssist = _dtOptions.keys.first;
          }
        }
      }

      setState(() {});
    } catch (e) {
      _msg('Errore caricamento liste: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingDicts = false);
    }
  }

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
            'aeroporto_partenza,aeroporto_arrivo,aeroporto_partenza_ritorno,'
            'aeroporto_arrivo_ritorno,commessa_id,status,master_note,'
            'requested_by_user_id,dt_user_uuid,viaggio_tipo,'
            'workflow_status,assigned_dt_user_uuid,bagaglio,parcheggio,'
            'targa_veicolo,personale_fullname,commessa_nome',
          );

      if (effectiveDtUuid != null && effectiveDtUuid.isNotEmpty) {
        q = q.filter('dt_user_uuid', 'eq', effectiveDtUuid);
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
      // ignore
    }
  }

  Future<void> _insertBooking() async {
    if (_insertInFlight) return;
    if (!await ensureCanPersist(context)) return;
    if (mounted) {
      setState(() => _insertInFlight = true);
    } else {
      _insertInFlight = true;
    }
    final effectiveDtUuid =
        _isAssistenteDt ? _selectedDtUuidForAssist : _currentDtUuid;

    if (effectiveDtUuid == null || effectiveDtUuid.isEmpty) {
      _msg('dt_user_uuid (selezione DT) non disponibile.', isError: true);
      return;
    }
    if (personaleIds.isEmpty ||
        aeroportoPartenza == null ||
        aeroportoArrivo == null ||
        commessaId == null ||
        orarioPartenza == null ||
        orarioPartenza!.trim().isEmpty) {
      _msg('Compila: Personale (uno o più), Partenza, Arrivo, Commessa, Data e Orario.', isError: true);
      return;
    }
    if (bagaglio == null || bagaglio!.trim().isEmpty) {
      _msg('Seleziona il tipo di bagaglio.', isError: true);
      return;
    }
    if (aeroportoPartenza == aeroportoArrivo) {
      _msg('Aeroporto di partenza e arrivo devono essere diversi.', isError: true);
      return;
    }
    if (parcheggio && targaCtrl.text.trim().isEmpty) {
      _msg('Inserisci la targa (parcheggio attivo).', isError: true);
      return;
    }
    if (viaggioTipo == 'AR') {
      if (dataRitorno == null || (orarioRitorno ?? '').trim().isEmpty) {
        _msg('Per A/R compila data e orario ritorno.', isError: true);
        return;
      }
      if (_ritornoDiverso) {
        if (aeroportoRitornoDest == null ||
            aeroportoRitornoDest!.trim().isEmpty) {
          _msg('Per ritorno diverso seleziona la destinazione di ritorno.', isError: true);
          return;
        }
        // Il ritorno parte dall'aeroporto di arrivo andata.
        if (aeroportoRitornoDest!.trim() == aeroportoArrivo) {
          _msg('La destinazione di ritorno deve essere diversa dall\'aeroporto di arrivo (andata).', isError: true);
          return;
        }
      }
    }

    bool looksUuid(String? v) => v != null && v.length >= 32 && v.contains('-');
    if (!looksUuid(commessaId) ||
        !looksUuid(effectiveDtUuid) ||
        (_isAssistenteDt &&
            (_selectedDtUuidForAssist == null ||
                !_dtOptions.containsKey(_selectedDtUuidForAssist)))) {
      _msg('Chiavi non valide (devono essere UUID). Controlla le selezioni.', isError: true);
      return;
    }

    final pastMsg = pastTravelDepartureMessage(
      dataPartenza: dataVolo,
      orarioPartenzaHHmm: orarioPartenza!,
      dataRitorno: dataRitorno,
      orarioRitornoHHmm: orarioRitorno,
      andataRitorno: viaggioTipo == 'AR',
      tipoViaggioLabel: 'biglietto aereo',
    );
    if (pastMsg != null) {
      if (mounted) {
        setState(() => _insertInFlight = false);
      } else {
        _insertInFlight = false;
      }
      await showPastTravelDepartureDialog(context, pastMsg);
      return;
    }

    try {
      final payload = personaleIds.map((pid) {
        return {
          'personale_id': pid,
          'aeroporto_partenza': aeroportoPartenza,
          'aeroporto_arrivo': aeroportoArrivo,
          'data': _iso(dataVolo),
          'orario': orarioPartenza,
          'viaggio_tipo': viaggioTipo,
          'data_ritorno': viaggioTipo == 'AR' ? _iso(dataRitorno!) : null,
          'orario_ritorno': viaggioTipo == 'AR' ? orarioRitorno : null,
          // Per default il ritorno torna dall'arrivo alla partenza.
          'aeroporto_partenza_ritorno': viaggioTipo == 'AR' ? aeroportoArrivo : null,
          'aeroporto_arrivo_ritorno': viaggioTipo == 'AR'
              ? (_ritornoDiverso ? aeroportoRitornoDest : aeroportoPartenza)
              : null,
          'commessa_id': commessaId,
          'bagaglio': bagaglio,
          'parcheggio': parcheggio,
          'targa_veicolo': parcheggio ? targaCtrl.text.trim() : null,
          'status': 'IN_ATTESA',
          'dt_user_uuid': effectiveDtUuid,
          'workflow_status': 'INVIATA_ADMIN',
          if (_isAssistenteDt) 'requested_by_user_id': widget.userId,
          'master_note': noteCtrl.text.trim(),
          'created_at': supabaseNowIsoUtc(),
          if (_currentDtUuid != null && _currentDtUuid!.length >= 32)
            'updated_by': _currentDtUuid,
        };
      }).toList(growable: false);

      final res = await SupabaseService.client
          .from(kTable)
          .insert(payload)
          .select('id');

      noteCtrl.clear();
      targaCtrl.clear();
      setState(() {
        personaleIds = <String>{};
        commessaId  = null;
        aeroportoPartenza = null;
        aeroportoArrivo   = null;
        aeroportoRitornoDest = null;
        _ritornoDiverso = false;
        _aeroportoRitornoDestCtrl.clear();
        bagaglio = null;
        parcheggio = false;
        orarioPartenza = null;
        viaggioTipo = 'A';
        dataRitorno = null;
        orarioRitorno = null;
      });
      _syncDropdownTexts();

      // Notifiche (DT/Admin + personale)
      final ids = (res as List)
          .map((e) => (e as Map)['id'])
          .where((v) => v != null)
          .map((v) => int.tryParse(v.toString()))
          .whereType<int>()
          .toList();

      for (final newId in ids) {
        await NotificationSender.notifyUserForBooking(
          dtUserId: effectiveDtUuid,
          bookingId: newId,
          action: 'create',
          title: 'Nuova prenotazione aereo',
          bookingType: 'aereo',
          message: 'Nuova prenotazione aereo inserita.',
        );
      }

      await _loadRows();
      _msg(
        'Prenotazioni aeree inserite correttamente (${payload.length}). '
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
    final workflow = (row['workflow_status'] ?? '').toString().toUpperCase();
    final isRejected = status == 'RIFIUTATA' || workflow == 'RIFIUTATA_DAL_DT';
    if (id == null) {
      _msg('Prenotazione non valida (id mancante).', isError: true);
      return;
    }
    if (!isRejected) {
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
            final entries = _personale.entries
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
                  onPressed: () => setD(() => selected.clear()),
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
            final label = _personale[id] ?? id;
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
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        orarioPartenza = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickReturnDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dataRitorno ?? dataVolo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => dataRitorno = picked);
  }

  Future<void> _pickReturnTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) {
      setState(() {
        orarioRitorno =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      });
    }
  }

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  DropdownMenu<String> _dropdownSearch({
    required String label,
    required TextEditingController textCtrl,
    required Map<String, String> sourceMap,
    required String? value,
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
      enableSearch: true,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        body: loadingDicts
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  if (_isAssistenteDt) ...[
                                    _dropdownSearch(
                                      label: 'DT supervisionato',
                                      textCtrl: _dtAssistantCtrl,
                                      sourceMap: _dtOptions,
                                      value: _selectedDtUuidForAssist,
                                      leading: Icons.approval_outlined,
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
                                  _dropdownSearch(
                                    label: 'Aeroporto di partenza',
                                    textCtrl: _partenzaCtrl,
                                    sourceMap: _aeroporti,
                                    value: aeroportoPartenza,
                                    leading: Icons.flight_takeoff,
                                    onSelected: (v) => setState(() => aeroportoPartenza = v),
                                  ),
                                  const SizedBox(height: 10),
                                  _dropdownSearch(
                                    label: 'Aeroporto di arrivo',
                                    textCtrl: _arrivoCtrl,
                                    sourceMap: _aeroporti,
                                    value: aeroportoArrivo,
                                    leading: Icons.flight_land,
                                    onSelected: (v) => setState(() => aeroportoArrivo = v),
                                  ),
                                  const SizedBox(height: 10),
                                  _dropdownSearch(
                                    label: 'Commessa',
                                    textCtrl: _commessaCtrl,
                                    sourceMap: _commesse,
                                    value: commessaId,
                                    leading: Icons.work_outline,
                                    onSelected: (v) => setState(() => commessaId = v),
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
                                            orarioRitorno = null;
                                          _ritornoDiverso = false;
                                          aeroportoRitornoDest = null;
                                          _aeroportoRitornoDestCtrl.clear();
                                          }),
                                        ),
                                        ChoiceChip(
                                          label: const Text('A/R'),
                                          selected: viaggioTipo == 'AR',
                                          onSelected: (_) => setState(() {
                                            viaggioTipo = 'AR';
                                            _ritornoDiverso = false;
                                            aeroportoRitornoDest = null;
                                            _aeroportoRitornoDestCtrl.clear();
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('Orario andata: ${orarioPartenza ?? '--:--'}',
                                            style: const TextStyle(fontSize: 14)),
                                      ),
                                      ElevatedButton(
                                        onPressed: _pickTime,
                                        child: const Text('Orario andata'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (viaggioTipo == 'AR') ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Ritorno: ${dataRitorno == null ? '--' : _displayDate(dataRitorno!)}',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        ElevatedButton(
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
                                            'Orario ritorno: ${orarioRitorno ?? '--:--'}',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        ElevatedButton(
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
                                          aeroportoRitornoDest = null;
                                          _aeroportoRitornoDestCtrl.clear();
                                        } else {
                                          aeroportoRitornoDest ??=
                                              aeroportoPartenza;
                                          _aeroportoRitornoDestCtrl.text =
                                              aeroportoRitornoDest ?? '';
                                        }
                                      }),
                                      title: const Text('Ritorno diverso'),
                                    ),
                                    if (_ritornoDiverso) ...[
                                      _dropdownSearch(
                                        label: 'Seleziona destinazione',
                                        textCtrl: _aeroportoRitornoDestCtrl,
                                        sourceMap: _aeroporti,
                                        value: aeroportoRitornoDest,
                                        leading: Icons.location_on,
                                        onSelected: (v) => setState(() {
                                          aeroportoRitornoDest = v;
                                        }),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: bagaglio,
                                      hint: const Text('Seleziona bagaglio'),
                                      decoration: const InputDecoration(
                                        labelText: 'Bagaglio *',
                                        border: UnderlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'mano', child: Text('Bagaglio a mano')),
                                        DropdownMenuItem(value: 'stiva', child: Text('Bagaglio in stiva')),
                                      ],
                                      onChanged: (v) => setState(() => bagaglio = v),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SwitchListTile(
                                          title: const Text('Parcheggio'),
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          value: parcheggio,
                                          onChanged: (v) => setState(() => parcheggio = v),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (parcheggio) ...[
                                    TextField(
                                      controller: targaCtrl,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: 'Targa veicolo',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
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
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _insertInFlight ? null : _insertBooking,
                                      child: _insertInFlight
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2.2),
                                            )
                                          : const Text('Inserisci prenotazione'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Data volo: ${_displayDate(dataVolo)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  CalendarDatePicker(
                                    initialDate: dataVolo,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                    onDateChanged: (d) => setState(() => dataVolo = d),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Prenotazioni',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                              // Manteniamo una larghezza minima alta per non tagliare le ultime colonne.
                              width: (MediaQuery.of(context).size.width).clamp(1500, 2200),
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
                                  DataColumn(label: Text('Bagaglio')),
                                  DataColumn(label: Text('Parcheggio')),
                                  DataColumn(label: Text('Targa')),
                                  DataColumn(label: Text('Stato')),
                                  DataColumn(label: Text('Azioni')),
                                  DataColumn(label: Text('Note')),
                                ],
                                source: _AereiTableSource(
                                  rows: _rows,
                                  fmtDate: _fmtDate,
                                  personale: _personale,
                                  commesse : _commesse,
                                  requesters: _requestersMap,
                                  onDeleteRejected: _deleteRejectedBooking,
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

class _AereiTableSource extends DataTableSource {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic) fmtDate;
  final Map<String, String> personale; 
  final Map<String, String> commesse;  
  final Map<String, String> requesters;
  final void Function(Map<String, dynamic> row) onDeleteRejected;

  _AereiTableSource({
    required this.rows,
    required this.fmtDate,
    required this.personale,
    required this.commesse,
    required this.requesters,
    required this.onDeleteRejected,
  });

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CONFERMATA': return Colors.green;
      case 'IN_ATTESA': return Colors.orange;
      case 'RIFIUTATA': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];

    final persona = personale[(r['personale_id'] ?? '').toString()] ?? (r['personale_id'] ?? '').toString();
    final commessa = commesse[(r['commessa_id'] ?? '').toString()] ?? (r['commessa_id'] ?? '').toString();

    final bag = (r['bagaglio'] ?? '').toString();
    final park = (r['parcheggio'] == true) ? 'Sì' : 'No';
    final targa = (r['targa_veicolo'] ?? '').toString();
    final stato = (r['status'] ?? '').toString();
    final note  = (r['master_note'] ?? r['note'] ?? '').toString();
    final ritornoDiverso = (r['aeroporto_arrivo_ritorno'] ?? '')
                .toString()
                .trim()
                .isNotEmpty &&
            (r['aeroporto_arrivo_ritorno'] ?? '').toString().trim() !=
                (r['aeroporto_partenza'] ?? '').toString().trim();
    final ritornoDiversoVal = ritornoDiverso
        ? (r['aeroporto_arrivo_ritorno'] ?? '').toString().trim()
        : '';
    final insertedAtLabel = (() {
      final s = formatDateTimeItFromSupabase(r['created_at']);
      return s.isEmpty ? '—' : s;
    })();

    return DataRow(
      cells: [
        DataCell(Text(persona)),
        DataCell(Text(fmtDate(r['data']))),
        DataCell(Text((r['orario'] ?? '').toString())),
        DataCell(Text((r['aeroporto_partenza'] ?? '').toString())),
        DataCell(Text((r['aeroporto_arrivo'] ?? '').toString())),
        DataCell(Text(fmtDate(r['data_ritorno']))),
        DataCell(Text((r['orario_ritorno'] ?? '').toString())),
        DataCell(Text(ritornoDiversoVal)),
        DataCell(Text(commessa)),
        DataCell(Text(bag == 'stiva' ? 'In stiva' : 'A mano')),
        DataCell(Text(park)),
        DataCell(Text(targa)),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(stato).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stato,
              style: TextStyle(color: _statusColor(stato), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 56,
            child: IconButton(
              tooltip: 'Cancella richiesta rifiutata',
              icon: const Icon(Icons.delete_outline),
              onPressed: (() {
                final raw = stato.toUpperCase();
                final workflow = (r['workflow_status'] ?? '').toString().toUpperCase();
                final canDelete = raw == 'RIFIUTATA' || workflow == 'RIFIUTATA_DAL_DT';
                return canDelete ? () => onDeleteRejected(r) : null;
              })(),
            ),
          ),
        ),
        DataCell(() {
          final reqId = (r['requested_by_user_id'] ?? '').toString().trim();
          final reqName = reqId.isNotEmpty ? (requesters[reqId] ?? reqId) : null;
          final text = (reqName == null || reqName.isEmpty)
              ? note
              : (note.trim().isEmpty ? 'Richiedente: $reqName' : 'Richiedente: $reqName\n$note');
          return SizedBox(
            width: 220,
            child: NotePreviewText(
              note: text,
              maxChars: 10,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }()),
      ].map((c) => DataCell(
            Tooltip(
              message: 'Inserita il: $insertedAtLabel',
              waitDuration: const Duration(milliseconds: 220),
              child: c.child,
            ),
          )).toList(),
    );
  }

  @override bool get isRowCountApproximate => false;
  @override int get rowCount => rows.length;
  @override int get selectedRowCount => 0;
}