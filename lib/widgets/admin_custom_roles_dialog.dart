import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/app_page_permissions.dart';

String normalizeCustomRoleKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '')
      .replaceAll(RegExp(r'_+'), '_');
}

Future<void> _syncPageRegistryFromAppCatalog(SupabaseClient supa) async {
  try {
    final payload = kAppPagePermissions
        .map((p) => {
              'page_key': p.key,
              'label': p.label,
              'active': true,
            })
        .toList(growable: false);
    if (payload.isEmpty) return;
    await supa.from('app_page_registry').upsert(payload);
  } catch (_) {}
}

/// Chiavi ruoli custom attivi (per dropdown «Ruolo» in Gestione dipendenti).
Future<List<String>> fetchCustomRoleKeys(SupabaseClient supa) async {
  try {
    final rolesRes = await supa
        .from('app_custom_roles')
        .select('role_key')
        .eq('active', true)
        .order('label', ascending: true);
    return (rolesRes as List)
        .map((e) => (Map<String, dynamic>.from(e as Map)['role_key'] ?? '')
            .toString()
            .trim())
        .where((k) => k.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Dialog «Ruoli personalizzati e pagine» (come in produzione).
Future<bool?> showAdminCustomRolesDialog(BuildContext context) async {
  final supa = SupabaseService.client;
  await _syncPageRegistryFromAppCatalog(supa);

  List<Map<String, dynamic>> customRoles = [];
  Map<String, Set<String>> customRolePages = {};
  Map<String, String> pageCatalog = {
    for (final p in kAppPagePermissions) p.key: p.label,
  };

  Future<void> reload() async {
    try {
      final rolesRes = await supa
          .from('app_custom_roles')
          .select('role_key, label, active')
          .eq('active', true)
          .order('label', ascending: true);
      final pagesRes = await supa
          .from('app_custom_role_pages')
          .select('role_key, page_key, can_view')
          .eq('can_view', true);
      final registryRes = await supa
          .from('app_page_registry')
          .select('page_key, label, active')
          .eq('active', true);

      customRoles = List<Map<String, dynamic>>.from(rolesRes as List);
      final pages = List<Map<String, dynamic>>.from(pagesRes as List);
      customRolePages = {};
      pageCatalog = {for (final p in kAppPagePermissions) p.key: p.label};
      for (final row in pages) {
        final roleKey = (row['role_key'] ?? '').toString().trim();
        final pageKey = (row['page_key'] ?? '').toString().trim();
        if (roleKey.isEmpty || pageKey.isEmpty) continue;
        customRolePages.putIfAbsent(roleKey, () => <String>{}).add(pageKey);
        pageCatalog.putIfAbsent(pageKey, () => pageKey);
      }
      for (final row in (registryRes as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final key = (m['page_key'] ?? '').toString().trim();
        final label = (m['label'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        pageCatalog[key] = label.isEmpty ? key : label;
      }
    } catch (_) {}
  }

  await reload();

  final roleLabelCtrl = TextEditingController();
  String? selectedRoleKey =
      customRoles.isNotEmpty ? customRoles.first['role_key']?.toString() : null;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) {
        final selectedPages = selectedRoleKey == null
            ? <String>{}
            : Set<String>.from(customRolePages[selectedRoleKey] ?? <String>{});
        return AlertDialog(
          title: const Text('Ruoli personalizzati e pagine'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roleLabelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nuovo ruolo',
                            hintText: 'es. magazzino',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final label = roleLabelCtrl.text.trim();
                          final roleKey = normalizeCustomRoleKey(label);
                          if (roleKey.isEmpty) return;
                          await supa.from('app_custom_roles').upsert({
                            'role_key': roleKey,
                            'label': label,
                            'active': true,
                          });
                          final registryRows = await supa
                              .from('app_page_registry')
                              .select('page_key')
                              .eq('active', true);
                          final grants = (registryRows as List)
                              .map((r) =>
                                  (r['page_key'] ?? '').toString().trim())
                              .where((k) => k.isNotEmpty)
                              .map((k) => {
                                    'role_key': roleKey,
                                    'page_key': k,
                                    'can_view': true,
                                  })
                              .toList(growable: false);
                          if (grants.isNotEmpty) {
                            await supa.from('app_custom_role_pages').upsert(grants);
                          }
                          roleLabelCtrl.clear();
                          await reload();
                          setLocalState(() => selectedRoleKey = roleKey);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Aggiungi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: customRoles.any((r) =>
                            (r['role_key'] ?? '').toString() == selectedRoleKey)
                        ? selectedRoleKey
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Ruolo da configurare',
                    ),
                    items: customRoles
                        .map(
                          (r) => DropdownMenuItem<String>(
                            value: (r['role_key'] ?? '').toString(),
                            child: Text(
                              '${(r['label'] ?? '').toString()} (${(r['role_key'] ?? '').toString()})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocalState(() => selectedRoleKey = v),
                  ),
                  const SizedBox(height: 10),
                  if (selectedRoleKey != null)
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: (pageCatalog.entries.toList()
                            ..sort((a, b) => a.value
                                .toLowerCase()
                                .compareTo(b.value.toLowerCase())))
                          .map((entry) {
                        final pageKey = entry.key;
                        final checked = selectedPages.contains(pageKey);
                        return FilterChip(
                          selected: checked,
                          label: Text(entry.value),
                          onSelected: (v) async {
                            if (selectedRoleKey == null) return;
                            if (v) {
                              await supa.from('app_custom_role_pages').upsert({
                                'role_key': selectedRoleKey,
                                'page_key': pageKey,
                                'can_view': true,
                              });
                            } else {
                              await supa
                                  .from('app_custom_role_pages')
                                  .delete()
                                  .eq('role_key', selectedRoleKey!)
                                  .eq('page_key', pageKey);
                            }
                            await reload();
                            setLocalState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  if (selectedRoleKey != null) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        await supa
                            .from('app_custom_roles')
                            .update({'active': false})
                            .eq('role_key', selectedRoleKey!);
                        await reload();
                        setLocalState(() {
                          selectedRoleKey = customRoles.isNotEmpty
                              ? customRoles.first['role_key']?.toString()
                              : null;
                        });
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Disattiva ruolo selezionato'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Chiudi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    ),
  );
  roleLabelCtrl.dispose();
  return result;
}
