import 'dart:async';

import 'package:flutter/material.dart';

import '../hub/hub_icon_catalog.dart';

/// Libreria icone con ricerca in italiano.
Future<int?> showHubIconPickerSheet({
  required BuildContext context,
  int? selectedCodepoint,
  IconData? fallbackIcon,
}) {
  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _HubIconPickerSheet(
      selectedCodepoint: selectedCodepoint,
      fallbackIcon: fallbackIcon,
    ),
  );
}

class _HubIconPickerSheet extends StatefulWidget {
  const _HubIconPickerSheet({
    this.selectedCodepoint,
    this.fallbackIcon,
  });

  final int? selectedCodepoint;
  final IconData? fallbackIcon;

  @override
  State<_HubIconPickerSheet> createState() => _HubIconPickerSheetState();
}

class _HubIconPickerSheetState extends State<_HubIconPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;
  List<HubIconCatalogEntry> _results = HubIconCatalog.all;

  @override
  void initState() {
    super.initState();
    _results = HubIconCatalog.all;
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _query = v;
        _results = HubIconCatalog.search(v);
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scegli icona',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText:
                      'Cerca in italiano o inglese (es. treno, hotel, alert…)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _query = '';
                              _results = HubIconCatalog.all;
                            });
                          },
                        ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (widget.fallbackIcon != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, null),
                  icon: Icon(widget.fallbackIcon),
                  label: const Text('Ripristina icona predefinita'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '${results.length} icone',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'Nessuna icona per «$_query»',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 56,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        final selected =
                            widget.selectedCodepoint == entry.codepoint;
                        return Material(
                          color: selected
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                Navigator.pop(context, entry.codepoint),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    entry.icon,
                                    size: 24,
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.labelIt,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      height: 1.0,
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
