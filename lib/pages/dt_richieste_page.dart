import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../services/notification_sender.dart';
import '../services/confirm_sound_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/neo_buttons.dart';
import '../utils/date_formatters.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../utils/admin_vista_guard.dart';

class DTRichiestePage extends StatefulWidget {
  final int userId; // users.id
  final String fullName;

  const DTRichiestePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<DTRichiestePage> createState() => _DTRichiestePageState();
}

class _DTRichiestePageState extends State<DTRichiestePage> {
  bool _loading = true;
  bool _busy = false;

  String? _dtUuid; // users.id_uuid

  final List<_ReqRow> _rows = [];
  final Map<String, String> _commesse = {};
  final Map<String, String> _personale = {};
  final Map<String, String> _requesters = {}; // users.id -> full_name/username
  final Map<int, String> _commessaSelection = {}; // bookingId -> commessaId_uuid (DT scelta)

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadDtUuid();
      await _loadDizionari();
      await _loadRows();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _loadDtUuid() async {
    final u = await SupabaseService.client
        .from('users')
        .select('id_uuid')
        .eq('id', widget.userId)
        .maybeSingle();
    final uuid = (u?['id_uuid'] ?? '').toString().trim();
    if (uuid.isNotEmpty) _dtUuid = uuid;
  }

  Future<void> _loadDizionari() async {
    // commesse
    final c = await SupabaseService.client
        .from('commesse')
        .select('id_uuid, nome')
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
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );

    // personale
    final p = await SupabaseService.client
        .from('personale')
        .select('id_uuid, full_name')
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
            ..sort((a, b) =>
                a.value.toLowerCase().trim().compareTo(b.value.toLowerCase().trim()))),
      );
  }

  Future<void> _loadRows() async {
    _rows.clear();
    _requesters.clear();
    _commessaSelection.clear();

    if (_dtUuid == null || _dtUuid!.isEmpty) {
      _toast('DT UUID non trovato.', error: true);
      return;
    }

    // Treni
    final tr = await SupabaseService.client
        .from('bookings_treno')
        .select(
          'id, data, orario, stazione_partenza, stazione_arrivo, commessa_id, personale_id, '
          'stazione_arrivo_ritorno, requested_by_user_id, workflow_status, assigned_dt_user_uuid',
        )
        .eq('workflow_status', 'INVIATA_AL_DT')
        .eq('assigned_dt_user_uuid', _dtUuid!)
        .order('data', ascending: false)
        .range(0, 499);
    for (final r in (tr as List)) {
      _rows.add(_ReqRow.fromTreno(r as Map<String, dynamic>));
    }

    // Aerei
    final ar = await SupabaseService.client
        .from('bookings_aereo')
        .select(
          'id, data, orario, aeroporto_partenza, aeroporto_arrivo, commessa_id, personale_id, '
          'aeroporto_arrivo_ritorno, requested_by_user_id, workflow_status, assigned_dt_user_uuid',
        )
        .eq('workflow_status', 'INVIATA_AL_DT')
        .eq('assigned_dt_user_uuid', _dtUuid!)
        .order('data', ascending: false)
        .range(0, 499);
    for (final r in (ar as List)) {
      _rows.add(_ReqRow.fromAereo(r as Map<String, dynamic>));
    }

    _rows.sort((a, b) => b.dataIso.compareTo(a.dataIso));

    // Requesters names (users.id)
    final ids = _rows
        .map((e) => e.requestedByUserId)
        .whereType<int>()
        .toSet()
        .toList();
    if (ids.isNotEmpty) {
      final orExpr = ids.map((id) => 'id.eq.$id').join(',');
      final ur = await SupabaseService.client
          .from('users')
          .select('id, full_name, username')
          .or(orExpr);
      for (final u in (ur as List)) {
        final id = u['id'] as int?;
        if (id == null) continue;
        final full = (u['full_name'] ?? '').toString().trim();
        final user = (u['username'] ?? '').toString().trim();
        _requesters[id.toString()] = full.isNotEmpty ? full : user;
      }
    }
  }

  Future<void> _approve(_ReqRow row) async {
    if (_dtUuid == null) return;
    if (!await ensureCanPersist(context)) return;
    final selectedCommessa = _commessaSelection[row.id] ?? row.commessaId;
    if (selectedCommessa == null || selectedCommessa.trim().isEmpty) {
      _toast('Seleziona una commessa prima di confermare.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.client
          .from(row.table)
          .update({
            'commessa_id': selectedCommessa,
            'workflow_status': 'INVIATA_ADMIN',
            'dt_decision_at': supabaseNowIsoUtc(),
            'dt_reject_reason': null,
            'dt_user_uuid': _dtUuid, // diventa del DT scelto
            'updated_by': _dtUuid,
          })
          .eq('id', row.id);

      // Notifica admin competenti secondo regola configurabile.
      final adminTargets = await NotificationSender.targetsForRule(
        'dt_approved_to_admin',
        fallback: const ['role:admin_trenoaereo'],
      );
      final adminIds = await NotificationSender.resolveRecipientsFromTargets(
        targets: adminTargets,
        requesterUserId: row.requestedByUserId,
        bookingId: row.id,
        bookingType: row.typeLabel.toLowerCase(),
      );
      final currentAuthId =
          SupabaseService.client.auth.currentUser?.id.toString().trim() ?? '';
      final selfLikeIds = <int>{widget.userId};
      try {
        final selfRows = await SupabaseService.client
            .from('users')
            .select('id')
            .or([
              'id.eq.${widget.userId}',
              if (_dtUuid != null && _dtUuid!.isNotEmpty) 'id_uuid.eq.${_dtUuid!}',
              if (currentAuthId.isNotEmpty) 'auth_id.eq.$currentAuthId',
            ].join(','));
        for (final row in (selfRows as List)) {
          final id = row['id'] as int?;
          if (id != null) selfLikeIds.add(id);
        }
      } catch (_) {}
      adminIds.removeWhere((id) => selfLikeIds.contains(id)); // evita auto-notifica

      if (adminIds.isNotEmpty) {
        await NotificationSender.sendToUserIds(
          userIds: adminIds,
          bookingId: row.id,
          action: 'dt_approved',
          title: 'Richiesta ${row.typeLabel} approvata dal DT',
          message: 'Richiesta ${row.typeLabel} pronta per la gestione admin.',
        );
      }

      // Notifica richiedente secondo regola configurabile.
      if (row.requestedByUserId != null && row.requestedByUserId != widget.userId) {
        final reqTargets = await NotificationSender.targetsForRule(
          'dt_approved_to_requester',
          fallback: const ['requester'],
        );
        final reqIds = await NotificationSender.resolveRecipientsFromTargets(
          targets: reqTargets,
          requesterUserId: row.requestedByUserId,
          bookingId: row.id,
          bookingType: row.typeLabel.toLowerCase(),
        );
        await NotificationSender.sendToUserIds(
          userIds: reqIds.isEmpty ? [row.requestedByUserId!] : reqIds,
          bookingId: row.id,
          action: 'dt_approved',
          title: 'Richiesta ${row.typeLabel} approvata',
          message: 'La tua richiesta ${row.typeLabel} è stata approvata dal DT.',
        );
      }

      await _loadRows();
      _toast(
        'Richiesta approvata e inoltrata agli admin. '
        'Notifica inviata a: admin competenti e richiedente.',
      );
    } catch (e) {
      _toast('Errore approvazione: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(_ReqRow row) async {
    if (_dtUuid == null) return;
    if (!await ensureCanPersist(context)) return;
    final reason = await _askReason();
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client
          .from(row.table)
          .update({
            'workflow_status': 'RIFIUTATA_DAL_DT',
            'dt_decision_at': supabaseNowIsoUtc(),
            'dt_reject_reason': reason.trim(),
            'dt_user_uuid': _dtUuid, // resta “del DT scelto” per tracciamento
            'updated_by': _dtUuid,
            'status': 'RIFIUTATA',
          })
          .eq('id', row.id);

      final rejTargets = await NotificationSender.targetsForRule(
        'dt_rejected_to_requester',
        fallback: const ['dipendente', 'requester'],
      );
      final selfRej = <int>{widget.userId};
      try {
        final currentAuthId =
            SupabaseService.client.auth.currentUser?.id.toString().trim() ?? '';
        final selfRows = await SupabaseService.client
            .from('users')
            .select('id')
            .or([
              'id.eq.${widget.userId}',
              if (_dtUuid != null && _dtUuid!.isNotEmpty) 'id_uuid.eq.${_dtUuid!}',
              if (currentAuthId.isNotEmpty) 'auth_id.eq.$currentAuthId',
            ].join(','));
        for (final row in (selfRows as List)) {
          final id = row['id'] as int?;
          if (id != null) selfRej.add(id);
        }
      } catch (_) {}
      var rejIds = await NotificationSender.resolveRecipientsFromTargets(
        targets: rejTargets,
        requesterUserId: row.requestedByUserId,
        bookingId: row.id,
        bookingType: row.typeLabel.toLowerCase(),
      );
      rejIds.removeWhere((id) => selfRej.contains(id));
      // Fallback se regole disattivate / risoluzione dipendente fallita (es. personale.user_id = id_uuid).
      if (rejIds.isEmpty) {
        final emp = await NotificationSender.employeeUserIdForBooking(
          row.id,
          row.typeLabel.toLowerCase(),
        );
        if (emp != null && !selfRej.contains(emp)) rejIds.add(emp);
        final req = row.requestedByUserId;
        if (req != null && !selfRej.contains(req)) rejIds.add(req);
        rejIds = rejIds.toSet().toList();
      } else {
        final req = row.requestedByUserId;
        if (req != null &&
            !selfRej.contains(req) &&
            !rejIds.contains(req)) {
          rejIds = [...rejIds, req];
        }
      }
      if (rejIds.isNotEmpty) {
        await NotificationSender.sendToUserIds(
          userIds: rejIds,
          bookingId: row.id,
          action: 'dt_rejected',
          title: 'Richiesta ${row.typeLabel} rifiutata',
          message: reason.trim().isEmpty
              ? 'La tua richiesta ${row.typeLabel} è stata rifiutata dal DT.'
              : 'Rifiutata dal DT: ${reason.trim()}',
        );
      }

      await _loadRows();
      if (rejIds.isEmpty) {
        _toast(
          'Richiesta rifiutata, ma nessun destinatario per la notifica '
          '(controlla collegamento personale↔utente e regole notifiche).',
          error: true,
        );
      } else {
        _toast('Richiesta rifiutata. Notifiche inviate a dipendente / richiedente (se applicabile).');
      }
    } catch (e) {
      _toast('Errore rifiuto: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final out = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Motivo rifiuto (opzionale)'),
        content: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Scrivi un motivo…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Rifiuta')),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  String _fmtDate(String iso) {
    return formatDateDdMmYyyy(iso);
  }

  @override
  Widget build(BuildContext context) {
    final isMobileLayout = useMobileUi(context);
    final ultraCompact = cronosIsUltraCompact(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        titleSpacing: 0,
        title: ResponsiveAppBarTitle(
          title: 'DT — Richieste da approvare (${widget.fullName})',
          desktopLogoSize: 40,
        ),
        actions: [
          IconButton(
            tooltip: 'Ricarica',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _bootstrap,
          ),
        ],
      )),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_rows.isEmpty)
            const Center(child: Text('Nessuna richiesta in attesa.'))
          else
            ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = _rows[i];
                final commId = _commessaSelection[r.id] ?? r.commessaId;
                final pers = _personale[r.personaleId ?? ''] ?? (r.personaleId ?? '—');
                final req = _requesters[(r.requestedByUserId ?? '').toString()] ?? '—';
                final ritornoDest = (r.ritornoDestLabel ?? '').toString().trim();
                final ritornoDiverso =
                    ritornoDest.isNotEmpty && ritornoDest.trim() != r.fromLabel.trim();
                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: isMobileLayout
                              ? [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${r.typeLabel}: ${r.fromLabel} → ${r.toLabel}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_fmtDate(r.dataIso)}${(r.orario != null && r.orario!.isNotEmpty) ? ' · ${r.orario!}' : ''}',
                                        ),
                                      ],
                                    ),
                                  ),
                                ]
                              : [
                                  Expanded(
                                    child: Text(
                                      '${r.typeLabel}: ${r.fromLabel} → ${r.toLabel}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_fmtDate(r.dataIso)),
                                  if (r.orario != null && r.orario!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(r.orario!),
                                  ],
                                ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            Chip(label: Text('Personale: $pers')),
                            SizedBox(
                              width: isMobileLayout ? double.infinity : 340,
                              child: DropdownSearch<String>(
                                items: _commesse.keys.toList(),
                                selectedItem: (commId != null &&
                                        commId.trim().isNotEmpty &&
                                        _commesse.containsKey(commId))
                                    ? commId
                                    : null,
                                itemAsString: (id) => _commesse[id] ?? id,
                                popupProps: const PopupProps.menu(
                                  showSearchBox: true,
                                  fit: FlexFit.loose,
                                ),
                                clearButtonProps:
                                    const ClearButtonProps(isVisible: true),
                                dropdownDecoratorProps:
                                    const DropDownDecoratorProps(
                                  dropdownSearchDecoration: InputDecoration(
                                    labelText:
                                        'Commessa (obbligatoria per confermare)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() {
                                          if (v == null || v.trim().isEmpty) {
                                            _commessaSelection.remove(r.id);
                                          } else {
                                            _commessaSelection[r.id] = v;
                                          }
                                        }),
                              ),
                            ),
                            if (ritornoDiverso)
                              Chip(label: Text('Destinazione ritorno: $ritornoDest')),
                            Chip(label: Text('Richiedente: $req')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (ultraCompact)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NeoAsyncFilledButton(
                                onTap: _busy ? null : () => _approve(r),
                                child: const Text('Conferma'),
                              ),
                              const SizedBox(height: 8),
                              NeoButton(
                                onTap: _busy ? null : () => _reject(r),
                                child: const Text('Rifiuta'),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: NeoAsyncFilledButton(
                                  onTap: _busy ? null : () => _approve(r),
                                  child: const Text('Conferma'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: NeoButton(
                                  onTap: _busy ? null : () => _reject(r),
                                  child: const Text('Rifiuta'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
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
}

class _ReqRow {
  final int id;
  final String table; // bookings_treno / bookings_aereo
  final String typeLabel; // Treno / Aereo
  final String dataIso;
  final String? orario;
  final String fromLabel;
  final String toLabel;
  final String? commessaId;
  final String? personaleId;
  final int? requestedByUserId;
  final String? ritornoDestLabel; // destinazione ritorno scelta (arrivo ritorno)

  _ReqRow({
    required this.id,
    required this.table,
    required this.typeLabel,
    required this.dataIso,
    required this.orario,
    required this.fromLabel,
    required this.toLabel,
    required this.commessaId,
    required this.personaleId,
    required this.requestedByUserId,
    required this.ritornoDestLabel,
  });

  factory _ReqRow.fromTreno(Map<String, dynamic> r) => _ReqRow(
        id: int.tryParse((r['id'] ?? '').toString()) ?? 0,
        table: 'bookings_treno',
        typeLabel: 'Treno',
        dataIso: (r['data'] ?? '').toString(),
        orario: (r['orario'] ?? '').toString(),
        fromLabel: (r['stazione_partenza'] ?? '').toString(),
        toLabel: (r['stazione_arrivo'] ?? '').toString(),
        commessaId: (r['commessa_id'] ?? '').toString(),
        personaleId: (r['personale_id'] ?? '').toString(),
        requestedByUserId: r['requested_by_user_id'] is int
            ? (r['requested_by_user_id'] as int)
            : int.tryParse((r['requested_by_user_id'] ?? '').toString()),
        ritornoDestLabel: (r['stazione_arrivo_ritorno'] ?? '').toString(),
      );

  factory _ReqRow.fromAereo(Map<String, dynamic> r) => _ReqRow(
        id: int.tryParse((r['id'] ?? '').toString()) ?? 0,
        table: 'bookings_aereo',
        typeLabel: 'Aereo',
        dataIso: (r['data'] ?? '').toString(),
        orario: (r['orario'] ?? '').toString(),
        fromLabel: (r['aeroporto_partenza'] ?? '').toString(),
        toLabel: (r['aeroporto_arrivo'] ?? '').toString(),
        commessaId: (r['commessa_id'] ?? '').toString(),
        personaleId: (r['personale_id'] ?? '').toString(),
        requestedByUserId: r['requested_by_user_id'] is int
            ? (r['requested_by_user_id'] as int)
            : int.tryParse((r['requested_by_user_id'] ?? '').toString()),
        ritornoDestLabel: (r['aeroporto_arrivo_ritorno'] ?? '').toString(),
      );
}

