import 'package:flutter/material.dart';

/// Editor dinamico per righe aggiuntive sul tesserino.
class TesserinoRigheExtraEditor extends StatefulWidget {
  const TesserinoRigheExtraEditor({
    super.key,
    required this.controllers,
    required this.onChanged,
    this.hintText = 'es. QUALIFICA: OPERAIO SPECIALIZZATO',
  });

  final List<TextEditingController> controllers;
  final VoidCallback onChanged;
  final String hintText;

  @override
  State<TesserinoRigheExtraEditor> createState() =>
      _TesserinoRigheExtraEditorState();
}

class _TesserinoRigheExtraEditorState extends State<TesserinoRigheExtraEditor> {
  void _addLine() {
    setState(() {
      widget.controllers.add(TextEditingController());
    });
    widget.onChanged();
  }

  void _removeLine(int index) {
    setState(() {
      widget.controllers[index].dispose();
      widget.controllers.removeAt(index);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Righe aggiuntive sul tesserino',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi riga'),
            ),
          ],
        ),
        if (widget.controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nessuna riga aggiuntiva. Usa «Aggiungi riga» per la commessa.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < widget.controllers.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controllers[i],
                  decoration: InputDecoration(
                    labelText: 'Riga ${i + 1}',
                    hintText: widget.hintText,
                  ),
                  maxLines: 2,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              IconButton(
                tooltip: 'Rimuovi riga',
                onPressed: () => _removeLine(i),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

List<TextEditingController> tesserinoRigheControllersFromLines(
  List<String> lines,
) {
  if (lines.isEmpty) return [];
  return lines.map((l) => TextEditingController(text: l)).toList();
}

void disposeTesserinoRigheControllers(List<TextEditingController> controllers) {
  for (final c in controllers) {
    c.dispose();
  }
}

List<String> linesFromTesserinoRigheControllers(
  List<TextEditingController> controllers,
) {
  return controllers
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
