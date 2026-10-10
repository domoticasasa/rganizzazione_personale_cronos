import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/mobile_navigation.dart';
import '../widgets/app_logo.dart';
import '../widgets/async_action_button.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// Anagrafica DOIT / strutture RFI per programmazione corsi.
class AdminFormazioneRfiStrutturePage extends StatefulWidget {
  const AdminFormazioneRfiStrutturePage({super.key});

  @override
  State<AdminFormazioneRfiStrutturePage> createState() =>
      _AdminFormazioneRfiStrutturePageState();
}

class _AdminFormazioneRfiStrutturePageState
    extends State<AdminFormazioneRfiStrutturePage> {
  final _supa = Supabase.instance.client;
  final _nome = TextEditingController();
  final _indirizzo = TextEditingController();
  final _maps = TextEditingController();
  final _search = TextEditingController();
  bool _active = true;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nome.dispose();
    _indirizzo.dispose();
    _maps.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _supa
          .from('formazione_rfi_strutture')
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
    final cNome = TextEditingController(text: (item['nome'] ?? '').toString());
    final cIndirizzo =
        TextEditingController(text: (item['indirizzo'] ?? '').toString());
    final cMaps =
        TextEditingController(text: (item['maps_link'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica struttura RFI'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cNome,
                decoration: const InputDecoration(
                  labelText: 'Nome (es. DOIT Milano)',
                ),
              ),
              TextField(
                controller: cIndirizzo,
                decoration: const InputDecoration(labelText: 'Indirizzo'),
                maxLines: 2,
              ),
              TextField(
                controller: cMaps,
                decoration: const InputDecoration(
                  labelText: 'Link Google Maps',
                ),
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
      await _supa.from('formazione_rfi_strutture').update({
        'nome': cNome.text.trim(),
        'indirizzo': cIndirizzo.text.trim(),
        'maps_link': cMaps.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).match({'id_uuid': item['id_uuid']});
      if (mounted) await _load();
    }
    cNome.dispose();
    cIndirizzo.dispose();
    cMaps.dispose();
  }

  Future<void> _insert() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome della struttura')),
      );
      return;
    }
    try {
      await _supa.from('formazione_rfi_strutture').insert({
        'nome': nome,
        'indirizzo': _indirizzo.text.trim(),
        'maps_link': _maps.text.trim(),
        'active': _active,
      });
      _nome.clear();
      _indirizzo.clear();
      _maps.clear();
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

  Future<void> _toggleActive(Map<String, dynamic> r, bool v) async {
    await _supa
        .from('formazione_rfi_strutture')
        .update({
          'active': v,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .match({'id_uuid': r['id_uuid']});
    _load();
  }

  Future<void> _deleteItem(Map<String, dynamic> r) async {
    if (await _confirm('Eliminare questa struttura?')) {
      await _supa
          .from('formazione_rfi_strutture')
          .delete()
          .match({'id_uuid': r['id_uuid']});
      _load();
    }
  }

  Widget _buildStrutturaCard(Map<String, dynamic> r) {
    final narrow = useMobileUi(context);
    final title = (r['nome'] ?? '').toString();
    final address = (r['indirizzo'] ?? '').toString();
    final maps = (r['maps_link'] ?? '').toString();

    Widget subtitle() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (address.trim().isNotEmpty) Text(address),
            if (maps.trim().isNotEmpty)
              Text(
                maps,
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                maxLines: narrow ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );

    Widget actions() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: r['active'] ?? false,
              onChanged: (v) => _toggleActive(r, v),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditDialog(r),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteItem(r),
            ),
          ],
        );

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
                    onChanged: (v) => _toggleActive(r, v),
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
                    onPressed: () => _deleteItem(r),
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
        trailing: actions(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = useMobileUi(context);
    final pad = narrow ? 12.0 : 16.0;
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((r) {
      final nome = (r['nome'] ?? '').toString().toLowerCase();
      final address = (r['indirizzo'] ?? '').toString().toLowerCase();
      return q.isEmpty || nome.contains(q) || address.contains(q);
    }).toList();

    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: ResponsiveAppBarTitle(
          title: narrow ? 'Strutture RFI' : 'Strutture RFI (DOIT)',
        ),
      )),
      body: PageWithTopLogo(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.all(pad),
                children: [
                  if (!narrow)
                    Text(
                      'Registra le sedi DOIT usate in programmazione corsi RFI. '
                      'In modifica corso potrai selezionarle dal menu a tendina.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF546E7A),
                          ),
                    ),
                  if (!narrow) const SizedBox(height: 12),
                  TextField(
                    controller: _nome,
                    decoration: InputDecoration(
                      labelText: narrow
                          ? 'Nome struttura'
                          : 'Nome struttura (es. DOIT di Milano)',
                    ),
                  ),
                  TextField(
                    controller: _indirizzo,
                    decoration: const InputDecoration(labelText: 'Indirizzo'),
                    maxLines: 2,
                  ),
                  TextField(
                    controller: _maps,
                    decoration: const InputDecoration(
                      labelText: 'Link Google Maps',
                      hintText: 'https://maps.google.com/...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Cerca',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
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
                  const Divider(),
                  for (final r in filtered) _buildStrutturaCard(r),
                ],
              ),
      ),
    );
  }
}
