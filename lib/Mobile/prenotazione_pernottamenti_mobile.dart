import 'dart:async';

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../utils/booking_inserted_by.dart';
import '../utils/booking_modifica_display.dart';
import '../utils/date_formatters.dart';
import '../utils/responsive.dart';
import '../utils/dt_user_list.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
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

class PernottamentiMobilePage extends StatefulWidget {
  final String username;
  final int userId;
  final String role;
  final String fullName;

  const PernottamentiMobilePage({
    super.key,
    required this.username,
    required this.userId,
    required this.role,
    required this.fullName,
  });

  @override
  State<PernottamentiMobilePage> createState() =>
      _PernottamentiMobilePageState();
}

class _PernottamentiMobilePageState extends State<PernottamentiMobilePage> {
  static const Duration _requestManageGrace = Duration(minutes: 5);

  // ===== Squadre (batch di personale nominati) =====
  final List<_PernottiSquadra> _squads = [];
  String? _selectedSquadId;
  final _squadNameCtrl = TextEditingController();

  // ------------------------------
  // Dizionari (UUID → label)
  // ------------------------------
  final Map<String, String> personale = {};
  final Map<String, String> personaleCameraDefault = {};
  final Map<String, String> strutture = {};
  final Map<String, String> commesse = {};
  final Map<String, String> structureLinks = {};
  final Map<String, String> structureAddress = {};
  final Map<String, String> _usersByUuid = {};
  final Map<String, String> _usersById = {};

  // ------------------------------
  // Valori scelti
  // ------------------------------
  final List<String> selectedPersonale = [];
  String? structureId;
  String? commessaId;

  String cameraTipo = "doppia";

  String _cameraTipoForPersonale(String? personaleUuid) {
    final pref = (personaleCameraDefault[personaleUuid] ?? '').trim().toLowerCase();
    return pref == 'singola' ? 'singola' : 'doppia';
  }

  String _cameraTipoLabelForSelection(List<String> personaleIds) {
    if (personaleIds.isEmpty) return 'Doppia';
    final set = personaleIds.map(_cameraTipoForPersonale).toSet();
    if (set.length == 1) return set.first == 'singola' ? 'Singola' : 'Doppia';
    return 'Mista (da anagrafica dipendente)';
  }

  List<DateTime?> range = [
    DateTime.now(),
    DateTime.now().add(const Duration(days: 1)),
  ];

  final noteCtrl = TextEditingController();

  // Controller visualizzazione label (campi pickers)
  final _structureCtrl = TextEditingController();
  final _commessaCtrl  = TextEditingController();

  // ------------------------------
  // UTENTE
  // ------------------------------
  String? dtUserUuid;

  bool get _isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';

  // Assistente DT: selezione DT supervisionato
  String? _selectedDtUuidForAssist;
  final Map<String, String> _dtOptions = {};

  String? get _effectiveDtUserUuid =>
      _isAssistenteDt ? _selectedDtUuidForAssist : dtUserUuid;

  // ------------------------------
  // PRENOTAZIONI
  // ------------------------------
  List<Map<String, dynamic>> prenotazioni = [];
  bool loading = true;
  bool _insertInFlight = false;
  Timer? _requestManageTimer;

  @override
  void initState() {
    super.initState();
    _requestManageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hasWindow = prenotazioni.any((r) {
        final rem = _remainingManageRequestTime(r);
        return rem != null && rem > Duration.zero;
      });
      if (hasWindow) setState(() {});
    });
    _bootstrap();
  }

  Future<void> _loadSquads() async {
    _squads.clear();
    _selectedSquadId = null;
    try {
      final effectiveDtUserUuid = _effectiveDtUserUuid;
      if (_isAssistenteDt &&
          (_selectedDtUuidForAssist == null ||
              !_dtOptions.containsKey(_selectedDtUuidForAssist))) {
        return;
      }
      if (effectiveDtUserUuid == null || effectiveDtUserUuid.isEmpty) {
        return;
      }
      final res = await SupabaseService.client
          .from('pernotti_squads')
          .select('id,nome,personale_ids')
          .eq('dt_user_uuid', effectiveDtUserUuid)
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
      // ignore
    }
  }

  void _applySquad(_PernottiSquadra squad) {
    setState(() {
      selectedPersonale
        ..clear()
        ..addAll(squad.personaleIds);
      _selectedSquadId = squad.id;
      _squadNameCtrl.text = squad.nome;
      final first = squad.personaleIds.isNotEmpty ? squad.personaleIds.first : null;
      final pref = (first != null ? personaleCameraDefault[first] : null) ?? '';
      final normalized = pref.trim().toLowerCase();
      if (normalized == 'singola' || normalized == 'doppia') {
        cameraTipo = normalized;
      }
    });
  }

  Future<void> _saveSquadFromSelection() async {
    if (!await ensureCanPersist(context)) return;
    try {
      final selected = selectedPersonale.toList();
      if (selected.isEmpty) {
        _msg("Seleziona almeno una persona per la squadra.", isError: true);
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
              .update({'nome': nome, 'personale_ids': selected}).eq('id', existing.id);
          _squads[idx] = _PernottiSquadra(
            id: existing.id,
            nome: nome,
            personaleIds: selected,
          );
          if (mounted) setState(() {});
          _msg("Squadra aggiornata: $nome");
          return;
        }
      }

      if (nameFromCtrl.isEmpty) {
        _msg("Dai un nome alla squadra.", isError: true);
        return;
      }

      // Se esiste già una squadra con lo stesso nome, sovrascriviamo.
      final existingIndex = _squads
          .indexWhere((s) => s.nome.toLowerCase() == nameFromCtrl.toLowerCase());
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
        _msg("Squadra salvata (aggiornata): $nameFromCtrl");
        return;
      }

      // Nuova squadra: lasciamo generare l'UUID e recuperiamo l'id.
      final effectiveDtUserUuid = _effectiveDtUserUuid;
      if (effectiveDtUserUuid == null || effectiveDtUserUuid.isEmpty) {
        _msg('dt_user_uuid non disponibile.', isError: true);
        return;
      }
      final inserted = await SupabaseService.client
          .from('pernotti_squads')
          .insert({
            'dt_user_uuid': effectiveDtUserUuid,
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
      _selectedSquadId = updated.id;
      if (mounted) setState(() {});
      _msg("Squadra salvata: $nameFromCtrl");
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

  @override
  void dispose() {
    _requestManageTimer?.cancel();
    noteCtrl.dispose();
    _structureCtrl.dispose();
    _commessaCtrl.dispose();
    _squadNameCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // BOOTSTRAP
  // ----------------------------------------------------------
  Future<void> _bootstrap() async {
    await _fetchDtUuid();
    if (_isAssistenteDt) {
      await _loadDtOptionsForAssistente();
    }
    await _loadSquads();
    await _loadDizionari();
    await _loadPrenotazioni();
    if (mounted) setState(() => loading = false);
  }

  // ----------------------------------------------------------
  // UTENTE → UUID
  // ----------------------------------------------------------
  Future<void> _fetchDtUuid() async {
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
          dtUserUuid = authUuid;
          return;
        }
      }

      final r2 = await SupabaseService.client
          .from("users")
          .select("id_uuid, username")
          .eq("username", widget.username)
          .maybeSingle();

      if (r2 != null &&
          r2["id_uuid"] is String &&
          (r2["id_uuid"] as String).length >= 32) {
        dtUserUuid = r2["id_uuid"];
        return;
      }

      final r1 = await SupabaseService.client
          .from("users")
          .select("id, username")
          .eq("username", widget.username)
          .maybeSingle();

      if (r1 != null &&
          r1["id"] is String &&
          (r1["id"] as String).length >= 32) {
        dtUserUuid = r1["id"];
      }
    } catch (_) {}
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
          final label = (e['full_name'] ?? '').toString().trim();
          final uName = (e['username'] ?? '').toString().trim();
          _dtOptions[idUuid] =
              label.isNotEmpty ? label : (uName.isNotEmpty ? uName : idUuid);
        }
      }

      if (_dtOptions.isNotEmpty) {
        if (_selectedDtUuidForAssist == null ||
            !_dtOptions.containsKey(_selectedDtUuidForAssist)) {
          _selectedDtUuidForAssist = _dtOptions.keys.first;
        }
      }
    } catch (_) {
      _dtOptions.addAll(await loadDtOptionsByUuid());
      if (_selectedDtUuidForAssist == null && _dtOptions.isNotEmpty) {
        _selectedDtUuidForAssist = _dtOptions.keys.first;
      }
    }

    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------
  // DIZIONARI
  // ----------------------------------------------------------
  Future<void> _loadDizionari() async {
    try {
      // PERSONALE
      final p = await SupabaseService.client
          .from("personale")
          .select("id_uuid, full_name, camera_tipo_default, active")
          .eq("active", true)
          .order("full_name");

      personale
        ..clear()
        ..addEntries(
          ((p as List)
                .map((e) => MapEntry(
                      (e["id_uuid"] ?? "").toString(),
                      (e["full_name"] ?? "").toString(),
                    ))
                .toList()
              ..sort((a, b) => a.value
                  .toLowerCase()
                  .trim()
                  .compareTo(b.value.toLowerCase().trim()))),
        );
      personaleCameraDefault
        ..clear()
        ..addEntries(
          ((p as List).map((e) {
            final id = (e["id_uuid"] ?? "").toString();
            final raw = (e["camera_tipo_default"] ?? "doppia")
                .toString()
                .trim()
                .toLowerCase();
            return MapEntry(id, raw == 'singola' ? 'singola' : 'doppia');
          })),
        );

      // STRUTTURE
      final s = await SupabaseService.client
          .from("structures")
          .select("id_uuid, name, address, maps_link, active")
          .eq("active", true)
          .order("name");

      strutture.clear();
      structureLinks.clear();
      structureAddress.clear();

      for (final e in (s as List)) {
        final id = (e["id_uuid"] ?? "").toString();
        final name = (e["name"] ?? "").toString();
        strutture[id] = name;

        final addr = (e["address"] ?? "").toString();
        final link = (e["maps_link"] ?? "").toString();
        if (addr.isNotEmpty) structureAddress[id] = addr;
        if (link.isNotEmpty) structureLinks[id] = link;
      }

      // COMMESSE
      final c = await SupabaseService.client
          .from("commesse")
          .select("id_uuid, nome, active")
          .eq("active", true)
          .order("nome");

      commesse
        ..clear()
        ..addEntries(
          ((c as List)
                .map((e) => MapEntry(
                      (e["id_uuid"] ?? "").toString(),
                      (e["nome"] ?? "").toString(),
                    ))
                .toList()
              ..sort((a, b) => a.value
                  .toLowerCase()
                  .trim()
                  .compareTo(b.value.toLowerCase().trim()))),
        );

      final u = await SupabaseService.client
          .from('users')
          .select('id, id_uuid, full_name, username')
          .order('username');
      _usersByUuid.clear();
      _usersById.clear();
      for (final e in (u as List)) {
        final idUuid = (e['id_uuid'] ?? '').toString();
        final idInt = (e['id'] ?? '').toString();
        final label = (e['full_name'] ?? e['username'] ?? '').toString();
        if (idUuid.trim().isNotEmpty) {
          _usersByUuid[idUuid.trim()] = label.trim();
        }
        if (idInt.trim().isNotEmpty) {
          _usersById[idInt.trim()] = label.trim();
        }
      }

      // Sincronizza label nei campi, se già presenti
      _syncControllers();
    } catch (e) {
      _msg("Errore caricamento dizionari: $e", isError: true);
    }
  }

  void _syncControllers() {
    _structureCtrl.text = structureId != null ? (strutture[structureId!] ?? "") : "";
    _commessaCtrl.text  = commessaId  != null ? (commesse[commessaId!]   ?? "") : "";
  }

  // ----------------------------------------------------------
  // PRENOTAZIONI
  // ----------------------------------------------------------
  Future<void> _loadPrenotazioni() async {
    final effectiveDtUserUuid = _effectiveDtUserUuid;
    if (effectiveDtUserUuid == null) return;
    if (_isAssistenteDt &&
        (_selectedDtUuidForAssist == null ||
            !_dtOptions.containsKey(_selectedDtUuidForAssist))) {
      prenotazioni = [];
      return;
    }

    try {
      final rows = await SupabaseService.client
          .from("bookings")
          .select()
          .eq("dt_user_uuid", effectiveDtUserUuid)
          .order("start_date", ascending: false);

      prenotazioni = List<Map<String, dynamic>>.from(rows);
      await _ensureUserLabelsForBookings(prenotazioni);
    } catch (e) {
      _msg("Errore caricamento prenotazioni: $e", isError: true);
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
    strutturaKey = strutturaKey != null && strutture.containsKey(strutturaKey)
        ? strutturaKey
        : structureId;
    String? commessaKey = (
      source['commessa_id'] ??
      source['commessa_uuid'] ??
      source['id_commessa']
    )?.toString();
    commessaKey =
        commessaKey != null && commesse.containsKey(commessaKey) ? commessaKey : commessaId;
    String? personaleKey = (
      source['personale_id'] ??
      source['personale_uuid'] ??
      source['id_personale']
    )?.toString();
    personaleKey = personaleKey != null && personale.containsKey(personaleKey)
        ? personaleKey
        : (selectedPersonale.isNotEmpty ? selectedPersonale.first : null);
    DateTime? dal = DateTime.tryParse(
        (source['start_date'] ?? current['start_date'] ?? '').toString());
    DateTime? al = DateTime.tryParse(
        (source['end_date'] ?? current['end_date'] ?? '').toString());
    final note =
        (source['master_note'] ?? current['master_note'] ?? '').toString();

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
        return StatefulBuilder(
          builder: (ctx2, setSt) {
            return AlertDialog(
              title: const Text('Richiedi modifica'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: personaleSel,
                        decoration: const InputDecoration(
                          labelText: 'Persona',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: personale.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() {
                          personaleSel = v;
                          cameraSel = _cameraTipoForPersonale(v);
                        }),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: strutturaSel,
                        decoration: const InputDecoration(
                          labelText: 'Struttura',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: strutture.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() => strutturaSel = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: commessaSel,
                        decoration: const InputDecoration(
                          labelText: 'Commessa',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: commesse.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() => commessaSel = v),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tipo camera automatico: ${cameraSel == 'singola' ? 'Singola' : 'Doppia'}',
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
                                    if (alSel != null && picked.isAfter(alSel!)) {
                                      alSel = picked;
                                    }
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
                                    if (dalSel != null && picked.isBefore(dalSel!)) {
                                      dalSel = picked;
                                    }
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
                TextButton(
                  onPressed: () => Navigator.pop(ctx2, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx2, true),
                  child: const Text('Invia richiesta'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    if (personaleSel == null ||
        strutturaSel == null ||
        commessaSel == null ||
        dalSel == null ||
        alSel == null) {
      _msg('Compila tutti i campi.', isError: true);
      return;
    }

    try {
      final wasPending =
          (current['status'] ?? '').toString().toUpperCase() == 'RICHIESTA_MODIFICA';
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

      await SupabaseService.client.from('bookings').update({
        'status': 'RICHIESTA_MODIFICA',
        'modifica_payload': payload,
        'modifica_note': wasPending
            ? 'Modifica richiesta aggiornata da DT'
            : 'Modifica richiesta da DT',
        'modifica_requested_at': requestedAtToPersist,
      }).eq('id', id);

      try {
        final adminIds = await NotificationSender.getAdminIdsByType(2);
        adminIds.removeWhere((x) => x == widget.userId);
        if (adminIds.isNotEmpty) {
          await NotificationSender.sendToUserIds(
            userIds: adminIds,
            bookingId: int.tryParse(id.toString()) ?? 0,
            action: 'pernottamento_modifica_richiesta',
            title: 'Pernottamento: richiesta modifica',
            message:
                '${widget.fullName} ha richiesto una modifica su un pernottamento.',
          );
        }
      } catch (_) {}

      await _loadPrenotazioni();
      if (mounted) setState(() {});
      _msg(
        'Richiesta modifica inviata all\'admin. Notifica inviata a: admin pernottamenti.',
      );
    } catch (e) {
      _msg('Errore richiesta modifica: $e', isError: true);
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

    final source = isRichiestaModifica(current) &&
            modificaPayloadOf(current).isNotEmpty
        ? modificaPayloadOf(current)
        : current;
    String? strutturaKey = (
      source['struttura_id'] ??
      source['structure_id'] ??
      source['structure_uuid']
    )?.toString();
    strutturaKey = strutturaKey != null && strutture.containsKey(strutturaKey)
        ? strutturaKey
        : structureId;
    String? commessaKey = (
      source['commessa_id'] ??
      source['commessa_uuid'] ??
      source['id_commessa']
    )?.toString();
    commessaKey =
        commessaKey != null && commesse.containsKey(commessaKey) ? commessaKey : commessaId;
    String? personaleKey = (
      source['personale_id'] ??
      source['personale_uuid'] ??
      source['id_personale']
    )?.toString();
    personaleKey = personaleKey != null && personale.containsKey(personaleKey)
        ? personaleKey
        : (selectedPersonale.isNotEmpty ? selectedPersonale.first : null);
    DateTime? dal = DateTime.tryParse(
        (source['start_date'] ?? current['start_date'] ?? '').toString());
    DateTime? al = DateTime.tryParse(
        (source['end_date'] ?? current['end_date'] ?? '').toString());
    final note =
        (source['master_note'] ?? current['master_note'] ?? '').toString();

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
        return StatefulBuilder(
          builder: (ctx2, setSt) {
            return AlertDialog(
              title: const Text('Modifica richiesta (entro 5 minuti)'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: personaleSel,
                        decoration: const InputDecoration(
                          labelText: 'Persona',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: personale.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() {
                          personaleSel = v;
                          cameraSel = _cameraTipoForPersonale(v);
                        }),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: strutturaSel,
                        decoration: const InputDecoration(
                          labelText: 'Struttura',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: strutture.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() => strutturaSel = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: commessaSel,
                        decoration: const InputDecoration(
                          labelText: 'Commessa',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: commesse.entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList()
                          ..sort((a, b) => (a.child as Text)
                              .data!
                              .toLowerCase()
                              .compareTo((b.child as Text).data!.toLowerCase())),
                        onChanged: (v) => setSt(() => commessaSel = v),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tipo camera automatico: ${cameraSel == 'singola' ? 'Singola' : 'Doppia'}',
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
                                    if (alSel != null && picked.isAfter(alSel!)) {
                                      alSel = picked;
                                    }
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
                                    if (dalSel != null && picked.isBefore(dalSel!)) {
                                      dalSel = picked;
                                    }
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
                TextButton(
                  onPressed: () => Navigator.pop(ctx2, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx2, true),
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;

    if (personaleSel == null ||
        strutturaSel == null ||
        commessaSel == null ||
        dalSel == null ||
        alSel == null) {
      _msg('Compila tutti i campi.', isError: true);
      return;
    }

    try {
      await SupabaseService.client.from('bookings').update({
        'personale_id': personaleSel,
        'struttura_id': strutturaSel,
        'commessa_id': commessaSel,
        'camera_tipo': cameraSel,
        'start_date': _iso(dalSel!),
        'end_date': _iso(alSel!),
        'master_note': noteCtrl2.text.trim(),
        'updated_by': dtUserUuid,
      }).eq('id', id);

      await _notifyPernottamentiAdmins(
        bookingId: id,
        action: 'update',
        title: 'Pernottamento modificato da DT',
        message: '${widget.fullName} ha modificato una richiesta entro 5 minuti.',
      );

      await _loadPrenotazioni();
      if (mounted) setState(() {});
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
      builder: (_) => AlertDialog(
        title: const Text('Conferma cancellazione'),
        content: const Text(
          'Vuoi cancellare questa richiesta pernottamento? '
          'L\'operazione e consentita solo entro 5 minuti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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

      await SupabaseService.client.from('bookings').delete().eq('id', id);
      await _loadPrenotazioni();
      if (mounted) setState(() {});
      _msg('Richiesta cancellata correttamente.');
    } catch (e) {
      _msg('Errore cancellazione richiesta: $e', isError: true);
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

  bool _canRequestModify(Map<String, dynamic> row) => true;

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

  String _requestModifyTimerLabel(Map<String, dynamic> row) => '';

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
      // Non blocchiamo l'utente se la notifica fallisce.
    }
  }

  // ----------------------------------------------------------
  // INSERIMENTO
  // ----------------------------------------------------------
  bool _looksUuid(String? v) =>
      v != null && v.length >= 32 && v.contains("-");

  Future<void> _insert() async {
    if (_insertInFlight) return;
    if (!await ensureCanPersist(context)) return;
    final dal = range[0];
    final al  = range.length > 1 ? range[1] : dal;

    final effectiveDtUserUuid = _effectiveDtUserUuid;
    if (effectiveDtUserUuid == null ||
        dal == null ||
        al == null ||
        structureId == null ||
        commessaId == null ||
        selectedPersonale.isEmpty) {
      _msg("Compila tutti i campi richiesti.", isError: true);
      return;
    }

    if (!_looksUuid(structureId) ||
        !_looksUuid(commessaId) ||
        !selectedPersonale.every(_looksUuid) ||
        (_isAssistenteDt &&
            (_selectedDtUuidForAssist == null ||
                !_dtOptions.containsKey(_selectedDtUuidForAssist)))) {
      _msg("ID non validi (devono essere UUID).", isError: true);
      return;
    }

    setState(() => _insertInFlight = true);
    try {
      final inserts = selectedPersonale.map((pid) {
        return {
          "personale_id": pid,
          "struttura_id": structureId,   // coerente con pagina desktop
          "commessa_id": commessaId,
          "camera_tipo": _cameraTipoForPersonale(pid),
          "start_date": _iso(dal),
          "end_date": _iso(al),
          "status": "IN_ATTESA",
          "master_note": noteCtrl.text.trim(),
          "dt_user_uuid": effectiveDtUserUuid,
          "created_at": supabaseNowIsoUtc(),
          if (dtUserUuid != null && dtUserUuid!.length >= 32) ...{
            "created_by": dtUserUuid,
            "updated_by": dtUserUuid,
          },
        };
      }).toList();

      final inserted = await SupabaseService.client
          .from("bookings")
          .insert(inserts)
          .select('id') as List;

      // Notifica: per batch, invia una notifica per ogni booking creato
      if (inserted.isNotEmpty) {
        final ids = inserted
            .map((e) => (e as Map)['id'])
            .map((v) => v != null ? int.tryParse(v.toString()) : null)
            .whereType<int>()
            .toList();
        for (final id in ids) {
          await NotificationSender.notifyUserForBooking(
            dtUserId: widget.userId,
            bookingId: id,
            action: 'create',
            title: 'Nuova prenotazione Pernottamento',
            bookingType: 'pernottamento',
          );
        }
      }

      _resetForm();
      await _loadPrenotazioni();
      _msg(
        "Pernottamento inserito. "
        "Notifica inviata a: admin pernottamenti, richiedente e dipendente interessato.",
      );
    } catch (e) {
      _msg("Errore inserimento: $e", isError: true);
    } finally {
      if (mounted) {
        setState(() => _insertInFlight = false);
      }
    }
  }

  void _resetForm() {
    setState(() {
      selectedPersonale.clear();
      structureId = null;
      commessaId  = null;
      noteCtrl.clear();
      _structureCtrl.clear();
      _commessaCtrl.clear();
    });
  }

  String _iso(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);

  // ----------------------------------------------------------
  // STATO → COLORE + BADGE
  // ----------------------------------------------------------
  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case "CONFERMATA":
        return Colors.green;
      case "IN_ATTESA":
        return Colors.orange;
      case "RIFIUTATA":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _statusBadge(String stato) {
    final color = _statusColor(stato);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stato,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // POPUP DETTAGLI (con STATO colorato)
  // ----------------------------------------------------------
  void _dettaglio(Map r) {
    final map = Map<String, dynamic>.from(r);
    final personaKey = bookingDisplayId(map, keys: kBookingPersonaleKeys);
    final strutturaKey = bookingDisplayId(map, keys: kBookingStrutturaKeys);
    final commessaKey = bookingDisplayId(map, keys: kBookingCommessaKeys);
    final persona = personale[personaKey] ?? "";
    final struttura = strutture[strutturaKey] ?? "";
    final comm = commesse[commessaKey] ?? "";
    final payload = modificaPayloadOf(map);
    final startDisp = isRichiestaModifica(map) &&
            (payload['start_date'] ?? '').toString().trim().isNotEmpty
        ? formatDateDdMmYyyy(payload['start_date'])
        : formatDateDdMmYyyy(r["start_date"]);
    final endDisp = isRichiestaModifica(map) &&
            (payload['end_date'] ?? '').toString().trim().isNotEmpty
        ? formatDateDdMmYyyy(payload['end_date'])
        : formatDateDdMmYyyy(r["end_date"]);
    final cameraDisp = isRichiestaModifica(map) &&
            (payload['camera_tipo'] ?? '').toString().trim().isNotEmpty
        ? (payload['camera_tipo'] ?? '').toString()
        : (r["camera_tipo"] ?? "").toString();

    final stato = (r["status"] ?? "").toString();
    final color = _statusColor(stato);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(persona),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Dal: $startDisp"),
            Text("Al: $endDisp"),
            Text(
              "Struttura: $struttura${bookingFieldIsProposed(map, keys: kBookingStrutturaKeys) ? ' (proposta)' : ''}",
            ),
            Text("Commessa: $comm"),
            Text("Camera: $cameraDisp"),
            Text(
              "Richiedente: ${bookingRequesterLabel(
                Map<String, dynamic>.from(r),
                usersByUuid: _usersByUuid,
                usersById: _usersById,
              )}",
            ),
            if ((r["master_note"] ?? '').toString().isNotEmpty)
              NotePreviewText(
                note: (r["master_note"] ?? '').toString(),
                prefix: 'Note: ',
                maxChars: 10,
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                stato,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Chiudi"),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // UI MODERNA
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(
          context,
          AppBar(title: const Text('Pernottamenti')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final dal = range[0];
    final al  = range.length > 1 ? range[1] : dal;

    final compactAppBar = useUltraCompactAppBar(context);

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            AppLogo(size: compactAppBar ? 28 : 44),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Pernottamenti – ${widget.fullName}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      )),
      body: PageWithTopLogo(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              //----------------------------------------------------
              // FORM
            //----------------------------------------------------
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    //----------------------------------------------------
                    // PERSONALE MULTISELECT (bottom‑sheet con ricerca)
                    //----------------------------------------------------
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: selectedPersonale
                            .map((id) => Chip(
                                  label: Text(personale[id] ?? id),
                                  onDeleted: () {
                                    setState(() => selectedPersonale.remove(id));
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _pickPersonaleBottomSheet,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add),
                          SizedBox(width: 8),
                          Text("Seleziona persone"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Assistente DT: selezione DT supervisionato
                    if (_isAssistenteDt) ...[
                      _modernDropdown(
                        label: "DT supervisionato",
                        value: _selectedDtUuidForAssist,
                        items: _dtOptions,
                        icon: Icons.approval_outlined,
                        onChanged: (v) async {
                          setState(() {
                            _selectedDtUuidForAssist = v;
                            // Reset: squad e selezioni legate al DT.
                            _selectedSquadId = null;
                            _squadNameCtrl.clear();
                            selectedPersonale.clear();
                          });
                          await _loadSquads();
                          await _loadPrenotazioni();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ===== Squadre (salva/ricarica batch di persone) =====
                    if (_squads.isNotEmpty) ...[
                      _modernDropdown(
                        label: "Seleziona squadra",
                        value: _selectedSquadId,
                        items: {
                          for (final s in _squads) s.id: s.nome,
                        },
                        onChanged: (id) {
                          if (id == null) return;
                          for (final s in _squads) {
                            if (s.id == id) {
                              _applySquad(s);
                              break;
                            }
                          }
                        },
                        icon: Icons.group_outlined,
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: _squadNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nome squadra",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AsyncFilledButton(
                      onPressed: _saveSquadFromSelection,
                      child: Text(
                        _selectedSquadId != null
                            ? "Salva modifiche squadra"
                            : "Crea squadra",
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

                    const SizedBox(height: 20),

                    // STRUTTURA – picker con ricerca (id->label)
                    _PickerFieldOption(
                      controller: _structureCtrl,
                      label: "Struttura",
                      options: strutture.entries
                          .map((e) => _Option(id: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (opt) {
                        setState(() {
                          structureId = opt?.id;
                          _structureCtrl.text = opt?.label ?? "";
                        });
                      },
                      leading: Icons.apartment,
                    ),

                    const SizedBox(height: 12),

                    // COMMESSA – picker con ricerca (id->label)
                    _PickerFieldOption(
                      controller: _commessaCtrl,
                      label: "Commessa",
                      options: commesse.entries
                          .map((e) => _Option(id: e.key, label: e.value))
                          .toList()
                        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
                      onSelected: (opt) {
                        setState(() {
                          commessaId = opt?.id;
                          _commessaCtrl.text = opt?.label ?? "";
                        });
                      },
                      leading: Icons.work_outline,
                    ),

                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Tipo camera automatico: ${_cameraTipoLabelForSelection(selectedPersonale)}",
                      ),
                    ),

                    const SizedBox(height: 20),

                    //----------------------------------------------------
                    // DATE RANGE PICKER (MOBILE)
                    //----------------------------------------------------
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Dal: ${dal != null ? _displayDate(dal) : '-'}   →   Al: ${al != null ? _displayDate(al) : '-'}",
                          ),
                        ),
                        FilledButton(
                          onPressed: _pickDateRange,
                          child: const Text("Periodo"),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: "Note opzionali",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),

                    const SizedBox(height: 20),
                    AsyncFilledButton(
                      onPressed: _insertInFlight ? null : _insert,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add),
                          SizedBox(width: 8),
                          Text("Inserisci prenotazione"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            //----------------------------------------------------
            // LISTA — SOLO NOMI + BADGE STATO
            //----------------------------------------------------
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Prenotazioni",
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: prenotazioni.length,
              itemBuilder: (_, i) {
                final r = prenotazioni[i];
                final personaKey =
                    (r["personale_id"] ?? r["personale_uuid"] ?? r["id_personale"] ?? "")
                        .toString();
                final nome = personale[personaKey] ?? "";
                final stato = (r["status"] ?? "").toString();
                final canManageRecent = _canManageRecentRequest(r);
                final manageTimerLabel = _manageRequestTimerLabel(r);
                final requestTimerLabel = _requestModifyTimerLabel(r);

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    title: Text(
                      nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifica richiesta (5 min)',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: canManageRecent ? () => _editRecentBooking(r) : null,
                            ),
                            IconButton(
                              tooltip: 'Cancella richiesta (5 min)',
                              icon: Icon(
                                Icons.delete_outline,
                                color: canManageRecent ? Colors.red : Colors.grey,
                              ),
                              onPressed: canManageRecent ? () => _deleteRecentBooking(r) : null,
                            ),
                            IconButton(
                              tooltip: 'Richiedi modifica',
                              icon: const Icon(Icons.edit_note),
                              onPressed: _canRequestModify(r) ? () => _requestModify(r) : null,
                            ),
                          ],
                        ),
                        if (manageTimerLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              manageTimerLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: manageTimerLabel.contains('scaduta')
                                    ? Colors.red.shade700
                                    : Colors.blueGrey.shade700,
                              ),
                            ),
                          ),
                        if (requestTimerLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              requestTimerLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: requestTimerLabel == 'Tempo scaduto'
                                    ? Colors.red.shade700
                                    : Colors.blueGrey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _statusBadge(stato),
                        const SizedBox(height: 4),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onLongPress: () async {
                      final action = await showModalBottomSheet<String>(
                        context: context,
                        useSafeArea: true,
                        builder: (ctx) => SafeArea(
                          child: Wrap(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: const Text('Modifica richiesta (5 min)'),
                                enabled: canManageRecent,
                                onTap: canManageRecent
                                    ? () => Navigator.pop(ctx, 'edit_recent')
                                    : null,
                              ),
                              ListTile(
                                leading: Icon(
                                  Icons.delete_outline,
                                  color: canManageRecent ? Colors.red : Colors.grey,
                                ),
                                title: const Text('Cancella richiesta (5 min)'),
                                enabled: canManageRecent,
                                onTap: canManageRecent
                                    ? () => Navigator.pop(ctx, 'delete_recent')
                                    : null,
                              ),
                              ListTile(
                                leading: const Icon(Icons.edit_note),
                                title: const Text('Richiedi modifica'),
                                enabled: _canRequestModify(r),
                                onTap: _canRequestModify(r)
                                    ? () => Navigator.pop(ctx, 'request_modify')
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                      if (action == 'edit_recent') {
                        await _editRecentBooking(r);
                      } else if (action == 'delete_recent') {
                        await _deleteRecentBooking(r);
                      } else if (action == 'request_modify') {
                        await _requestModify(r);
                      }
                    },
                    onTap: () => _dettaglio(r),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ----------------------------------------------------------
  // PICK PERSONALE MULTISELECT (bottom‑sheet con ricerca)
  // ----------------------------------------------------------
  Future<void> _pickPersonaleBottomSheet() async {
    final tmp = Set<String>.from(selectedPersonale);
    final TextEditingController searchCtrl = TextEditingController();
    List<MapEntry<String, String>> source =
        personale.entries.toList()..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    List<MapEntry<String, String>> filtered = List.of(source);

    void apply(String q) {
      final t = q.trim().toLowerCase();
      filtered = t.isEmpty
          ? List.of(source)
          : source.where((e) => e.value.toLowerCase().contains(t)).toList();
    }

    apply("");

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottom = mq.viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (ctx2, sc) {
              return StatefulBuilder(
                builder: (ctx3, setSt) {
                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Seleziona persone",
                        style: Theme.of(ctx3).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Cerca persona...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setSt(() {
                              apply(v);
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                setSt(() {
                                  tmp
                                    ..clear()
                                    ..addAll(filtered.map((e) => e.key));
                                });
                              },
                              icon: const Icon(Icons.done_all),
                              label: const Text("Seleziona tutti"),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                setSt(() {
                                  tmp.clear();
                                });
                              },
                              icon: const Icon(Icons.clear_all),
                              label: const Text("Pulisci"),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: sc,
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            final checked = tmp.contains(e.key);
                            return CheckboxListTile(
                              value: checked,
                              title: Text(e.value),
                              onChanged: (v) {
                                setSt(() {
                                  if (v == true) {
                                    tmp.add(e.key);
                                  } else {
                                    tmp.remove(e.key);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("Annulla"),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    selectedPersonale
                                      ..clear()
                                      ..addAll(tmp);
                                    final first = selectedPersonale.isNotEmpty
                                        ? selectedPersonale.first
                                        : null;
                                    if (first != null) {
                                      final pref = (personaleCameraDefault[first] ?? '')
                                          .trim()
                                          .toLowerCase();
                                      if (pref == 'singola' || pref == 'doppia') {
                                        cameraTipo = pref;
                                      }
                                    }
                                  });
                                },
                                child: const Text("OK"),
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------
  // DATE RANGE PICKER
  // ----------------------------------------------------------
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final pick = await showDateRangePicker(
      context: context,
      initialDateRange:
          DateTimeRange(start: range[0] ?? now, end: range[1] ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pick != null) {
      setState(() {
        range = [pick.start, pick.end];
      });
    }
  }

  // ----------------------------------------------------------
  // WIDGET UI MODERNO (solo se ti serve altrove)
  // ----------------------------------------------------------
  Widget _modernDropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    required Function(String?) onChanged,
    IconData? icon,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
    );
  }

  void _msg(String text, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

// ======================================================================
// REUSABLE PICKER (campo singola scelta id/label) — come nelle altre pagine
// ======================================================================

class _Option {
  final String id;
  final String label;
  const _Option({required this.id, required this.label});
}

/// Campo readOnly che apre un bottom‑sheet con **elenco completo + ricerca**
class _PickerFieldOption extends StatelessWidget {
  final TextEditingController controller;  // mostra il label scelto
  final String label;
  final List<_Option> options;             // elenco completo (id, label)
  final ValueChanged<_Option?> onSelected;
  final IconData? leading;

  const _PickerFieldOption({
    required this.controller,
    required this.label,
    required this.options,
    required this.onSelected,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: leading != null ? Icon(leading) : null,
        suffixIcon: const Icon(Icons.arrow_drop_down),
      ),
      onTap: () async {
        final picked = await _openOptionPicker(
          context: context,
          title: label,
          all: options,
          initialLabel: controller.text,
        );
        if (picked != null) {
          controller.text = picked.label;
          onSelected(picked);
        }
      },
    );
  }

  Future<_Option?> _openOptionPicker({
    required BuildContext context,
    required String title,
    required List<_Option> all,
    String? initialLabel,
  }) async {
    final searchCtrl = TextEditingController(text: "");
    List<_Option> source = List<_Option>.from(all)
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    List<_Option> filtered = List<_Option>.from(source);

    void apply(String q) {
      final t = q.trim().toLowerCase();
      filtered = t.isEmpty
          ? List<_Option>.from(source)
          : source.where((o) => o.label.toLowerCase().contains(t)).toList();
    }

    apply(searchCtrl.text);

    return await showModalBottomSheet<_Option>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final bottom = mq.viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (ctx2, sc) {
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Cerca...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        apply(v);
                        (ctx as Element).markNeedsBuild();
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      controller: sc,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        return ListTile(
                          title: Text(o.label),
                          onTap: () => Navigator.pop(ctx, o),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}