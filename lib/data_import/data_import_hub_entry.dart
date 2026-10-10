import 'package:flutter/material.dart';

/// Voce nel catalogo import dati (hub Impostazioni App).
class DataImportHubEntry {
  const DataImportHubEntry({
    required this.id,
    required this.sectionId,
    required this.sectionLabel,
    required this.title,
    required this.description,
    required this.sortOrder,
    this.prerequisites = const [],
    this.requiresCommessa = false,
    this.opensExistingPage = false,
    this.icon = Icons.table_rows_outlined,
  });

  final String id;
  final String sectionId;
  final String sectionLabel;
  final String title;
  final String description;
  final int sortOrder;
  final List<String> prerequisites;
  final bool requiresCommessa;

  /// Se true: niente modello Cronos; apre la pagina dedicata (es. fatture QT).
  final bool opensExistingPage;
  final IconData icon;
}

class DataImportHubSection {
  const DataImportHubSection({
    required this.id,
    required this.label,
    required this.sortOrder,
    this.subtitle,
  });

  final String id;
  final String label;
  final int sortOrder;
  final String? subtitle;
}

class DataImportResult {
  const DataImportResult({
    required this.message,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
  });

  final String message;
  final int added;
  final int updated;
  final int skipped;
  final int errors;

  bool get isSuccess => errors == 0;
}
