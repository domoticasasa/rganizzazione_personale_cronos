import 'package:flutter/material.dart';

import '../data_import/data_import_hub_catalog.dart';
import '../data_import/data_import_hub_entry.dart';
import '../data_import/data_import_hub_service.dart';
import '../Mobile/cronos_mobile_pages.dart';
import '../utils/excel_export_helper.dart';
import '../utils/futuristic_navigation.dart';
import '../utils/gestopro_page_chrome.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import 'logistica_qt_carburante_verifica_page.dart';

/// Hub centralizzato: modelli Excel e import dati per tutte le aree applicative.
class AdminDataImportHubPage extends StatefulWidget {
  const AdminDataImportHubPage({
    super.key,
    this.userId,
    this.role,
  });

  final int? userId;
  final String? role;

  @override
  State<AdminDataImportHubPage> createState() => _AdminDataImportHubPageState();
}

class _AdminDataImportHubPageState extends State<AdminDataImportHubPage> {
  bool _busy = false;
  String? _busyEntryId;
  final Set<String> _expandedSections = {
    'impostazioni',
    'uqsa',
    'logistica',
    'carburante',
    'dpi',
  };

  Future<void> _downloadTemplate(DataImportHubEntry entry) async {
    setState(() {
      _busy = true;
      _busyEntryId = entry.id;
    });
    try {
      final safeName = entry.title.replaceAll(RegExp(r'[^\w]+'), '_');
      final saved = await DataImportHubService.downloadTemplate(
        entryId: entry.id,
        pageName: 'Modello_$safeName',
      );
      if (!mounted) return;
      final path = ExcelExportHelper.lastSavedPath ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? path.isEmpty
                    ? 'Modello «${entry.title}» scaricato.'
                    : 'Modello scaricato:\n$path'
                : 'Download annullato.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore modello: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyEntryId = null;
        });
      }
    }
  }

  Future<void> _import(DataImportHubEntry entry) async {
    setState(() {
      _busy = true;
      _busyEntryId = entry.id;
    });
    try {
      final result = await DataImportHubService.pickFileAndImport(
        context: context,
        entry: entry,
        userId: widget.userId,
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DataImportHubService.formatResultMessage(result)),
          backgroundColor: result.isSuccess ? null : Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import non riuscito: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyEntryId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = 'Import dati e modelli Excel';
    return buildGestoproAwarePage(
      context: context,
      title: pageTitle,
      classicAppBar: wrapClassicAppBarChrome(context, AppBar(
        title: const ResponsiveAppBarTitle(title: pageTitle),
      )),
      lightVeilOverTrain: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildIntroCard(context),
          const SizedBox(height: 16),
          for (final section in DataImportHubCatalog.sortedSections()) ...[
            _buildSection(context, section),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Avvio dati applicazione',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Per ogni modulo: scarica il modello Excel, compilalo seguendo le '
              'intestazioni, poi importa da qui senza aprire la pagina originale.\n\n'
              'Ordine consigliato: Commesse → Dipendenti → Logistica (BOX con GPS) → '
              'Liste POS → Formazione → Tesserini → DPI.\n\n'
              'Carburante / QT: le fatture fornitore non usano un modello Cronos — '
              'apri «Verifica fatturazione QT» dalla sezione Carburante.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, DataImportHubSection section) {
    final entries = DataImportHubCatalog.entriesForSection(section.id);
    final expanded = _expandedSections.contains(section.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(_sectionIcon(section.id)),
            title: Text(
              section.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: section.subtitle != null ? Text(section.subtitle!) : null,
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedSections.remove(section.id);
                } else {
                  _expandedSections.add(section.id);
                }
              });
            },
          ),
          if (expanded)
            for (final entry in entries) _buildEntryTile(context, entry),
        ],
      ),
    );
  }

  IconData _sectionIcon(String id) {
    switch (id) {
      case 'impostazioni':
        return Icons.admin_panel_settings_outlined;
      case 'uqsa':
        return Icons.school_outlined;
      case 'logistica':
        return Icons.local_shipping_outlined;
      case 'carburante':
        return Icons.local_gas_station_outlined;
      case 'dpi':
        return Icons.checkroom_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Future<void> _openLinkedPage(DataImportHubEntry entry) async {
    final Widget? page = switch (entry.id) {
      'qt_fatturazione_verifica' => useMobileUi(context)
          ? const LogisticaQtCarburanteVerificaMobilePage()
          : const LogisticaQtCarburanteVerificaPage(),
      _ => null,
    };
    if (page == null) return;
    await FuturisticNavigation.pushPage(
      context,
      page: page,
      title: entry.title,
      activeSubKey: entry.id,
    );
  }

  Widget _buildEntryTile(BuildContext context, DataImportHubEntry entry) {
    final busyThis = _busy && _busyEntryId == entry.id;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(entry.icon, size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.description,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (entry.prerequisites.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Prerequisiti: ${entry.prerequisites.join(', ')}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                      if (entry.requiresCommessa) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Richiede selezione commessa all\'import.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (entry.opensExistingPage)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _openLinkedPage(entry),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Apri pagina'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _downloadTemplate(entry),
                    icon: busyThis
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Scarica modello Excel'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _import(entry),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Importa da Excel'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
