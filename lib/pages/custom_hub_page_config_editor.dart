import 'package:flutter/material.dart';

import '../hub/custom_hub_page_config.dart';
import '../services/app_ui_layout_service.dart';

Future<CustomHubPageConfig?> showCustomHubPageConfigEditor(
  BuildContext context, {
  required String layoutKey,
  required String pageLabel,
  required CustomHubPageConfig initial,
}) {
  return showDialog<CustomHubPageConfig>(
    context: context,
    builder: (ctx) => _CustomHubPageConfigEditorDialog(
      layoutKey: layoutKey,
      pageLabel: pageLabel,
      initial: initial,
    ),
  );
}

class _CustomHubPageConfigEditorDialog extends StatefulWidget {
  const _CustomHubPageConfigEditorDialog({
    required this.layoutKey,
    required this.pageLabel,
    required this.initial,
  });

  final String layoutKey;
  final String pageLabel;
  final CustomHubPageConfig initial;

  @override
  State<_CustomHubPageConfigEditorDialog> createState() =>
      _CustomHubPageConfigEditorDialogState();
}

class _CustomHubPageConfigEditorDialogState
    extends State<_CustomHubPageConfigEditorDialog> {
  late List<CustomHubFormField> _formFields;
  late List<CustomHubTableColumn> _columns;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _formFields = List<CustomHubFormField>.from(widget.initial.formFields);
    _columns = List<CustomHubTableColumn>.from(widget.initial.tableColumns);
  }

  Future<String?> _editLabel(String current) async {
    final ctrl = TextEditingController(text: current);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica etichetta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return next;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = CustomHubPageConfig(
        formFields: _formFields,
        tableColumns: _columns,
      );
      await AppUiLayoutService.updateCustomHubPageConfig(
        layoutKey: widget.layoutKey,
        pageConfig: config,
      );
      if (!mounted) return;
      Navigator.pop(context, config);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _configList<T>({
    required List<T> items,
    required String Function(T) idOf,
    required String Function(T) labelOf,
    required bool Function(T) visibleOf,
    required void Function(int, T) onUpdate,
    required void Function(int, int) onReorder,
  }) {
    return ReorderableListView.builder(
      itemCount: items.length,
      // ignore: deprecated_member_use
      onReorder: onReorder,
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          key: ValueKey<String>(idOf(item)),
          leading: const Icon(Icons.drag_handle),
          title: Text(labelOf(item)),
          subtitle: Text(idOf(item)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Rinomina',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final label = await _editLabel(labelOf(item));
                  if (label == null || label.isEmpty || !mounted) return;
                  setState(() {
                    if (item is CustomHubFormField) {
                      onUpdate(i, item.copyWith(label: label) as T);
                    } else if (item is CustomHubTableColumn) {
                      onUpdate(i, item.copyWith(label: label) as T);
                    }
                  });
                },
              ),
              Switch(
                value: visibleOf(item),
                onChanged: (v) {
                  setState(() {
                    if (item is CustomHubFormField) {
                      onUpdate(i, item.copyWith(visible: v) as T);
                    } else if (item is CustomHubTableColumn) {
                      onUpdate(i, item.copyWith(visible: v) as T);
                    }
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Configura — ${widget.pageLabel}'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Form e pulsanti'),
                  Tab(text: 'Colonne tabella'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _configList<CustomHubFormField>(
                      items: _formFields,
                      idOf: (f) => f.id,
                      labelOf: (f) => f.label,
                      visibleOf: (f) => f.visible,
                      onUpdate: (i, f) => _formFields[i] = f,
                      onReorder: (o, n) {
                        setState(() {
                          if (n > o) n--;
                          final item = _formFields.removeAt(o);
                          _formFields.insert(n, item);
                        });
                      },
                    ),
                    _configList<CustomHubTableColumn>(
                      items: _columns,
                      idOf: (c) => c.id,
                      labelOf: (c) => c.label,
                      visibleOf: (c) => c.visible,
                      onUpdate: (i, c) => _columns[i] = c,
                      onReorder: (o, n) {
                        setState(() {
                          if (n > o) n--;
                          final item = _columns.removeAt(o);
                          _columns.insert(n, item);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}
