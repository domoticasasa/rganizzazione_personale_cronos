import 'package:flutter/material.dart';

import '../hub/custom_hub_structure_type.dart';
import '../widgets/premium_glass_hub.dart';

class CustomHubCreateRequest {
  const CustomHubCreateRequest({required this.label});

  final String label;
}

/// Dialogo minimale: solo nome pagina/cartella vuota.
Future<CustomHubCreateRequest?> showCustomHubCreateDialog(
  BuildContext context, {
  bool asFolder = false,
}) {
  return showDialog<CustomHubCreateRequest>(
    context: context,
    builder: (ctx) => _CustomHubCreateDialog(asFolder: asFolder),
  );
}

class _CustomHubCreateDialog extends StatefulWidget {
  const _CustomHubCreateDialog({this.asFolder = false});

  final bool asFolder;

  @override
  State<_CustomHubCreateDialog> createState() => _CustomHubCreateDialogState();
}

class _CustomHubCreateDialogState extends State<_CustomHubCreateDialog> {
  final _nameCtrl = TextEditingController();

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.asFolder
                ? 'Inserisci il nome della cartella.'
                : 'Inserisci il nome della pagina.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, CustomHubCreateRequest(label: name));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: PremiumGlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PremiumGlassHubTheme.brandBlue
                          .withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      widget.asFolder
                          ? Icons.create_new_folder_outlined
                          : Icons.note_add_outlined,
                      color: PremiumGlassHubTheme.brandBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.asFolder ? 'Nuova cartella' : 'Nuova pagina',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: PremiumGlassHubTheme.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chiudi',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const SizedBox(
                  width: 64,
                  height: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: PremiumGlassHubTheme.italianGreen,
                        ),
                      ),
                      Expanded(child: ColoredBox(color: Colors.white)),
                      Expanded(
                        child: ColoredBox(
                          color: PremiumGlassHubTheme.italianRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText:
                      widget.asFolder ? 'Nome cartella' : 'Nome pagina',
                  hintText:
                      widget.asFolder ? 'Es. Logistica' : 'Es. Formazione extra',
                  helperText: widget.asFolder
                      ? 'La cartella compare in questa pagina. Poi, in «Riordina», sposta i pulsanti dentro.'
                      : 'La pagina sarà creata vuota: potrai aggiungere pulsanti dopo.',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.55),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: PremiumGlassHubTheme.brandBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text('Crea'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rinomina le etichette delle sezioni (chiavi invariate).
Future<List<CustomHubSlot>?> showRenameCustomHubSlotsDialog(
  BuildContext context, {
  required List<CustomHubSlot> slots,
  required String pageLabel,
}) {
  return showDialog<List<CustomHubSlot>>(
    context: context,
    builder: (ctx) => _RenameCustomHubSlotsDialog(
      slots: slots,
      pageLabel: pageLabel,
    ),
  );
}

class _RenameCustomHubSlotsDialog extends StatefulWidget {
  const _RenameCustomHubSlotsDialog({
    required this.slots,
    required this.pageLabel,
  });

  final List<CustomHubSlot> slots;
  final String pageLabel;

  @override
  State<_RenameCustomHubSlotsDialog> createState() =>
      _RenameCustomHubSlotsDialogState();
}

class _RenameCustomHubSlotsDialogState extends State<_RenameCustomHubSlotsDialog> {
  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.slots
        .map((s) => TextEditingController(text: s.label))
        .toList(growable: false);
  }

  void _submit() {
    final updated = <CustomHubSlot>[];
    for (var i = 0; i < widget.slots.length; i++) {
      final label = _ctrls[i].text.trim();
      if (label.isEmpty) continue;
      updated.add(widget.slots[i].copyWith(label: label));
    }
    if (updated.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Almeno una sezione deve avere un nome.')),
      );
      return;
    }
    Navigator.pop(context, updated);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: PremiumGlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rinomina sezioni — ${widget.pageLabel}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: PremiumGlassHubTheme.navy,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_ctrls.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _ctrls[i],
                        decoration: InputDecoration(
                          labelText: 'Sezione ${i + 1}',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.55),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: PremiumGlassHubTheme.brandBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _submit,
                    child: const Text('Salva'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
