import 'package:flutter/material.dart';
import 'dart:async';
import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/neo_buttons.dart';
import '../utils/dt_user_list.dart';
import '../utils/dipendente_view_navigation.dart';
import '../utils/booking_inserted_by.dart';
import '../utils/booking_maps_link.dart';
import '../utils/booking_modifica_display.dart';
import '../utils/date_formatters.dart';
import '../hub/custom_hub_page_config.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

/// Squadra nominata: una combinazione salvata di persone selezionate.
class _PernottiSquadra {
  final String id;
  final String nome;
  final List<String> personaleIds; // personale.id_uuid

  _PernottiSquadra({
    required this.id,
    required this.nome,
    required this.personaleIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'personaleIds': personaleIds,
      };
}

/// DT/Admin — Prenotazione pernottamenti
/// - Dizionari con id_uuid (UUID)
/// - Inserimento su bookings con status = 'IN_ATTESA'
/// - Colonna “Posizione” con icona cliccabile (no URL in chiaro)
/// - UI compatta + campi con ricerca digitando (DropdownMenu Material 3)
class PrenotazionePernottamentiPage extends StatefulWidget {
  final String username;
  final int userId; // legacy int (per log/compat)
  final String role;
  final String fullName;
  final String? customHubLayoutKey;
  final String? pageTitle;
  final CustomHubPageConfig? pageConfig;
  final VoidCallback? onEditPageConfig;

  const PrenotazionePernottamentiPage({
    super.key,
    required this.username,
    required this.userId,
    required this.role,
    required this.fullName,
    this.customHubLayoutKey,
    this.pageTitle,
    this.pageConfig,
    this.onEditPageConfig,
  });

  @override
  State<PrenotazionePernottamentiPage> createState() =>
      _PrenotazionePernottamentiPageState();
}

class _PrenotazionePernottamentiPageState
    extends State<PrenotazionePernottamentiPage> {
  static const String kTable = 'bookings';
  static const Duration _requestManageGrace = Duration(minutes: 5);

  bool get _isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';

  String _fl(String id, String fallback) =>
      widget.pageConfig?.fieldLabel(id, fallback) ?? fallback;

  bool _fv(String id) => widget.pageConfig?.isFieldVisible(id) ?? true;

  String _cl(String id, String fallback) =>
      widget.pageConfig?.columnLabel(id, fallback) ?? fallback;

  // Assistente DT: selezione DT supervisionato.
  // - filtra squads e prenotazioni
  // - imposta dt_user_uuid durante l'inserimento
  String? _selectedDtUuidForAssist;
  final _dtAssistantCtrl = TextEditingController();
  final Map<String, String> _dtOptions = {}; // id_uuid -> label

  String? get _effectiveDtUuid =>
      _isAssistenteDt ? _selectedDtUuidForAssist : _currentDtUuid;

  // ===== Squadre (batch di personale nominati) =====
  final List<_PernottiSquadra> _squads = [];
  String? _selectedSquadId;
  final _squadNameCtrl = TextEditingController();

  // Dizionari display (UUID -> label)
  final Map<String, String> _personale = {};   // personale.id_uuid   -> full_name
  final Map<String, String> _personaleCameraDefault = {}; // personale.id_uuid -> singola/doppia
  final Map<String, String> _structures = {};  // structures.id_uuid  -> name
  final Map<String, String> _commesse   = {};  // commesse.id_uuid    -> nome

  // users lookup per mostrare "Inserito da" correttamente per ogni riga.
  // booking.updated_by (inserimento) viene salvato come users.id_uuid.
  final Map<String, String> _usersByUuid = {}; // users.id_uuid -> label
  final Map<String, String> _usersById = {}; // users.id (int) -> label
  final Map<String, String> _userRoleByUuid = {}; // users.id_uuid -> role
  final Map<String, String> _userRoleById = {}; // users.id -> role

  // Info struttura: address + maps_link (by id_uuid)
  final Map<String, String> _structureAddress = {}; // id_uuid -> address
  final Map<String, String> _structureMapLink = {}; // id_uuid -> maps_link

  // Scelte form (tutte chiavi UUID)
  String? personaleId;  // personale.id_uuid
  final List<String> _selectedPersonaleIds = []; // multi-selection
  String? structureId;  // structures.id_uuid
  String? commessaId;   // commesse.id_uuid
  String cameraTipo = 'doppia'; // 'singola' | 'doppia'
  final noteCtrl = TextEditingController();

  String _cameraTipoForPersonale(String? personaleUuid) {
    final pref = (_personaleCameraDefault[personaleUuid] ?? '').trim().toLowerCase();
    return pref == 'singola' ? 'singola' : 'doppia';
  }

  String _cameraTipoLabelForSelection(List<String> personaleIds) {
    if (personaleIds.isEmpty) return 'Doppia';
    final set = personaleIds.map(_cameraTipoForPersonale).toSet();
    if (set.length == 1) return set.first == 'singola' ? 'Singola' : 'Doppia';
    return 'Mista (da anagrafica dipendente)';
  }

  // Controller testuali per DropdownMenu (così puoi digitare per filtrare)
  final _personaleCtrl = TextEditingController();
  final _strutturaCtrl = TextEditingController();
  final _commessaCtrl  = TextEditingController();

  // Range date
  List<DateTime?> _range = [
    DateTime.now(),
    DateTime.now().add(const Duration(days: 1)),
  ];

  // DT corrente (UUID: users.id oppure users.id_uuid)
  String? _currentDtUuid;

  // Stato/caricamento
  bool loadingDicts = false;
  bool loadingRows = false;
  bool _insertInFlight = false;
  List<Map<String, dynamic>> _rows = [];
  int _rowsPerPage = 10;
  Timer? _requestModifyTimer;

  @override
  void initState() {
    super.initState();
    _requestModifyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hasPending = _rows.any(
        (r) => (r['status'] ?? '').toString().toUpperCase() == 'RICHIESTA_MODIFICA',
      );
      final hasManageWindow = _rows.any((r) {
        final rem = _remainingManageRequestTime(r);
        return rem != null && rem > Duration.zero;
      });
      if (hasPending || hasManageWindow) setState(() {});
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _fetchCurrentUserUuid();
    if (_isAssistenteDt) {
      await _loadDtOptionsForAssistente();
    }
    await _loadDizionari();
    await _loadSquads();
    _syncDropdownTexts();
    await _loadRows();
  }

  Future<void> _requestModify(Map<String, dynamic> current) async {
    if (!await ensureCanPersist(context)) return;
    final id = current['id'];
    if (id == null) {
      _msg('Prenotazione non valida (id mancante).', isError: true);
      return;
    }

    // Prefill: se c'è già una richiesta pendente, usa i valori proposti.
    final source = isRichiestaModifica(current) &&
            modificaPayloadOf(current).isNotEmpty
        ? modificaPayloadOf(current)
        : current;
    String? strutturaKey = (
      source['struttura_id'] ??
      source['structure_id'] ??
      source['structure_uuid']
    )?.toString();
    strutturaKey = strutturaKey != null && _structures.containsKey(strutturaKey) ? strutturaKey : structureId;
    String? commessaKey = (
      source['commessa_id'] ??
      source['commessa_uuid'] ??
      source['id_commessa']
    )?.toString();
    commessaKey = commessaKey != null && _commesse.containsKey(commessaKey) ? commessaKey : commessaId;
    String? personaleKey = (
      source['personale_id'] ??
      source['personale_uuid'] ??
      source['id_personale']
    )?.toString();
    personaleKey = personaleKey != null && _personale.containsKey(personaleKey) ? personaleKey : personaleId;
    DateTime? dal = DateTime.tryParse((source['start_date'] ?? current['start_date'] ?? '').toString());
    DateTime? al = DateTime.tryParse((source['end_date'] ?? current['end_date'] ?? '').toString());
    final note = (source['master_note'] ?? current['master_note'] ?? '').toString();

    final noteCtrl2 = TextEditingController(text: note);
    String? strutturaSel = strutturaKey;
    String? commessaSel = commessaKey;
    String? personaleSel = personaleKey;
    DateTime? dalSel = dal;
    DateTime? alSel = al;
    String cameraSel = _cameraTipoForPersonale(personaleSel);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSt) {
          return AlertDialog(
            title: const Text('Richiedi modifica'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownMenu<String>(
                      label: const Text('Persona'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: personaleSel,
                      dropdownMenuEntries: _personale.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() {
                        personaleSel = v;
                        cameraSel = _cameraTipoForPersonale(v);
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownMenu<String>(
                      label: const Text('Struttura'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: strutturaSel,
                      dropdownMenuEntries: _structures.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() => strutturaSel = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownMenu<String>(
                      label: const Text('Commessa'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: commessaSel,
                      dropdownMenuEntries: _commesse.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() => commessaSel = v),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tipo camera automatico: ${cameraSel == 'singola' ? 'Singola' : 'Doppia'}',
                        style: Theme.of(ctx2).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx2,
                                initialDate: dalSel ?? now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setSt(() {
                                  dalSel = picked;
                                  if (alSel != null && picked.isAfter(alSel!)) alSel = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Dal',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(dalSel == null ? '—' : _displayDate(dalSel!)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx2,
                                initialDate: alSel ?? (dalSel ?? now),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setSt(() {
                                  alSel = picked;
                                  if (dalSel != null && picked.isBefore(dalSel!)) dalSel = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Al',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(alSel == null ? '—' : _displayDate(alSel!)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl2,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Annulla')),
              FilledButton(onPressed: () => Navigator.pop(ctx2, true), child: const Text('Invia richiesta')),
            ],
          );
        });
      },
    );
    if (ok != true) return;

    if (personaleSel == null || strutturaSel == null || commessaSel == null || dalSel == null || alSel == null) {
      _msg('Compila tutti i campi.', isError: true);
      return;
    }

    try {
      final wasPending = (current['status'] ?? '').toString().toUpperCase() == 'RICHIESTA_MODIFICA';
      final existingRequestedAt = DateTime.tryParse(
        (current['modifica_requested_at'] ?? '').toString(),
      );
      final requestedAtToPersist = wasPending && existingRequestedAt != null
          ? existingRequestedAt.toIso8601String()
          : supabaseNowIsoUtc();
      final payload = <String, dynamic>{
        'personale_id': personaleSel,
        'personale_uuid': personaleSel,
        'id_personale': personaleSel,
        // manteniamo entrambe le chiavi per compatibilità schema legacy
        'struttura_id': strutturaSel,
        'structure_id': strutturaSel,
        'structure_uuid': strutturaSel,
        'commessa_id': commessaSel,
        'commessa_uuid': commessaSel,
        'id_commessa': commessaSel,
        'camera_tipo': cameraSel,
        'start_date': _iso(dalSel!),
        'end_date': _iso(alSel!),
        'master_note': noteCtrl2.text.trim(),
      };

      await SupabaseService.client.from(kTable).update({
        'status': 'RICHIESTA_MODIFICA',
        'modifica_payload': payload,
        'modifica_note': wasPending
            ? 'Modifica richiesta aggiornata da DT'
            : 'Modifica richiesta da DT',
        'modifica_requested_at': requestedAtToPersist,
      }).eq('id', id);

      // Notifica agli admin pernottamenti (admin_type=2)
      try {
        final adminIds = await NotificationSender.getAdminIdsByType(2);
        // evita auto-notifica (se l'utente corrente è anche admin)
        adminIds.removeWhere((x) => x == widget.userId);
        if (adminIds.isNotEmpty) {
          await NotificationSender.sendToUserIds(
            userIds: adminIds,
            bookingId: int.tryParse(id.toString()) ?? 0,
            action: 'pernottamento_modifica_richiesta',
            title: 'Pernottamento: richiesta modifica',
            message: '${widget.fullName} ha richiesto una modifica su un pernottamento.',
          );
        }
      } catch (_) {}

      await _loadRows();
      _msg(
        'Richiesta modifica inviata all\'admin. '
        'Notifica inviata a: admin pernottamenti.',
      );
    } catch (e) {
      _msg('Errore richiesta modifica: $e', isError: true);
    }
  }

  Duration? _remainingManageRequestTime(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status != 'IN_ATTESA') return null;
    // created_at è timestamptz UTC (spesso senza suffisso Z da PostgREST).
    final createdAt = parseSupabaseTimestampToUtc(row['created_at']);
    if (createdAt == null) return null;
    final elapsed = DateTime.now().toUtc().difference(createdAt);
    final remaining = _requestManageGrace - elapsed;
    if (remaining <= Duration.zero) return Duration.zero;
    return remaining;
  }

  bool _canManageRecentRequest(Map<String, dynamic> row) {
    final rem = _remainingManageRequestTime(row);
    return rem != null && rem > Duration.zero;
  }

  String _manageRequestTimerLabel(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString().toUpperCase();
    if (status != 'IN_ATTESA') return '';
    final rem = _remainingManageRequestTime(row);
    if (rem == null) return '';
    if (rem <= Duration.zero) return 'Finestra modifica/cancella scaduta';
    final mm = rem.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = rem.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Modifica/annulla entro: $mm:$ss';
  }

  Future<void> _notifyPernottamentiAdmins({
    required int bookingId,
    required String action,
    required String title,
    required String message,
  }) async {
    try {
      final adminIds = await NotificationSender.getAdminIdsByType(2);
      adminIds.removeWhere((id) => id == widget.userId);
      if (adminIds.isEmpty) return;
      await NotificationSender.sendToUserIds(
        userIds: adminIds,
        bookingId: bookingId,
        action: action,
        title: title,
        message: message,
      );
    } catch (_) {
      // Non bloccare il flusso utente se la notifica fallisce.
    }
  }

  Future<void> _editRecentBooking(Map<String, dynamic> current) async {
    if (!_canManageRecentRequest(current)) {
      _msg(
        'Tempo scaduto: puoi modificare la richiesta solo entro 5 minuti dall\'invio.',
        isError: true,
      );
      return;
    }

    final id = int.tryParse((current['id'] ?? '').toString());
    if (id == null) {
      _msg('Prenotazione non valida (id mancante).', isError: true);
      return;
    }

    String? strutturaKey = (
      current['struttura_id'] ??
      current['structure_id'] ??
      current['structure_uuid']
    )?.toString();
    strutturaKey = strutturaKey != null && _structures.containsKey(strutturaKey) ? strutturaKey : structureId;
    String? commessaKey = (
      current['commessa_id'] ??
      current['commessa_uuid'] ??
      current['id_commessa']
    )?.toString();
    commessaKey = commessaKey != null && _commesse.containsKey(commessaKey) ? commessaKey : commessaId;
    String? personaleKey = (
      current['personale_id'] ??
      current['personale_uuid'] ??
      current['id_personale']
    )?.toString();
    personaleKey = personaleKey != null && _personale.containsKey(personaleKey) ? personaleKey : personaleId;
    DateTime? dal = DateTime.tryParse((current['start_date'] ?? '').toString());
    DateTime? al = DateTime.tryParse((current['end_date'] ?? '').toString());
    final note = (current['master_note'] ?? '').toString();

    final noteCtrl2 = TextEditingController(text: note);
    String? strutturaSel = strutturaKey;
    String? commessaSel = commessaKey;
    String? personaleSel = personaleKey;
    DateTime? dalSel = dal;
    DateTime? alSel = al;
    String cameraSel = _cameraTipoForPersonale(personaleSel);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSt) {
          return AlertDialog(
            title: const Text('Modifica richiesta (entro 5 minuti)'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownMenu<String>(
                      label: const Text('Persona'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: personaleSel,
                      dropdownMenuEntries: _personale.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() {
                        personaleSel = v;
                        cameraSel = _cameraTipoForPersonale(v);
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownMenu<String>(
                      label: const Text('Struttura'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: strutturaSel,
                      dropdownMenuEntries: _structures.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() => strutturaSel = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownMenu<String>(
                      label: const Text('Commessa'),
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      initialSelection: commessaSel,
                      dropdownMenuEntries: _commesse.entries
                          .map((e) => DropdownMenuEntry(value: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (v) => setSt(() => commessaSel = v),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tipo camera automatico: ${cameraSel == 'singola' ? 'Singola' : 'Doppia'}',
                        style: Theme.of(ctx2).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx2,
                                initialDate: dalSel ?? now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setSt(() {
                                  dalSel = picked;
                                  if (alSel != null && picked.isAfter(alSel!)) alSel = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Dal',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(dalSel == null ? '—' : _displayDate(dalSel!)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx2,
                                initialDate: alSel ?? (dalSel ?? now),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setSt(() {
                                  alSel = picked;
                                  if (dalSel != null && picked.isBefore(dalSel!)) dalSel = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Al',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(alSel == null ? '—' : _displayDate(alSel!)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl2,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Annulla')),
              FilledButton(onPressed: () => Navigator.pop(ctx2, true), child: const Text('Salva')),
            ],
          );
        });
      },
    );
    if (ok != true) return;

    if (personaleSel == null || strutturaSel == null || commessaSel == null || dalSel == null || alSel == null) {
      _msg('Compila tutti i campi.', isError: true);
      return;
    }

    try {
      await SupabaseService.client.from(kTable).update({
        'personale_id': personaleSel,
        'struttura_id': strutturaSel,
        'commessa_id': commessaSel,
        'camera_tipo': cameraSel,
        'start_date': _iso(dalSel!),
        'end_date': _iso(alSel!),
        'master_note': noteCtrl2.text.trim(),
        'updated_by': _currentDtUuid,
      }).eq('id', id);

      await _notifyPernottamentiAdmins(
        bookingId: id,
        action: 'update',
        title: 'Pernottamento modificato da DT',
        message: '${widget.fullName} ha modificato una richiesta entro 5 minuti.',
      );

      await _loadRows();
      _msg('Richiesta modificata correttamente.');
    } catch (e) {
      _msg('Errore modifica richiesta: $e', isError: true);
    }
  }

  Future<void> _deleteRecentBooking(Map<String, dynamic> row) async {
    if (!await ensureCanPersist(context)) return;
    if (!_canManageRecentRequest(row)) {
      _msg(
        'Tempo scaduto: puoi cancellare la richiesta solo entro 5 minuti dall\'invio.',
        isError: true,
      );
      return;
    }

    final id = int.tryParse((row['id'] ?? '').toString());
    if (id == null) {
      _msg('Prenotazione non valida (id mancante).', isError: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma cancellazione'),
        content: const Text(
          'Vuoi cancellare questa richiesta pernottamento? '
          'L\'operazione e consentita solo entro 5 minuti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Si, cancella'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _notifyPernottamentiAdmins(
        bookingId: id,
        action: 'delete',
        title: 'Pernottamento cancellato da DT',
        message: '${widget.fullName} ha cancellato una richiesta entro 5 minuti.',
      );

      await SupabaseService.client.from(kTable).delete().eq('id', id);
      await _loadRows();
      _msg('Richiesta cancellata correttamente.');
    } catch (e) {
      _msg('Errore cancellazione richiesta: $e', isError: true);
    }
  }


  void _syncDropdownTexts() {
    _personaleCtrl.text = personaleId == null ? '' : (_personale[personaleId!] ?? '');
    _strutturaCtrl.text = structureId == null ? '' : (_structures[structureId!] ?? '');
    _commessaCtrl.text  = commessaId  == null ? '' : (_commesse[commessaId!] ?? '');
  }

  Future<void> _loadSquads() async {
    _squads.clear();
    _selectedSquadId = null;
    try {
      final effectiveDtUuid = _effectiveDtUuid;
      if (effectiveDtUuid == null || effectiveDtUuid.isEmpty) return;
      final res = await SupabaseService.client
          .from('pernotti_squads')
          .select('id,nome,personale_ids')
          .eq('dt_user_uuid', effectiveDtUuid)
          .order('nome');
      final list = res as List;
      _squads.addAll(list.map((e) {
        final m = e as Map<String, dynamic>;
        return _PernottiSquadra(
          id: (m['id'] ?? '').toString(),
          nome: (m['nome'] ?? '').toString(),
          personaleIds: (m['personale_ids'] as List<dynamic>? ?? [])
              .map((x) => x.toString())
              .toList(),
        );
      }));
    } catch (_) {
      // se faila il parsing, non blocchiamo la UI
    }
    if (mounted) setState(() {});
  }

  void _applySquad(_PernottiSquadra squad) {
    setState(() {
      _selectedPersonaleIds
        ..clear()
        ..addAll(squad.personaleIds);
      personaleId = squad.personaleIds.isNotEmpty ? squad.personaleIds.first : null;
      _selectedSquadId = squad.id;
      _syncDropdownTexts();
      if (personaleId != null) {
        final pref = (_personaleCameraDefault[personaleId!] ?? '').trim().toLowerCase();
        if (pref == 'singola' || pref == 'doppia') {
          cameraTipo = pref;
        }
      }
    });
  }

  Future<void> _saveSquadFromSelection() async {
    if (!await ensureCanPersist(context)) return;
    try {
      final selected = _selectedPersonaleIds.toList();
      if (selected.isEmpty && personaleId != null) {
        selected.add(personaleId!);
      }
      if (selected.isEmpty) {
        _msg('Seleziona almeno una persona nella squadra.', isError: true);
        return;
      }

      final nameFromCtrl = _squadNameCtrl.text.trim();

      if (_selectedSquadId != null) {
        final idx = _squads.indexWhere((s) => s.id == _selectedSquadId);
        if (idx >= 0) {
          final existing = _squads[idx];
          final nome = nameFromCtrl.isNotEmpty ? nameFromCtrl : existing.nome;
          await SupabaseService.client
              .from('pernotti_squads')
              .update({'nome': nome, 'personale_ids': selected})
              .eq('id', existing.id);
          _squads[idx] = _PernottiSquadra(
            id: existing.id,
            nome: nome,
            personaleIds: selected,
          );
          if (mounted) setState(() {});
          _msg('Squadra aggiornata: $nome');
          return;
        }
      }

      // Creazione nuova
      if (nameFromCtrl.isEmpty) {
        _msg('Dai un nome alla squadra.', isError: true);
        return;
      }

      // Se esiste già una squadra con lo stesso nome, la sovrascriviamo.
      final existingIndex =
          _squads.indexWhere((s) => s.nome.toLowerCase() == nameFromCtrl.toLowerCase());
      if (existingIndex >= 0) {
        final existing = _squads[existingIndex];
        await SupabaseService.client
            .from('pernotti_squads')
            .update({'nome': nameFromCtrl, 'personale_ids': selected})
            .eq('id', existing.id);
        _squads[existingIndex] = _PernottiSquadra(
          id: existing.id,
          nome: nameFromCtrl,
          personaleIds: selected,
        );
        _selectedSquadId = existing.id;
        if (mounted) setState(() {});
        _msg('Squadra salvata (aggiornata): $nameFromCtrl');
        return;
      }

      // Nuova squadra: lasciamo generare l'UUID a Postgres/Supabase e recuperiamo l'id.
      final effectiveDtUuid = _effectiveDtUuid;
      if (effectiveDtUuid == null || effectiveDtUuid.isEmpty) {
        _msg('dt_user_uuid non disponibile.', isError: true);
        return;
      }
      final inserted = await SupabaseService.client
          .from('pernotti_squads')
          .insert({
            'dt_user_uuid': effectiveDtUuid,
            'nome': nameFromCtrl,
            'personale_ids': selected,
          })
          .select('id')
          .single();

      final newId = inserted['id']?.toString() ?? '';
      final updated = _PernottiSquadra(
        id: newId,
        nome: nameFromCtrl,
        personaleIds: selected,
      );
      _squads.add(updated);
      _selectedSquadId = newId;
      if (mounted) setState(() {});
      _msg('Squadra salvata: ${updated.nome}');
    } catch (e) {
      _msg('Errore salvataggio squadre: $e', isError: true);
    }
  }

  Future<void> _deleteSelectedSquad() async {
    if (_selectedSquadId == null) return;
    if (!await ensureCanPersist(context)) return;
    final squadId = _selectedSquadId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina squadra'),
        content: const Text('Confermi eliminazione della squadra selezionata?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('pernotti_squads').delete().eq('id', squadId);
      setState(() {
        _squads.removeWhere((s) => s.id == squadId);
        _selectedSquadId = null;
        _squadNameCtrl.clear();
      });
      _msg('Squadra eliminata.');
    } catch (e) {
      _msg('Errore eliminazione squadra: $e', isError: true);
    }
  }

  // Risolve l'UUID del DT corrente: policy RLS usa `users.id_uuid` (quindi
  // lo cerchiamo prima lì, come fallback proviamo `users.id`).
  Future<void> _fetchCurrentUserUuid() async {
    try {
      final authUser = SupabaseService.client.auth.currentUser;
      if (authUser != null) {
        final byAuth = await SupabaseService.client
            .from('users')
            .select('id_uuid')
            .eq('auth_id', authUser.id)
            .maybeSingle();
        final authUuid = (byAuth?['id_uuid'] ?? '').toString().trim();
        if (authUuid.length >= 32) {
          _currentDtUuid = authUuid;
          return;
        }
      }

      final byId = await SupabaseService.client
          .from('users')
          .select('id_uuid')
          .eq('id', widget.userId)
          .maybeSingle();
      final idUuid = (byId?['id_uuid'] ?? '').toString().trim();
      if (idUuid.length >= 32) {
        _currentDtUuid = idUuid;
        return;
      }

      final r2 = await SupabaseService.client
          .from('users')
          .select('id_uuid, username')
          .eq('username', widget.username)
          .maybeSingle();
      if (r2 != null &&
          r2['id_uuid'] is String &&
          (r2['id_uuid'] as String).length >= 32) {
        _currentDtUuid = r2['id_uuid'] as String;
        return;
      }

      final r1 = await SupabaseService.client
          .from('users')
          .select('id, username')
          .eq('username', widget.username)
          .maybeSingle();
      if (r1 != null &&
          r1['id'] is String &&
          (r1['id'] as String).length >= 32) {
        _currentDtUuid = r1['id'] as String;
        return;
      }
      _msg('Attenzione: impossibile determinare dt_user_uuid.', isError: true);
    } catch (e) {
      _msg('Errore utente corrente: $e', isError: true);
    }
  }

  Future<void> _loadDtOptionsForAssistente() async {
    _dtOptions.clear();
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

      if (allowedUuids.isNotEmpty) {
        final orExpr =
            allowedUuids.map((u) => 'id_uuid.eq.$u').join(',');
        final dtRes = await SupabaseService.client
            .from('users')
            .select('id_uuid, full_name, username')
            .or(orExpr);

        for (final e in (dtRes as List)) {
          final idUuid = (e['id_uuid'] ?? '').toString().trim();
          if (idUuid.isEmpty) continue;
          final label = (e['full_name'] ?? '').toString().trim().isNotEmpty
              ? (e['full_name'] ?? '').toString().trim()
              : (e['username'] ?? '').toString().trim();
          _dtOptions[idUuid] = label.isNotEmpty ? label : idUuid;
        }
      }

      if (_dtOptions.isNotEmpty) {
        if (_selectedDtUuidForAssist == null ||
            !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
          _selectedDtUuidForAssist = _dtOptions.keys.first;
        }
      }

      if (mounted && _selectedDtUuidForAssist != null) {
        _dtAssistantCtrl.text =
            _dtOptions[_selectedDtUuidForAssist!] ?? '';
      }
    } catch (_) {
      _dtOptions.addAll(await loadDtOptionsByUuid());
      if (_selectedDtUuidForAssist == null && _dtOptions.isNotEmpty) {
        _selectedDtUuidForAssist = _dtOptions.keys.first;
      }
      if (mounted && _selectedDtUuidForAssist != null) {
        _dtAssistantCtrl.text =
            _dtOptions[_selectedDtUuidForAssist!] ?? '';
      }
    }
  }

  // Carica dizionari (⚠️ Personale/Strutture/Commesse con id_uuid)
  Future<void> _loadDizionari() async {
    setState(() => loadingDicts = true);
    try {
      // PERSONALE — usa id_uuid (UUID)
      final p = await SupabaseService.client
          .from('personale')
          .select('id_uuid, full_name, camera_tipo_default, active')
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
      _personaleCameraDefault
        ..clear()
        ..addEntries(
          ((p as List).map((e) {
            final id = (e['id_uuid'] ?? '').toString();
            final raw = (e['camera_tipo_default'] ?? 'doppia')
                .toString()
                .trim()
                .toLowerCase();
            return MapEntry(id, raw == 'singola' ? 'singola' : 'doppia');
          })),
        );

      // STRUTTURE — id_uuid + address + maps_link
      final s = await SupabaseService.client
          .from('structures')
          .select('id_uuid, name, address, maps_link, active')
          .eq('active', true)
          .order('name');
      _structures.clear();
      _structureAddress.clear();
      _structureMapLink.clear();
      for (final e in (s as List)) {
        final id = (e['id_uuid'] ?? '').toString();
        _structures[id] = (e['name'] ?? '').toString();
        final addr = (e['address'] ?? '').toString();
        final link = (e['maps_link'] ?? '').toString();
        if (addr.isNotEmpty) _structureAddress[id] = addr;
        if (link.isNotEmpty) _structureMapLink[id] = link;
      }

      // COMMESSE — id_uuid + active
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

      // USERS — lookup per chi ha inserito (bookings.updated_by)
      final u = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, full_name, username, role')
          .order('username');
      _usersByUuid.clear();
      _usersById.clear();
      _userRoleByUuid.clear();
      _userRoleById.clear();
      for (final e in (u as List)) {
        final idUuid = (e['id_uuid'] ?? '').toString();
        final idInt = (e['id'] ?? '').toString();
        final label = (e['full_name'] ?? e['username'] ?? '').toString();
        final role = (e['role'] ?? '').toString().trim().toLowerCase();
        if (idUuid.trim().isNotEmpty) _usersByUuid[idUuid.trim()] = label.trim();
        if (idInt.trim().isNotEmpty) _usersById[idInt.trim()] = label.trim();
        if (idUuid.trim().isNotEmpty) _userRoleByUuid[idUuid.trim()] = role;
        if (idInt.trim().isNotEmpty) _userRoleById[idInt.trim()] = role;
      }

      setState(() {});
    } catch (e) {
      _msg('Errore caricamento liste: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingDicts = false);
    }
  }

  Future<void> _ensureUserLabelsForBookings(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = <String>{};
    for (final r in rows) {
      for (final key in ['created_by', 'updated_by', 'dt_user_uuid']) {
        final v = (r[key] ?? '').toString().trim();
        if (v.length >= 32 && v.contains('-')) ids.add(v);
      }
    }
    final missing =
        ids.where((id) => !_usersByUuid.containsKey(id)).toList(growable: false);
    if (missing.isEmpty) return;
    try {
      final users = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, full_name, username')
          .inFilter('id_uuid', missing);
      for (final e in (users as List)) {
        final idUuid = (e['id_uuid'] ?? '').toString().trim();
        final idInt = (e['id'] ?? '').toString().trim();
        final label =
            (e['full_name'] ?? e['username'] ?? '').toString().trim();
        if (idUuid.isNotEmpty && label.isNotEmpty) {
          _usersByUuid[idUuid] = label;
        }
        if (idInt.isNotEmpty && label.isNotEmpty) {
          _usersById[idInt] = label;
        }
      }
    } catch (_) {}
  }

  // Carica prenotazioni del DT corrente (finestra recente + limite anti-timeout)
  Future<void> _loadRows() async {
    setState(() => loadingRows = true);
    try {
      final customKey = widget.customHubLayoutKey?.trim();
      final fromDate = DateTime.now()
          .subtract(const Duration(days: 120))
          .toIso8601String()
          .substring(0, 10);

      dynamic q = SupabaseService.client.from(kTable).select(
            'id,personale_id,struttura_id,commessa_id,camera_tipo,'
            'start_date,end_date,status,master_note,dt_user_uuid,'
            'created_by,updated_by,custom_hub_layout_key,maps_link,'
            'created_at,modifica_payload,modifica_requested_at,'
            'modifica_confirmed_at',
          );

      if (customKey != null && customKey.isNotEmpty) {
        q = q.eq('custom_hub_layout_key', customKey);
      } else {
        final effectiveDtUuid = _effectiveDtUuid;
        if (_isAssistenteDt) {
          if (effectiveDtUuid == null ||
              _selectedDtUuidForAssist == null ||
              !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
            _rows = [];
            return;
          }
        }
        if (effectiveDtUuid != null && effectiveDtUuid.isNotEmpty) {
          q = q.filter('dt_user_uuid', 'eq', effectiveDtUuid);
        }
      }

      final res = await q
          .gte('start_date', fromDate)
          .order('start_date', ascending: false)
          .limit(500);
      _rows = List<Map<String, dynamic>>.from(res as List);
      await _ensureUserLabelsForBookings(_rows);
      setState(() {});
    } catch (e) {
      _msg('Errore caricamento prenotazioni: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingRows = false);
    }
  }

  // Inserisce il pernottamento (ORA tutti gli ID sono UUID)
  Future<void> _insertBooking() async {
    if (_insertInFlight) return;
    if (!await ensureCanPersist(context)) return;
    _insertInFlight = true;
    final dal = _range.isNotEmpty ? _range[0] : null;
    final al  = _range.length > 1 ? _range[1] : dal;

    final effectiveDtUuid = _effectiveDtUuid;
    if (effectiveDtUuid == null || effectiveDtUuid.isEmpty) {
      _msg('dt_user_uuid non disponibile.', isError: true);
      return;
    }
    // allow either a single selected person (personaleId) or multiple
    final persons = _selectedPersonaleIds.isNotEmpty ? _selectedPersonaleIds.toList() : (personaleId != null ? [personaleId!] : []);
    if (persons.isEmpty || structureId == null || commessaId == null || dal == null || al == null) {
      _msg('Compila: almeno una Persona, Struttura, Commessa e seleziona il periodo Dal/Al.', isError: true);
      return;
    }

    bool looksUuid(String v) => v.isNotEmpty && v.length >= 32 && v.contains('-');
    if (!persons.every((p) => looksUuid(p)) ||
        !(structureId != null && looksUuid(structureId!)) ||
        !(commessaId != null && looksUuid(commessaId!)) ||
        !looksUuid(effectiveDtUuid) ||
        (_isAssistenteDt &&
            (_selectedDtUuidForAssist == null ||
                !_dtOptions.containsKey(_selectedDtUuidForAssist)))) {
      _msg('Chiavi non valide (devono essere UUID). Controlla le selezioni.', isError: true);
      return;
    }

    try {
      final customKey = widget.customHubLayoutKey?.trim();
      final inserts = persons.map((pid) {
        final row = <String, dynamic>{
          'personale_id': pid,
          'struttura_id': structureId,
          'commessa_id': commessaId,
          'camera_tipo': _cameraTipoForPersonale(pid),
          'start_date': _iso(dal),
          'end_date': _iso(al),
          'status': 'IN_ATTESA',
          'master_note': noteCtrl.text.trim(),
          'dt_user_uuid': effectiveDtUuid,
          'created_at': supabaseNowIsoUtc(),
          'created_by': _currentDtUuid,
          'updated_by': _currentDtUuid,
        };
        if (customKey != null && customKey.isNotEmpty) {
          row['custom_hub_layout_key'] = customKey;
        }
        return row;
      }).toList();

      final inserted = await SupabaseService.client.from(kTable).insert(inserts).select('id');
      final firstId = inserted.isNotEmpty
          ? int.tryParse(inserted.first['id']?.toString() ?? '')
          : null;
      if (firstId != null) {
        await NotificationSender.notifyUserForBooking(
          dtUserId: widget.userId,
          bookingId: firstId,
          action: 'create',
          title: 'Nuova prenotazione pernottamento',
          bookingType: 'pernottamento',
        );
      }

      noteCtrl.clear();
      _personaleCtrl.clear();
      _strutturaCtrl.clear();
      _commessaCtrl.clear();
      setState(() {
        personaleId = null;
        _selectedPersonaleIds.clear();
        structureId = null;
        commessaId  = null;
      });

      await _loadRows();
      _msg(
        'Pernottamento inserito correttamente. '
        'Notifica inviata a: admin pernottamenti, richiedente e dipendente interessato.',
      );
    } catch (e) {
      _msg('Errore inserimento: $e', isError: true);
    } finally {
      _insertInFlight = false;
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

  bool _canRequestModify(Map<String, dynamic> row) => true;

  String _requestModifyTimerLabel(Map<String, dynamic> row) => '';

  void _msg(String text, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  // Stato → colore
  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'IN_ATTESA': return Colors.orange;
      case 'CONFERMATA': return Colors.green;
      case 'RIFIUTATA': return Colors.red;
      case 'RICHIESTA_MODIFICA': return Colors.deepOrange;
      case 'CONFERMA_MODIFICA': return Colors.blue;
      default: return Colors.grey;
    }
  }

  // ====== WIDGET: DropdownMenu con ricerca (Material 3) ======
  DropdownMenu<String> _dropdownSearch({
    required String label,
    required TextEditingController textCtrl,
    required Map<String, String> sourceMap, // id_uuid -> label
    required String? value,                 // id_uuid selezionato
    required void Function(String?) onSelected,
    IconData? leading,
  }) {
    // Nota: DropdownMenu filtra automaticamente in base al testo digitato.
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
      enableSearch: true, // in alcune versioni è sinonimo di enableFilter
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

  // ====== WIDGET: Multi-person selector (shows chips + opens dialog) ======
  Widget _multiPersonSelector({
    required Map<String, String> personale,
    required List<String> selectedIds,
    required String? singleValue,
    required void Function(List<String> selected, String? single) onChange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: selectedIds.map((id) {
            final label = personale[id] ?? id;
            return Chip(
              label: Text(label),
              onDeleted: () {
                final next = List<String>.from(selectedIds)..remove(id);
                onChange(next, next.isNotEmpty ? next.first : singleValue);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Seleziona persone'),
              onPressed: () async {
                final sorted = personale.entries.toList()
                  ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

                final picked = await showDialog<Set<String>>(context: context, builder: (ctx) {
                  final temp = Set<String>.from(selectedIds);
                  final filterCtrl = TextEditingController();
                  String filter = '';

                  return StatefulBuilder(builder: (ctx2, setSt) {
                    final query = filter.trim().toLowerCase();
                    final filtered = query.isEmpty
                        ? sorted
                        : sorted.where((e) => e.value.toLowerCase().contains(query)).toList();

                    return AlertDialog(
                      title: const Text('Seleziona persone'),
                      content: SizedBox(
                        width: 520,
                        height: 420,
                        child: Column(
                          children: [
                            TextField(
                              controller: filterCtrl,
                              autofocus: true,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Cerca nome...'
                              ),
                              onChanged: (v) => setSt(() => filter = v),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Scrollbar(
                                child: ListView(
                                  children: filtered.map((e) => CheckboxListTile(
                                        value: temp.contains(e.key),
                                        title: Text(e.value),
                                        onChanged: (v) => setSt(() => v == true ? temp.add(e.key) : temp.remove(e.key)),
                                      )).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx2, null), child: const Text('Annulla')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx2, temp), child: const Text('OK')),
                      ],
                    );
                  });
                });

                if (picked != null) {
                  final list = picked.toList();
                  onChange(list, list.isNotEmpty ? list.first : singleValue);
                }
              },
            ),
            const SizedBox(width: 8),
            if (singleValue != null && singleValue.isNotEmpty)
              Text('Selezione singola: ${_personale[singleValue] ?? singleValue}'),
          ],
        ),
      ],
    );
  }

  List<DataColumn> _buildDataColumns() {
    const defaults = <String, String>{
      'persona': 'Persona',
      'dal': 'Dal',
      'al': 'Al',
      'struttura': 'Struttura',
      'posizione': 'Posizione',
      'commessa': 'Commessa',
      'camera': 'Camera',
      'stato': 'Stato',
      'note': 'Note',
      'richiedente': 'Richiedente',
      'azioni': 'Azioni',
    };
    final cfg = widget.pageConfig;
    if (cfg == null) {
      return defaults.values
          .map((l) => DataColumn(label: Text(l)))
          .toList(growable: false);
    }
    return cfg.visibleColumns().isEmpty
        ? defaults.entries
            .map((e) => DataColumn(label: Text(_cl(e.key, e.value))))
            .toList(growable: false)
        : cfg
            .visibleColumns()
            .map((c) => DataColumn(label: Text(_cl(c.id, c.label))))
            .toList(growable: false);
  }

  // AppBar: freccia indietro + titolo benvenuto + azioni pagina
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
        if (widget.onEditPageConfig != null)
          IconButton(
            tooltip: 'Configura campi e pulsanti',
            icon: const Icon(Icons.tune),
            onPressed: widget.onEditPageConfig,
          ),
        IconButton(
          tooltip: 'Ricarica',
          icon: const Icon(Icons.refresh),
          onPressed: _loadRows,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _requestModifyTimer?.cancel();
    noteCtrl.dispose();
    _personaleCtrl.dispose();
    _strutturaCtrl.dispose();
    _commessaCtrl.dispose();
    _squadNameCtrl.dispose();
    _dtAssistantCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Tema più compatto SOLO per questa pagina
    final compactTheme = theme.copyWith(
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      textTheme: theme.textTheme.apply(fontSizeFactor: 0.95),
      dataTableTheme: const DataTableThemeData(
        dataRowMinHeight: 28,
        dataRowMaxHeight: 40,
        headingRowHeight: 34,
      ),
    );

    final dal = _range.isNotEmpty ? _range[0] : null;
    final al  = _range.length > 1 ? _range[1] : dal;
    final dalStr = dal == null ? '—' : _displayDate(dal);
    final alStr  = al  == null ? '—' : _displayDate(al);

    return Theme(
      data: compactTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: wrapClassicAppBarChrome(context, _buildAppBar()),
        body: PageWithTopLogo(
          child: loadingDicts
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                  children: [
                    // ====== FORM + CALENDARIO (range) ======
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      // Leggibile sul treno: bianco/grigio intenso, sfondo ancora leggermente visibile.
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // SINISTRA: form
                            Expanded(
                              child: Column(
                                children: [
                                  // Multi-person selector: shows selected chips and
                                  // a button to open a selection dialog.
                                  _multiPersonSelector(
                                    personale: _personale,
                                    selectedIds: _selectedPersonaleIds,
                                    singleValue: personaleId,
                                    onChange: (selected, single) {
                                      setState(() {
                                        _selectedPersonaleIds.clear();
                                        _selectedPersonaleIds.addAll(selected);
                                        personaleId = single;
                                        _syncDropdownTexts();
                                        if (single != null) {
                                          final pref = (_personaleCameraDefault[single] ?? '')
                                              .trim()
                                              .toLowerCase();
                                          if (pref == 'singola' || pref == 'doppia') {
                                            cameraTipo = pref;
                                          }
                                        }
                                      });
                                    },
                                  ),
                                  if (_isAssistenteDt) ...[
                                    _dropdownSearch(
                                      label: 'DT supervisionato',
                                      textCtrl: _dtAssistantCtrl,
                                      sourceMap: _dtOptions,
                                      value: _selectedDtUuidForAssist,
                                      leading: Icons.approval_outlined,
                                      onSelected: (v) async {
                                        setState(() {
                                          _selectedDtUuidForAssist = v;
                                          // reseta selezioni dipendenti dal DT
                                          _selectedSquadId = null;
                                          _squadNameCtrl.clear();
                                          _selectedPersonaleIds.clear();
                                          personaleId = null;
                                        });
                                        await _loadSquads();
                                        await _loadRows();
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                  ] else
                                    const SizedBox(height: 12),
                                  // ===== Squadre: crea + applica =====
                                  if (_squads.isNotEmpty) ...[
                                    DropdownMenu<String>(
                                      width: 520,
                                      label: const Text('Seleziona squadra'),
                                      initialSelection: _selectedSquadId,
                                      dropdownMenuEntries: _squads
                                          .map((s) => DropdownMenuEntry(value: s.id, label: s.nome))
                                          .toList(),
                                      onSelected: (id) {
                                        if (id == null) return;
                                        for (final s in _squads) {
                                          if (s.id == id) {
                                            _applySquad(s);
                                            _squadNameCtrl.text = s.nome;
                                            break;
                                          }
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_fv('team_name')) ...[
                                    TextField(
                                      controller: _squadNameCtrl,
                                      decoration: InputDecoration(
                                        labelText: _fl('team_name', 'Nome squadra'),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (_fv('create_team'))
                                    SizedBox(
                                      width: double.infinity,
                                      child: NeoAsyncFilledButton(
                                        onTap: _saveSquadFromSelection,
                                        child: Center(
                                          child: Text(
                                            _selectedSquadId != null
                                                ? 'Salva modifiche squadra'
                                                : _fl('create_team', 'Crea squadra'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_selectedSquadId != null) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _deleteSelectedSquad,
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Elimina squadra'),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),

                                  if (_fv('structure')) ...[
                                    _dropdownSearch(
                                      label: _fl('structure', 'Struttura'),
                                      textCtrl: _strutturaCtrl,
                                      sourceMap: _structures,
                                      value: structureId,
                                      leading: Icons.apartment_outlined,
                                      onSelected: (v) =>
                                          setState(() => structureId = v),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_fv('commessa')) ...[
                                    _dropdownSearch(
                                      label: _fl('commessa', 'Commessa'),
                                      textCtrl: _commessaCtrl,
                                      sourceMap: _commesse,
                                      value: commessaId,
                                      leading: Icons.work_outline,
                                      onSelected: (v) =>
                                          setState(() => commessaId = v),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_fv('camera_auto')) ...[
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${_fl('camera_auto', 'Tipo camera automatico')}: '
                                        '${_cameraTipoLabelForSelection(_selectedPersonaleIds.isNotEmpty ? _selectedPersonaleIds : (personaleId != null ? [personaleId!] : const []))}',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  if (_fv('notes')) ...[
                                    TextField(
                                      controller: noteCtrl,
                                      minLines: 2,
                                      maxLines: 4,
                                      decoration: InputDecoration(
                                        labelText:
                                            _fl('notes', 'Note opzionali...'),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_fv('insert_booking'))
                                    SizedBox(
                                      width: double.infinity,
                                      child: NeoAsyncFilledButton(
                                        onTap: _insertBooking,
                                        child: Center(
                                          child: Text(
                                            _fl(
                                              'insert_booking',
                                              'Inserisci prenotazione',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // DESTRA: Calendario range + dal/al
                            if (_fv('calendar'))
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Dal: $dalStr  →  Al: $alStr',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  CalendarDatePicker2(
                                    config:CalendarDatePicker2Config(
                                      calendarType: CalendarDatePicker2Type.range,
                                    ),
                                    value: _range,
                                    onValueChanged: (v) => setState(() => _range = v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ====== LISTA PRENOTAZIONI ======
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: const Color(0xFFF3F5F8).withValues(alpha: 0.94),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.pageTitle ?? 'Prenotazioni',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            loadingRows
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : Material(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    borderRadius: BorderRadius.circular(8),
                                    clipBehavior: Clip.antiAlias,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: (MediaQuery.of(context).size.width)
                                            .clamp(1100, 1600),
                                        child: PaginatedDataTable(
                                          header: const Text(''),
                                          rowsPerPage: _rowsPerPage,
                                          dataRowMinHeight: 84,
                                          dataRowMaxHeight: 96,
                                          columnSpacing: 22,
                                          horizontalMargin: 8,
                                          availableRowsPerPage: const [10, 25, 50],
                                          onRowsPerPageChanged: (v) {
                                            if (v != null) {
                                              setState(() => _rowsPerPage = v);
                                            }
                                          },
                                          columns: _buildDataColumns(),
                                          source: _PernottiTableSource(
                                            rows: _rows,
                                            fmtDate: _fmtDate,
                                            statusColor: _statusColor,
                                            personale: _personale,
                                            structures: _structures,
                                            structureMapLinks: _structureMapLink,
                                            commesse: _commesse,
                                            usersByUuid: _usersByUuid,
                                            usersById: _usersById,
                                            userRoleByUuid: _userRoleByUuid,
                                            userRoleById: _userRoleById,
                                            canRequestModify: _canRequestModify,
                                            canManageRecentRequest:
                                                _canManageRecentRequest,
                                            requestModifyTimerLabel:
                                                _requestModifyTimerLabel,
                                            manageRequestTimerLabel:
                                                _manageRequestTimerLabel,
                                            onRequestModify: _requestModify,
                                            onEditRecentRequest:
                                                _editRecentBooking,
                                            onDeleteRecentRequest:
                                                _deleteRecentBooking,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
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
class _PernottiTableSource extends DataTableSource {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic) fmtDate;
  final Color Function(String) statusColor;
  final Map<String, String> personale;  // personale.id_uuid -> full_name
  final Map<String, String> structures; // structures.id_uuid -> name
  final Map<String, String> structureMapLinks; // structures.id_uuid -> maps_link
  final Map<String, String> commesse;   // commesse.id_uuid -> nome
  final Map<String, String> usersByUuid;
  final Map<String, String> usersById;
  final Map<String, String> userRoleByUuid;
  final Map<String, String> userRoleById;
  final bool Function(Map<String, dynamic> row) canRequestModify;
  final bool Function(Map<String, dynamic> row) canManageRecentRequest;
  final String Function(Map<String, dynamic> row) requestModifyTimerLabel;
  final String Function(Map<String, dynamic> row) manageRequestTimerLabel;
  final void Function(Map<String, dynamic> row) onRequestModify;
  final void Function(Map<String, dynamic> row) onEditRecentRequest;
  final void Function(Map<String, dynamic> row) onDeleteRecentRequest;

  _PernottiTableSource({
    required this.rows,
    required this.fmtDate,
    required this.statusColor,
    required this.personale,
    required this.structures,
    required this.structureMapLinks,
    required this.commesse,
    required this.usersByUuid,
    required this.usersById,
    required this.userRoleByUuid,
    required this.userRoleById,
    required this.canRequestModify,
    required this.canManageRecentRequest,
    required this.requestModifyTimerLabel,
    required this.manageRequestTimerLabel,
    required this.onRequestModify,
    required this.onEditRecentRequest,
    required this.onDeleteRecentRequest,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];

    final personaKey = bookingDisplayId(r, keys: kBookingPersonaleKeys);
    final persona = personale[personaKey] ?? personaKey;
    final isPersonaProposed =
        bookingFieldIsProposed(r, keys: kBookingPersonaleKeys);

    // Struttura: supporta anche varianti schema legacy + proposta modifica.
    final strutturaKey = bookingDisplayId(r, keys: kBookingStrutturaKeys);
    final struttura = structures[strutturaKey] ?? strutturaKey;
    final isStrutturaProposed =
        bookingFieldIsProposed(r, keys: kBookingStrutturaKeys);

    final commessaKey = bookingDisplayId(r, keys: kBookingCommessaKeys);
    final commessa = commesse[commessaKey] ?? commessaKey;
    final isCommessaProposed =
        bookingFieldIsProposed(r, keys: kBookingCommessaKeys);

    final link = mapsLinkForBooking(
      Map<String, dynamic>.from(r),
      structureLinksById: structureMapLinks,
    );

    // Stato: mappa a label leggibili
    final rawStato = (r['status'] ?? '').toString().toUpperCase();
    String statoLabel;
    switch (rawStato) {
      case 'IN_ATTESA':   statoLabel = 'Attesa';      break;
      case 'CONFERMATA':  statoLabel = 'Confermata';   break;
      case 'RIFIUTATA':   statoLabel = 'Rifiutata';    break;
      case 'RICHIESTA_MODIFICA': statoLabel = 'Richiesta modifica'; break;
      case 'CONFERMA_MODIFICA':  statoLabel = 'Conferma modifica';  break;
      default:            statoLabel = (r['status'] ?? '').toString();
    }
    final sColor = statusColor(rawStato);
    final payload = modificaPayloadOf(r);
    final reqStartRaw = (payload['start_date'] ?? '').toString();
    final reqEndRaw = (payload['end_date'] ?? '').toString();
    final currentStart = fmtDate(r['start_date']);
    final currentEnd = fmtDate(r['end_date']);
    final isStartProposed = rawStato == 'RICHIESTA_MODIFICA' &&
        reqStartRaw.trim().isNotEmpty &&
        fmtDate(reqStartRaw) != currentStart;
    final isEndProposed = rawStato == 'RICHIESTA_MODIFICA' &&
        reqEndRaw.trim().isNotEmpty &&
        fmtDate(reqEndRaw) != currentEnd;
    final startDateDisplay = (rawStato == 'RICHIESTA_MODIFICA' &&
            reqStartRaw.trim().isNotEmpty)
        ? fmtDate(reqStartRaw)
        : fmtDate(r['start_date']);
    final endDateDisplay =
        (rawStato == 'RICHIESTA_MODIFICA' && reqEndRaw.trim().isNotEmpty)
            ? fmtDate(reqEndRaw)
            : fmtDate(r['end_date']);
    final cameraDisplay = () {
      if (rawStato != 'RICHIESTA_MODIFICA') {
        return (r['camera_tipo'] ?? '').toString();
      }
      final proposed = (payload['camera_tipo'] ?? '').toString().trim();
      return proposed.isNotEmpty ? proposed : (r['camera_tipo'] ?? '').toString();
    }();
    final isCameraProposed = rawStato == 'RICHIESTA_MODIFICA' &&
        (payload['camera_tipo'] ?? '').toString().trim().isNotEmpty &&
        (payload['camera_tipo'] ?? '').toString().trim() !=
            (r['camera_tipo'] ?? '').toString().trim();
    final noteDisplay = () {
      if (rawStato != 'RICHIESTA_MODIFICA') {
        return (r['master_note'] ?? '').toString();
      }
      if (payload.containsKey('master_note')) {
        return (payload['master_note'] ?? '').toString();
      }
      return (r['master_note'] ?? '').toString();
    }();
    final insertedAtLabel = (() {
      final s = formatDateTimeItFromSupabase(r['created_at']);
      return s.isEmpty ? '—' : s;
    })();

    Widget propostaBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'proposta',
            style: TextStyle(
              color: Colors.deepOrange,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        );

    Widget withProposta(String text, bool proposed) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(text)),
            if (proposed) ...[
              const SizedBox(width: 6),
              propostaBadge(),
            ],
          ],
        );

    return DataRow(cells: [
      DataCell(withProposta(persona, isPersonaProposed)),
      DataCell(withProposta(startDateDisplay, isStartProposed)),
      DataCell(withProposta(endDateDisplay, isEndProposed)),

      // Struttura
      DataCell(withProposta(struttura, isStrutturaProposed)),

      // Posizione (ICONA cliccabile, niente URL a vista)
      DataCell(
        link.isEmpty
            ? const Text('—')
            : InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(link.trim());
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Tooltip(
                  message: 'Apri posizione',
                  child: Icon(Icons.location_on, color: Colors.blue, size: 18),
                ),
              ),
      ),

      // Commessa
      DataCell(withProposta(commessa, isCommessaProposed)),

      // Camera
      DataCell(withProposta(cameraDisplay, isCameraProposed)),

      // Stato (colorato + label)
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          statoLabel,
          style: TextStyle(color: sColor, fontWeight: FontWeight.w600),
        ),
      )),

      // Note
      DataCell(Text(noteDisplay)),

      // Richiedente: autore richiesta iniziale (created_by), non ultima modifica.
      DataCell(
        Text(
          bookingRequesterLabel(
            r,
            usersByUuid: usersByUuid,
            usersById: usersById,
          ),
        ),
      ),

      // Azioni
      DataCell(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.orange.shade800,
                backgroundColor: Colors.orange.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
              onPressed: canRequestModify(r) ? () => onRequestModify(r) : null,
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('Rich. modifica'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Modifica richiesta (5 min)',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: canManageRecentRequest(r) ? () => onEditRecentRequest(r) : null,
                ),
                IconButton(
                  tooltip: 'Cancella richiesta (5 min)',
                  icon: Icon(
                    Icons.delete_outline,
                    color: canManageRecentRequest(r) ? Colors.red : Colors.grey,
                  ),
                  onPressed: canManageRecentRequest(r) ? () => onDeleteRecentRequest(r) : null,
                ),
              ],
            ),
            Builder(
              builder: (_) {
                final manageLabel = manageRequestTimerLabel(r);
                final t = requestModifyTimerLabel(r);
                if (manageLabel.isEmpty && t.isEmpty) return const SizedBox.shrink();
                final requestExpired = t == 'Tempo scaduto';
                final manageExpired = manageLabel.contains('scaduta');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (manageLabel.isNotEmpty)
                      Text(
                        manageLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: manageExpired ? Colors.red.shade700 : Colors.blueGrey.shade700,
                          fontWeight: manageExpired ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    if (t.isNotEmpty)
                      Text(
                        t,
                        style: TextStyle(
                          fontSize: 11,
                          color: requestExpired ? Colors.red.shade700 : Colors.blueGrey.shade700,
                          fontWeight: requestExpired ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
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