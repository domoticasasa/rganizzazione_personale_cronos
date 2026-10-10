import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/note_preview_text.dart';
import '../widgets/async_action_button.dart';
import '../utils/date_formatters.dart';
import '../utils/travel_departure_guard.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/responsive.dart';
import '../utils/dt_user_list.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AereoMobilePage extends StatefulWidget {
  final String username;
  final int userId;
  final String role;
  final String fullName;

  const AereoMobilePage({
    super.key,
    required this.username,
    required this.userId,
    required this.role,
    required this.fullName,
  });

  @override
  State<AereoMobilePage> createState() => _AereoMobilePageState();
}

class _AereoMobilePageState extends State<AereoMobilePage> {
  bool get _isAssistenteDt =>
      widget.role.toLowerCase().replaceAll(' ', '_') == 'assistente_dt';

  // Dizionari
  final Map<String, String> personale = {}; // personale.id_uuid -> full_name
  final Map<String, String> personaleEmail = {}; // personale.id_uuid -> email
  final Map<String, String> commesse = {}; // commesse.id_uuid  -> nome
  final List<String> aeroporti = []; // nomi aeroporti attivi (tutti, paginato)

  // Valori form
  final List<String> selectedPersonale = []; // UUID multi
  String? aeroportoPartenza; // nome
  String? aeroportoArrivo; // nome
  String? commessaId; // UUID

  String? dtUserUuid;
  String? _selectedDtUuidForAssist;
  final Map<String, String> _dtOptions = {}; // id_uuid -> label
  final _dtAssistantCtrl = TextEditingController();
  DateTime dataVolo = DateTime.now();
  String? orarioHHmm;
  String viaggioTipo = 'A'; // A | AR
  DateTime? dataRitorno;
  String? orarioRitornoHHmm;
  // Se A/R e flag attivo, si seleziona solo la destinazione del ritorno (arrivo ritorno).
  bool _ritornoDiverso = false;
  String? aeroportoRitornoDest;

  String? bagaglio;
  bool parcheggio = false;

  final noteCtrl = TextEditingController();
  final targaCtrl = TextEditingController();

  // Controller di visualizzazione (mostrano il LABEL nei campi)
  final _aerPartCtrl = TextEditingController();
  final _aerArrCtrl = TextEditingController();
  final _commessaCtrl = TextEditingController();
  final _aerRitornoDestCtrl = TextEditingController();

  List<Map<String, dynamic>> prenotazioni = [];
  bool loading = true;
  bool _insertInFlight = false;

  int _compareTextAz(String a, String b) =>
      a.trim().toLowerCase().compareTo(b.trim().toLowerCase());

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    targaCtrl.dispose();
    _aerPartCtrl.dispose();
    _aerArrCtrl.dispose();
    _commessaCtrl.dispose();
    _aerRitornoDestCtrl.dispose();
    _dtAssistantCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // BOOTSTRAP
  // ----------------------------------------------------------
  Future<void> _bootstrap() async {
    await _fetchDtUuid();
    await _loadDizionari();
    await _loadPrenotazioni();
    if (mounted) setState(() => loading = false);
  }

  // DT: prova users.id (se UUID), altrimenti users.id_uuid
  Future<void> _fetchDtUuid() async {
    try {
      final r1 = await SupabaseService.client
          .from("users")
          .select("id, username")
          .eq("username", widget.username)
          .maybeSingle();

      final id1 = (r1?["id"])?.toString();
      if (id1 != null && id1.length >= 32) {
        dtUserUuid = id1;
        return;
      }

      final r2 = await SupabaseService.client
          .from("users")
          .select("id_uuid, username")
          .eq("username", widget.username)
          .maybeSingle();

      final id2 = (r2?["id_uuid"])?.toString();
      if (id2 != null && id2.length >= 32) {
        dtUserUuid = id2;
        return;
      }
    } catch (_) {}
  }

  // ---------- PAGINAZIONE: scarica TUTTI gli aeroporti a blocchi da 1000 ----------
  Future<List<String>> _fetchAllAeroporti({bool soloAttivi = true}) async {
    const pageSize = 1000;
    int from = 0;
    final List<String> acc = [];

    while (true) {
      final base =
          SupabaseService.client.from("aeroporti").select("nome, attiva");

      final filtered = soloAttivi ? base.eq("attiva", true) : base;

      final page = await filtered
          .order("nome", ascending: true)
          .range(from, from + pageSize - 1);

      final list = List<Map<String, dynamic>>.from(page as List);
      if (list.isEmpty) break;

      acc.addAll(list.map((e) => (e["nome"] ?? "").toString()));

      if (list.length < pageSize) break; // ultima pagina
      from += pageSize;
    }

    acc.sort(_compareTextAz);
    return acc;
  }

  // Dizionari (personale/commesse/aeroporti)
  Future<void> _loadDizionari() async {
    try {
      // Personale
      final p = await SupabaseService.client
          .from("personale")
          .select("id_uuid, full_name, email")
          .eq("active", true)
          .order("full_name");

      personale
        ..clear()
        ..addEntries(
          ((p as List)
                .map(
                  (e) => MapEntry(
                    (e["id_uuid"] ?? '').toString(),
                    (e["full_name"] ?? '').toString(),
                  ),
                )
                .toList()
              ..sort((a, b) => _compareTextAz(a.value, b.value))),
        );
      personaleEmail
        ..clear()
        ..addEntries(
          ((p as List).map(
                (e) => MapEntry(
                  (e["id_uuid"] ?? '').toString(),
                  (e["email"] ?? '').toString().trim(),
                ),
              )),
        );

      // Aeroporti (tutti, paginato)
      final apAll = await _fetchAllAeroporti(soloAttivi: true);
      aeroporti
        ..clear()
        ..addAll(apAll);

      // Commesse
      final cm = await SupabaseService.client
          .from("commesse")
          .select("id_uuid, nome")
          .eq("active", true)
          .order("nome");

      commesse
        ..clear()
        ..addEntries(
          ((cm as List)
                .map(
                  (e) => MapEntry(
                    (e["id_uuid"] ?? '').toString(),
                    (e["nome"] ?? '').toString(),
                  ),
                )
                .toList()
              ..sort((a, b) => _compareTextAz(a.value, b.value))),
        );

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
            _dtOptions.clear();
          } else {
            final orExpr = allowedUuids.map((u) => 'id_uuid.eq.$u').join(',');
            final dtRes = await SupabaseService.client
                .from('users')
                .select('id_uuid, full_name, username')
                .or(orExpr);

            _dtOptions
              ..clear()
              ..addAll({
                for (final e in (dtRes as List))
                  if ((e['id_uuid'] ?? '').toString().trim().isNotEmpty)
                    (e['id_uuid'] ?? '').toString().trim():
                        ((e['full_name'] ?? '').toString().trim().isNotEmpty
                            ? (e['full_name'] ?? '').toString().trim()
                            : (e['username'] ?? '').toString().trim())
              });
            final sortedEntries = _dtOptions.entries.toList()
              ..sort((a, b) => _compareTextAz(a.value, b.value));
            _dtOptions
              ..clear()
              ..addEntries(sortedEntries);
          }
        } catch (_) {
          _dtOptions
            ..clear()
            ..addAll(await loadDtOptionsByUuid());
          final sortedEntries = _dtOptions.entries.toList()
            ..sort((a, b) => _compareTextAz(a.value, b.value));
          _dtOptions
            ..clear()
            ..addEntries(sortedEntries);
        }

        if (_dtOptions.isNotEmpty &&
            (_selectedDtUuidForAssist == null ||
                !_dtOptions.containsKey(_selectedDtUuidForAssist))) {
          _selectedDtUuidForAssist = _dtOptions.keys.first;
        }
      }

      _syncControllers();

      if (mounted) setState(() {});
    } catch (e) {
      _msg("Errore caricamento dizionari: $e", isError: true);
    }
  }

  void _syncControllers() {
    _commessaCtrl.text =
        (commessaId != null) ? (commesse[commessaId!] ?? "") : "";
    _aerPartCtrl.text = aeroportoPartenza ?? "";
    _aerArrCtrl.text = aeroportoArrivo ?? "";
    _dtAssistantCtrl.text = (_selectedDtUuidForAssist != null)
        ? (_dtOptions[_selectedDtUuidForAssist!] ?? '')
        : '';
  }

  // Prenotazioni
  Future<void> _loadPrenotazioni() async {
    final effectiveDtUuid =
        _isAssistenteDt ? _selectedDtUuidForAssist : dtUserUuid;
    if (effectiveDtUuid == null) return;

    try {
      final rows = await SupabaseService.client
          .from("bookings_aereo")
          .select()
          .eq("dt_user_uuid", effectiveDtUuid)
          .order("data", ascending: false);

      prenotazioni = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _msg("Errore caricamento prenotazioni: $e", isError: true);
    }
  }

  // ----------------------------------------------------------
  // Pickers
  // ----------------------------------------------------------
  Future<void> _pickData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dataVolo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => dataVolo = d);
  }

  Future<void> _pickOrario() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        orarioHHmm =
            "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _pickDataRitorno() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dataRitorno ?? dataVolo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => dataRitorno = d);
  }

  Future<void> _pickOrarioRitorno() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        orarioRitornoHHmm =
            "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _pickPersonaleBottomSheet() async {
    final tmp = Set<String>.from(selectedPersonale);
    final TextEditingController searchCtrl = TextEditingController();
    final source = personale.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
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
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Cerca persona...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setSt(() => apply(v));
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
  // Insert
  // ----------------------------------------------------------
  bool _looksUuid(String? v) => v != null && v.length >= 32 && v.contains("-");

  Future<void> _insert() async {
    if (_insertInFlight) return;
    if (!await ensureCanPersist(context)) return;
    final effectiveDtUuid =
        _isAssistenteDt ? _selectedDtUuidForAssist : dtUserUuid;
    if (effectiveDtUuid == null) {
      _msg("dt_user_uuid non disponibile.", isError: true);
      return;
    }
    if (_isAssistenteDt &&
        (_selectedDtUuidForAssist == null ||
            !_dtOptions.containsKey(_selectedDtUuidForAssist))) {
      _msg("Seleziona il DT supervisore.", isError: true);
      return;
    }

    if (selectedPersonale.isEmpty ||
        !_looksUuid(commessaId) ||
        (aeroportoPartenza == null || aeroportoPartenza!.trim().isEmpty) ||
        (aeroportoArrivo == null || aeroportoArrivo!.trim().isEmpty) ||
        (orarioHHmm == null || orarioHHmm!.trim().isEmpty)) {
      _msg(
          "Compila: Personale, Aeroporto partenza/arrivo, Data, Orario e Commessa.",
          isError: true);
      return;
    }
    if (bagaglio == null || bagaglio!.trim().isEmpty) {
      _msg("Seleziona il tipo di bagaglio.", isError: true);
      return;
    }

    if (aeroportoPartenza == aeroportoArrivo) {
      _msg("Partenza e arrivo devono essere diversi.", isError: true);
      return;
    }

    if (parcheggio && targaCtrl.text.trim().isEmpty) {
      _msg("Inserisci la targa.", isError: true);
      return;
    }
    if (viaggioTipo == 'AR') {
      if (dataRitorno == null || (orarioRitornoHHmm ?? '').trim().isEmpty) {
        _msg("Per A/R compila data e orario ritorno.", isError: true);
        return;
      }
      if (_ritornoDiverso) {
        if (aeroportoRitornoDest == null ||
            aeroportoRitornoDest!.trim().isEmpty) {
          _msg(
              "Se hai selezionato ritorno diverso, seleziona anche la destinazione di ritorno.",
              isError: true);
          return;
        }
        if (aeroportoRitornoDest == aeroportoArrivo) {
          _msg(
              "La destinazione di ritorno deve essere diversa dall'aeroporto di partenza del ritorno.",
              isError: true);
          return;
        }
      }
    }

    if (!selectedPersonale.every(_looksUuid)) {
      _msg("ID personale non validi (devono essere UUID).", isError: true);
      return;
    }

    final pastMsg = pastTravelDepartureMessage(
      dataPartenza: dataVolo,
      orarioPartenzaHHmm: orarioHHmm!,
      dataRitorno: dataRitorno,
      orarioRitornoHHmm: orarioRitornoHHmm,
      andataRitorno: viaggioTipo == 'AR',
      tipoViaggioLabel: 'biglietto aereo',
    );
    if (pastMsg != null) {
      await showPastTravelDepartureDialog(context, pastMsg);
      return;
    }

    setState(() => _insertInFlight = true);
    try {
      final payload = selectedPersonale
          .map((pid) => {
                "personale_id": pid,
                "aeroporto_partenza": aeroportoPartenza,
                "aeroporto_arrivo": aeroportoArrivo,
                "data": _iso(dataVolo),
                "orario": orarioHHmm,
                "viaggio_tipo": viaggioTipo,
                "data_ritorno": viaggioTipo == 'AR' ? _iso(dataRitorno!) : null,
                "orario_ritorno":
                    viaggioTipo == 'AR' ? orarioRitornoHHmm : null,
                // Per default il ritorno torna dall'arrivo alla partenza.
                "aeroporto_partenza_ritorno":
                    viaggioTipo == 'AR' ? aeroportoArrivo : null,
                "aeroporto_arrivo_ritorno": viaggioTipo == 'AR'
                    ? (_ritornoDiverso
                        ? aeroportoRitornoDest
                        : aeroportoPartenza)
                    : null,
                "commessa_id": commessaId,
                "bagaglio": bagaglio,
                "parcheggio": parcheggio,
                "targa_veicolo": parcheggio ? targaCtrl.text.trim() : null,
                "status": "IN_ATTESA",
                "dt_user_uuid": effectiveDtUuid,
                "master_note": noteCtrl.text.trim(),
                "created_at": supabaseNowIsoUtc(),
                if (dtUserUuid != null && dtUserUuid!.length >= 32)
                  "updated_by": dtUserUuid,
                if (_isAssistenteDt) "requested_by_user_id": widget.userId,
              })
          .toList(growable: false);

      final inserted = await SupabaseService.client
          .from("bookings_aereo")
          .insert(payload)
          .select('id') as List;

      final ids = inserted
          .map((e) => (e as Map)['id'])
          .map((v) => v != null ? int.tryParse(v.toString()) : null)
          .whereType<int>()
          .toList();
      for (final id in ids) {
        await NotificationSender.notifyUserForBooking(
          dtUserId: effectiveDtUuid,
          bookingId: id,
          action: 'create',
          title: 'Nuova prenotazione Aerea',
          bookingType: 'aereo',
        );
      }

      setState(() {
        selectedPersonale.clear();
        commessaId = null;
        aeroportoPartenza = null;
        aeroportoArrivo = null;
        bagaglio = null;
        parcheggio = false;
        _ritornoDiverso = false;
        aeroportoRitornoDest = null;
        _aerRitornoDestCtrl.text = '';
        orarioHHmm = null;
        viaggioTipo = 'A';
        dataRitorno = null;
        orarioRitornoHHmm = null;
        noteCtrl.clear();
        targaCtrl.clear();
        _syncControllers();
      });

      await _loadPrenotazioni();
      _msg(
        "Prenotazione inserita. "
        "Notifiche: admin treni/aereo; se sei DT anche al dipendente; "
        "se Assistente DT anche al DT supervisore (Regole notifiche).",
      );
    } catch (e) {
      _msg("Errore: $e", isError: true);
    } finally {
      if (mounted) {
        setState(() => _insertInFlight = false);
      }
    }
  }

  String _iso(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  String _displayDate(DateTime d) =>
      formatDateDdMmYyyyFromDate(d);

  // ----------------------------------------------------------
  // Stato → colore
  // ----------------------------------------------------------
  Future<void> _copyEmailToClipboard(String? email) async {
    final e = (email ?? '').trim();
    if (e.isEmpty) {
      _msg('Email non disponibile', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: e));
    _msg('Email copiata negli appunti');
  }

  Widget _atCopyButton(String? email) {
    final ok = (email ?? '').trim().isNotEmpty;
    return IconButton(
      tooltip: ok ? 'Copia email' : 'Email non disponibile',
      icon: const Text(
        '@',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1),
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: ok ? () => _copyEmailToClipboard(email) : null,
    );
  }

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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          stato,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Dettagli
  // ----------------------------------------------------------
  void _dettaglio(Map r) {
    final stato = (r["status"] ?? "").toString();
    final color = _statusColor(stato);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(personale[r["personale_id"]] ?? ""),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Data: ${formatDateDdMmYyyy(r["data"])}"),
            Text("Orario: ${r["orario"]}"),
            Text("Da: ${r["aeroporto_partenza"]}"),
            Text("A: ${r["aeroporto_arrivo"]}"),
            if (((r["data_ritorno"] ?? '').toString().isNotEmpty) ||
                ((r["orario_ritorno"] ?? '').toString().isNotEmpty)) ...[
              const SizedBox(height: 6),
              Text("Ritorno: ${formatDateDdMmYyyy(r["data_ritorno"])}"),
              Text(
                "Orario ritorno: ${r["orario_ritorno"] ?? '--:--'}",
              ),
              Text(
                "Da ritorno: ${(r["aeroporto_partenza_ritorno"] ?? '').toString().isNotEmpty ? r["aeroporto_partenza_ritorno"] : r["aeroporto_arrivo"]}",
              ),
              Text(
                "A ritorno: ${(r["aeroporto_arrivo_ritorno"] ?? '').toString().isNotEmpty ? r["aeroporto_arrivo_ritorno"] : r["aeroporto_partenza"]}",
              ),
            ],
            Text("Commessa: ${commesse[r["commessa_id"]]}"),
            Text("Bagaglio: ${r["bagaglio"]}"),
            Text("Parcheggio: ${(r["parcheggio"] == true) ? 'Sì' : 'No'}"),
            if ((r["targa_veicolo"] ?? '').toString().isNotEmpty)
              Text("Targa: ${r["targa_veicolo"]}"),
            if ((r["master_note"] ?? '').toString().isNotEmpty)
              NotePreviewText(
                note: (r["master_note"] ?? '').toString(),
                prefix: 'Note: ',
                maxChars: 10,
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
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
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: wrapClassicAppBarChrome(
          context,
          AppBar(title: const Text('Aereo')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
                'Aerei – ${widget.fullName}',
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
              //====================================================
              // FORM
              //====================================================
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_isAssistenteDt) ...[
                        _PickerFieldOption(
                          controller: _dtAssistantCtrl,
                          label: "DT supervisore",
                          options: _dtOptions.entries
                              .map((e) => _Option(id: e.key, label: e.value))
                              .toList()
                            ..sort((a, b) => a.label
                                .toLowerCase()
                                .compareTo(b.label.toLowerCase())),
                          onSelected: (opt) async {
                            setState(() {
                              _selectedDtUuidForAssist = opt?.id;
                              _dtAssistantCtrl.text = opt?.label ?? "";
                            });
                            await _loadPrenotazioni();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      // PERSONALE (multi) come pernottamenti
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: selectedPersonale
                              .map((id) => Chip(
                                    label: Text(personale[id] ?? id),
                                    onDeleted: () {
                                      setState(
                                          () => selectedPersonale.remove(id));
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

                      const SizedBox(height: 12),

                      // AEROPORTO PARTENZA — elenco completo + ricerca immediata
                      _PickerFieldString(
                        controller: _aerPartCtrl,
                        label: "Aeroporto di partenza",
                        allItems: aeroporti,
                        onSelected: (value) {
                          setState(() {
                            aeroportoPartenza = value;
                            _aerPartCtrl.text = value ?? "";
                            if (_ritornoDiverso) {
                              // Default ritorno destinazione = partenza andata.
                              aeroportoRitornoDest = value;
                              _aerRitornoDestCtrl.text =
                                  aeroportoRitornoDest ?? '';
                            }
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // AEROPORTO ARRIVO — elenco completo + ricerca immediata
                      _PickerFieldString(
                        controller: _aerArrCtrl,
                        label: "Aeroporto di arrivo",
                        allItems: aeroporti,
                        onSelected: (value) {
                          setState(() {
                            aeroportoArrivo = value;
                            _aerArrCtrl.text = value ?? "";
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // COMMESSA — bottom-sheet con ricerca
                      _PickerFieldOption(
                        controller: _commessaCtrl,
                        label: "Commessa",
                        options: commesse.entries
                            .map((e) => _Option(id: e.key, label: e.value))
                            .toList()
                          ..sort((a, b) => a.label
                              .toLowerCase()
                              .compareTo(b.label.toLowerCase())),
                        onSelected: (opt) {
                          setState(() {
                            commessaId = opt?.id;
                            _commessaCtrl.text = opt?.label ?? "";
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text("Viaggio:"),
                            ChoiceChip(
                              label: const Text("A"),
                              selected: viaggioTipo == 'A',
                              onSelected: (_) => setState(() {
                                viaggioTipo = 'A';
                                dataRitorno = null;
                                orarioRitornoHHmm = null;
                                _ritornoDiverso = false;
                                aeroportoRitornoDest = null;
                                _aerRitornoDestCtrl.text = '';
                              }),
                            ),
                            ChoiceChip(
                              label: const Text("A/R"),
                              selected: viaggioTipo == 'AR',
                              onSelected: (_) =>
                                  setState(() => viaggioTipo = 'AR'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                "Data: ${dataVolo.day}/${dataVolo.month}/${dataVolo.year}"),
                          ),
                          FilledButton(
                            onPressed: _pickData,
                            child: const Text("Data"),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child:
                                Text("Orario andata: ${orarioHHmm ?? '--:--'}"),
                          ),
                          FilledButton(
                            onPressed: _pickOrario,
                            child: const Text("Orario andata"),
                          ),
                        ],
                      ),

                      if (viaggioTipo == 'AR') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Data ritorno: ${dataRitorno == null ? '--' : _displayDate(dataRitorno!)}",
                              ),
                            ),
                            FilledButton(
                              onPressed: _pickDataRitorno,
                              child: const Text("Data ritorno"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Orario ritorno: ${orarioRitornoHHmm ?? '--:--'}",
                              ),
                            ),
                            FilledButton(
                              onPressed: _pickOrarioRitorno,
                              child: const Text("Orario ritorno"),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      SwitchListTile(
                        dense: true,
                        value: _ritornoDiverso,
                        onChanged: (v) => setState(() {
                          _ritornoDiverso = v;
                          if (!_ritornoDiverso) {
                            aeroportoRitornoDest = null;
                            _aerRitornoDestCtrl.text = '';
                          } else {
                            aeroportoRitornoDest = aeroportoPartenza;
                            _aerRitornoDestCtrl.text =
                                aeroportoRitornoDest ?? '';
                          }
                        }),
                        title: const Text('Ritorno diverso'),
                      ),
                      if (_ritornoDiverso) ...[
                        _PickerFieldString(
                          controller: _aerRitornoDestCtrl,
                          label: 'Seleziona destinazione',
                          allItems: aeroporti,
                          onSelected: (value) {
                            setState(() {
                              aeroportoRitornoDest = value;
                              _aerRitornoDestCtrl.text = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      const SizedBox(height: 16),

                      // Bagaglio statico
                      DropdownButtonFormField<String>(
                        initialValue: bagaglio,
                        hint: const Text("Seleziona bagaglio"),
                        decoration: InputDecoration(
                          labelText: "Bagaglio *",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: "mano", child: Text("Bagaglio a mano")),
                          DropdownMenuItem(
                              value: "stiva", child: Text("Bagaglio in stiva")),
                        ],
                        onChanged: (v) => setState(() => bagaglio = v),
                      ),

                      const SizedBox(height: 10),

                      SwitchListTile(
                        value: parcheggio,
                        onChanged: (v) => setState(() => parcheggio = v),
                        title: const Text("Parcheggio"),
                      ),

                      if (parcheggio)
                        TextField(
                          controller: targaCtrl,
                          decoration: const InputDecoration(
                            labelText: "Targa veicolo",
                            border: OutlineInputBorder(),
                          ),
                        ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: noteCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      AsyncFilledButton(
                        onPressed: _insertInFlight ? null : _insert,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add),
                            SizedBox(width: 8),
                            Text("Inserisci"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              //====================================================
              // LISTA PRENOTAZIONI
              //====================================================
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Prenotazioni",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),

              // (debug) quante aeroporti sono stati caricati
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Aeroporti caricati: ${aeroporti.length}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: prenotazioni.length,
                itemBuilder: (_, i) {
                  final r = prenotazioni[i];
                  final nome = personale[r["personale_id"]] ?? "";
                  final email = personaleEmail[r["personale_id"]] ?? "";
                  final stato = (r["status"] ?? "").toString();

                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      title: Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              email.trim().isEmpty ? 'Email non disponibile' : email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: email.trim().isEmpty ? Colors.grey : null,
                              ),
                            ),
                          ),
                          _atCopyButton(email),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _statusBadge(stato),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
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
// REUSABLE PICKERS (campi che aprono un bottom-sheet con ricerca e lista)
// ======================================================================

class _Option {
  final String id;
  final String label;
  const _Option({required this.id, required this.label});
}

/// Campo per scegliere *String* (es. Aeroporti) — UI: TextField readOnly.
/// Tocco => apre un bottom-sheet con elenco completo + barra di ricerca.
class _PickerFieldString extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<String> allItems; // elenco completo (già ordinato)
  final ValueChanged<String?> onSelected;

  const _PickerFieldString({
    required this.controller,
    required this.label,
    required this.allItems,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true, // si scrive dentro al picker
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: const Icon(Icons.list),
      ),
      onTap: () async {
        final picked = await _openStringPicker(
          context: context,
          title: label,
          all: allItems,
          initial: controller.text,
        );
        if (picked != null) {
          controller.text = picked;
          onSelected(picked);
        }
      },
    );
  }

  /// Bottom-sheet per stringhe con ricerca locale
  Future<String?> _openStringPicker({
    required BuildContext context,
    required String title,
    required List<String> all,
    String? initial,
  }) async {
    final searchCtrl = TextEditingController(text: "");
    List<String> filtered = List<String>.from(all);

    void apply(String q) {
      final t = q.trim().toLowerCase();
      filtered = t.isEmpty
          ? List<String>.from(all)
          : all
              .where((s) => s.toLowerCase().contains(t))
              .toList(growable: false);
    }

    apply(searchCtrl.text);

    return await showModalBottomSheet<String>(
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
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true, // tastiera subito
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
                        final s = filtered[i];
                        return ListTile(
                          title: Text(s),
                          onTap: () => Navigator.pop(ctx, s),
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

/// Campo per scegliere *Option (id,label)* (es. Personale/Commessa)
class _PickerFieldOption extends StatelessWidget {
  final TextEditingController controller; // mostra il label scelto
  final String label;
  final List<_Option> options; // elenco (id,label) completo
  final ValueChanged<_Option?> onSelected;

  const _PickerFieldOption({
    required this.controller,
    required this.label,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true, // si scrive nel picker
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
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
    List<_Option> filtered = List<_Option>.from(all);

    void apply(String q) {
      final t = q.trim().toLowerCase();
      filtered = t.isEmpty
          ? List<_Option>.from(all)
          : all
              .where((o) => o.label.toLowerCase().contains(t))
              .toList(growable: false);
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
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
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
