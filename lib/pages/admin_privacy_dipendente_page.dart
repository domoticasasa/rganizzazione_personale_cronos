import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/admin_vista_guard.dart';
import '../utils/roles.dart';

/// Audit legale A5: esporta / cancella i dati di un dipendente.
/// Usa la Edge Function `admin-employee-privacy` (da deployare: vedi
/// CHECKLIST_modifiche_legali.md).
class AdminPrivacyDipendentePage extends StatefulWidget {
  const AdminPrivacyDipendentePage({super.key});

  @override
  State<AdminPrivacyDipendentePage> createState() =>
      _AdminPrivacyDipendentePageState();
}

class _AdminPrivacyDipendentePageState
    extends State<AdminPrivacyDipendentePage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _personale = const [];
  String? _selectedId;
  bool _loading = true;
  bool _busy = false;
  String _filter = '';
  String? _lastReport;

  bool get _canWrite => canMutateAsAdmin(currentSessionRole() ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _supa
          .from('personale')
          .select('id_uuid, full_name, active, email')
          .order('full_name');
      if (!mounted) return;
      setState(() {
        _personale = (res as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Errore caricamento dipendenti: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Map<String, dynamic>? get _selected {
    for (final p in _personale) {
      if (p['id_uuid']?.toString() == _selectedId) return p;
    }
    return null;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await _supa.functions.invoke(
      'admin-employee-privacy',
      body: body,
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }
    return Map<String, dynamic>.from(data as Map);
  }

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_').replaceAll(RegExp('_+'), '_');

  Future<void> _export() async {
    final sel = _selected;
    if (sel == null) return;
    setState(() => _busy = true);
    try {
      final out = await _invoke({
        'action': 'export',
        'personale_id_uuid': sel['id_uuid'],
      });
      final archive = Archive();
      final jsonBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'generated_at': out['generated_at'],
          'personale_id_uuid': out['personale_id_uuid'],
          'data': out['data'],
          'files': [
            for (final f in (out['files'] as List? ?? const []))
              {
                'bucket': (f as Map)['bucket'],
                'path': f['path'],
                'source': f['source'],
              },
          ],
        }),
      );
      archive.addFile(ArchiveFile('dati.json', jsonBytes.length, jsonBytes));
      var missing = 0;
      for (final f in (out['files'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(f as Map);
        final url = m['url']?.toString();
        if (url == null || url.isEmpty) {
          missing++;
          continue;
        }
        try {
          final r = await http.get(Uri.parse(url));
          if (r.statusCode == 200) {
            final name = 'file/${m['bucket']}/${m['path']}';
            archive.addFile(ArchiveFile(name, r.bodyBytes.length, r.bodyBytes));
          } else {
            missing++;
          }
        } catch (_) {
          missing++;
        }
      }
      final zip = ZipEncoder().encode(archive);
      if (zip == null) throw Exception('ZIP non generato');
      final nome = _safeName((sel['full_name'] ?? 'dipendente').toString());
      await FileSaver.instance.saveFile(
        name: 'export_dati_$nome',
        bytes: Uint8List.fromList(zip),
        ext: 'zip',
        mimeType: MimeType.other,
      );
      _snack(missing == 0
          ? 'Esportazione completata.'
          : 'Esportazione completata ($missing file non scaricati).');
    } catch (e) {
      _snack('Esportazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purge() async {
    final sel = _selected;
    if (sel == null) return;
    if (!_canWrite) {
      await showAdminVistaReadOnlyDialog(context);
      return;
    }
    final name = (sel['full_name'] ?? '').toString().trim();
    final confirmCtrl = TextEditingController();
    var includeSigned = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Cancellare i dati del dipendente?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verranno eliminati in modo definitivo per «$name»:\n'
                  '• visite mediche (programmazione e RFI) con i PDF\n'
                  '• assenze\n'
                  '• attestati UQSA con i file\n'
                  '• posizioni GPS (buoni pasto e viaggi mezzi)\n'
                  '• token notifiche del dispositivo\n\n'
                  'Prima esporta i dati se servono. Verifica gli obblighi di '
                  'conservazione (es. documenti sulla sicurezza). Account e '
                  'anagrafica si eliminano poi da «Gestione dipendenti».',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeSigned,
                  onChanged: (v) => setD(() => includeSigned = v ?? false),
                  title: const Text('Elimina anche i PDF dei documenti firmati'),
                ),
                const SizedBox(height: 8),
                Text('Per confermare scrivi il nome: $name'),
                TextField(controller: confirmCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx)
                  .pop(confirmCtrl.text.trim().toLowerCase() == name.toLowerCase()),
              child: const Text('Cancella definitivamente'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final out = await _invoke({
        'action': 'purge',
        'personale_id_uuid': sel['id_uuid'],
        'include_signed_documents': includeSigned,
      });
      final report = Map<String, dynamic>.from(out['report'] as Map? ?? {});
      setState(() => _lastReport = report.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n'));
      _snack('Cancellazione completata.');
    } catch (e) {
      _snack('Cancellazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _personale.where((p) {
      if (_filter.isEmpty) return true;
      return (p['full_name'] ?? '')
          .toString()
          .toLowerCase()
          .contains(_filter.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy dipendente')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Esporta tutti i dati di un dipendente (richiesta di accesso '
                  'o portabilità) oppure cancellali (richiesta di '
                  'cancellazione o fine del rapporto).',
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Cerca dipendente',
                  ),
                  onChanged: (v) => setState(() => _filter = v.trim()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: filtered.any(
                          (p) => p['id_uuid']?.toString() == _selectedId)
                      ? _selectedId
                      : null,
                  hint: const Text('Seleziona dipendente'),
                  items: [
                    for (final p in filtered)
                      DropdownMenuItem(
                        value: p['id_uuid']?.toString(),
                        child: Text(
                          '${p['full_name'] ?? ''}'
                          '${p['active'] == false ? ' (disattivato)' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedId = v;
                    _lastReport = null;
                  }),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || _selectedId == null ? null : _export,
                      icon: const Icon(Icons.download),
                      label: const Text('Esporta dati (ZIP)'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: _busy || _selectedId == null ? null : _purge,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Cancella dati'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_lastReport != null) ...[
                  const SizedBox(height: 16),
                  Text('Esito:\n$_lastReport'),
                ],
              ],
            ),
    );
  }
}
