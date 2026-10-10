import 'package:flutter/material.dart';

import '../services/pos_commessa_dipendente_service.dart';

/// Selettore commessa condiviso per import da hub.
Future<String?> pickCommessaForImport(BuildContext context) async {
  final commesse = await PosCommessaDipendenteService.loadCommesseAttive();
  if (!context.mounted) return null;
  if (commesse.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nessuna commessa attiva. Importa prima le commesse '
          'dalla sezione Amministrazione.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
    return null;
  }
  final sorted = commesse.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  String? selected = sorted.first.key;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Seleziona commessa'),
      content: DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: const InputDecoration(
          labelText: 'Commessa',
          border: OutlineInputBorder(),
        ),
        items: sorted
            .map(
              (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
            )
            .toList(),
        onChanged: (v) => selected = v,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, selected),
          child: const Text('Continua'),
        ),
      ],
    ),
  );
}

Future<bool> confirmImportSummary(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importa')),
      ],
    ),
  );
  return ok == true;
}
