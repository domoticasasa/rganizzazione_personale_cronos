import 'package:flutter/material.dart';

import '../utils/casetta_ps_materiale.dart';

/// Checklist materiali Allegato 1 / 2: scadenza = presente, chip Assente altrimenti.
class CasettaPsMaterialeChecklist extends StatefulWidget {
  const CasettaPsMaterialeChecklist({
    super.key,
    required this.righe,
    required this.onChanged,
    this.enabled = true,
  });

  final List<CasettaPsMaterialeRiga> righe;
  final void Function(List<CasettaPsMaterialeRiga> righe) onChanged;
  final bool enabled;

  @override
  State<CasettaPsMaterialeChecklist> createState() =>
      _CasettaPsMaterialeChecklistState();
}

class _CasettaPsMaterialeChecklistState extends State<CasettaPsMaterialeChecklist> {
  void _notify() {
    widget.onChanged(List<CasettaPsMaterialeRiga>.from(widget.righe));
    setState(() {});
  }

  void _setAllAssente() {
    if (!widget.enabled) return;
    for (final r in widget.righe) {
      r.presente = false;
      r.scadenzaMmYyyy = '';
    }
    _notify();
  }

  void _markAssente(CasettaPsMaterialeRiga r) {
    r.presente = false;
    r.scadenzaMmYyyy = '';
    _notify();
  }

  void _onScadenzaChanged(CasettaPsMaterialeRiga r, String v) {
    r.scadenzaMmYyyy = v;
    r.presente = v.trim().isNotEmpty;
    widget.onChanged(List<CasettaPsMaterialeRiga>.from(widget.righe));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.righe.isEmpty) {
      return const Text(
        'Seleziona il tipo di cassetta (Allegato 1 o 2) per caricare l\'elenco materiali.',
      );
    }

    final presenti = widget.righe.where((r) => r.presente).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Materiali presenti: $presenti/${widget.righe.length}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (widget.enabled)
              TextButton(
                onPressed: _setAllAssente,
                child: const Text('Nessuno'),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Inserisci la scadenza se il materiale è presente; altrimenti usa «Assente».',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ...widget.righe.map((r) {
          final assente = !r.presente;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.descrizione,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ChoiceChip(
                      label: const Text('Assente'),
                      avatar: const Icon(Icons.cancel_outlined, size: 16),
                      selected: assente,
                      selectedColor: Colors.red.withValues(alpha: 0.14),
                      onSelected: widget.enabled
                          ? (_) => _markAssente(r)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey(
                      'scad_${r.id}_${r.presente}_${r.scadenzaMmYyyy}',
                    ),
                    enabled: widget.enabled,
                    initialValue: r.scadenzaMmYyyy,
                    decoration: const InputDecoration(
                      labelText: 'Scadenza (MM/AAAA)',
                      hintText: 'es. 06/2026',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => _onScadenzaChanged(r, v),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
