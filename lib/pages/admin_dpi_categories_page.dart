import 'package:flutter/material.dart';
import '../services/dpi_categories_service.dart';
import '../services/confirm_sound_service.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminDpiCategoriesPage extends StatefulWidget {
  const AdminDpiCategoriesPage({super.key});

  @override
  State<AdminDpiCategoriesPage> createState() => _AdminDpiCategoriesPageState();
}

class _AdminDpiCategoriesPageState extends State<AdminDpiCategoriesPage> {
  bool _loading = true;
  bool _saving = false;
  String _query = '';
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final TextEditingController _newCategoryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await DpiCategoriesService.listAll();
      if (!mounted) return;
      setState(() => _rows = data);
    } catch (e) {
      _snack('Errore caricamento categorie: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) {
      ConfirmSoundService.play();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : null),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((r) => (r['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  Future<void> _addCategory() async {
    final name = _newCategoryCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await DpiCategoriesService.addCategory(name);
      _newCategoryCtrl.clear();
      await _load();
      _snack('Categoria aggiunta');
    } catch (e) {
      _snack('Errore aggiunta categoria: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row, bool value) async {
    final name = (row['name'] ?? '').toString();
    if (name.isEmpty) return;
    try {
      await DpiCategoriesService.setActive(name: name, active: value);
      await _load();
    } catch (e) {
      _snack('Errore aggiornamento stato: $e', isError: true);
    }
  }

  Future<void> _rename(Map<String, dynamic> row) async {
    final oldName = (row['name'] ?? '').toString();
    if (oldName.isEmpty) return;
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina categoria'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nome categoria',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    try {
      await DpiCategoriesService.renameCategory(oldName: oldName, newName: newName);
      await _load();
      _snack('Categoria rinominata');
    } catch (e) {
      _snack('Errore rinomina categoria: $e', isError: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final name = (row['name'] ?? '').toString();
    if (name.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina categoria'),
        content: Text('Confermi eliminazione di "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DpiCategoriesService.deleteCategory(name);
      await _load();
      _snack('Categoria eliminata');
    } catch (e) {
      _snack('Errore eliminazione categoria: $e', isError: true);
    }
  }

  Widget _rowCard(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString();
    final active = row['active'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: active,
                  onChanged: (v) => _toggleActive(row, v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _rename(row),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Rinomina'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _delete(row),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Elimina'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final isMobileLayout = useMobileUi(context) || useCompactPageLayout(context);
    return Scaffold(
      appBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(
          title: 'Categorie DPI',
          desktopLogoSize: 36,
        ),
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: isMobileLayout ? cronosFullFieldWidth(context, horizontalMargin: 24) : 320,
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            labelText: 'Cerca categoria',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobileLayout ? cronosFullFieldWidth(context, horizontalMargin: 24) : 320,
                        child: TextField(
                          controller: _newCategoryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nuova categoria',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (isMobileLayout)
                        SizedBox(
                          width: cronosFullFieldWidth(context, horizontalMargin: 24),
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _addCategory,
                            icon: const Icon(Icons.add),
                            label: const Text('Aggiungi'),
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _saving ? null : _addCategory,
                          icon: const Icon(Icons.add),
                          label: const Text('Aggiungi'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('Nessuna categoria trovata'))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) => _rowCard(rows[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
