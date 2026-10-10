import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/confirm_sound_service.dart';
import '../services/notification_routing_rules_service.dart';
import '../utils/date_formatters.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminNotificationRulesPage extends StatefulWidget {
  const AdminNotificationRulesPage({super.key});

  @override
  State<AdminNotificationRulesPage> createState() =>
      _AdminNotificationRulesPageState();
}

class _AdminNotificationRulesPageState extends State<AdminNotificationRulesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  List<Map<String, dynamic>> _rules = const [];
  bool _exceptionsLoading = true;
  List<Map<String, dynamic>> _adminCreateSkipRows = const [];
  List<Map<String, dynamic>> _adminGeneraleSkipRows = const [];

  final _createSkipWorkflowCtrl = TextEditingController();
  final _adminGeneraleSkipActionCtrl = TextEditingController();

  static const List<String> _targetOptions = [
    'selected_dt',
    'requester',
    'dt_prenotazione',
    'assistenti_dt_prenotazione',
    'dipendente',
    'actor',
    'role:admin_pernottamenti',
    'role:admin_trenoaereo',
    'role:admin_generale',
    'role:logistica',
    'role:dt',
    'role:assistente_dt',
    'role:user',
    'role:dipendente',
    'role:caposquadra',
  ];

  static const Map<String, String> _targetLabels = {
    'selected_dt': 'DT selezionato',
    'requester': 'Richiedente',
    'dt_prenotazione': 'DT della prenotazione (treno/aereo)',
    'assistenti_dt_prenotazione': 'Assistenti del DT della prenotazione',
    'dipendente': 'Dipendente coinvolto',
    'actor': 'Utente che esegue l\'azione',
    'role:admin_pernottamenti': 'Tutti Admin Pernottamenti',
    'role:admin_trenoaereo': 'Tutti Admin Treni/Aerei',
    'role:admin_generale': 'Tutti Admin Generali',
    'role:logistica': 'Tutti Logistica',
    'role:dt': 'Tutti DT',
    'role:assistente_dt': 'Tutti Assistenti DT',
    'role:user': 'Tutti User',
    'role:dipendente': 'Tutti Dipendenti',
    'role:caposquadra': 'Tutti Caposquadra',
  };

  static const Set<String> _mandatoryRuleKeys = {
    'request_to_dt',
    'dt_approved_to_admin',
    'dt_approved_to_requester',
    'dt_rejected_to_requester',
    'create_treno_aereo_by_dt',
    'create_treno_aereo_by_assistente_dt',
    'create_to_admin_trenoaereo',
    'create_to_admin_pernottamenti',
    'admin_update_notify',
    'admin_delete_notify',
    'admin_pernottamenti_update_notify',
    'admin_pernottamenti_delete_notify',
    'admin_treno_aereo_update_notify',
    'admin_treno_aereo_delete_notify',
    'admin_formazione_update_notify',
    'admin_formazione_delete_notify',
    'logistica_box_check_completed_notify',
    'logistica_mdo_general_check_completed_notify',
    'logistica_mdo_dotazioni_check_completed_notify',
    'assenza_request_to_dt',
    'assenza_dt_approved_to_requester',
    'assenza_dt_approved_to_admin',
    'assenza_dt_rejected_to_requester',
    'assenza_admin_approved_to_requester',
    'assenza_admin_rejected_to_requester',
  };

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _createSkipWorkflowCtrl.dispose();
    _adminGeneraleSkipActionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await NotificationRoutingRulesService.listRules();
      rows.sort((a, b) => (a['rule_key'] ?? '').toString().compareTo((b['rule_key'] ?? '').toString()));
      setState(() => _rules = rows);
      await _loadExceptions();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExceptions() async {
    setState(() => _exceptionsLoading = true);
    try {
      final createSkip = await Supabase.instance.client
          .from('notification_admin_create_skip_workflow_statuses')
          .select('action_key,workflow_status,enabled')
          .eq('action_key', 'create')
          .order('workflow_status');

      _adminCreateSkipRows = (createSkip as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final genSkip = await Supabase.instance.client
          .from('notification_admin_generale_filter_skip_actions')
          .select('action_key,enabled')
          .order('action_key');

      _adminGeneraleSkipRows = (genSkip as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _adminCreateSkipRows = const [];
      _adminGeneraleSkipRows = const [];
    } finally {
      if (mounted) setState(() => _exceptionsLoading = false);
    }
  }

  Future<void> _upsertAdminCreateSkip(String workflowStatus, bool enabled) async {
    final ws = workflowStatus.trim();
    if (ws.isEmpty) return;
    await Supabase.instance.client
        .from('notification_admin_create_skip_workflow_statuses')
        .upsert(
          {
            'action_key': 'create',
            'workflow_status': ws,
            'enabled': enabled,
          },
          onConflict: 'action_key,workflow_status',
        );
    await _loadExceptions();
  }

  Future<void> _upsertAdminGeneraleSkip(String actionKey, bool enabled) async {
    final ak = actionKey.trim();
    if (ak.isEmpty) return;
    await Supabase.instance.client
        .from('notification_admin_generale_filter_skip_actions')
        .upsert(
          {
            'action_key': ak,
            'enabled': enabled,
          },
          onConflict: 'action_key',
        );
    await _loadExceptions();
  }

  String _targetLabel(String value) => _targetLabels[value] ?? value;

  Set<String> get _knownTargets => {..._targetOptions, ..._targetLabels.keys};

  Set<String> get _existingRuleKeys => _rules
      .map((r) => (r['rule_key'] ?? '').toString().trim())
      .where((k) => k.isNotEmpty)
      .toSet();

  List<String> get _missingMandatoryKeys {
    final missing = _mandatoryRuleKeys.difference(_existingRuleKeys).toList();
    missing.sort();
    return missing;
  }

  List<String> get _unknownTargetsInRules {
    final unknown = <String>{};
    for (final r in _rules) {
      final t = (r['targets'] as List?) ?? const [];
      for (final raw in t) {
        final v = raw.toString().trim();
        if (v.isEmpty) continue;
        if (!_knownTargets.contains(v)) unknown.add(v);
      }
    }
    final out = unknown.toList()..sort();
    return out;
  }

  Future<void> _syncDefaults() async {
    try {
      await NotificationRoutingRulesService.syncDefaultsToDatabase();
      await _load();
      if (!mounted) return;
      ConfirmSoundService.play();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Regole predefinite riallineate con successo'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore riallineamento regole: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _prettyRuleKey(String key) {
    if (key.trim().isEmpty) return key;
    return key
        .trim()
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _normalizeRuleKey(String key) {
    return key
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Sintesi “da chi / a chi / quando” per regole note (chiave = rule_key DB).
  static const Map<String, String> _ruleFlowHelp = {
    'request_to_dt':
        'Quando: dipendente invia richiesta treno o aereo.\n'
        'Destinatari tipici: DT selezionato nel modulo.',
    'dt_approved_to_admin':
        'Quando: il DT conferma la richiesta (biglietto verso admin).\n'
        'Destinatari tipici: tutti gli Admin treni/aereo.',
    'dt_approved_to_requester':
        'Quando: stessa conferma DT.\n'
        'Destinatari tipici: dipendente della prenotazione; più il richiedente se registrato e diverso.',
    'dt_rejected_to_requester':
        'Quando: il DT rifiuta la richiesta.\n'
        'Destinatari tipici: come sopra (dipendente + richiedente se presente).',
    'create_treno_aereo_by_dt':
        'Quando: un DT inserisce una prenotazione treno/aereo (già inviata ad admin).\n'
        'Destinatari tipici: admin treni/aereo + utente del dipendente coinvolto.',
    'create_treno_aereo_by_assistente_dt':
        'Quando: un Assistente DT inserisce la prenotazione per conto del DT.\n'
        'Destinatari tipici: admin treni/aereo + DT supervisore (campo richiedente).',
    'create_to_admin_trenoaereo':
        'Quando: creazione treno/aereo in casi particolari (fallback).\n'
        'Destinatari tipici: solo admin treni/aereo.',
    'create_to_admin_pernottamenti':
        'Quando: viene creata una prenotazione pernottamento che notifica gli admin.\n'
        'Destinatari tipici: admin pernottamenti.',
    'admin_update_notify':
        'Quando: admin modifica o cambia stato su flussi che usano notifyUserForBooking generico.\n'
        'Destinatari tipici: richiedente + dipendente (prenotazioni non gestite da regola treno/aereo dedicata).',
    'admin_delete_notify':
        'Quando: admin elimina in flussi generici.\n'
        'Destinatari tipici: richiedente + dipendente.',
    'admin_pernottamenti_update_notify':
        'Quando: admin pernottamenti modifica, conferma o cambia stato su una prenotazione pernottamento.\n'
        'Destinatari tipici: DT inseritore della prenotazione + dipendente coinvolto.',
    'admin_pernottamenti_delete_notify':
        'Quando: admin pernottamenti elimina una prenotazione pernottamento.\n'
        'Destinatari tipici: DT inseritore della prenotazione + dipendente coinvolto.',
    'admin_treno_aereo_update_notify':
        'Quando: admin treni/aereo modifica, cambia stato o aggiorna una prenotazione treno o aereo.\n'
        'Destinatari tipici: DT legato alla prenotazione, assistenti autorizzati, dipendente.',
    'admin_treno_aereo_delete_notify':
        'Quando: admin treni/aereo elimina una prenotazione treno o aereo.\n'
        'Destinatari tipici: come sopra.',
    'admin_formazione_update_notify':
        'Quando: admin inserisce/aggiorna corsi formazione, date attestato/scadenza o programmazione.\n'
        'Destinatari tipici: dipendente coinvolto.',
    'admin_formazione_delete_notify':
        'Quando: admin elimina un corso formazione del dipendente.\n'
        'Destinatari tipici: dipendente coinvolto.',
    'logistica_box_check_completed_notify':
        'Quando: viene confermato il check su un BOX logistica.\n'
        'Destinatari tipici: DT, Assistenti DT, Logistica.',
    'logistica_mdo_general_check_completed_notify':
        'Quando: viene confermato il check generale su un MDO ferroviario.\n'
        'Destinatari tipici: DT, Assistenti DT, Logistica.',
    'logistica_mdo_dotazioni_check_completed_notify':
        'Quando: vengono confermati check dotazioni su un MDO ferroviario.\n'
        'Destinatari tipici: DT, Assistenti DT, Logistica.',
    'assenza_request_to_dt':
        'Quando: un dipendente invia una richiesta ferie/permessi/malattia.\n'
        'Destinatari tipici: DT selezionato nel modulo.',
    'assenza_dt_approved_to_requester':
        'Quando: il DT approva la richiesta assenza (in attesa admin).\n'
        'Destinatari tipici: dipendente richiedente.',
    'assenza_dt_approved_to_admin':
        'Quando: il DT approva la richiesta ferie/permessi.\n'
        'Destinatari tipici: admin (devono confermare o rifiutare).',
    'assenza_dt_rejected_to_requester':
        'Quando: il DT rifiuta la richiesta assenza.\n'
        'Destinatari tipici: dipendente richiedente.',
    'assenza_admin_approved_to_requester':
        'Quando: l\'admin approva definitivamente la richiesta assenza.\n'
        'Destinatari tipici: dipendente richiedente.',
    'assenza_admin_rejected_to_requester':
        'Quando: l\'admin rifiuta la richiesta assenza.\n'
        'Destinatari tipici: dipendente richiedente.',
  };

  static const List<String> _groupOrder = [
    'Workflow DT',
    'Treni/Aerei',
    'Pernottamenti',
    'Generali',
    'Altre',
  ];

  String _ruleGroupForKey(String key) {
    final k = key.toLowerCase().trim();
    if (k == 'request_to_dt' ||
        k == 'dt_approved_to_admin' ||
        k == 'dt_approved_to_requester' ||
        k == 'dt_rejected_to_requester' ||
        k.startsWith('assenza_')) {
      return 'Workflow DT';
    }
    if (k.contains('treno') || k.contains('aereo')) return 'Treni/Aerei';
    if (k.contains('pernott')) return 'Pernottamenti';
    if (k.startsWith('admin_') || k.contains('notify')) return 'Generali';
    return 'Altre';
  }

  IconData _groupIcon(String group) {
    switch (group) {
      case 'Workflow DT':
        return Icons.approval_outlined;
      case 'Treni/Aerei':
        return Icons.train_outlined;
      case 'Pernottamenti':
        return Icons.hotel_outlined;
      case 'Generali':
        return Icons.tune_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupedRules() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in _rules) {
      final key = (r['rule_key'] ?? '').toString();
      final group = _ruleGroupForKey(key);
      map.putIfAbsent(group, () => <Map<String, dynamic>>[]).add(r);
    }
    final entries = map.entries.toList()
      ..sort((a, b) {
        final ia = _groupOrder.indexOf(a.key);
        final ib = _groupOrder.indexOf(b.key);
        final aa = ia == -1 ? 999 : ia;
        final bb = ib == -1 ? 999 : ib;
        if (aa != bb) return aa.compareTo(bb);
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  Future<void> _openRuleDialog({Map<String, dynamic>? rule}) async {
    final originalKey = (rule?['rule_key'] ?? '').toString();
    final keyCtrl = TextEditingController(text: originalKey);
    final labelCtrl =
        TextEditingController(text: (rule?['label'] ?? '').toString());
    final selected = (((rule?['targets']) as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    bool enabled = rule?['enabled'] == true;
    final isNew = rule == null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: Text(isNew ? 'Nuova regola notifiche' : 'Regola: $originalKey'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: keyCtrl,
                    enabled: isNew,
                    decoration: InputDecoration(
                      labelText: 'Chiave regola (es. dt_to_admin_extra)',
                      border: const OutlineInputBorder(),
                      helperText: isNew
                          ? 'Usa lettere/numeri; verrà convertita in snake_case.'
                          : 'La chiave esistente non può essere modificata.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Etichetta chiara',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: enabled,
                    onChanged: (v) => setSt(() => enabled = v),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Regola attiva'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Destinatari',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ..._targetOptions.map((opt) {
                    final on = selected.contains(opt);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_targetLabel(opt)),
                      subtitle: Text(opt),
                      onChanged: (v) => setSt(() {
                        if (v == true) {
                          selected.add(opt);
                        } else {
                          selected.remove(opt);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            AsyncFilledButton(
              onPressed: () async {
                final normalizedKey = isNew
                    ? _normalizeRuleKey(keyCtrl.text)
                    : originalKey;
                if (normalizedKey.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chiave regola non valida'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                await NotificationRoutingRulesService.saveRule(
                  ruleKey: normalizedKey,
                  label: labelCtrl.text.trim().isEmpty
                      ? _prettyRuleKey(normalizedKey)
                      : labelCtrl.text.trim(),
                  targets: selected.toList(),
                  enabled: enabled,
                );
                if (!context.mounted) return;
                Navigator.pop(context, true);
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    keyCtrl.dispose();
    labelCtrl.dispose();
    if (saved == true) {
      await _load();
      if (!mounted) return;
      ConfirmSoundService.play();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isNew
              ? 'Nuova regola notifiche creata'
              : 'Regola notifiche salvata'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: 'Admin — Regole Notifiche'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Regole', icon: Icon(Icons.rule_folder_outlined)),
            Tab(text: 'Log', icon: Icon(Icons.history)),
          ],
        ),
        actions: [
          if (_tab.index == 0) ...[
            IconButton(
              tooltip: 'Nuova regola',
              onPressed: _loading ? null : () => _openRuleDialog(),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Ricarica regole',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      )),
      body: PageWithTopLogo(
        child: TabBarView(
          controller: _tab,
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final grouped = _groupedRules();
                    final sections = <Widget>[];
                    sections.add(
                      Builder(builder: (context) {
                        final missingKeys = _missingMandatoryKeys;
                        final unknownTargets = _unknownTargetsInRules;
                        final hasIssues =
                            missingKeys.isNotEmpty || unknownTargets.isNotEmpty;
                        return Card(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.65),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Come funziona',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ogni riga è una regola attivata dall’app in un momento preciso del flusso '
                                  '(richiesta, conferma DT, creazione da DT/assistente, modifica admin, ecc.). '
                                  'Sotto il titolo vedi la chiave tecnica, i destinatari scelti e — se disponibile — '
                                  'una sintesi “quando / a chi”. Puoi aggiungere più destinatari (token) spuntando le caselle in modifica.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      hasIssues
                                          ? Icons.warning_amber_rounded
                                          : Icons.verified_outlined,
                                      color: hasIssues ? Colors.orange : Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        hasIssues
                                            ? 'Verifica: trovate incongruenze nelle regole.'
                                            : 'Verifica: tutte le regole principali sono presenti.',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                if (missingKeys.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Regole mancanti: ${missingKeys.join(', ')}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                if (unknownTargets.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Target non riconosciuti: ${unknownTargets.join(', ')}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _loading ? null : _syncDefaults,
                                      icon: const Icon(Icons.sync),
                                      label: const Text('Riallinea regole standard'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _loading ? null : _load,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Riesegui verifica'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    );

                    sections.add(const SizedBox(height: 12));
                    sections.add(
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Eccezioni “quando” (Supabase)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              if (_exceptionsLoading)
                                const Center(child: CircularProgressIndicator())
                              else ...[
                                Text(
                                  '1) Blocca admin su `action=create` per `workflow_status` treno/aereo',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                ..._adminCreateSkipRows.map((r) {
                                  final ws =
                                      (r['workflow_status'] ?? '').toString().trim();
                                  final enabled = r['enabled'] == true;
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(ws),
                                    value: enabled,
                                    onChanged: (v) => _upsertAdminCreateSkip(
                                      ws,
                                      v == true,
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _createSkipWorkflowCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Nuovo workflow_status',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        final ws =
                                            _createSkipWorkflowCtrl.text.trim();
                                        if (ws.isEmpty) return;
                                        await _upsertAdminCreateSkip(ws, true);
                                        if (!context.mounted) return;
                                        _createSkipWorkflowCtrl.clear();
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Aggiungi'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '2) Filtra admin_generale: azioni che saltano il filtro',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                ..._adminGeneraleSkipRows.map((r) {
                                  final ak =
                                      (r['action_key'] ?? '').toString().trim();
                                  final enabled = r['enabled'] == true;
                                  return CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(ak),
                                    value: enabled,
                                    onChanged: (v) =>
                                        _upsertAdminGeneraleSkip(ak, v == true),
                                  );
                                }),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _adminGeneraleSkipActionCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Nuova action (action_key)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        final ak =
                                            _adminGeneraleSkipActionCtrl.text.trim();
                                        if (ak.isEmpty) return;
                                        await _upsertAdminGeneraleSkip(ak, true);
                                        if (!context.mounted) return;
                                        _adminGeneraleSkipActionCtrl.clear();
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Aggiungi'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );

                    for (final entry in grouped) {
                      sections.add(const SizedBox(height: 12));
                      sections.add(
                        Row(
                          children: [
                            Icon(_groupIcon(entry.key), size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${entry.key} (${entry.value.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                      sections.add(const SizedBox(height: 6));
                      for (final r in entry.value) {
                        final key = (r['rule_key'] ?? '').toString();
                        final label = (r['label'] ?? '').toString();
                        final enabled = r['enabled'] == true;
                        final targets = ((r['targets'] as List?) ?? const [])
                            .map((e) => e.toString())
                            .toList();
                        final targetText = targets.map(_targetLabel).join(', ');
                        final flow = _ruleFlowHelp[key];
                        sections.add(
                          Card(
                            child: InkWell(
                              onTap: () => _openRuleDialog(rule: r),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label.isEmpty ? _prettyRuleKey(key) : label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            key,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(fontFamily: 'monospace'),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Destinatari: $targetText',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          if (flow != null) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              flow,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    height: 1.35,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        Icon(
                                          enabled ? Icons.toggle_on : Icons.toggle_off,
                                          color: enabled ? Colors.green : Colors.grey,
                                        ),
                                        const SizedBox(height: 4),
                                        const Icon(Icons.edit_outlined, size: 20),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: sections,
                    );
                  }),
            const _AdminNotificationsLogPanel(),
          ],
        ),
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openRuleDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nuova regola'),
            )
          : null,
    );
  }
}

/// Log notifiche (lettura globale per admin tramite policy RLS).
class _AdminNotificationsLogPanel extends StatefulWidget {
  const _AdminNotificationsLogPanel();

  @override
  State<_AdminNotificationsLogPanel> createState() =>
      _AdminNotificationsLogPanelState();
}

class _AdminNotificationsLogPanelState
    extends State<_AdminNotificationsLogPanel> {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  /// `users.id` → etichetta leggibile (full_name / username).
  Map<int, String> _userLabelById = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _supa
          .from('notifications')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);
      final list = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final ids = <int>{};
      for (final r in list) {
        final v = r['user_id'];
        if (v is int) {
          ids.add(v);
        } else if (v != null) {
          final p = int.tryParse(v.toString());
          if (p != null) ids.add(p);
        }
      }
      Map<int, String> labels = {};
      if (ids.isNotEmpty) {
        final usersRes = await _supa
            .from('users')
            .select('id, full_name, username')
            .inFilter('id', ids.toList());
        for (final row in (usersRes as List)) {
          final idRaw = row['id'];
          final id = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
          if (id == null) continue;
          final fn = (row['full_name'] ?? '').toString().trim();
          final un = (row['username'] ?? '').toString().trim();
          labels[id] =
              fn.isNotEmpty ? fn : (un.isNotEmpty ? un : 'Utente #$id');
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = list;
        _userLabelById = labels;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _recipientLine(dynamic uid) {
    if (uid == null) return 'Destinatario: —';
    final id = uid is int ? uid : int.tryParse(uid.toString());
    if (id == null) return 'Destinatario: $uid';
    final label = _userLabelById[id];
    if (label != null) return 'Destinatario: $label';
    return 'Destinatario: utente #$id';
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is DateTime) return formatDateTimeIt(v);
    final s = v.toString();
    if (s.isEmpty) return '—';
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return formatDateTimeIt(parsed.toLocal());
    return s;
  }

  Iterable<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final uid = r['user_id'];
      final id = uid is int ? uid : int.tryParse((uid ?? '').toString());
      final nameHint =
          id != null ? (_userLabelById[id] ?? '').toLowerCase() : '';
      final parts = [
        r['user_id'],
        r['title'],
        r['message'],
        r['action'],
        r['booking_id'],
        nameHint,
      ].map((x) => (x ?? '').toString().toLowerCase());
      return parts.any((p) => p.contains(q));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                'Impossibile caricare il log. Verifica di aver applicato la migrazione Supabase e i permessi admin.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _error!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cerca (utente, titolo, messaggio…)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Aggiorna log',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${filtered.length} righe (max 500 più recenti)',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nessuna notifica trovata.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    final title = (r['title'] ?? '').toString();
                    final msg = (r['message'] ?? '').toString();
                    final uid = r['user_id'];
                    final read = r['is_read'] == true;
                    return Card(
                      child: ListTile(
                        dense: true,
                        isThreeLine: true,
                        leading: Icon(
                          read ? Icons.notifications_none : Icons.notifications,
                          color: read ? Colors.grey : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          title.isEmpty ? '(senza titolo)' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            _recipientLine(uid),
                            if (r['booking_id'] != null)
                              'Prenotazione: ${r['booking_id']}',
                            if (r['action'] != null) 'Azione: ${r['action']}',
                            _fmt(r['created_at']),
                            if (msg.isNotEmpty) msg,
                          ].join('\n'),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

