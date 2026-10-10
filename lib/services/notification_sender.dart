// lib/services/notification_sender.dart

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';
import 'notification_routing_rules_service.dart';

class NotificationSender {
  NotificationSender._();

  static Map<String, Map<String, dynamic>> _rulesCache = {};
  static DateTime? _rulesLoadedAt;
  static final Map<String, bool> _skipAdminCreateCache = {};

  /// Risolve un identificatore (id int, id_uuid uuid string, auth_id string)
  /// in `users.id` (int) così possiamo inviare notifiche via user_ids.
  static String? _trimActorUuid(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static Future<int?> resolveUserId(Object identifier) async {
    final supa = Supabase.instance.client;

    if (identifier is int) return identifier;
    final raw = identifier.toString().trim();
    if (raw.isEmpty) return null;

    final parsedInt = int.tryParse(raw);
    if (parsedInt != null) {
      // Se è già un id users (int) o comunque numerico, prova a considerarlo.
      final u = await supa.from('users').select('id').eq('id', parsedInt).maybeSingle();
      final id = u?['id'];
      return id is int ? id : null;
    }

    // Prova id_uuid
    final u1 = await supa
        .from('users')
        .select('id')
        .eq('id_uuid', raw)
        .maybeSingle();
    final id1 = u1?['id'];
    if (id1 is int) return id1;

    // Prova auth_id
    final u2 = await supa
        .from('users')
        .select('id')
        .eq('auth_id', raw)
        .maybeSingle();
    final id2 = u2?['id'];
    if (id2 is int) return id2;

    return null;
  }

  /// Invia una notifica direttamente a una lista di `users.id` (senza logica di routing).
  static Future<Map<String, dynamic>?> sendToUserIds({
    required List<int> userIds,
    required int bookingId,
    required String action,
    required String title,
    String? message,
    String? actorIdUuid,
    String? bookingType,
  }) async {
    if (userIds.isEmpty) return null;
    return _send(
      userIds,
      bookingId,
      action.toLowerCase().trim(),
      title,
      message,
      actorIdUuid: actorIdUuid,
      bookingType: bookingType,
      forceAllRecipients: true,
    );
  }

  /// Id numerico stabile per edge function / notifiche (assenze usano `id_uuid`).
  static int assenzaNotificationBookingId(String idUuid) {
    final clean = idUuid.replaceAll('-', '').toLowerCase();
    if (clean.length >= 8) {
      return int.parse(clean.substring(0, 8), radix: 16) & 0x7FFFFFFF;
    }
    return idUuid.hashCode.abs() & 0x7FFFFFFF;
  }

  static const String _assenzaBookingType = 'assenze';

  /// Audit legale A2: nelle notifiche (anche push) non indicare il tipo di
  /// assenza quando rivela dati sulla salute (malattia, visite, infortunio,
  /// L.104, maternità…). Il dettaglio resta visibile solo in app.
  static String pushSafeTipoLabel(String tipoLabel) {
    final t = tipoLabel.toLowerCase();
    const sensitive = [
      'malatt', 'visit', 'infortun', '104', 'matern', 'patern',
      'gravid', 'salute', 'sanit', 'ricover', 'terap', 'donazione',
    ];
    for (final k in sensitive) {
      if (t.contains(k)) return 'di assenza';
    }
    return tipoLabel;
  }

  /// Dipendente invia richiesta ferie/permessi → DT selezionato.
  static Future<void> notifyAssenzaSubmittedToDt({
    required String assenzaIdUuid,
    required String assignedDtUserUuid,
    int? requesterUserId,
    required String dipendenteNome,
    required String tipoLabel,
    required String periodoLabel,
  }) async {
    final bookingId = assenzaNotificationBookingId(assenzaIdUuid);
    final dtId = await resolveUserId(assignedDtUserUuid);
    if (dtId == null) return;

    final targets = await targetsForRule(
      'assenza_request_to_dt',
      fallback: const ['selected_dt'],
    );
    if (targets.isEmpty) return;

    var recipientIds = await resolveRecipientsFromTargets(
      targets: targets,
      requesterUserId: requesterUserId,
      selectedDtUuid: assignedDtUserUuid,
      bookingId: bookingId,
      bookingType: _assenzaBookingType,
    );
    if (recipientIds.isEmpty) recipientIds = [dtId];
    if (!recipientIds.contains(dtId)) recipientIds = [...recipientIds, dtId];

    final nome = dipendenteNome.trim().isEmpty ? 'Un dipendente' : dipendenteNome.trim();
    await sendToUserIds(
      userIds: recipientIds,
      bookingId: bookingId,
      action: 'assenza_request_dt',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)}',
      message: '$nome ha inviato una richiesta ${pushSafeTipoLabel(tipoLabel)} ($periodoLabel). Attende la tua valutazione.',
      bookingType: _assenzaBookingType,
    );
  }

  /// DT/assistente DT inserisce richiesta ferie/permessi a nome del dipendente.
  static Future<void> notifyAssenzaRegisteredByDtToEmployee({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String tipoLabel,
    String? periodoLabel,
  }) async {
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    await _notifyAssenzaToRequester(
      assenzaIdUuid: assenzaIdUuid,
      requesterUserId: requesterUserId,
      ruleKey: 'assenza_registered_by_dt_to_employee',
      fallbackTargets: const ['requester'],
      action: 'assenza_registered_by_dt',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} registrata',
      message:
          'Il DT ha registrato una richiesta ${pushSafeTipoLabel(tipoLabel)} a tuo nome. '
          'È in attesa di approvazione amministrativa.$extra',
    );
  }

  static Future<void> _notifyAssenzaToRequester({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String ruleKey,
    required List<String> fallbackTargets,
    required String action,
    required String title,
    required String message,
  }) async {
    if (requesterUserId == null) return;

    final targets = await targetsForRule(ruleKey, fallback: fallbackTargets);
    if (targets.isEmpty) return;

    final bookingId = assenzaNotificationBookingId(assenzaIdUuid);
    var recipientIds = await resolveRecipientsFromTargets(
      targets: targets,
      requesterUserId: requesterUserId,
      bookingId: bookingId,
      bookingType: _assenzaBookingType,
    );
    if (recipientIds.isEmpty) recipientIds = [requesterUserId];
    if (!recipientIds.contains(requesterUserId)) {
      recipientIds = [...recipientIds, requesterUserId];
    }

    await sendToUserIds(
      userIds: recipientIds,
      bookingId: bookingId,
      action: action,
      title: title,
      message: message,
      bookingType: _assenzaBookingType,
    );
  }

  static Future<void> notifyAssenzaDtApprovedToRequester({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String tipoLabel,
    String? periodoLabel,
  }) async {
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    await _notifyAssenzaToRequester(
      assenzaIdUuid: assenzaIdUuid,
      requesterUserId: requesterUserId,
      ruleKey: 'assenza_dt_approved_to_requester',
      fallbackTargets: const ['requester'],
      action: 'assenza_dt_approved',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} approvata dal DT',
      message: 'La tua richiesta ${pushSafeTipoLabel(tipoLabel)} è stata approvata dal DT ed è in attesa di conferma admin.$extra',
    );
  }

  /// DT approva ferie/permessi → admin deve confermare o rifiutare.
  static Future<void> notifyAssenzaDtApprovedToAdmin({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String dipendenteNome,
    required String tipoLabel,
    String? periodoLabel,
    int? actorUserId,
  }) async {
    final targets = await targetsForRule(
      'assenza_dt_approved_to_admin',
      fallback: const [
        'role:admin',
        'role:admin_generale',
        'role:admin_pernottamenti',
        'role:admin_trenoaereo',
        'role:admin_dpi',
        'role:admin_formazione',
      ],
    );
    if (targets.isEmpty) return;

    final bookingId = assenzaNotificationBookingId(assenzaIdUuid);
    var recipientIds = await resolveRecipientsFromTargets(
      targets: targets,
      requesterUserId: requesterUserId,
      bookingId: bookingId,
      bookingType: _assenzaBookingType,
      actorUserId: actorUserId,
    );
    if (actorUserId != null) {
      recipientIds = recipientIds.where((id) => id != actorUserId).toList();
    }
    if (recipientIds.isEmpty) return;

    final nome = dipendenteNome.trim().isEmpty ? 'Un dipendente' : dipendenteNome.trim();
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    await sendToUserIds(
      userIds: recipientIds,
      bookingId: bookingId,
      action: 'assenza_dt_approved',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} da approvare (admin)',
      message:
          '$nome: richiesta ${pushSafeTipoLabel(tipoLabel)} approvata dal DT$extra. Conferma o rifiuta come amministrazione.',
      bookingType: _assenzaBookingType,
    );
  }

  static Future<void> notifyAssenzaDtRejectedToRequester({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String tipoLabel,
    String? comment,
    String? periodoLabel,
  }) async {
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    final note = (comment ?? '').trim();
    final notePart = note.isEmpty ? '' : ' Motivo: $note';
    await _notifyAssenzaToRequester(
      assenzaIdUuid: assenzaIdUuid,
      requesterUserId: requesterUserId,
      ruleKey: 'assenza_dt_rejected_to_requester',
      fallbackTargets: const ['requester'],
      action: 'assenza_dt_rejected',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} rifiutata dal DT',
      message: 'La tua richiesta ${pushSafeTipoLabel(tipoLabel)} è stata rifiutata dal DT.$extra$notePart',
    );
  }

  static Future<void> notifyAssenzaAdminApprovedToRequester({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String tipoLabel,
    String? periodoLabel,
  }) async {
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    await _notifyAssenzaToRequester(
      assenzaIdUuid: assenzaIdUuid,
      requesterUserId: requesterUserId,
      ruleKey: 'assenza_admin_approved_to_requester',
      fallbackTargets: const ['requester'],
      action: 'assenza_admin_approved',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} confermata',
      message: 'La tua richiesta ${pushSafeTipoLabel(tipoLabel)} è stata approvata dall\'amministrazione.$extra',
    );
  }

  static Future<void> notifyAssenzaAdminRejectedToRequester({
    required String assenzaIdUuid,
    required int? requesterUserId,
    required String tipoLabel,
    String? comment,
    String? periodoLabel,
  }) async {
    final periodo = (periodoLabel ?? '').trim();
    final extra = periodo.isEmpty ? '' : ' ($periodo)';
    final note = (comment ?? '').trim();
    final notePart = note.isEmpty ? '' : ' Motivo: $note';
    await _notifyAssenzaToRequester(
      assenzaIdUuid: assenzaIdUuid,
      requesterUserId: requesterUserId,
      ruleKey: 'assenza_admin_rejected_to_requester',
      fallbackTargets: const ['requester'],
      action: 'assenza_admin_rejected',
      title: 'Richiesta ${pushSafeTipoLabel(tipoLabel)} rifiutata',
      message: 'La tua richiesta ${pushSafeTipoLabel(tipoLabel)} è stata rifiutata dall\'amministrazione.$extra$notePart',
    );
  }

  /// Notifica formazione: modifiche admin su corsi dipendente.
  /// Regole: `admin_formazione_update_notify` / `admin_formazione_delete_notify`.
  static Future<void> notifyEmployeeFormazioneChange({
    required String personaleId,
    required int formazioneId,
    required String action,
    required String title,
    String? message,
  }) async {
    final supa = Supabase.instance.client;
    final sess = supa.auth.currentSession;
    if (sess == null) return;

    final actorRow = await supa
        .from('users')
        .select('id, id_uuid')
        .eq('auth_id', sess.user.id)
        .maybeSingle();
    final int? actorUserId = actorRow?['id'] as int?;
    final String? actorUuid = _trimActorUuid(actorRow?['id_uuid']);
    if (actorUserId == null) return;

    final p = await supa
        .from('personale')
        .select('user_id')
        .eq('id_uuid', personaleId)
        .maybeSingle();
    final userLink = (p?['user_id'] ?? '').toString().trim();
    if (userLink.isEmpty) return;
    final employeeUserId = await resolveUserId(userLink);
    if (employeeUserId == null) return;

    final act = action.toLowerCase().trim();
    final ruleKey = act == 'delete'
        ? 'admin_formazione_delete_notify'
        : 'admin_formazione_update_notify';
    final targets = await _targetsForRule(
      ruleKey: ruleKey,
      fallback: const ['requester'],
    );
    if (targets.isEmpty) return;

    final recipients = await resolveRecipientsFromTargets(
      targets: targets,
      requesterUserId: employeeUserId,
      actorUserId: actorUserId,
    );
    final filtered = recipients.where((id) => id != actorUserId).toSet().toList();
    if (filtered.isEmpty) return;

    await _send(
      filtered,
      formazioneId,
      act,
      title,
      message,
      actorIdUuid: actorUuid,
    );
  }

  /// Notifica i referenti carico/scarico di un trasferimento MDO, se hanno account app.
  static Future<void> notifyMdoTrasferimentoReferenti({
    required String action,
    required List<String> mezziLabels,
    required String commessaOrigine,
    required String commessaDestinazione,
    required String periodoLabel,
    String? trasportatore,
    String? referenteCaricoPersonaleUuid,
    String? referenteCaricoNome,
    String? referenteScaricoPersonaleUuid,
    String? referenteScaricoNome,
    String? luogoCarico,
    String? luogoScarico,
  }) async {
    final supa = Supabase.instance.client;
    final sess = supa.auth.currentSession;
    if (sess == null) return;

    final actorRow = await supa
        .from('users')
        .select('id, id_uuid')
        .eq('auth_id', sess.user.id)
        .maybeSingle();
    final int? actorUserId = actorRow?['id'] as int?;
    final String? actorUuid = _trimActorUuid(actorRow?['id_uuid']);

    final caricoUserId = await _resolveUserIdFromPersonale(
      personaleUuid: referenteCaricoPersonaleUuid,
      fullName: referenteCaricoNome,
    );
    final scaricoUserId = await _resolveUserIdFromPersonale(
      personaleUuid: referenteScaricoPersonaleUuid,
      fullName: referenteScaricoNome,
    );

    final mezzi = mezziLabels
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final mezziTxt = mezzi.isEmpty
        ? 'mezzo MDO'
        : (mezzi.length == 1
            ? mezzi.first
            : '${mezzi.length} mezzi (${mezzi.take(3).join(', ')}'
                '${mezzi.length > 3 ? '…' : ''})');
    final da = commessaOrigine.trim().isEmpty
        ? 'Senza commessa'
        : commessaOrigine.trim();
    final a = commessaDestinazione.trim();
    final periodo = periodoLabel.trim();
    final transport = (trasportatore ?? '').trim();
    final lc = (luogoCarico ?? '').trim();
    final ls = (luogoScarico ?? '').trim();

    String extras() {
      final parts = <String>[
        if (periodo.isNotEmpty) 'Periodo: $periodo',
        if (transport.isNotEmpty) 'Trasportatore: $transport',
        if (lc.isNotEmpty) 'Luogo carico: $lc',
        if (ls.isNotEmpty) 'Luogo scarico: $ls',
      ];
      return parts.isEmpty ? '' : ' ${parts.join(' · ')}.';
    }

    final isUpdate = action.toLowerCase().trim() == 'update';
    final verb = isUpdate ? 'aggiornato' : 'avviato';
    final bookingId =
        DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;

    Future<void> sendOne({
      required int userId,
      required String ruolo,
    }) async {
      if (actorUserId != null && userId == actorUserId) return;
      await sendToUserIds(
        userIds: [userId],
        bookingId: bookingId,
        action: isUpdate ? 'mdo_trasferimento_update' : 'mdo_trasferimento_create',
        title: isUpdate
            ? 'Trasferimento MDO aggiornato'
            : 'Nuovo trasferimento MDO',
        message:
            'Sei indicato come referente $ruolo per il trasferimento $verb '
            'di $mezziTxt: $da → $a.${extras()}',
        actorIdUuid: actorUuid,
        bookingType: 'mdo_trasferimento',
      );
    }

    if (caricoUserId != null &&
        scaricoUserId != null &&
        caricoUserId == scaricoUserId) {
      await sendOne(userId: caricoUserId, ruolo: 'carico e scarico');
      return;
    }
    if (caricoUserId != null) {
      await sendOne(userId: caricoUserId, ruolo: 'carico');
    }
    if (scaricoUserId != null) {
      await sendOne(userId: scaricoUserId, ruolo: 'scarico');
    }
  }

  /// Risolve `users.id` da `personale.id_uuid` o, in alternativa, da nome esatto.
  static Future<int?> _resolveUserIdFromPersonale({
    String? personaleUuid,
    String? fullName,
  }) async {
    final supa = Supabase.instance.client;
    final uuid = (personaleUuid ?? '').trim();
    if (uuid.isNotEmpty) {
      final p = await supa
          .from('personale')
          .select('user_id')
          .eq('id_uuid', uuid)
          .maybeSingle();
      final link = (p?['user_id'] ?? '').toString().trim();
      if (link.isNotEmpty) return resolveUserId(link);
    }

    final name = (fullName ?? '').trim();
    if (name.isEmpty) return null;

    final rows = await supa
        .from('personale')
        .select('user_id, full_name')
        .eq('active', true)
        .ilike('full_name', name)
        .limit(5);
    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final n = (m['full_name'] ?? '').toString().trim().toLowerCase();
          return n == name.toLowerCase();
        })
        .toList(growable: false);
    if (list.isEmpty) return null;
    // Se più omonimi, notifica solo se uno solo ha account.
    final withAccount = <int>[];
    for (final m in list) {
      final link = (m['user_id'] ?? '').toString().trim();
      if (link.isEmpty) continue;
      final id = await resolveUserId(link);
      if (id != null) withAccount.add(id);
    }
    if (withAccount.length == 1) return withAccount.first;
    return null;
  }

  /// Legacy helper: 2=pernottamenti, 3=treni/aerei.
  /// admin_generale non viene mai incluso nei destinatari.
  static Future<List<int>> getAdminIdsByType(int adminType) async {
    if (adminType == 2) {
      return _getAdminIdsByRoles(const ['admin_pernottamenti']);
    }
    if (adminType == 3) {
      return _getAdminIdsByRoles(const ['admin_trenoaereo']);
    }
    return <int>[];
  }

  /// [bookingType] per action 'create': 'treno' | 'aereo' | 'pernottamento'.
  /// Notifica: pernottamento -> admin_pernottamenti; treno/aereo -> admin_trenoaereo.
  /// admin_generale non riceve notifiche di workflow.
  ///
  /// Destinatari da **Regole notifiche**: `admin_treno_aereo_update_notify` /
  /// `admin_treno_aereo_delete_notify` (token `dt_prenotazione`,
  /// `assistenti_dt_prenotazione`, `dipendente`, ecc.).
  static Future<void> notifyTrenoAereoAdminChange({
    required String bookingType,
    required int bookingId,
    required String action,
    required String title,
    String? message,
    required String dtUserUuid,
  }) async {
    final supa = Supabase.instance.client;
    final sess = supa.auth.currentSession;
    if (sess == null) {
      // ignore: avoid_print
      print('>>> NotificationSender: NESSUNA SESSIONE, skip notifyTrenoAereoAdminChange');
      return;
    }

    final actorRow = await supa
        .from('users')
        .select('id, role, id_uuid')
        .eq('auth_id', sess.user.id)
        .maybeSingle();
    final int? actorUserId = actorRow?['id'] as int?;
    if (actorUserId == null) return;
    final actorUuid = _trimActorUuid(actorRow?['id_uuid']);

    final act = action.toLowerCase().trim();
    final ruleKey = act == 'delete'
        ? 'admin_treno_aereo_delete_notify'
        : 'admin_treno_aereo_update_notify';
    final targets = await _targetsForRule(
      ruleKey: ruleKey,
      fallback: const [
        'dt_prenotazione',
        'assistenti_dt_prenotazione',
        'dipendente',
      ],
    );
    if (targets.isEmpty) {
      // ignore: avoid_print
      print('>>> notifyTrenoAereoAdminChange: regola $ruleKey disattiva o senza target');
      return;
    }

    final dtUuid = dtUserUuid.trim();
    final dtUid = dtUuid.isEmpty ? null : await resolveUserId(dtUuid);
    final bt = bookingType.toLowerCase().trim();
    final bookingResolvedType = bt == 'treno' || bt == 'aereo' ? bt : null;

    final ids = await resolveRecipientsFromTargets(
      targets: targets,
      bookingId: bookingId,
      bookingType: bookingResolvedType,
      actorUserId: actorUserId,
      bookingDtUuid: dtUuid.isEmpty ? null : dtUuid,
      bookingDtUserId: dtUid,
    );

    final filtered = ids.where((id) => id != actorUserId).toList();

    if (filtered.isEmpty) {
      // ignore: avoid_print
      print('>>> notifyTrenoAereoAdminChange: nessun destinatario (bookingId=$bookingId)');
      return;
    }

    await _send(
      filtered,
      bookingId,
      act,
      title,
      message,
      actorIdUuid: actorUuid,
      bookingType: bookingResolvedType,
    );
  }

  /// Destinatari effettivi (`users.id`) per il ramo admin di [notifyUserForBooking] (update/delete/approve/…),
  /// senza inviare. Allineato a regole `admin_update_notify` / `admin_delete_notify`.
  static Future<List<int>> recipientUserIdsForAdminBookingAction({
    required Object dtUserId,
    required int bookingId,
    required String action,
    String? bookingType,
  }) async {
    final supa = Supabase.instance.client;
    final sess = supa.auth.currentSession;
    if (sess == null) return [];

    int? requesterUserId = _toInt(dtUserId);
    if (requesterUserId == null) {
      try {
        final String raw = dtUserId.toString();
        Map<String, dynamic>? u;
        u = await supa
            .from('users')
            .select('id')
            .eq('id_uuid', raw)
            .maybeSingle();
        u ??= await supa
            .from('users')
            .select('id')
            .eq('auth_id', raw)
            .maybeSingle();
        requesterUserId = u?['id'] as int?;
      } catch (_) {}
    }
    if (requesterUserId == null) return [];

    final row = await supa
        .from('users')
        .select('id, role')
        .eq('auth_id', sess.user.id)
        .maybeSingle();
    final int? actorUserId = row?['id'];
    final String actorRole =
        (row?['role'] ?? '').toString().toLowerCase().trim();
    if (actorUserId == null) return [];

    final act = action.toLowerCase().trim();
    final isAdminWorkflowAction = act == 'update' ||
        act == 'delete' ||
        act == 'approve' ||
        act == 'approved' ||
        act == 'confirm' ||
        act == 'confirmed' ||
        act == 'conferma';
    if (!_isAdminRole(actorRole) || !isAdminWorkflowAction) return [];

    if (actorUserId == requesterUserId) return [];

    final normalizedType = (bookingType ?? '').toLowerCase().trim();
    final isPernottamenti =
        normalizedType == 'pernottamento' || normalizedType == 'pernottamenti';
    final ruleKey = act == 'delete'
        ? (isPernottamenti
            ? 'admin_pernottamenti_delete_notify'
            : 'admin_delete_notify')
        : (isPernottamenti
            ? 'admin_pernottamenti_update_notify'
            : 'admin_update_notify');
    final targets = await _targetsForRule(
      ruleKey: ruleKey,
      fallback: const ['requester', 'dipendente'],
    );
    final recipients = await resolveRecipientsFromTargets(
      targets: targets,
      requesterUserId: requesterUserId,
      bookingId: bookingId,
      bookingType: bookingType,
    );
    return recipients;
  }

  static Future<void> notifyUserForBooking({
    required Object dtUserId,
    required Object bookingId,
    required String action,
    required String title,
    String? message,
    String? bookingType,
  }) async {

    final supa = Supabase.instance.client;
    final sess = supa.auth.currentSession;
    if (sess == null) {
      // ignore: avoid_print
      print('>>> NotificationSender: NESSUNA SESSIONE, skip notifyUserForBooking');
      return;
    }

    final int? bookingIdInt = _toInt(bookingId);
    if (bookingIdInt == null) {
      // ignore: avoid_print
      print('>>> NotificationSender: bookingId NON valido ($bookingId), skip');
      return;
    }

    int? requesterUserId = _toInt(dtUserId);
    if (requesterUserId == null) {
      // dtUserId può essere un UUID o auth_id: provo a risolvere in users.id
      try {
        final String raw = dtUserId.toString();
        Map<String, dynamic>? u;

        u = await supa
            .from('users')
            .select('id')
            .eq('id_uuid', raw)
            .maybeSingle();
        u ??= await supa
            .from('users')
            .select('id')
            .eq('auth_id', raw)
            .maybeSingle();

        final int? resolved = u?['id'] as int?;
        requesterUserId = resolved;
        // ignore: avoid_print
        print(
            '>>> NotificationSender: risolto dtUserId=$dtUserId in user_id=$requesterUserId');
      } catch (e) {
        // ignore: avoid_print
        print('>>> NotificationSender: errore risoluzione dtUserId=$dtUserId -> $e');
      }
    }

    if (requesterUserId == null) {
      // ignore: avoid_print
      print(
          '>>> NotificationSender: requesterUserId NULL (dtUserId=$dtUserId), skip');
      return;
    }

    final row = await supa
        .from('users')
        .select('id, role, id_uuid')
        .eq('auth_id', sess.user.id)
        .maybeSingle();

    final int? actorUserId = row?['id'];
    final String actorRole =
        (row?['role'] ?? '').toString().toLowerCase().trim();
    final String? actorUuid = _trimActorUuid(row?['id_uuid']);

    if (actorUserId == null) return;

    final act = action.toLowerCase().trim();

    // 1) DT/Assistente DT CREA → 1=no notifiche, 2=pernottamenti, 3=treni/aerei.
    // Notifica solo 2 o 3.
    // In alcune parti dell'app il creator di "create" è `dt` (non `user`), quindi accettiamo entrambi.
    if ((actorRole == "dt" ||
            actorRole == "user" ||
            actorRole == "assistente_dt") &&
        act == "create") {
      // ✅ Nuovo workflow: se la prenotazione treno/aereo è "INVIATA_AL_DT"
      // NON dobbiamo notificare gli admin, anche se qualcuno invoca ancora "create".
      // Non dipendiamo da bookingType: controlliamo entrambe le tabelle.
      try {
        Map<String, dynamic>? bt;
        Map<String, dynamic>? ba;
        try {
          bt = await supa
              .from('bookings_treno')
              .select('workflow_status')
              .eq('id', bookingIdInt)
              .maybeSingle();
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        }
        try {
          ba = await supa
              .from('bookings_aereo')
              .select('workflow_status')
              .eq('id', bookingIdInt)
              .maybeSingle();
        } on PostgrestException catch (e) {
          if (e.code != '42703') rethrow;
        }

        final ws = ((bt?['workflow_status'] ?? ba?['workflow_status']) ?? '')
            .toString()
            .toUpperCase()
            .trim();
        if (ws.isNotEmpty && await _shouldSkipAdminCreateForWorkflowStatus(ws)) {
          // ignore: avoid_print
          print(
              '>>> NotificationSender: skip admin notify per workflow_status=$ws (id=$bookingIdInt) [Supabase controlled]');
          return;
        }
      } catch (_) {
        // se fallisce il controllo, continuiamo col comportamento vecchio
      }

      final bt0 = (bookingType ?? '').toLowerCase().trim();
      final isPern = bt0 == 'pernottamento' || bt0 == 'pernottamenti';

      final String ruleKey;
      final List<String> fallback;
      if (isPern) {
        ruleKey = 'create_to_admin_pernottamenti';
        fallback = _bookingTypeToTargetAdminRoles(bookingType)
            .map((r) => 'role:$r')
            .toList();
      } else {
        // Treno / aereo: DT vs Assistente DT vs altri
        if (actorRole == 'assistente_dt') {
          ruleKey = 'create_treno_aereo_by_assistente_dt';
          fallback = const ['role:admin_trenoaereo', 'requester'];
        } else if (actorRole == 'dt') {
          ruleKey = 'create_treno_aereo_by_dt';
          fallback = const ['role:admin_trenoaereo', 'dipendente'];
        } else {
          ruleKey = 'create_to_admin_trenoaereo';
          fallback = _bookingTypeToTargetAdminRoles(bookingType)
              .map((r) => 'role:$r')
              .toList();
        }
      }

      final targets = await _targetsForRule(
        ruleKey: ruleKey,
        fallback: fallback,
      );
      final ids = await resolveRecipientsFromTargets(
        targets: targets,
        requesterUserId: requesterUserId,
        selectedDtUuid: null,
        bookingId: bookingIdInt,
        bookingType: bookingType,
      );

      ids.removeWhere((id) => id == actorUserId);

      if (ids.isNotEmpty) {
        await _send(ids, bookingIdInt, act, title, message,
            actorIdUuid: actorUuid, bookingType: bookingType);
      } else {
        // ignore: avoid_print
        print(
            '>>> NotificationSender: nessun admin target trovato per bookingType=$bookingType');
      }
      return;
    }

    // 2) ADMIN UPDATE/DELETE/APPROVE/CONFIRM -> notifica al richiedente.
    final isAdminWorkflowAction = act == "update" ||
        act == "delete" ||
        act == "approve" ||
        act == "approved" ||
        act == "confirm" ||
        act == "confirmed" ||
        act == "conferma";
    if (_isAdminRole(actorRole) && isAdminWorkflowAction) {
      // Evita che l'admin riceva una notifica delle proprie azioni
      if (actorUserId == requesterUserId) {
        // ignore: avoid_print
        print(
            '>>> NotificationSender: admin stessa persona (actor=$actorUserId, target=$requesterUserId), niente notifica');
        return;
      }
      final recipients = await recipientUserIdsForAdminBookingAction(
        dtUserId: dtUserId,
        bookingId: bookingIdInt,
        action: act,
        bookingType: bookingType,
      );
      if (recipients.isNotEmpty) {
        await _send(recipients, bookingIdInt, act, title, message,
            actorIdUuid: actorUuid, bookingType: bookingType);
      }
      return;
    }

    // 3) Evita notifiche a se stessi per il caso generico
    // (es. admin che crea/modifica una propria prenotazione).
    if (actorUserId == requesterUserId) {
      // ignore: avoid_print
      print(
          '>>> NotificationSender: stessa persona (actor=$actorUserId, target=$requesterUserId), niente notifica');
      return;
    }

    await _send([requesterUserId], bookingIdInt, act, title, message,
        actorIdUuid: actorUuid, bookingType: bookingType);
  }

  static List<String> _bookingTypeToTargetAdminRoles(String? bookingType) {
    if (bookingType == null) {
      return const ['admin_pernottamenti', 'admin_trenoaereo'];
    }
    switch (bookingType.toLowerCase().trim()) {
      case 'treno':
      case 'aereo':
        return const ['admin_trenoaereo'];
      case 'pernottamento':
      case 'pernottamenti':
        return const ['admin_pernottamenti'];
      default:
        return const ['admin_pernottamenti', 'admin_trenoaereo'];
    }
  }

  static bool _isAdminRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'admin' ||
        r == 'admin_generale' ||
        r == 'admin_pernottamenti' ||
        r == 'admin_trenoaereo';
  }

  static Future<List<int>> _getAdminIdsByRoles(List<String> roles) async {
    if (roles.isEmpty) return <int>[];
    final supa = Supabase.instance.client;
    final orExpr = roles.map((r) => 'role.eq.$r').join(',');
    final res = await supa.from('users').select('id, role').or(orExpr);
    return (res as List)
        .map((e) => e['id'] as int?)
        .whereType<int>()
        .toList();
  }

  static Future<Map<String, dynamic>?> _send(
    List<int> userIds,
    int bookingId,
    String action,
    String title,
    String? message, {
    String? actorIdUuid,
    String? bookingType,
    bool forceAllRecipients = false,
  }) async {
    final supa = Supabase.instance.client;
    try {
      final res = await supa.functions.invoke(
        'admin-send-notification',
        body: {
          'user_ids': userIds,
          'booking_id': bookingId,
          'title': title,
          'action': action,
          if (bookingType != null && bookingType.trim().isNotEmpty)
            'booking_type': bookingType.trim().toLowerCase(),
          'message': ?message,
          if (actorIdUuid != null && actorIdUuid.isNotEmpty)
            'actor_id_uuid': actorIdUuid,
          if (forceAllRecipients) 'force_all_recipients': true,
        },
      );
      if (res.status >= 400) {
        throw Exception('admin-send-notification failed (${res.status}): ${res.data}');
      }
      // ignore: avoid_print
      print('>>> Edge Function admin-send-notification: status=${res.status} data=${res.data}');
      // Consegna locale immediata (popup/suono) senza attendere il poll periodico.
      unawaited(NotificationService().pollNow(catchUpMissed: true));
      final data = res.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('>>> Edge Function admin-send-notification ERRORE: $e');
      rethrow;
    }
  }

  static int? _toInt(Object v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static Future<List<String>> targetsForRule(
    String ruleKey, {
    required List<String> fallback,
  }) async {
    return _targetsForRule(ruleKey: ruleKey, fallback: fallback);
  }

  static Future<List<int>> resolveRecipientsFromTargets({
    required List<String> targets,
    int? requesterUserId,
    int? bookingId,
    String? bookingType,
    String? selectedDtUuid,
    int? actorUserId,
    String? bookingDtUuid,
    int? bookingDtUserId,
  }) async {
    final out = <int>{};
    final supa = Supabase.instance.client;

    for (final raw in targets) {
      final t = raw.toLowerCase().trim();
      if (t.isEmpty) continue;

      if (t == 'requester' && requesterUserId != null) {
        out.add(requesterUserId);
        continue;
      }
      if (t == 'actor' && actorUserId != null) {
        out.add(actorUserId);
        continue;
      }
      if (t == 'selected_dt' && selectedDtUuid != null && selectedDtUuid.isNotEmpty) {
        final dt = await supa
            .from('users')
            .select('id')
            .eq('id_uuid', selectedDtUuid)
            .maybeSingle();
        final id = dt?['id'] as int?;
        if (id != null) out.add(id);
        continue;
      }
      if (t == 'dt_prenotazione') {
        int? uid = bookingDtUserId;
        if (uid == null) {
          final bu = (bookingDtUuid ?? '').trim();
          if (bu.isNotEmpty) uid = await resolveUserId(bu);
        }
        if (uid != null) out.add(uid);
        continue;
      }
      if (t == 'assistenti_dt_prenotazione') {
        final u = (bookingDtUuid ?? '').trim();
        final assistants = await _assistantUserIdsForDt(supa, u, bookingDtUserId);
        out.addAll(assistants);
        continue;
      }
      if (t.startsWith('role:')) {
        final role = t.substring(5).trim();
        if (role.isEmpty) continue;
        final byRole = await supa.from('users').select('id').eq('role', role);
        for (final r in (byRole as List)) {
          final id = r['id'] as int?;
          if (id != null) out.add(id);
        }
        continue;
      }
      if (t == 'dipendente' && bookingId != null) {
        final empIds = await _resolveEmployeeRecipientIds(bookingId, bookingType);
        out.addAll(empIds);
      }
    }

    return out.toList();
  }

  static Future<List<int>> _assistantUserIdsForDt(
    SupabaseClient supa,
    String dtUuid,
    int? dtUid,
  ) async {
    final out = <int>{};
    if (dtUuid.isNotEmpty) {
      try {
        final res = await supa
            .from('assistente_dt_permissions')
            .select('assistant_user_id')
            .eq('grantor_dt_user_uuid', dtUuid);
        for (final p in (res as List)) {
          final v = p['assistant_user_id'];
          final i = v is int ? v : int.tryParse(v.toString());
          if (i != null) out.add(i);
        }
      } catch (_) {}
    }
    if (dtUid != null) {
      try {
        final res = await supa
            .from('assistente_dt_permissions')
            .select('assistant_user_id')
            .eq('grantor_dt_user_id', dtUid);
        for (final p in (res as List)) {
          final v = p['assistant_user_id'];
          final i = v is int ? v : int.tryParse(v.toString());
          if (i != null) out.add(i);
        }
      } catch (_) {}
    }
    return out.toList();
  }

  static Future<List<int>> _resolveEmployeeRecipientIds(
    int bookingId,
    String? bookingType,
  ) async {
    final supa = Supabase.instance.client;
    final out = <int>{};
    final type = (bookingType ?? '').toLowerCase().trim();

    Future<void> fromPersonaleUuidTable(
      String table,
      String personaleCol,
    ) async {
      final b = await supa
          .from(table)
          .select(personaleCol)
          .eq('id', bookingId)
          .maybeSingle();
      final personaleId = (b?[personaleCol] ?? '').toString().trim();
      if (personaleId.isEmpty) return;
      final p = await supa
          .from('personale')
          .select('user_id')
          .eq('id_uuid', personaleId)
          .maybeSingle();
      final link = (p?['user_id'] ?? '').toString().trim();
      if (link.isEmpty) return;
      // user_id può essere auth_id (Supabase) oppure users.id_uuid (vedi richiesta_treno bootstrap).
      final uid = await resolveUserId(link);
      if (uid != null) out.add(uid);
    }

    if (type == 'pernottamento' || type == 'pernottamenti') {
      await fromPersonaleUuidTable('bookings', 'personale_id');
      return out.toList();
    }
    if (type == 'treno') {
      await fromPersonaleUuidTable('bookings_treno', 'personale_id');
      return out.toList();
    }
    if (type == 'aereo') {
      await fromPersonaleUuidTable('bookings_aereo', 'personale_id');
      return out.toList();
    }

    // Fallback sicuro: se il tipo non è specificato, risolviamo SOLO se il bookingId
    // esiste in UNA sola tabella; se è ambiguo (stesso id in più tabelle), evitiamo
    // associazioni errate del dipendente.
    final matches = <String>[];
    final checks = <String, String>{
      'bookings_treno': 'personale_id',
      'bookings_aereo': 'personale_id',
      'bookings': 'personale_id',
    };
    for (final entry in checks.entries) {
      final row = await supa
          .from(entry.key)
          .select(entry.value)
          .eq('id', bookingId)
          .maybeSingle();
      final personaleId = (row?[entry.value] ?? '').toString().trim();
      if (personaleId.isNotEmpty) {
        matches.add(entry.key);
      }
    }
    if (matches.length == 1) {
      await fromPersonaleUuidTable(matches.first, 'personale_id');
    }
    return out.toList();
  }

  /// `users.id` del dipendente legato alla prenotazione (da `personale_id` → `personale.user_id`).
  static Future<int?> employeeUserIdForBooking(int bookingId, String bookingType) async {
    final ids = await _resolveEmployeeRecipientIds(bookingId, bookingType);
    return ids.isEmpty ? null : ids.first;
  }

  static Future<List<String>> _targetsForRule({
    required String ruleKey,
    required List<String> fallback,
  }) async {
    await _loadRulesIfNeeded();
    final rule = _rulesCache[ruleKey];
    if (rule == null) return fallback;
    final enabled = rule['enabled'] == true;
    if (!enabled) return <String>[];
    final t = rule['targets'];
    if (t is List) {
      final parsed = t.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (parsed.isNotEmpty) return parsed;
    }
    return fallback;
  }

  static Future<void> _loadRulesIfNeeded() async {
    final now = DateTime.now();
    if (_rulesLoadedAt != null &&
        now.difference(_rulesLoadedAt!) < const Duration(seconds: 20) &&
        _rulesCache.isNotEmpty) {
      return;
    }
    try {
      final rows = await NotificationRoutingRulesService.listRules();
      final map = <String, Map<String, dynamic>>{};
      for (final r in rows) {
        final key = (r['rule_key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        map[key] = r;
      }
      _rulesCache = map;
      _rulesLoadedAt = now;
    } catch (_) {}
  }

  /// Decide se per action=create su treno/aereo (workflow_status) va BLOCCATA la
  /// notifica agli admin. La lista è controllata da Supabase (no hardcode).
  static Future<bool> _shouldSkipAdminCreateForWorkflowStatus(
    String workflowStatus,
  ) async {
    final ws = workflowStatus.trim().toUpperCase();
    if (ws.isEmpty) return false;

    if (_skipAdminCreateCache.containsKey(ws)) {
      return _skipAdminCreateCache[ws]!;
    }

    final supa = Supabase.instance.client;
    try {
      final row = await supa
          .from('notification_admin_create_skip_workflow_statuses')
          .select('workflow_status')
          .eq('action_key', 'create')
          .eq('workflow_status', ws)
          .eq('enabled', true)
          .maybeSingle();

      final skip = row != null;
      _skipAdminCreateCache[ws] = skip;
      return skip;
    } catch (_) {
      _skipAdminCreateCache[ws] = false;
      return false;
    }
  }

  /// Etichette per messaggi utente (es. snackbar dopo invio richiesta).
  /// Preserva l’ordine di [userIds], ignora duplicati; elenco abbreviato se molti destinatari.
  static Future<String> recipientLabelsForUserIds(List<int> userIds) async {
    final seen = <int>{};
    final orderedIds = <int>[];
    for (final id in userIds) {
      if (id <= 0 || seen.contains(id)) continue;
      seen.add(id);
      orderedIds.add(id);
    }
    if (orderedIds.isEmpty) return 'nessun destinatario';

    final supa = Supabase.instance.client;
    final res = await supa
        .from('users')
        .select('id, full_name, username')
        .inFilter('id', orderedIds);
    final byId = <int, String>{};
    for (final row in (res as List)) {
      final idRaw = row['id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      if (id == null) continue;
      final fn = (row['full_name'] ?? '').toString().trim();
      final un = (row['username'] ?? '').toString().trim();
      byId[id] = fn.isNotEmpty ? fn : (un.isNotEmpty ? un : 'Utente #$id');
    }

    final labels = <String>[];
    for (final id in orderedIds) {
      labels.add(byId[id] ?? 'Utente #$id');
    }
    const maxShown = 4;
    if (labels.length <= maxShown) {
      return labels.join(', ');
    }
    final head = labels.take(maxShown).join(', ');
    final rest = labels.length - maxShown;
    return '$head e altri $rest';
  }
}
