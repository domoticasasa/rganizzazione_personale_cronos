import 'package:flutter/material.dart';

import '../services/confirm_sound_service.dart';
import '../services/vestiario_articoli_service.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/responsive.dart';
import '../widgets/classic_app_bar_chrome.dart';

class AdminVestiarioCategoriePage extends StatefulWidget {
  const AdminVestiarioCategoriePage({super.key});

  @override
  State<AdminVestiarioCategoriePage> createState() =>
      _AdminVestiarioCategoriePageState();
}

class _AdminVestiarioCategoriePageState
    extends State<AdminVestiarioCategoriePage> {
  bool _loading = true;
  bool _saving = false;
  String _query = '';
  List<VestiarioArticoloDef> _rows = <VestiarioArticoloDef>[];
  final TextEditingController _newLabelCtrl = TextEditingController();

  static const List<String> _sizeTypes = <String>[
    'top',
    'trouser',
    'shoe',
    'glove',
    'unit',
    'none',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await VestiarioArticoliService.refresh();
      if (!mounted) return;
      setState(() {
        _rows = List<VestiarioArticoloDef>.from(VestiarioArticoliService.all)
          ..sort((a, b) {
            final c = a.sortOrder.compareTo(b.sortOrder);
            if (c != 0) return c;
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });
      });
    } catch (e) {
      _snack('Errore caricamento categorie: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (!isError) ConfirmSoundService.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  List<VestiarioArticoloDef> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where(
          (r) =>
              r.label.toLowerCase().contains(q) ||
              r.key.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<_ArticoloFormData?> _showArticoloFormDialog({
    required String title,
    required String initialLabel,
    String initialSizeType = 'top',
    bool initialInMagazzino = false,
    bool initialInAssegnazione = true,
    bool initialStagioneEstivo = true,
    bool initialStagioneInvernale = true,
    bool initialModelloUnico = false,
    bool initialIsDpiIii = false,
    String confirmLabel = 'Salva',
  }) async {
    final labelCtrl = TextEditingController(text: initialLabel);
    var sizeType = initialSizeType;
    var inMagazzino = initialInMagazzino;
    var inAssegnazione = initialInAssegnazione;
    var estivo = initialStagioneEstivo;
    var invernale = initialStagioneInvernale;
    var modelloUnico = initialModelloUnico;
    var isDpiIii = initialIsDpiIii;

    final result = await showDialog<_ArticoloFormData>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome categoria',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sizeType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo taglia',
                      border: OutlineInputBorder(),
                    ),
                    items: _sizeTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDlg(() => sizeType = v ?? 'top'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Dove compare la categoria',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Magazzino / inventario'),
                    subtitle: const Text('Visibile in inventario e fabbisogno'),
                    value: inMagazzino,
                    onChanged: (v) => setDlg(() => inMagazzino = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Assegnazione vestiario'),
                    subtitle: const Text('Nel menu Aggiungi DPI'),
                    value: inAssegnazione,
                    onChanged: (v) => setDlg(() => inAssegnazione = v),
                  ),
                  const Divider(height: 16),
                  const Text(
                    'Stagioni e fabbisogno',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Estivo'),
                    value: estivo,
                    onChanged: (v) => setDlg(() => estivo = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invernale'),
                    value: invernale,
                    onChanged: (v) => setDlg(() => invernale = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Modello unico'),
                    subtitle: const Text('Un solo fabbisogno annuo (no doppio conteggio)'),
                    value: modelloUnico,
                    onChanged: (v) => setDlg(() => modelloUnico = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('DPI III categoria'),
                    subtitle: const Text('Inventario unitario (elmetto, cordini…)'),
                    value: isDpiIii,
                    onChanged: (v) => setDlg(() {
                      isDpiIii = v;
                      if (v) {
                        inMagazzino = true;
                        sizeType = 'unit';
                      }
                    }),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(
                  ctx,
                  _ArticoloFormData(
                    label: label,
                    sizeType: sizeType,
                    inMagazzino: inMagazzino,
                    inAssegnazione: inAssegnazione,
                    stagioneEstivo: estivo,
                    stagioneInvernale: invernale,
                    modelloUnico: modelloUnico,
                    isDpiIii: isDpiIii,
                  ),
                );
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    labelCtrl.dispose();
    return result;
  }

  Future<void> _addArticolo() async {
    final form = await _showArticoloFormDialog(
      title: 'Nuova categoria vestiario',
      initialLabel: _newLabelCtrl.text.trim(),
      confirmLabel: 'Aggiungi',
    );
    if (form == null) return;

    setState(() => _saving = true);
    try {
      await VestiarioArticoliService.addArticolo(
        label: form.label,
        sizeType: form.sizeType,
        inMagazzino: form.inMagazzino,
        inAssegnazione: form.inAssegnazione,
        stagioneEstivo: form.stagioneEstivo,
        stagioneInvernale: form.stagioneInvernale,
        modelloUnico: form.modelloUnico,
        isDpiIii: form.isDpiIii,
      );
      _newLabelCtrl.clear();
      await _load();
      _snack('Categoria aggiunta e sincronizzata');
    } catch (e) {
      _snack('Errore aggiunta: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(VestiarioArticoloDef row, bool value) async {
    try {
      await VestiarioArticoliService.setActive(
        articoloKey: row.key,
        active: value,
      );
      await _load();
      _snack(value ? 'Categoria attivata' : 'Categoria disattivata');
    } catch (e) {
      _snack('Errore aggiornamento: $e', isError: true);
    }
  }

  Future<void> _editArticolo(VestiarioArticoloDef row) async {
    final form = await _showArticoloFormDialog(
      title: 'Modifica · ${row.key}',
      initialLabel: row.label,
      initialSizeType: row.sizeType,
      initialInMagazzino: row.inMagazzino,
      initialInAssegnazione: row.inAssegnazione,
      initialStagioneEstivo: row.stagioneEstivo,
      initialStagioneInvernale: row.stagioneInvernale,
      initialModelloUnico: row.modelloUnico,
      initialIsDpiIii: row.isDpiIii,
    );
    if (form == null) return;

    try {
      await VestiarioArticoliService.updateArticolo(
        row.copyWith(
          label: form.label,
          sizeType: form.sizeType,
          inMagazzino: form.inMagazzino,
          inAssegnazione: form.inAssegnazione,
          stagioneEstivo: form.stagioneEstivo,
          stagioneInvernale: form.stagioneInvernale,
          modelloUnico: form.modelloUnico,
          isDpiIii: form.isDpiIii,
        ),
      );
      await _load();
      _snack('Categoria aggiornata');
    } catch (e) {
      _snack('Errore salvataggio: $e', isError: true);
    }
  }

  Future<void> _delete(VestiarioArticoloDef row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina categoria'),
        content: Text(
          'Confermi eliminazione di "${row.label}"?\n'
          'La categoria non comparirà più in magazzino, assegnazione e fabbisogno.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await VestiarioArticoliService.deleteArticolo(row.key);
      await _load();
      _snack('Categoria eliminata');
    } catch (e) {
      _snack('Errore eliminazione: $e', isError: true);
    }
  }

  Widget _chip(String text, {Color? color}) {
    return Chip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withValues(alpha: 0.15),
      side: BorderSide(color: color ?? Colors.grey),
    );
  }

  Widget _rowCard(VestiarioArticoloDef row) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        row.key,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: row.active,
                  onChanged: (v) => _toggleActive(row, v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (row.inMagazzino) _chip('Magazzino', color: Colors.blue),
                if (row.inAssegnazione) _chip('Assegnazione', color: Colors.teal),
                if (row.stagioneEstivo) _chip('Estivo', color: Colors.orange),
                if (row.stagioneInvernale) _chip('Invernale', color: Colors.indigo),
                if (row.modelloUnico) _chip('Modello unico'),
                if (row.isDpiIii) _chip('DPI III', color: Colors.red),
                _chip('Taglia: ${row.sizeType}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editArticolo(row),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifica'),
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
    final isMobileLayout =
        useMobileUi(context) || useCompactPageLayout(context);

    return buildGestoproAwarePage(
      context: context,
      title: 'Categorie Vestiario',
      classicAppBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const Text('Categorie Vestiario'),
          actions: [
            IconButton(
              tooltip: 'Aggiorna',
              onPressed: _loading || _saving ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Gestisci le categorie sincronizzate con magazzino, '
                    'assegnazione vestiario e fabbisogno taglie.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: isMobileLayout
                            ? cronosFullFieldWidth(context, horizontalMargin: 24)
                            : 280,
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            labelText: 'Cerca',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobileLayout
                            ? cronosFullFieldWidth(context, horizontalMargin: 24)
                            : 280,
                        child: TextField(
                          controller: _newLabelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nuova categoria',
                            hintText: 'Nome rapido (opzionale)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addArticolo(),
                        ),
                      ),
                      if (isMobileLayout)
                        SizedBox(
                          width: cronosFullFieldWidth(
                            context,
                            horizontalMargin: 24,
                          ),
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _addArticolo,
                            icon: const Icon(Icons.add),
                            label: const Text('Aggiungi'),
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _saving ? null : _addArticolo,
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

class _ArticoloFormData {
  final String label;
  final String sizeType;
  final bool inMagazzino;
  final bool inAssegnazione;
  final bool stagioneEstivo;
  final bool stagioneInvernale;
  final bool modelloUnico;
  final bool isDpiIii;

  const _ArticoloFormData({
    required this.label,
    required this.sizeType,
    required this.inMagazzino,
    required this.inAssegnazione,
    required this.stagioneEstivo,
    required this.stagioneInvernale,
    required this.modelloUnico,
    required this.isDpiIii,
  });
}
