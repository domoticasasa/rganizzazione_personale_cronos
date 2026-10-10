import 'package:flutter/material.dart';

import '../services/security_incident_service.dart';
import '../utils/modify_feedback.dart';
import '../widgets/app_logo.dart';

/// Segnalazione incidente cybersecurity senza login (account bloccato / pre-auth).
class SecurityIncidentPublicPage extends StatefulWidget {
  const SecurityIncidentPublicPage({super.key});

  @override
  State<SecurityIncidentPublicPage> createState() =>
      _SecurityIncidentPublicPageState();
}

class _SecurityIncidentPublicPageState extends State<SecurityIncidentPublicPage> {
  bool _submitting = false;
  bool _done = false;

  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _honeypotCtrl = TextEditingController();
  String _category = 'account_compromesso';
  String _severity = 'alta';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _deviceCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    _honeypotCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (name.length < 2 || title.isEmpty || desc.isEmpty) {
      ModifyFeedback.hint(
        context,
        'Nome, titolo e descrizione sono obbligatori.',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await SecurityIncidentService.submitPublic(
        reporterName: name,
        category: _category,
        severity: _severity,
        title: title,
        description: desc,
        deviceInfo: _deviceCtrl.text,
        locationInfo: _locationCtrl.text,
        phone: _phoneCtrl.text,
        honeypot: _honeypotCtrl.text,
      );
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ResponsiveAppBarTitle(title: 'Segnalazione sicurezza'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/login');
            }
          },
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
                      'Emergenza senza accesso',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Usa questo modulo se non riesci ad accedere (password '
                      'sbagliata, account bloccato, dispositivo perso). '
                      'La segnalazione arriva subito agli amministratori.',
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
            if (_done) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Segnalazione inviata',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Gli amministratori sono stati avvisati. '
                        'Se possibile, resta raggiungibile al telefono indicato.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pushReplacementNamed('/login'),
                        child: const Text('Torna al login'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Il tuo nome *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              // Honeypot nascosto
              Offstage(
                child: TextField(
                  controller: _honeypotCtrl,
                  decoration: const InputDecoration(labelText: 'Website'),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: const [
                  DropdownMenuItem(
                    value: 'account_compromesso',
                    child: Text('Account compromesso / bloccato'),
                  ),
                  DropdownMenuItem(
                    value: 'phishing',
                    child: Text('Phishing / messaggio sospetto'),
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
                onChanged: (v) =>
                    setState(() => _category = v ?? 'altro'),
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
                onChanged: (v) =>
                    setState(() => _severity = v ?? 'media'),
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
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefono di contatto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _deviceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dispositivo (opzionale)',
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
            ],
          ],
        ),
      ),
    );
  }
}
