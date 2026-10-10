import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/mobile_navigation.dart';
import '../utils/roles.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Anagrafica strutture D.Lgs. 81/08 per programmazione corsi.
class AdminFormazioneDlgsStrutturePage extends StatefulWidget {
  const AdminFormazioneDlgsStrutturePage({
    super.key,
    this.embedded = false,
    this.role,
    this.readOnly = false,
  });

  /// Se true, solo contenuto (es. tab in Gestione Dati).
  final bool embedded;
  final String? role;
  final bool readOnly;

  @override
  State<AdminFormazioneDlgsStrutturePage> createState() =>
      _AdminFormazioneDlgsStrutturePageState();
}

class _AdminFormazioneDlgsStrutturePageState
    extends State<AdminFormazioneDlgsStrutturePage> {
  final _supa = Supabase.instance.client;
  final _nome = TextEditingController();
  final _indirizzo = TextEditingController();
  final _maps = TextEditingController();
  final _email = TextEditingController();
  final _search = TextEditingController();
  bool _active = true;
  bool _loading = true;
  String? _resolvedRole;
  List<Map<String, dynamic>> _items = [];

  bool get _canWriteResolved =>
      !widget.readOnly &&
      canManageFormazioneDlgs81Griglia(widget.role ?? _resolvedRole ?? '');

  @override
  void initState() {
    super.initState();
    _initRoleThenLoad();
  }

  Future<void> _initRoleThenLoad() async {
    if (widget.role == null) {
      try {
        final uid = _supa.auth.currentUser?.id;
        if (uid != null) {
          final row = await _supa
              .from('users')
              .select('role')
              .eq('auth_id', uid)
              .maybeSingle();
          _resolvedRole = (row?['role'] ?? '').toString();
        }
      } catch (_) {}
    }
    await _load();
  }

  @override
  void dispose() {
    _nome.dispose();
    _indirizzo.dispose();
    _maps.dispose();
    _email.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _supa
          .from('formazione_dlgs_strutture')
          .select('*')
          .order('nome', ascending: true);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e')),
      );
    }
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Conferma'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Conferma'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    if (!_canWriteResolved) return;
    final cNome = TextEditingController(text: (item['nome'] ?? '').toString());
    final cIndirizzo =
        TextEditingController(text: (item['indirizzo'] ?? '').toString());
    final cMaps =
        TextEditingController(text: (item['maps_link'] ?? '').toString());
    final cEmail =
        TextEditingController(text: (item['email_outlook'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica struttura'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cNome,
                decoration: const InputDecoration(labelText: 'Nome Struttura'),
              ),
              TextField(
                controller: cIndirizzo,
                decoration: const InputDecoration(labelText: 'Indirizzo'),
                maxLines: 2,
              ),
              TextField(
                controller: cMaps,
                decoration: const InputDecoration(labelText: 'Link Maps'),
              ),
              TextField(
                controller: cEmail,
                decoration: const InputDecoration(
                  labelText: 'Email struttura (Outlook)',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (ok == true && cNome.text.trim().isNotEmpty) {
      await _supa.from('formazione_dlgs_strutture').update({
        'nome': cNome.text.trim(),
        'indirizzo': cIndirizzo.text.trim(),
        'maps_link': cMaps.text.trim(),
        'email_outlook': cEmail.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).match({'id_uuid': item['id_uuid']});
      if (mounted) await _load();
    }
    cNome.dispose();
    cIndirizzo.dispose();
    cMaps.dispose();
    cEmail.dispose();
  }

  Future<void> _insert() async {
    if (!_canWriteResolved) return;
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome della struttura')),
      );
      return;
    }
    try {
      await _supa.from('formazione_dlgs_strutture').insert({
        'nome': nome,
        'indirizzo': _indirizzo.text.trim(),
        'maps_link': _maps.text.trim(),
        'email_outlook': _email.text.trim(),
        'active': _active,
      });
      _nome.clear();
      _indirizzo.clear();
      _maps.clear();
      _email.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Struttura salvata')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    }
  }

  Widget _buildStrutturaCard(Map<String, dynamic> r, {required bool canWrite}) {
    final narrow = useMobileUi(context);
    final title = (r['nome'] ?? '').toString();
    final address = (r['indirizzo'] ?? '').toString();
    final email = (r['email_outlook'] ?? '').toString();
    final maps = (r['maps_link'] ?? '').toString();

    Widget subtitle() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (address.trim().isNotEmpty) Text(address),
            if (email.trim().isNotEmpty) Text(email),
            if (maps.trim().isNotEmpty)
              Text(
                maps,
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                maxLines: narrow ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );

    if (!canWrite) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: subtitle(),
          isThreeLine: true,
        ),
      );
    }

    if (narrow) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              subtitle(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Attiva'),
                  Switch(
                    value: r['active'] ?? false,
                    onChanged: (v) async {
                      await _supa.from('formazione_dlgs_strutture').update({
                        'active': v,
                        'updated_at':
                            DateTime.now().toUtc().toIso8601String(),
                      }).match({'id_uuid': r['id_uuid']});
                      _load();
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Modifica',
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                    onPressed: () => _showEditDialog(r),
                  ),
                  IconButton(
                    tooltip: 'Elimina',
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () async {
                      if (await _confirm('Eliminare questa struttura?')) {
                        await _supa
                            .from('formazione_dlgs_strutture')
                            .delete()
                            .match({'id_uuid': r['id_uuid']});
                        _load();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: subtitle(),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: r['active'] ?? false,
              onChanged: (v) async {
                await _supa.from('formazione_dlgs_strutture').update({
                  'active': v,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                }).match({'id_uuid': r['id_uuid']});
                _load();
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditDialog(r),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                if (await _confirm('Eliminare questa struttura?')) {
                  await _supa
                      .from('formazione_dlgs_strutture')
                      .delete()
                      .match({'id_uuid': r['id_uuid']});
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final canWrite = _canWriteResolved;
    final narrow = useMobileUi(context);
    final pad = narrow ? 12.0 : 16.0;
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final nome = (r['nome'] ?? '').toString().toLowerCase();
      final address = (r['indirizzo'] ?? '').toString().toLowerCase();
      final email = (r['email_outlook'] ?? '').toString().toLowerCase();
      return q.isEmpty ||
          nome.contains(q) ||
          address.contains(q) ||
          email.contains(q);
    }).toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.all(pad),
      children: [
        if (!narrow)
          Text(
            'Registra le sedi usate in programmazione corsi D.Lgs. 81/08. '
            'In modifica corso potrai selezionarle dal menu a tendina.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF546E7A),
                ),
          ),
        if (!canWrite)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Sola lettura: inserimento e modifica consentiti solo al ruolo Admin Pernottamenti.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        if (canWrite) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _nome,
            decoration: const InputDecoration(labelText: 'Nome Struttura'),
          ),
          TextField(
            controller: _indirizzo,
            decoration: const InputDecoration(labelText: 'Indirizzo'),
            maxLines: 2,
          ),
          TextField(
            controller: _maps,
            decoration: const InputDecoration(
              labelText: 'Link Maps',
              hintText: 'https://maps.google.com/...',
            ),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email struttura (Outlook)',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Cerca',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (canWrite) ...[
          Row(
            children: [
              const Text('Attiva'),
              Switch(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const Spacer(),
              AsyncFilledButton(
                onPressed: _insert,
                child: const Text('SALVA'),
              ),
            ],
          ),
        ],
        const Divider(),
        for (final r in filtered) _buildStrutturaCard(r, canWrite: canWrite),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Embedded in Gestione Dati: evita doppio logo (il parent ha già PageWithTopLogo).
    if (widget.embedded) {
      return _buildBody();
    }
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(
          title: useMobileUi(context) ? 'Strutture 81' : 'Strutture Formazioni 81',
        ),
      )),
      body: PageWithTopLogo(child: _buildBody()),
    );
  }
}
