import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/commessa_tesserino_modelli_service.dart';
import '../utils/modify_feedback.dart';
import '../utils/tesserino_helpers.dart';
import '../widgets/commessa_uuid_autocomplete_field.dart';
import '../widgets/tesserino_righe_extra_editor.dart';

class CommessaTesserinoModelliPanel extends StatefulWidget {
  const CommessaTesserinoModelliPanel({
    super.key,
    required this.supa,
  });

  final SupabaseClient supa;

  @override
  State<CommessaTesserinoModelliPanel> createState() =>
      _CommessaTesserinoModelliPanelState();
}

class _CommessaTesserinoModelliPanelState
    extends State<CommessaTesserinoModelliPanel> {
  bool _loading = true;
  Map<String, String> _commesse = const {};
  List<CommessaTesserinoModello> _modelli = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final commesse = await CommessaTesserinoModelliService.loadCommesseMap(
        widget.supa,
      );
      final modelli = await CommessaTesserinoModelliService.loadModelli(
        widget.supa,
      );
      if (!mounted) return;
      setState(() {
        _commesse = commesse;
        _modelli = modelli
          ..sort(
            (a, b) => (a.commessaNome ?? a.commessaIdUuid)
                .toLowerCase()
                .compareTo(
                  (b.commessaNome ?? b.commessaIdUuid).toLowerCase(),
                ),
          );
      });
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Errore caricamento modelli: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editModello({CommessaTesserinoModello? existing}) async {
    String? commessaUuid = existing?.commessaIdUuid;
    final righeControllers = tesserinoRigheControllersFromLines(
      existing?.righeExtra ?? const [''],
    );
    if (righeControllers.isEmpty) {
      righeControllers.add(TextEditingController());
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(
              existing == null
                  ? 'Nuovo modello tesserino'
                  : 'Modifica modello tesserino',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Definisci le righe aggiuntive tipiche per la commessa '
                      '(es. commessa, qualifica, cantiere).',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    CommessaUuidAutocompleteField(
                      commesseByUuid: _commesse,
                      selectedUuid: commessaUuid,
                      labelText: 'Commessa',
                      onSelected: (v) => setLocal(() => commessaUuid = v),
                    ),
                    const SizedBox(height: 12),
                    TesserinoRigheExtraEditor(
                      controllers: righeControllers,
                      hintText: 'es. COMMESSA: Milano-Roma',
                      onChanged: () => setLocal(() {}),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salva modello'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      disposeTesserinoRigheControllers(righeControllers);
      return;
    }

    final commessa = (commessaUuid ?? '').trim();
    if (commessa.isEmpty || !_commesse.containsKey(commessa)) {
      disposeTesserinoRigheControllers(righeControllers);
      if (mounted) {
        ModifyFeedback.error(context, 'Selezionare una commessa valida.');
      }
      return;
    }

    final righe = normalizeTesserinoRigheExtra(
      linesFromTesserinoRigheControllers(righeControllers),
    );
    disposeTesserinoRigheControllers(righeControllers);

    if (righe.isEmpty) {
      if (mounted) {
        ModifyFeedback.error(context, 'Aggiungere almeno una riga al modello.');
      }
      return;
    }

    setState(() => _loading = true);
    try {
      await CommessaTesserinoModelliService.upsertModello(
        supa: widget.supa,
        idUuid: existing?.idUuid,
        commessaIdUuid: commessa,
        righeExtra: righe,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modello salvato')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ModifyFeedback.error(context, 'Salvataggio modello: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteModello(CommessaTesserinoModello modello) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina modello'),
        content: Text(
          'Eliminare il modello tesserino per '
          '${modello.commessaNome ?? modello.commessaIdUuid}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await CommessaTesserinoModelliService.deleteModello(
        supa: widget.supa,
        idUuid: modello.idUuid,
      );
      await _load();
    } catch (e) {
      if (mounted) ModifyFeedback.error(context, 'Eliminazione: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _modelli.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Crea un modello per commessa con le righe aggiuntive '
                  'da stampare sul tesserino.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _editModello(),
                icon: const Icon(Icons.add),
                label: const Text('Nuovo modello'),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _modelli.isEmpty
              ? const Center(
                  child: Text('Nessun modello commessa. Creane uno nuovo.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _modelli.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = _modelli[i];
                    return Card(
                      child: ListTile(
                        title: Text(m.commessaNome ?? m.commessaIdUuid),
                        subtitle: Text(
                          m.righeExtra.join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Modifica',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editModello(existing: m),
                            ),
                            IconButton(
                              tooltip: 'Elimina',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteModello(m),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
