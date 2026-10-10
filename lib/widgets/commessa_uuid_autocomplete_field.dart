import 'package:flutter/material.dart';

/// Commessa con ricerca per nome: digita, scegli dalla lista, oppure azzera.
class CommessaUuidAutocompleteField extends StatefulWidget {
  final Map<String, String> commesseByUuid;
  final String? selectedUuid;
  final ValueChanged<String?> onSelected;
  final bool readOnly;
  final String labelText;
  final int maxOptions;

  const CommessaUuidAutocompleteField({
    super.key,
    required this.commesseByUuid,
    required this.selectedUuid,
    required this.onSelected,
    this.readOnly = false,
    this.labelText = 'Commessa (scrivi e seleziona)',
    this.maxOptions = 50,
  });

  @override
  State<CommessaUuidAutocompleteField> createState() =>
      _CommessaUuidAutocompleteFieldState();
}

class _CommessaUuidAutocompleteFieldState
    extends State<CommessaUuidAutocompleteField> {
  String? _syncedUuid;

  List<MapEntry<String, String>> get _sortedItems {
    final items = widget.commesseByUuid.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return items;
  }

  String _labelForUuid(String? uuid) {
    if (uuid == null || uuid.trim().isEmpty) return '';
    return widget.commesseByUuid[uuid] ?? uuid;
  }

  Iterable<MapEntry<String, String>> _filterOptions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _sortedItems.take(widget.maxOptions);
    return _sortedItems
        .where((e) => e.value.toLowerCase().contains(q))
        .take(widget.maxOptions);
  }

  @override
  void initState() {
    super.initState();
    _syncedUuid = widget.selectedUuid;
  }

  @override
  void didUpdateWidget(CommessaUuidAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedUuid != oldWidget.selectedUuid) {
      _syncedUuid = widget.selectedUuid;
    }
  }

  void _clear(TextEditingController fieldCtrl) {
    fieldCtrl.clear();
    _syncedUuid = null;
    widget.onSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _labelForUuid(widget.selectedUuid);

    if (widget.readOnly) {
      return TextField(
        readOnly: true,
        controller: TextEditingController(text: displayText),
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }

    return Autocomplete<MapEntry<String, String>>(
      key: ValueKey<String>('commessa-field-${widget.selectedUuid ?? ''}'),
      initialValue: TextEditingValue(text: displayText),
      displayStringForOption: (opt) => opt.value,
      optionsBuilder: (textEditingValue) =>
          _filterOptions(textEditingValue.text),
      onSelected: (opt) {
        _syncedUuid = opt.key;
        widget.onSelected(opt.key);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(opt.value),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, fieldCtrl, focusNode, onFieldSubmitted) {
        if (widget.selectedUuid != _syncedUuid) {
          _syncedUuid = widget.selectedUuid;
          final label = displayText;
          if (fieldCtrl.text != label) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (widget.selectedUuid == _syncedUuid) {
                fieldCtrl.value = TextEditingValue(
                  text: label,
                  selection: TextSelection.collapsed(offset: label.length),
                );
              }
            });
          }
        }

        return TextField(
          controller: fieldCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: fieldCtrl,
              builder: (_, value, _) {
                if (value.text.trim().isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Azzera commessa',
                  icon: const Icon(Icons.clear),
                  onPressed: () => _clear(fieldCtrl),
                );
              },
            ),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
    );
  }
}
