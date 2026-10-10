/// Schema UI pagina custom (modificabile senza codice).
class CustomHubPageConfig {
  const CustomHubPageConfig({
    required this.formFields,
    required this.tableColumns,
  });

  final List<CustomHubFormField> formFields;
  final List<CustomHubTableColumn> tableColumns;

  static CustomHubPageConfig defaultPrenotazioni() {
    return CustomHubPageConfig(
      formFields: <CustomHubFormField>[
        const CustomHubFormField(
          id: 'select_people',
          type: CustomHubFieldType.actionButton,
          label: 'Seleziona persone',
        ),
        const CustomHubFormField(
          id: 'team_name',
          type: CustomHubFieldType.text,
          label: 'Nome squadra',
        ),
        const CustomHubFormField(
          id: 'create_team',
          type: CustomHubFieldType.submitButton,
          label: 'Crea squadra',
        ),
        const CustomHubFormField(
          id: 'structure',
          type: CustomHubFieldType.dropdown,
          label: 'Struttura',
        ),
        const CustomHubFormField(
          id: 'commessa',
          type: CustomHubFieldType.dropdown,
          label: 'Commessa',
        ),
        const CustomHubFormField(
          id: 'camera_auto',
          type: CustomHubFieldType.info,
          label: 'Tipo camera automatico',
        ),
        const CustomHubFormField(
          id: 'notes',
          type: CustomHubFieldType.multilineText,
          label: 'Note opzionali...',
        ),
        const CustomHubFormField(
          id: 'insert_booking',
          type: CustomHubFieldType.submitButton,
          label: 'Inserisci prenotazione',
        ),
        const CustomHubFormField(
          id: 'calendar',
          type: CustomHubFieldType.calendar,
          label: 'Calendario',
        ),
      ],
      tableColumns: <CustomHubTableColumn>[
        const CustomHubTableColumn(id: 'persona', label: 'Persona'),
        const CustomHubTableColumn(id: 'dal', label: 'Dal'),
        const CustomHubTableColumn(id: 'al', label: 'Al'),
        const CustomHubTableColumn(id: 'struttura', label: 'Struttura'),
        const CustomHubTableColumn(id: 'posizione', label: 'Posizione'),
        const CustomHubTableColumn(id: 'commessa', label: 'Commessa'),
        const CustomHubTableColumn(id: 'camera', label: 'Camera'),
        const CustomHubTableColumn(id: 'stato', label: 'Stato'),
        const CustomHubTableColumn(id: 'note', label: 'Note'),
        const CustomHubTableColumn(id: 'richiedente', label: 'Richiedente'),
        const CustomHubTableColumn(id: 'azioni', label: 'Azioni'),
      ],
    );
  }

  factory CustomHubPageConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return CustomHubPageConfig.defaultPrenotazioni();
    }
    final rawForm = json['formFields'];
    final rawCols = json['tableColumns'];
    var formFields = <CustomHubFormField>[];
    var tableColumns = <CustomHubTableColumn>[];
    if (rawForm is List) {
      formFields = rawForm
          .whereType<Map>()
          .map((e) => CustomHubFormField.fromJson(Map<String, dynamic>.from(e)))
          .where((f) => f.id.isNotEmpty)
          .toList(growable: false);
    }
    if (rawCols is List) {
      tableColumns = rawCols
          .whereType<Map>()
          .map((e) => CustomHubTableColumn.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.id.isNotEmpty)
          .toList(growable: false);
    }
    if (formFields.isEmpty && tableColumns.isEmpty) {
      return CustomHubPageConfig.defaultPrenotazioni();
    }
    final defaults = CustomHubPageConfig.defaultPrenotazioni();
    if (formFields.isEmpty) formFields = defaults.formFields;
    if (tableColumns.isEmpty) tableColumns = defaults.tableColumns;
    return CustomHubPageConfig(
      formFields: formFields,
      tableColumns: tableColumns,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'formFields': formFields.map((f) => f.toJson()).toList(),
        'tableColumns': tableColumns.map((c) => c.toJson()).toList(),
      };

  CustomHubFormField? fieldById(String id) {
    for (final f in formFields) {
      if (f.id == id) return f;
    }
    return null;
  }

  CustomHubTableColumn? columnById(String id) {
    for (final c in tableColumns) {
      if (c.id == id) return c;
    }
    return null;
  }

  String fieldLabel(String id, String fallback) =>
      fieldById(id)?.label ?? fallback;

  bool isFieldVisible(String id) => fieldById(id)?.visible ?? true;

  String columnLabel(String id, String fallback) =>
      columnById(id)?.label ?? fallback;

  bool isColumnVisible(String id) => columnById(id)?.visible ?? true;

  List<CustomHubTableColumn> visibleColumns() =>
      tableColumns.where((c) => c.visible).toList(growable: false);
}

enum CustomHubFieldType {
  actionButton('action_button'),
  text('text'),
  dropdown('dropdown'),
  multilineText('multiline_text'),
  submitButton('submit_button'),
  info('info'),
  calendar('calendar');

  const CustomHubFieldType(this.storageKey);
  final String storageKey;

  static CustomHubFieldType fromStorage(String? raw) {
    final v = (raw ?? '').trim();
    for (final t in CustomHubFieldType.values) {
      if (t.storageKey == v) return t;
    }
    return CustomHubFieldType.text;
  }
}

class CustomHubFormField {
  const CustomHubFormField({
    required this.id,
    required this.type,
    required this.label,
    this.visible = true,
  });

  final String id;
  final CustomHubFieldType type;
  final String label;
  final bool visible;

  factory CustomHubFormField.fromJson(Map<String, dynamic> json) {
    return CustomHubFormField(
      id: (json['id'] ?? '').toString(),
      type: CustomHubFieldType.fromStorage(json['type']?.toString()),
      label: (json['label'] ?? '').toString(),
      visible: json['visible'] != false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.storageKey,
        'label': label,
        'visible': visible,
      };

  CustomHubFormField copyWith({String? label, bool? visible}) =>
      CustomHubFormField(
        id: id,
        type: type,
        label: label ?? this.label,
        visible: visible ?? this.visible,
      );
}

class CustomHubTableColumn {
  const CustomHubTableColumn({
    required this.id,
    required this.label,
    this.visible = true,
  });

  final String id;
  final String label;
  final bool visible;

  factory CustomHubTableColumn.fromJson(Map<String, dynamic> json) {
    return CustomHubTableColumn(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      visible: json['visible'] != false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'visible': visible,
      };

  CustomHubTableColumn copyWith({String? label, bool? visible}) =>
      CustomHubTableColumn(
        id: id,
        label: label ?? this.label,
        visible: visible ?? this.visible,
      );
}
