import 'package:flutter/material.dart';

import '../services/formazione_dlgs_strutture_service.dart';
import 'struttura_link_cell.dart';

/// Selettore struttura D.Lgs. 81/08 (nome, indirizzo, Maps, email).
class DlgsStrutturaSelector extends StatelessWidget {
  const DlgsStrutturaSelector({
    super.key,
    required this.strutture,
    required this.selectedId,
    required this.onChanged,
    this.onlineMode = false,
    this.onlineLinkController,
    this.readOnly = false,
    this.onOpenLinkFailed,
  });

  final List<Map<String, dynamic>> strutture;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>?>? onChanged;
  final bool onlineMode;
  final TextEditingController? onlineLinkController;
  final bool readOnly;
  final VoidCallback? onOpenLinkFailed;

  static String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    if (onlineMode) {
      final link = _s(onlineLinkController?.text);
      if (readOnly) {
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Link corso (online)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          child: link.isEmpty
              ? const Text('-')
              : StrutturaLinkCell(
                  link: link,
                  compact: true,
                  onOpenFailed: onOpenLinkFailed,
                ),
        );
      }
      return TextField(
        controller: onlineLinkController,
        decoration: const InputDecoration(
          labelText: 'Link corso (online)',
          hintText: 'URL del corso online',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );
    }

    final active = strutture.where((s) => s['active'] != false).toList();
    final ids = active.map((s) => _s(s['id_uuid'])).where((id) => id.isNotEmpty);
    final value = selectedId != null && ids.contains(selectedId) ? selectedId : null;
    final selected = FormazioneDlgsStruttureService.findById(active, value);

    if (readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadonlyLine(label: 'Struttura', value: _s(selected?['nome'])),
          _ReadonlyLine(label: 'Indirizzo', value: _s(selected?['indirizzo'])),
          _ReadonlyLine(label: 'Email', value: _s(selected?['email_outlook'])),
          if (_s(selected?['maps_link']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: StrutturaLinkCell(
                link: _s(selected?['maps_link']),
                onOpenFailed: onOpenLinkFailed,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: const InputDecoration(
            labelText: 'Struttura (in presenza)',
            hintText: 'Seleziona struttura registrata',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('- Nessuna -'),
            ),
            ...active.map(
              (s) => DropdownMenuItem<String>(
                value: _s(s['id_uuid']),
                child: Text(_s(s['nome'])),
              ),
            ),
          ],
          onChanged: onChanged == null
              ? null
              : (id) {
                  onChanged!(FormazioneDlgsStruttureService.findById(active, id));
                },
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Text(
            _s(selected['indirizzo']),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF455A64),
                ),
          ),
          if (_s(selected['email_outlook']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _s(selected['email_outlook']),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF546E7A),
                  ),
            ),
          ],
          if (_s(selected['maps_link']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: StrutturaLinkCell(
                link: _s(selected['maps_link']),
                onOpenFailed: onOpenLinkFailed,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ReadonlyLine extends StatelessWidget {
  const _ReadonlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

/// Riga compatta tabella programmazione D.Lgs.
class DlgsStrutturaTableCell extends StatelessWidget {
  const DlgsStrutturaTableCell({
    super.key,
    required this.row,
    this.onOpenLinkFailed,
    this.compact = false,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onOpenLinkFailed;
  final bool compact;

  static String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final nome = _s(row['struttura_nome']);
    final indirizzo = _s(row['struttura_indirizzo']);
    final link = _s(row['struttura_link']);
    final modalita = _s(row['modalita']).toLowerCase();

    if (modalita == 'online') {
      return StrutturaLinkCell(
        link: link,
        compact: compact,
        onOpenFailed: onOpenLinkFailed,
      );
    }

    if (nome.isEmpty && indirizzo.isEmpty && link.isEmpty) {
      return const Text('-');
    }

    final tooltipLines = <String>[
      if (nome.isNotEmpty) nome,
      if (indirizzo.isNotEmpty) indirizzo,
      if (_s(row['struttura_email']).isNotEmpty) _s(row['struttura_email']),
      if (link.isNotEmpty) link,
    ];

    if (compact) {
      final primary = nome.isNotEmpty ? nome : indirizzo;
      return Tooltip(
        message: tooltipLines.join('\n'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            if (link.isNotEmpty) ...[
              const SizedBox(width: 4),
              StrutturaLinkCell(
                link: link,
                compact: true,
                onOpenFailed: onOpenLinkFailed,
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (nome.isNotEmpty)
          Text(
            nome,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        if (indirizzo.isNotEmpty)
          Text(
            indirizzo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        if (link.isNotEmpty)
          StrutturaLinkCell(
            link: link,
            compact: true,
            onOpenFailed: onOpenLinkFailed,
          ),
      ],
    );
  }
}
