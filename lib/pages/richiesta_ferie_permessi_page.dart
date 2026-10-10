import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/confirm_sound_service.dart';
import '../services/assenza_richiesta_pdf_export.dart';
import '../services/supabase_service.dart';
import '../utils/date_formatters.dart';
import '../utils/excel_export_helper.dart';
import '../utils/modify_feedback.dart';
import 'admin_dipendente_assenze_page.dart'
    show
        colorWorkflow,
        formatAssenzaPeriodoDetail,
        labelTipoAssenza,
        labelWorkflow;
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

const String _stApprovataAdmin = 'APPROVATA_ADMIN';

const List<String> _tipiRichiestaDipendente = <String>['FERIE', 'PERMESSO'];

class RichiestaFeriePermessiPage extends StatefulWidget {
  final int userId;
  final String fullName;

  const RichiestaFeriePermessiPage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<RichiestaFeriePermessiPage> createState() =>
      _RichiestaFeriePermessiPageState();
}

class _RichiestaFeriePermessiPageState extends State<RichiestaFeriePermessiPage> {
  bool _busy = false;
  bool _loadingRequests = false;
  String? _myPersonaleUuid;
  String? _myUserUuid;
  final List<Map<String, dynamic>> _myRequests = <Map<String, dynamic>>[];
  final Map<String, String> _usersByUuid = <String, String>{};
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _requestsSectionKey = GlobalKey();

  final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  bool _isUuid(String? v) => v != null && _uuidRe.hasMatch(v);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _loadUserLabelsForRequests(List<Map<String, dynamic>> rows) async {
    final uuids = <String>{};
    for (final r in rows) {
      final dt = _s(r['assigned_dt_user_uuid']);
      final admin = _s(r['admin_decision_by_user_uuid']);
      if (dt.isNotEmpty) uuids.add(dt);
      if (admin.isNotEmpty) uuids.add(admin);
    }
    if (uuids.isEmpty) return;
    final res = await SupabaseService.client
        .from('users')
        .select('id_uuid, full_name, username')
        .inFilter('id_uuid', uuids.toList());
    for (final e in (res as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final uuid = _s(m['id_uuid']);
      if (uuid.isEmpty) continue;
      final label = _s(m['full_name']).isNotEmpty
          ? _s(m['full_name'])
          : _s(m['username']);
      if (label.isNotEmpty) _usersByUuid[uuid] = label;
    }
  }

  String _userLabelByUuid(String? uuid) {
    final u = (uuid ?? '').trim();
    if (u.isEmpty) return '—';
    return _usersByUuid[u] ?? u;
  }

  String _decisionAuditLine({
    required String verb,
    required dynamic decidedAt,
    required String decidedByUuid,
  }) {
    final chi = _userLabelByUuid(decidedByUuid);
    if (chi == '—') return '';
    final quando = formatDateTimeItFromSupabase(decidedAt).trim();
    if (quando.isEmpty) return '$verb · da $chi';
    return '$verb il $quando · da $chi';
  }

  List<String> _workflowDecisionLines(Map<String, dynamic> r) {
    final st = _s(r['workflow_status']);
    final lines = <String>[];

    final dtUuid = _s(r['dt_decision_by_user_uuid']);
    if (dtUuid.isNotEmpty) {
      final dtVerb = st == 'RIFIUTATA_DT'
          ? 'Rifiutata dal DT'
          : 'Approvata dal DT';
      final dtLine = _decisionAuditLine(
        verb: dtVerb,
        decidedAt: r['dt_decision_at'],
        decidedByUuid: dtUuid,
      );
      if (dtLine.isNotEmpty) lines.add(dtLine);
    }

    final adminUuid = _s(r['admin_decision_by_user_uuid']);
    if (adminUuid.isNotEmpty) {
      final adminVerb = st == 'RIFIUTATA_ADMIN'
          ? 'Rifiutata da admin'
          : 'Autorizzata admin';
      final adminLine = _decisionAuditLine(
        verb: adminVerb,
        decidedAt: r['admin_decision_at'],
        decidedByUuid: adminUuid,
      );
      if (adminLine.isNotEmpty) lines.add(adminLine);
    }

    return lines;
  }

  String _approvatoreAdminLabelForRow(Map<String, dynamic> r) {
    final adminUuid = _s(r['admin_decision_by_user_uuid']);
    if (adminUuid.isNotEmpty) {
      final label = _usersByUuid[adminUuid];
      if (label != null && label.trim().isNotEmpty) return label.trim();
    }
    return 'Admin';
  }

  String _dipendenteLabelForRow(Map<String, dynamic> r) {
    final nome = _s(r['dipendente_nome']);
    if (nome.isNotEmpty) return nome;
    return widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : 'Dipendente';
  }

  Future<void> _exportRichiestaPdf(Map<String, dynamic> r) async {
    if (_s(r['workflow_status']) != _stApprovataAdmin) return;
    try {
      final bytes = await buildAssenzaRichiestaPdfBytes(
        row: r,
        dipendenteLabel: _dipendenteLabelForRow(r),
        dtLabel: _userLabelByUuid(_s(r['assigned_dt_user_uuid'])),
        approvatoreAdminLabel: _approvatoreAdminLabelForRow(r),
        adminComment: _s(r['admin_comment']),
      );
      final tipo = _s(r['tipo_assenza']).toLowerCase();
      final dal = formatDateDdMmYyyy(_s(r['data_dal'])).replaceAll('/', '-');
      final alRaw = _s(r['prolungato_fino_al']).isNotEmpty
          ? _s(r['prolungato_fino_al'])
          : _s(r['data_al']);
      final al = formatDateDdMmYyyy(alRaw).replaceAll('/', '-');
      final ok = await ExcelExportHelper.saveAndReveal(
        pageName: 'Richiesta_${tipo}_${dal}_$al',
        bytes: bytes,
        extension: 'pdf',
        openFile: true,
      );
      if (ok && mounted) {
        ModifyFeedback.success(context, 'PDF esportato correttamente.');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ModifyFeedback.error(
        context,
        msg.contains('convertire') || msg.contains('ExcelTS') || msg.contains('Gotenberg')
            ? msg
            : 'Errore export PDF da Excel: $msg',
      );
    }
  }

  Future<void> _loadMyRequests() async {
    if ((_myPersonaleUuid ?? '').isEmpty && (_myUserUuid ?? '').isEmpty) return;
    setState(() => _loadingRequests = true);
    try {
      var q = SupabaseService.client
          .from('dipendente_assenze')
          .select()
          .eq('active', true)
          .eq('segnalazione_admin', false)
          .inFilter('tipo_assenza', _tipiRichiestaDipendente);
      if ((_myPersonaleUuid ?? '').isNotEmpty) {
        q = q.eq('personale_id_uuid', _myPersonaleUuid!);
      } else {
        q = q.eq('requester_user_uuid', _myUserUuid!);
      }
      final res = await q.order('created_at', ascending: false);
      final list =
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _usersByUuid.clear();
      await _loadUserLabelsForRequests(list);
      if (!mounted) return;
      setState(() {
        _myRequests
          ..clear()
          ..addAll(list);
      });
    } catch (e) {
      if (mounted) {
        _toast('Impossibile caricare le richieste: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Widget _statusChip(String status) {
    final color = colorWorkflow(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        labelWorkflow(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final st = _s(r['workflow_status']);
    final canExportPdf = st == _stApprovataAdmin;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _statusChip(st),
                const Spacer(),
                Text(
                  labelTipoAssenza(_s(r['tipo_assenza'])),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(formatAssenzaPeriodoDetail(r)),
            if (_s(r['dt_comment']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('DT: ${_s(r['dt_comment'])}'),
              ),
            if (_s(r['admin_comment']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Admin: ${_s(r['admin_comment'])}'),
              ),
            for (final line in _workflowDecisionLines(r))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  line,
                  style: TextStyle(
                    color: line.startsWith('Autorizzata admin')
                        ? Colors.green.shade800
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: line.startsWith('Autorizzata admin') ||
                            line.startsWith('Rifiutata da admin')
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            if (canExportPdf)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _exportRichiestaPdf(r),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export PDF'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _bootstrap() async {
    setState(() => _busy = true);
    try {
      await _resolveMyUuids();
      await _loadMyRequests();
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

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        titleSpacing: 0,
        title: const ResponsiveAppBarTitle(
          title: 'Le mie ferie / permessi',
          desktopLogoSize: 36,
        ),
      )),
      body: Stack(
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadMyRequests();
              },
              child: SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Le richieste ferie e permessi vengono inserite dal DT o dall\'assistente DT. '
                        'Qui vedi lo stato delle richieste registrate a tuo nome. '
                        'Dopo l\'approvazione amministrativa potrai scaricare il PDF.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(key: _requestsSectionKey),
                  Row(
                    children: [
                      Text(
                        'Le mie richieste',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingRequests)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          tooltip: 'Aggiorna elenco',
                          onPressed: _busy ? null : _loadMyRequests,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!_loadingRequests && _myRequests.isEmpty)
                    Text(
                      'Nessuna richiesta registrata a tuo nome.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    )
                  else
                    ..._myRequests.map(_buildRequestCard),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.06),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
