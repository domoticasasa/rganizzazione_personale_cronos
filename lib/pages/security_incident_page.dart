import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/classic_nav_session_cache.dart';
import '../services/hub_pending_poll_service.dart';
import '../services/security_incident_service.dart';
import '../utils/modify_feedback.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Segnalazione incidente cybersecurity (NIS2 / procedura interna).
class SecurityIncidentPage extends StatefulWidget {
  const SecurityIncidentPage({super.key});

  @override
  State<SecurityIncidentPage> createState() => _SecurityIncidentPageState();
}

class _SecurityIncidentPageState extends State<SecurityIncidentPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<SecurityIncidentReport> _rows = const [];

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _category = 'phishing';
  String _severity = 'media';

  final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

  bool get _isAdmin {
    final role = ClassicNavSessionCache.current?.role ?? '';
    final n = normalizeRole(role);
    return n == 'admin' ||
        n == 'admin_generale' ||
        n == 'logistica' ||
        n == 'admin_vista';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _deviceCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SecurityIncidentService.listMineOrAdmin();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty || desc.isEmpty) {
      ModifyFeedback.hint(context, 'Titolo e descrizione sono obbligatori.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await SecurityIncidentService.submit(
        category: _category,
        severity: _severity,
        title: title,
        description: desc,
        deviceInfo: _deviceCtrl.text,
        locationInfo: _locationCtrl.text,
        phone: _phoneCtrl.text,
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _descCtrl.clear();
      _deviceCtrl.clear();
      _locationCtrl.clear();
      ModifyFeedback.hint(
        context,
        'Segnalazione inviata. Gli amministratori sono stati avvisati.',
      );
      await _load();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _setStatus(SecurityIncidentReport r, String status) async {
    try {
      await SecurityIncidentService.updateStatus(id: r.id, status: status);
      HubPendingPollService.instance.invalidateSecurityIncidents();
      unawaited(
        HubPendingPollService.instance.refreshAllListeners(invalidateCache: true),
      );
      await _load();
      if (mounted && status == 'gestita') {
        ModifyFeedback.hint(context, 'Segnalazione segnata come gestita.');
      }
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'Incidenti sicurezza'),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: PageWithTopLogo(
        showLogo: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protocollo emergenza',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Se sospetti phishing, furto del tablet, account violato o '
                      'software anomalo: segnala subito qui e contatta il referente '
                      'IT / sicurezza. Non inoltrare allegati sospetti e non collegarti '
                      'a Wi‑Fi aperti senza VPN.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nuova segnalazione',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: const [
                DropdownMenuItem(
                  value: 'phishing',
                  child: Text('Phishing / messaggio sospetto'),
                ),
                DropdownMenuItem(
                  value: 'account_compromesso',
                  child: Text('Account compromesso'),
                ),
                DropdownMenuItem(
                  value: 'dispositivo_perso',
                  child: Text('Dispositivo perso / rubato'),
                ),
                DropdownMenuItem(
                  value: 'malware',
                  child: Text('Malware / comportamento anomalo'),
                ),
                DropdownMenuItem(
                  value: 'accesso_non_autorizzato',
                  child: Text('Accesso non autorizzato'),
                ),
                DropdownMenuItem(value: 'altro', child: Text('Altro')),
              ],
              onChanged: (v) => setState(() => _category = v ?? 'altro'),
              decoration: const InputDecoration(
                labelText: 'Categoria',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _severity,
              items: const [
                DropdownMenuItem(value: 'bassa', child: Text('Bassa')),
                DropdownMenuItem(value: 'media', child: Text('Media')),
                DropdownMenuItem(value: 'alta', child: Text('Alta')),
                DropdownMenuItem(value: 'critica', child: Text('Critica')),
              ],
              onChanged: (v) => setState(() => _severity = v ?? 'media'),
              decoration: const InputDecoration(
                labelText: 'Gravità',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titolo *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Cosa è successo *',
                hintText: 'Quando, cosa hai visto, azioni già fatte…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deviceCtrl,
              decoration: const InputDecoration(
                labelText: 'Dispositivo (opzionale)',
                hintText: 'Es. tablet Samsung, PC ufficio…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Luogo / cantiere (opzionale)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefono di contatto (opzionale)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.report_gmailerrorred_outlined),
              label: const Text('Invia segnalazione'),
            ),
            const SizedBox(height: 24),
            Text(
              _isAdmin ? 'Tutte le segnalazioni' : 'Le mie segnalazioni',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (_rows.isEmpty)
              const Text('Nessuna segnalazione.')
            else
              ..._rows.map((r) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        _dtFmt.format(r.createdAt.toLocal()),
                        SecurityIncidentReport.categoryLabel(r.category),
                        'Gravità ${SecurityIncidentReport.severityLabel(r.severity)}',
                        'Stato: ${SecurityIncidentReport.statusLabel(r.status)}',
                        if (r.isPublicSubmit) 'Invio pre-login',
                        if (r.reporterName.isNotEmpty) r.reporterName,
                        if (r.description.isNotEmpty) r.description,
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: _isAdmin && r.isOpen
                        ? PopupMenuButton<String>(
                            onSelected: (v) => unawaited(_setStatus(r, v)),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'in_lavorazione',
                                child: Text('In lavorazione'),
                              ),
                              PopupMenuItem(
                                value: 'gestita',
                                child: Text('Segna come gestita'),
                              ),
                              PopupMenuItem(
                                value: 'chiuso',
                                child: Text('Chiudi'),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
