import '../utils/password_policy.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/dpi_categories_service.dart';
import '../services/app_activity_log_service.dart';
import '../services/supabase_service.dart';
import '../services/formazioni_repository.dart';
import '../services/numero_tesserino_service.dart';
import '../utils/numero_tesserino_generator.dart';
import '../services/confirm_sound_service.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/responsive.dart';
import '../services/tesserino_foto.dart';
import '../widgets/app_logo.dart';
import '../widgets/personale_tesserino_foto_section.dart';
import '../widgets/admin_custom_roles_dialog.dart';
import '../widgets/employee_taglie_editor_dialog.dart';
import '../pages/admin_dpi_terza_categoria_page.dart';
import '../utils/personale_contacts_export.dart';
import '../utils/personale_data_export.dart';
import '../utils/users_directory.dart';
import '../widgets/classic_app_bar_chrome.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  Neumorphism Soft (Light) – Palette & Helpers
/// ─────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFFECECEC); // sfondo principale (Neumorphism Light)
const _kShadowDark = Color(0xFFBEBEBE);
const _kShadowLight = Color(0xFFFFFFFF);
const _kText = Color(0xFF222222);
const _kAccent = Color(0xFF2F6FED);

BoxDecoration _neoDecoration({
  double radius = 14,
  Color? color,
}) {
  return BoxDecoration(
    color: color ?? _kBg,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: const [
      BoxShadow(color: _kShadowDark, offset: Offset(6, 6), blurRadius: 12),
      BoxShadow(color: _kShadowLight, offset: Offset(-6, -6), blurRadius: 12),
    ],
  );
}

class _NeoContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final Color? color;

  const _NeoContainer({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  })  : margin = EdgeInsets.zero,
        radius = 14,
        color = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: _neoDecoration(radius: radius, color: color),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _NeoButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? color;

  const _NeoButton({
    required this.child,
    required this.onTap,
    this.color,
  })  : padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius = 14;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: _neoDecoration(
          radius: radius,
          color: color ?? (enabled ? _kBg : _kBg.withValues(alpha: 0.6)),
        ),
        padding: padding,
        child: DefaultTextStyle(
          style: Theme.of(context)
              .textTheme
              .labelLarge!
              .copyWith(color: enabled ? _kText : _kText.withValues(alpha: 0.4)),
          child: child,
        ),
      ),
    );
  }
}

class _NeoTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onChanged;

  const _NeoTextField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _NeoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        readOnly: readOnly,
        onChanged: onChanged == null ? null : (_) => onChanged!(),
        keyboardType: keyboardType,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _kText),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _kText.withValues(alpha: 0.7)),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Ruoli (UI vs DB)
/// ─────────────────────────────────────────────────────────────────────────

const kRuoliUtente = <String>[
  "Admin generale",
  "Admin vista",
  "Admin pernottamenti",
  "Admin treno/aereo",
  "Caposquadra",
  "DT",
  "Assistente DT",
  "user",
  "dipendente",
];

String _normalizeRole(String r) {
  final t = r.trim().toLowerCase().replaceAll(" ", "_").replaceAll("/", "_");
  if (t == "admin" || t == "admin_generale") return "admin_generale";
  if (t == "admin_vista" ||
      t == "admin_readonly" ||
      t == "admin_sola_lettura" ||
      t == "admin_sola_vista") {
    return "admin_vista";
  }
  if (t == "admin_pernottamenti") return "admin_pernottamenti";
  if (t == "admin_treno_aereo" || t == "admin_trenoaereo") {
    return "admin_trenoaereo";
  }
  if (t == "caposquadra") return "caposquadra";
  if (t == "user") return "user";
  if (t == "dt") return "dt";
  if (t.contains("assistente") && t.contains("dt")) return "assistente_dt";
  if (t == "assistente_dt") return "assistente_dt";
  return t;
}

String _roleDbToUi(String r) {
  final t = r.trim().toLowerCase().replaceAll(" ", "_");
  if (t == "admin_generale" || t == "admin") return "Admin generale";
  if (t == "admin_vista") return "Admin vista";
  if (t == "admin_pernottamenti") return "Admin pernottamenti";
  if (t == "admin_trenoaereo" || t == "admin_treno_aereo") {
    return "Admin treno/aereo";
  }
  if (t == "caposquadra") return "Caposquadra";
  if (t == "user") return "user";
  if (t == "dt") return "DT";
  if (t == "assistente_dt") return "Assistente DT";
  return r;
}

int? _adminTypeForRole(String roleUiOrDb) {
  final role = _normalizeRole(roleUiOrDb);
  if (role == "admin_pernottamenti") return 2;
  if (role == "admin_trenoaereo") return 3;
  if (role == "admin_dpi") return 4;
  if (role == "admin_formazione") return 5;
  if (role == "admin" || role == "admin_generale" || role == "admin_vista") {
    return 1;
  }
  return null;
}

Future<void> _persistSecondaryRole({
  required String authId,
  String? secondaryRole,
  int? secondaryAdminType,
}) async {
  try {
    await SupabaseService.client.from('users').update({
      'secondary_role': (secondaryRole ?? '').trim().isEmpty
          ? null
          : _normalizeRole(secondaryRole!),
      'secondary_admin_type': secondaryAdminType,
    }).eq('auth_id', authId);
  } catch (_) {}
}

/// ─────────────────────────────────────────────────────────────────────────
///  Pagina Mobile
/// ─────────────────────────────────────────────────────────────────────────

class AdminGestioneDipendentiMobilePage extends StatefulWidget {
  const AdminGestioneDipendentiMobilePage({super.key});

  @override
  State<AdminGestioneDipendentiMobilePage> createState() =>
      _AdminGestioneDipendentiMobilePageState();
}

class _AdminGestioneDipendentiMobilePageState
    extends State<AdminGestioneDipendentiMobilePage> {
  List<Map<String, dynamic>> _personale = [];
  List<String> _roleOptions = [...kRuoliUtente];
  bool _loading = false;
  bool _addPersonaleInFlight = false;
  String _search = "";
  bool _isNfcWriting = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadCustomRolesAndPermissions();
  }

  Future<void> _loadCustomRolesAndPermissions() async {
    try {
      final keys = await fetchCustomRoleKeys(SupabaseService.client);
      if (!mounted) return;
      setState(() => _roleOptions = [...kRuoliUtente, ...keys]);
    } catch (_) {}
  }

  Future<void> _openCustomRolesManager() async {
    final result = await showAdminCustomRolesDialog(context);
    if (result == true) {
      await _loadCustomRolesAndPermissions();
      _snack('Ruoli personalizzati aggiornati');
    }
  }

  /// Carica elenco personale
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final rows = await SupabaseService.client
          .from("personale")
          .select(
              "id, id_uuid, full_name, active, email, user_id, camera_tipo_default, matricola, telefono, data_assunzione, data_nascita, numero_tesserino, foto_tesserino_path, ruolo_aziendale")
          .order("full_name", ascending: true);

      final hiddenKeys = await UsersDirectory.loadHiddenLinkKeys(
        includeAdminVistaRole: false,
      );
      _personale = UsersDirectory.onlyVisiblePersonale(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
        hiddenKeys,
      );
      _personale.sort((a, b) {
        final an = (a["full_name"] ?? "").toString().toLowerCase().trim();
        final bn = (b["full_name"] ?? "").toString().toLowerCase().trim();
        return an.compareTo(bn);
      });
      setState(() {});
    } catch (e) {
      _snack("Errore caricamento: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _provisionDefaultPasswordForMissingLogins() async {
    const pw = "12345678";

    final targets = _personale.where((dip) {
      final userId = (dip["user_id"] ?? "").toString().trim();
      final email = (dip["email"] ?? "").toString().trim();
      return userId.isEmpty && email.isNotEmpty;
    }).toList();

    final skippedNoEmail = _personale.where((dip) {
      final userId = (dip["user_id"] ?? "").toString().trim();
      final email = (dip["email"] ?? "").toString().trim();
      return userId.isEmpty && email.isEmpty;
    }).length;

    if (targets.isEmpty) {
      _snack("Nessun dipendente senza login da aggiornare.");
      return;
    }

    final ok = await _confirm(
      title: "Password provvisoria per chi non ha login",
      message:
          "Verranno creati (o riparati) gli accessi Supabase per tutti i dipendenti senza login.\n\nPassword provvisoria: $pw\n\nDipendenti da aggiornare: ${targets.length}\nSaltati per email mancante: $skippedNoEmail",
      confirmLabel: "Crea login + forza cambio password",
    );
    if (!ok) return;

    setState(() => _loading = true);
    int okCount = 0;
    int failedCount = 0;
    final failures = <String>[];

    String buildUsername(String fullName, String email) {
      final base = fullName.trim().isNotEmpty ? fullName.trim() : email;
      final prefix = base.split("@").first;
      final cleaned = prefix
          .toLowerCase()
          .replaceAll(RegExp(r"\s+"), ".")
          .replaceAll(RegExp(r"[^a-z0-9._]"), "")
          .replaceAll(RegExp(r"\.+"), ".");
      return cleaned.isNotEmpty ? cleaned : "user";
    }

    try {
      for (final dip in targets) {
        final personaleId = (dip["id"] ?? dip["id_uuid"]).toString();
        final personaleIdInt = int.tryParse(personaleId);
        if (personaleIdInt == null) {
          failedCount++;
          failures.add('${dip["full_name"]}: id personale non valido');
          continue;
        }

        final email = (dip["email"] ?? "").toString().trim();
        final fullName = (dip["full_name"] ?? "").toString().trim();
        final username = buildUsername(fullName, email);

        try {
          final authId = await _adminCreateUser(
            personaleId: personaleIdInt,
            email: email,
            password: pw,
            username: username,
            fullName: fullName.isNotEmpty ? fullName : email,
            ruolo: "user",
          );

          if (authId == null || authId.isEmpty) {
            failedCount++;
            failures.add('$email: login non creato (risposta vuota)');
            continue;
          }

          okCount++;
        } catch (e) {
          failedCount++;
          final label = fullName.isNotEmpty ? '$fullName ($email)' : email;
          failures.add('$label: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    await _loadAll();
    if (failedCount == 0) {
      _snack("Fatto. Ok: $okCount, falliti: $failedCount.");
    } else {
      final detail = failures.take(3).join('\n');
      final more = failures.length > 3 ? '\n…' : '';
      _snack(
        "Ok: $okCount, falliti: $failedCount.\n$detail$more",
        error: okCount == 0,
      );
    }
  }

  /// Notifiche
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    if (!error) {
      ConfirmSoundService.play();
    }
    final bg = error ? Colors.redAccent : const Color(0xFF68C090);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: bg,
          content: Text(msg)),
    );
  }

  String _safeText(String value) => value.trim().isEmpty ? 'N/D' : value.trim();
  String _friendlyNfcError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('not available') ||
        s.contains('nfc') && s.contains('disable')) {
      return 'NFC disattivato o non disponibile sul dispositivo.';
    }
    if (s.contains('read only')) return 'Tag NFC in sola lettura.';
    if (s.contains('size') ||
        s.contains('too large') ||
        s.contains('capacity')) {
      return 'Dati troppo lunghi per questo tag NFC.';
    }
    if (s.contains('ndef')) return 'Tag non compatibile con scrittura NDEF.';
    return 'Errore durante la scrittura NFC.';
  }

  String _fit(String value, int max) {
    final v = _safeText(value);
    return v.length <= max ? v : '${v.substring(0, max)}...';
  }

  String? _parseInputDateToIso(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(v);
    if (m != null) {
      final dd = int.tryParse(m.group(1)!);
      final mm = int.tryParse(m.group(2)!);
      final yyyy = int.tryParse(m.group(3)!);
      if (dd == null || mm == null || yyyy == null) return null;
      final d = DateTime.tryParse(
        '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}',
      );
      if (d == null) return null;
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    final d = DateTime.tryParse(v);
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _buildDpiNfcPayloadFull({
    required String fullName,
    required Map<String, dynamic> row,
  }) {
    return [
      'CRONOS - DATI DPI',
      'Nome: ${_safeText(fullName)}',
      'Categoria: ${_safeText((row['categoria'] ?? '').toString())}',
      'Quantita assegnata: ${_safeText((row['quantita_assegnata'] ?? '').toString())}',
      'Marca: ${_safeText((row['marca'] ?? '').toString())}',
      'Data produzione: ${_safeText(formatDateDdMmYyyy(row['data_produzione']))}',
      'Data consegna: ${_safeText(formatDateDdMmYyyy(row['data_consegna']))}',
      'Data revisione: ${_safeText(formatDateDdMmYyyy(row['data_revisione']))}',
      'Matricola: ${_safeText((row['matricola'] ?? '').toString())}',
      'Modello: ${_safeText((row['modello'] ?? '').toString())}',
    ].join('\n');
  }

  String _buildDpiNfcPayloadCompact({
    required String fullName,
    required Map<String, dynamic> row,
  }) {
    return [
      'CRONOS DPI',
      'N:${_fit(fullName, 22)}',
      'C:${_fit((row['categoria'] ?? '').toString(), 14)}',
      'Q:${_fit((row['quantita_assegnata'] ?? '').toString(), 4)}',
      'Ma:${_fit((row['marca'] ?? '').toString(), 14)}',
      'Dt:${_fit(formatDateDdMmYyyy(row['data_produzione']), 10)}',
      'Dc:${_fit(formatDateDdMmYyyy(row['data_consegna']), 10)}',
      'Dr:${_fit(formatDateDdMmYyyy(row['data_revisione']), 10)}',
      'Mt:${_fit((row['matricola'] ?? '').toString(), 14)}',
      'Mo:${_fit((row['modello'] ?? '').toString(), 14)}',
    ].join('\n');
  }

  NdefRecord _createTextRecord(String text, {String languageCode = 'it'}) {
    final langBytes = utf8.encode(languageCode);
    final textBytes = utf8.encode(text);
    final payload = Uint8List(1 + langBytes.length + textBytes.length)
      ..[0] = langBytes.length
      ..setRange(1, 1 + langBytes.length, langBytes)
      ..setRange(1 + langBytes.length, 1 + langBytes.length + textBytes.length,
          textBytes);

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList(utf8.encode('T')),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  Future<void> _writeDpiToNfc({
    required String fullName,
    required Map<String, dynamic> row,
  }) async {
    if (_isNfcWriting) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _snack('Scrittura NFC disponibile solo su Android.', error: true);
      return;
    }

    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      _snack('NFC non disponibile su questo dispositivo.', error: true);
      return;
    }

    setState(() => _isNfcWriting = true);
    _snack('Modalita scrittura attiva: avvicina il tag NFC...');
    var handled = false;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        noPlatformSoundsAndroid: true,
        onDiscovered: (NfcTag tag) async {
          if (handled) return;
          handled = true;
          try {
            var message = NdefMessage(
              records: [
                _createTextRecord(
                  _buildDpiNfcPayloadFull(fullName: fullName, row: row),
                ),
              ],
            );

            final ndef = NdefAndroid.from(tag);
            if (ndef != null) {
              if (!ndef.isWritable) throw Exception('Tag in sola lettura.');
              if (message.byteLength > ndef.maxSize) {
                message = NdefMessage(
                  records: [
                    _createTextRecord(
                      _buildDpiNfcPayloadCompact(fullName: fullName, row: row),
                    ),
                  ],
                );
                if (message.byteLength > ndef.maxSize) {
                  throw Exception(
                    'Payload too large for this tag (${message.byteLength}/${ndef.maxSize}).',
                  );
                }
              }
              await ndef.writeNdefMessage(message);
            } else {
              final formatable = NdefFormatableAndroid.from(tag);
              if (formatable == null) {
                throw Exception('Tag non compatibile con scrittura NDEF.');
              }
              await formatable.format(message);
            }

            await NfcManager.instance.stopSession(
              alertMessageIos: 'Dati DPI scritti con successo.',
            );
            _snack('Scrittura NFC completata.');
          } catch (e) {
            await NfcManager.instance.stopSession(
              errorMessageIos: _friendlyNfcError(e),
            );
            _snack(_friendlyNfcError(e), error: true);
          } finally {
            if (mounted) setState(() => _isNfcWriting = false);
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isNfcWriting = false);
      _snack(_friendlyNfcError(e), error: true);
    }
  }

  Future<void> _openDpiManager(Map<String, dynamic> dip) async {
    final categorie = await DpiCategoriesService.listCategories();

    final personaleUuid = (dip['id_uuid'] ?? '').toString().trim();
    if (personaleUuid.isEmpty) {
      _snack('ID UUID personale mancante', error: true);
      return;
    }

    List<Map<String, dynamic>> rows = [];
    var dpiListLoadScheduled = false;

    Future<void> loadRows(StateSetter setSt, BuildContext dialogContext) async {
      try {
        final res = await SupabaseService.client
            .from('dpi_dotazioni')
            .select(
                'id, categoria, quantita_assegnata, marca, data_produzione, data_consegna, data_revisione, matricola, modello')
            .eq('personale_id', personaleUuid)
            .order('categoria')
            .order('created_at');
        rows = List<Map<String, dynamic>>.from(res as List);
        if (!dialogContext.mounted) return;
        setSt(() {});
      } catch (e) {
        if (!dialogContext.mounted) return;
        _snack('Errore caricamento DPI: $e', error: true);
      }
    }

    Future<void> saveForm(StateSetter setSt, BuildContext dialogContext,
        {Map<String, dynamic>? current}) async {
      String categoria = (current?['categoria'] ?? categorie.first).toString();
      final qCtrl = TextEditingController(
          text: (current?['quantita_assegnata'] ?? 1).toString());
      final marcaCtrl =
          TextEditingController(text: (current?['marca'] ?? '').toString());
      final dataCtrl = TextEditingController(
          text: formatDateDdMmYyyy(current?['data_produzione']));
      final dataConsegnaCtrl = TextEditingController(
          text: formatDateDdMmYyyy(current?['data_consegna']));
      final dataRevisioneCtrl = TextEditingController(
          text: formatDateDdMmYyyy(current?['data_revisione']));
      final matricolaCtrl =
          TextEditingController(text: (current?['matricola'] ?? '').toString());
      final modelloCtrl =
          TextEditingController(text: (current?['modello'] ?? '').toString());

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(current == null ? 'Nuovo DPI' : 'Modifica DPI'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: categoria,
                      isExpanded: true,
                      items: categorie
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setLocal(() => categoria = v ?? categoria),
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final addCtrl = TextEditingController();
                          final addOk = await showDialog<bool>(
                            context: ctx,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Nuova categoria DPI'),
                              content: TextField(
                                controller: addCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nome categoria',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, false),
                                  child: const Text('Annulla'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx2, true),
                                  child: const Text('Aggiungi'),
                                ),
                              ],
                            ),
                          );
                          final newName = addCtrl.text.trim();
                          if (addOk != true || newName.isEmpty) return;
                          try {
                            await DpiCategoriesService.addCategory(newName);
                            if (!categorie.any((c) => c.toLowerCase() == newName.toLowerCase())) {
                              categorie.add(newName);
                              categorie.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            }
                            setLocal(() => categoria = newName);
                          } catch (e) {
                            if (!mounted) return;
                            _snack('Errore creazione categoria: $e', error: true);
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Nuova categoria'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantita assegnata',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: marcaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Marca',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dataCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data produzione (DD-MM-YYYY)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dataConsegnaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data consegna (DD-MM-YYYY)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dataRevisioneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Data revisione (DD-MM-YYYY)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: matricolaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Matricola',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: modelloCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Modello',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annulla')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salva')),
            ],
          ),
        ),
      );

      if (ok != true) return;
      final quantita = int.tryParse(qCtrl.text.trim());
      if (quantita == null || quantita < 0) {
        _snack('Quantita assegnata non valida.', error: true);
        return;
      }
      final dataStr = _parseInputDateToIso(dataCtrl.text);
      final dataConsegnaStr = _parseInputDateToIso(dataConsegnaCtrl.text);
      final dataRevisioneStr = _parseInputDateToIso(dataRevisioneCtrl.text);
      if (dataCtrl.text.trim().isNotEmpty && dataStr == null) {
        _snack('Data produzione non valida. Usa formato DD-MM-YYYY.',
            error: true);
        return;
      }
      if (dataConsegnaCtrl.text.trim().isNotEmpty && dataConsegnaStr == null) {
        _snack('Data consegna non valida. Usa formato DD-MM-YYYY.',
            error: true);
        return;
      }
      if (dataRevisioneCtrl.text.trim().isNotEmpty &&
          dataRevisioneStr == null) {
        _snack('Data revisione non valida. Usa formato DD-MM-YYYY.',
            error: true);
        return;
      }

      try {
        final payload = {
          'personale_id': personaleUuid,
          'categoria': categoria,
          'quantita_assegnata': quantita,
          'marca': marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
          'data_produzione': dataStr,
          'data_consegna': dataConsegnaStr,
          'data_revisione': dataRevisioneStr,
          'matricola': matricolaCtrl.text.trim().isEmpty
              ? null
              : matricolaCtrl.text.trim(),
          'modello':
              modelloCtrl.text.trim().isEmpty ? null : modelloCtrl.text.trim(),
        };
        if (current == null) {
          await SupabaseService.client.from('dpi_dotazioni').insert(payload);
          _snack('DPI inserito');
        } else {
          await SupabaseService.client
              .from('dpi_dotazioni')
              .update(payload)
              .eq('id', current['id']);
          _snack('DPI aggiornato');
        }
        await loadRows(setSt, dialogContext);
      } catch (e) {
        _snack('Errore salvataggio DPI: $e', error: true);
      }
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          final screen = MediaQuery.of(ctx).size;
          final dialogHeight = screen.height * 0.72;
          final contentWidth =
              (screen.width * 0.96).clamp(280.0, screen.width - 16);
          if (!dpiListLoadScheduled) {
            dpiListLoadScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              loadRows(setSt, ctx);
            });
          }
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
            title: Text('DPI - ${(dip['full_name'] ?? '').toString()}'),
            content: SizedBox(
              width: contentWidth,
              height: dialogHeight,
              child: rows.isEmpty
                  ? const Center(child: Text('Nessun DPI assegnato'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: SingleChildScrollView(
                        primary: false,
                        child: DataTable(
                          columnSpacing: 14,
                          horizontalMargin: 12,
                          columns: const [
                            DataColumn(label: Text('Categoria')),
                            DataColumn(label: Text('Azioni')),
                            DataColumn(label: Text('NFC')),
                            DataColumn(label: Text('Qta')),
                            DataColumn(label: Text('Marca')),
                            DataColumn(label: Text('Data prod.')),
                            DataColumn(label: Text('Data consegna')),
                            DataColumn(label: Text('Data revisione')),
                            DataColumn(label: Text('Matricola')),
                            DataColumn(label: Text('Modello')),
                          ],
                          rows: rows
                              .map(
                                (r) => DataRow(
                                  cells: [
                                    DataCell(Text(
                                        (r['categoria'] ?? '').toString())),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 40,
                                              minHeight: 40,
                                            ),
                                            iconSize: 22,
                                            tooltip: 'Modifica',
                                            icon: const Icon(Icons.edit_outlined),
                                            onPressed: () =>
                                                saveForm(setSt, ctx, current: r),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 40,
                                              minHeight: 40,
                                            ),
                                            iconSize: 22,
                                            tooltip: 'Elimina',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                            ),
                                            onPressed: () async {
                                              await SupabaseService.client
                                                  .from('dpi_dotazioni')
                                                  .delete()
                                                  .eq('id', r['id']);
                                              _snack('DPI eliminato');
                                              await loadRows(setSt, ctx);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      FilledButton.tonalIcon(
                                        onPressed: () => _writeDpiToNfc(
                                          fullName: (dip['full_name'] ?? '')
                                              .toString(),
                                          row: r,
                                        ),
                                        icon: const Icon(Icons.nfc),
                                        label: const Text('Scrivi su NFC'),
                                      ),
                                    ),
                                    DataCell(Text(
                                        (r['quantita_assegnata'] ?? '')
                                            .toString())),
                                    DataCell(
                                        Text((r['marca'] ?? '').toString())),
                                    DataCell(Text(formatDateDdMmYyyy(r['data_produzione']))),
                                    DataCell(Text(formatDateDdMmYyyy(r['data_consegna']))),
                                    DataCell(Text(formatDateDdMmYyyy(r['data_revisione']))),
                                    DataCell(Text(
                                        (r['matricola'] ?? '').toString())),
                                    DataCell(
                                        Text((r['modello'] ?? '').toString())),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminDpiTerzaCategoriaPage(),
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Nuovo DPI'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openVestiarioEditor(Map<String, dynamic> dip) async {
    final personaleId =
        (dip['id_uuid'] ?? dip['id'] ?? '').toString().trim();
    final fullName = (dip['full_name'] ?? '').toString().trim();
    if (personaleId.isEmpty) {
      _snack('Impossibile aprire vestiario: ID dipendente mancante', error: true);
      return;
    }
    await showEmployeeTaglieEditorDialog(
      context,
      personaleIdUuid: personaleId,
      dialogTitle: fullName.isEmpty ? 'Vestiario dipendente' : 'Vestiario — $fullName',
      messenger: _snack,
    );
  }

  /// Conferma
  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = "Conferma",
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: TextStyle(color: _kText.withValues(alpha: 0.9))),
        content:
            Text(message, style: TextStyle(color: _kText.withValues(alpha: 0.9))),
        actions: [
          _NeoButton(
              onTap: () => Navigator.pop(context, false),
              child: const Text("Annulla")),
          _NeoButton(
            color: danger ? const Color(0xFFFFE6E6) : null,
            onTap: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: danger ? Colors.red.shade700 : _kText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  /// Scelta reset password: null = annulla, 'email' = invia email, 'password' = nuova password
  Future<String?> _resetPasswordChoice() async {
    return showDialog<String?>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          "Reset Password",
          style: TextStyle(color: _kText.withValues(alpha: 0.9)),
        ),
        content: Text(
          "Come vuoi procedere con il reset della password?",
          style: TextStyle(color: _kText.withValues(alpha: 0.9)),
        ),
        actions: [
          _NeoButton(
            onTap: () => Navigator.pop(dialogCtx, null),
            child: const Text("Annulla"),
          ),
          _NeoButton(
            onTap: () => Navigator.pop(dialogCtx, 'email'),
            child: const Text("Invia email"),
          ),
          _NeoButton(
            onTap: () => Navigator.pop(dialogCtx, 'password'),
            child: Text(
              "Nuova password",
              style: TextStyle(color: _kText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Filtro
  bool _matchesSearch(Map<String, dynamic> dip) {
    final q = _search.toLowerCase().trim();
    if (q.isEmpty) return true;
    return dip["full_name"].toString().toLowerCase().contains(q) ||
        (dip["matricola"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["ruolo_aziendale"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["numero_tesserino"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["email"] ?? "").toString().toLowerCase().contains(q);
  }

  List<Map<String, dynamic>> _filteredPersonale() {
    final list = _personale.where(_matchesSearch).toList();
    list.sort((a, b) {
      final an = (a["full_name"] ?? "").toString().toLowerCase().trim();
      final bn = (b["full_name"] ?? "").toString().toLowerCase().trim();
      return an.compareTo(bn);
    });
    return list;
  }

  Future<void> _exportPersonaleCsv() async {
    await exportPersonaleDataCsv(
      context,
      personaleRows: _filteredPersonale(),
      messenger: (msg, {error = false}) => _snack(msg, error: error),
    );
  }

  /// Helpers nome/cognome
  _NamePair _splitFullName(String full) {
    final parts = full.trim().split(RegExp(r"\s+"));
    if (parts.isEmpty || (parts.length == 1 && parts.first.isEmpty)) {
      return const _NamePair("", "");
    }
    if (parts.length == 1) return _NamePair("", parts.first);
    final cognome = parts.first;
    final nome = parts.sublist(1).join(" ");
    return _NamePair(nome, cognome);
  }

  String _composeFullName(String nome, String cognome) =>
      "$cognome $nome".trim();

  Future<String> _adminJwt() async {
    final auth = SupabaseService.client.auth;
    // Forza sempre un refresh per evitare di usare un access token stale.
    try {
      await auth.refreshSession();
    } catch (_) {}

    String? jwt = auth.currentSession?.accessToken;
    if (jwt == null || jwt.isEmpty) {
      final refreshed = await auth.refreshSession();
      jwt = refreshed.session?.accessToken ?? auth.currentSession?.accessToken;
    }
    // Verifica reale validità token con endpoint auth corrente.
    final userRes = await auth.getUser();
    jwt = auth.currentSession?.accessToken ?? jwt;
    if (userRes.user == null) {
      throw Exception("Sessione admin non valida. Effettua logout/login.");
    }
    if (jwt == null || jwt.isEmpty) {
      throw Exception("Sessione admin scaduta. Effettua nuovamente il login.");
    }
    return jwt;
  }

  Future<FunctionResponse> _invokeAdminFn(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    Future<FunctionResponse> runInvoke() async {
      final jwt = await _adminJwt();
      return SupabaseService.client.functions.invoke(
        functionName,
        body: body,
        headers: {
          "Authorization": "Bearer $jwt",
        },
      );
    }

    try {
      return await runInvoke();
    } catch (e) {
      final s = e.toString().toLowerCase();
      final isJwtErr =
          s.contains("invalid jwt") || s.contains("status: 401") || s.contains("unauthorized");
      if (!isJwtErr) rethrow;
      await SupabaseService.client.auth.refreshSession();
      try {
        return await runInvoke();
      } catch (e2) {
        throw Exception(
          "Sessione scaduta/non valida ($functionName). Effettua logout/login. Dettaglio: $e2",
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Edge Functions – CALLERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _adminCreateUser({
    required int personaleId,
    required String email,
    required String password,
    required String username,
    required String fullName,
    required String ruolo,
    int? adminType,
    String? secondaryRole,
    int? secondaryAdminType,
  }) async {
    await _adminJwt();

    final normRole = _normalizeRole(ruolo);
    final resolvedAdminType = adminType ?? _adminTypeForRole(ruolo);
    final body = <String, dynamic>{
      "email": email.trim(),
      "password": password.trim(),
      "username": username.trim(),
      "full_name": fullName,
      "role": normRole,
      "personale_id": personaleId,
    };
    if (resolvedAdminType != null) body["admin_type"] = resolvedAdminType;
    if ((secondaryRole ?? '').trim().isNotEmpty) {
      body["secondary_role"] = _normalizeRole(secondaryRole!);
    }
    if (secondaryAdminType != null) {
      body["secondary_admin_type"] = secondaryAdminType;
    }

    final res = await _invokeAdminFn(
      "admin-create-user",
      body: body,
    );

    final data = res.data;
    if (data is Map) {
      final authId = data["auth_id"]?.toString().trim();
      if (authId != null && authId.isNotEmpty) return authId;
      final err = (data["error"] ?? data["details"] ?? "").toString().trim();
      if (err.isNotEmpty) throw Exception(err);
    }
    if (res.status >= 400) {
      throw Exception("admin-create-user HTTP ${res.status}");
    }
    return null;
  }

  Future<void> _adminSetPassword({
    required String authId,
    required String newPassword,
  }) async {
    await _adminJwt();

    await _invokeAdminFn(
      "admin-set-password",
      body: {"auth_id": authId, "new_password": newPassword},
    );
  }

  Future<void> _adminDeleteUser({
    required String authId,
    required int personaleId,
    required bool hard,
  }) async {
    await _adminJwt();

    await _invokeAdminFn(
      "admin-delete-user",
      body: {
        "auth_id": authId,
        "personale_id": personaleId,
        "mode": hard ? "hard" : "soft"
      },
    );
  }

  Future<void> _adminUpdateEmployee({
    String? authId,
    int? userId,
    int? personaleId, // supporto per personale_id
    String? email,
    String? fullName,
    String? username,
    bool? active,
    String? role,
    String? password, // opzionale
    bool notify = false, // opzionale
  }) async {
    await _adminJwt();

    final body = <String, dynamic>{};

    if (authId != null && authId.trim().isNotEmpty) {
      body['auth_id'] = authId.trim();
    }
    if (userId != null) body['user_id'] = userId;
    if (personaleId != null) body['personale_id'] = personaleId;

    if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
    if (fullName != null && fullName.trim().isNotEmpty) {
      body['full_name'] = fullName.trim();
    }
    if (username != null && username.trim().isNotEmpty) {
      body['username'] = username.trim();
    }
    if (active != null) body['active'] = active;
    if (role != null && role.trim().isNotEmpty) {
      body['role'] = _normalizeRole(role);
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (notify) body['notify'] = true;

    final res = await _invokeAdminFn(
      "admin-update-employee",
      body: body,
    );

    if (res.data == null || res.data['ok'] != true) {
      final msg = res.data?['error'] ?? 'Aggiornamento fallito';
      throw Exception(msg);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _addPersonale() async {
    if (!await ensureCanPersist(context)) return;
    if (_addPersonaleInFlight) return;
    final res = await _showDipSheet(
      isEdit: false,
      hasLogin: false,
      initial: const _DipFullData(
        nome: '',
        cognome: '',
        attivo: true,
        cameraTipoDefault: 'doppia',
        matricola: '',
        telefono: '',
        dataAssunzione: '',
        dataNascita: '',
        creaLogin: true,
        username: '',
        email: '',
        ruolo: 'user',
        passwordProvvisoria: '',
        urlFormazioni: '',
        adminType: 1,
      ),
    );
    if (res == null) return;

    // Validazioni minime per creazione login durante aggiunta
    if (res.creaLogin) {
      final email = (res.email ?? '').trim();
      final username = (res.username ?? '').trim();
      final pw = (res.passwordProvvisoria ?? '').trim();
      final emailOk = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);

      if (username.isEmpty || !emailOk || pw.length < 8) {
        _snack(
            'Per creare il login servono Username, Email valida e Password (min 8).',
            error: true);
        return;
      }
    }

    setState(() {
      _loading = true;
      _addPersonaleInFlight = true;
    });
    try {
      final fullName = _composeFullName(res.nome, res.cognome);
      final dataAssunzioneIso = parseFlexibleDateToIsoDate(res.dataAssunzione);
      final dataNascitaIso = parseFlexibleDateToIsoDate(res.dataNascita);
      final numeroTesserino = await NumeroTesserinoService.allocate(
        supa: SupabaseService.client,
        cognome: res.cognome,
        nome: res.nome,
      );

      // 1) Inserisci anagrafica
      final inserted = await SupabaseService.client
          .from("personale")
          .insert({
            "full_name": fullName,
            "numero_tesserino": numeroTesserino,
            "email":
                (res.email ?? '').trim().isEmpty ? null : res.email!.trim(),
            "active": res.attivo,
            "camera_tipo_default": res.cameraTipoDefault,
            "matricola":
                res.matricola.trim().isEmpty ? null : res.matricola.trim(),
            "telefono":
                res.telefono.trim().isEmpty ? null : res.telefono.trim(),
            "data_assunzione": dataAssunzioneIso,
            "data_nascita": dataNascitaIso,
            "ruolo_aziendale": res.ruoloAziendale.trim().isEmpty
                ? null
                : res.ruoloAziendale.trim(),
          })
          .select("id")
          .maybeSingle();

      if (inserted == null) {
        _snack("Errore creazione dipendente", error: true);
        return;
      }
      final personaleId = inserted["id"] as int;

      // 2) Crea login opzionale
      String? authId;
      if (res.creaLogin) {
        authId = await _adminCreateUser(
          personaleId: personaleId,
          email: res.email!.trim(),
          password: res.passwordProvvisoria!.trim(),
          username: res.username!.trim(),
          fullName: fullName,
          ruolo: res.ruolo ?? 'user',
          adminType: res.adminType ?? _adminTypeForRole(res.ruolo ?? ''),
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? ''),
        );
        if (authId == null || authId.isEmpty) {
          await AppActivityLogService.recordUserCreate(
            fullName: fullName,
            email: (res.email ?? '').trim(),
            login: false,
          );
          _snack("Errore creazione login", error: true);
          return;
        }
        await _persistSecondaryRole(
          authId: authId,
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? ''),
        );
      }

      // 3) Formazioni (se presente e ho authId)
      if ((res.urlFormazioni ?? '').trim().isNotEmpty &&
          (authId ?? '').isNotEmpty) {
        await FormazioniRepository.setForUser(
            authId!, res.urlFormazioni!.trim());
      }

      _snack("Dipendente creato");
      if (!(res.creaLogin && (authId ?? '').isNotEmpty)) {
        await AppActivityLogService.recordUserCreate(
          fullName: fullName,
          email: (res.email ?? '').trim(),
          login: false,
        );
      }
      await _loadAll();
    } catch (e) {
      _snack("Errore creazione: $e", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _addPersonaleInFlight = false;
        });
      }
    }
  }

  Future<void> _editPersonaleFull(Map<String, dynamic> dip) async {
    if (!await ensureCanPersist(context)) return;
    final parsed = _splitFullName(dip["full_name"]);
    final userIdUuid = (dip["user_id"] ?? "").toString();
    final hasLogin = userIdUuid.isNotEmpty;

    String? currentRoleDb;
    String? currentUsernameDb;
    int? currentAdminTypeDb;
    String? currentSecondaryRoleDb;
    int? currentSecondaryAdminTypeDb;
    if (hasLogin) {
      try {
        final row = await SupabaseService.client
            .from("users")
            .select(
                "role, username, admin_type, secondary_role, secondary_admin_type")
            .eq("auth_id", userIdUuid)
            .maybeSingle();
        if (row != null) {
          if (row["role"] != null) currentRoleDb = row["role"].toString();
          if (row["username"] != null) {
            currentUsernameDb = row["username"].toString();
          }
          if (row["admin_type"] != null) {
            currentAdminTypeDb = int.tryParse(row["admin_type"].toString());
          }
          if (row["secondary_role"] != null) {
            currentSecondaryRoleDb = row["secondary_role"].toString();
          }
          if (row["secondary_admin_type"] != null) {
            currentSecondaryAdminTypeDb =
                int.tryParse(row["secondary_admin_type"].toString());
          }
        }
      } catch (_) {}
    }

    String? formazioneUrl =
        hasLogin ? await FormazioniRepository.getForUser(userIdUuid) : null;

    final res = await _showDipSheet(
      isEdit: true,
      hasLogin: hasLogin,
      personaleId: dip["id"] as int?,
      personaleIdUuid: (dip["id_uuid"] ?? '').toString(),
      initial: _DipFullData(
        nome: parsed.nome,
        cognome: parsed.cognome,
        attivo: dip["active"] == true,
        cameraTipoDefault:
            ((dip["camera_tipo_default"] ?? "doppia").toString().trim() == "singola")
                ? "singola"
                : "doppia",
        matricola: (dip["matricola"] ?? '').toString(),
        telefono: (dip["telefono"] ?? '').toString(),
        dataAssunzione: (dip["data_assunzione"] ?? '').toString(),
        dataNascita: (dip["data_nascita"] ?? '').toString(),
        fotoTesserinoPath: (dip["foto_tesserino_path"] ?? '').toString(),
        ruoloAziendale: (dip["ruolo_aziendale"] ?? '').toString(),
        creaLogin: !hasLogin,
        username: currentUsernameDb ?? '',
        email: dip["email"],
        ruolo: (hasLogin && currentRoleDb != null)
            ? _roleDbToUi(currentRoleDb)
            : "user",
        ruoloSecondario: (hasLogin && currentSecondaryRoleDb != null)
            ? _roleDbToUi(currentSecondaryRoleDb)
            : null,
        passwordProvvisoria: null,
        numeroTesserino: (dip["numero_tesserino"] ?? '').toString(),
        urlFormazioni: formazioneUrl,
        adminType: currentAdminTypeDb,
        adminTypeSecondario: currentSecondaryAdminTypeDb,
      ),
    );
    if (res == null) return;

    setState(() => _loading = true);
    try {
      final newFullName = _composeFullName(res.nome, res.cognome);
      final personaleId = dip["id"] as int;
      var numeroTesserino = (dip["numero_tesserino"] ?? "").toString().trim();
      if (numeroTesserino.isEmpty) {
        numeroTesserino = await NumeroTesserinoService.allocate(
          supa: SupabaseService.client,
          cognome: res.cognome,
          nome: res.nome,
          excludePersonaleId: personaleId,
        );
      }

      final dataAssunzioneIso = parseFlexibleDateToIsoDate(res.dataAssunzione);
      final dataNascitaIso = parseFlexibleDateToIsoDate(res.dataNascita);

      Future<void> updatePersonale() => SupabaseService.client.from("personale").update({
            "full_name": newFullName,
            "numero_tesserino": numeroTesserino,
            "active": res.attivo,
            "email": res.email,
            "camera_tipo_default": res.cameraTipoDefault,
            "matricola":
                res.matricola.trim().isEmpty ? null : res.matricola.trim(),
            "telefono":
                res.telefono.trim().isEmpty ? null : res.telefono.trim(),
            "data_assunzione": dataAssunzioneIso,
            "data_nascita": dataNascitaIso,
            "ruolo_aziendale": res.ruoloAziendale.trim().isEmpty
                ? null
                : res.ruoloAziendale.trim(),
          }).eq("id", personaleId);

      try {
        await updatePersonale();
      } catch (e) {
        if (!isDuplicateTesserinoError(e)) rethrow;
        numeroTesserino = await NumeroTesserinoService.allocate(
          supa: SupabaseService.client,
          cognome: res.cognome,
          nome: res.nome,
          excludePersonaleId: personaleId,
        );
        await updatePersonale();
      }

      // 2) Crea login se mancava
      if (res.creaLogin && !hasLogin) {
        final email = (res.email ?? '').trim();
        final username = (res.username ?? '').trim();
        final pw = (res.passwordProvvisoria ?? '').trim();
        final emailOk = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);

        if (username.isEmpty || !emailOk || pw.length < 8) {
          _snack(
            'Per creare il login servono Username, Email valida e Password (min 8).',
            error: true,
          );
          return;
        }

        final authId = await _adminCreateUser(
          personaleId: dip["id"],
          email: email,
          password: pw,
          username: username,
          fullName: newFullName,
          ruolo: res.ruolo ?? 'user',
          adminType: res.adminType ?? _adminTypeForRole(res.ruolo ?? ''),
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? ''),
        );
        if (authId == null) {
          _snack("Errore creazione login", error: true);
          return;
        }
        await _persistSecondaryRole(
          authId: authId,
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? ''),
        );
      }

      // 3) Reset password (se richiesto su login esistente)
      if (hasLogin && (res.passwordProvvisoria ?? "").isNotEmpty) {
        await _adminSetPassword(
            authId: userIdUuid, newPassword: res.passwordProvvisoria!.trim());
      }

      // 4) Modifica dati login esistente — con personale_id
      if (hasLogin) {
        final bool roleChanged = (res.ruolo ?? "").trim().isNotEmpty &&
            _normalizeRole(res.ruolo!) != _normalizeRole(currentRoleDb ?? "");

        await _adminUpdateEmployee(
          authId: userIdUuid,
          personaleId: dip["id"],
          email: (res.email ?? '').trim().isNotEmpty ? res.email!.trim() : null,
          fullName: newFullName,
          username: (res.username ?? '').trim().isNotEmpty
              ? res.username!.trim()
              : null,
          active: res.attivo,
          role: roleChanged ? res.ruolo : null,
        );
      }

      // 5) Ruolo secondario (login esistente)
      if (hasLogin) {
        await _persistSecondaryRole(
          authId: userIdUuid,
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? ''),
        );
      }

      // 6) Formazioni
      if (hasLogin && (res.urlFormazioni ?? "").isNotEmpty) {
        await FormazioniRepository.setForUser(
            userIdUuid, res.urlFormazioni!.trim());
      }

      _snack("Dipendente aggiornato");
      await _loadAll();
    } catch (e) {
      _snack("Errore modifica: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActivePersonale(Map<String, dynamic> dip) async {
    final newValue = !(dip["active"] == true);
    try {
      setState(() => _loading = true);

      await SupabaseService.client
          .from("personale")
          .update({"active": newValue}).eq("id", dip["id"]);

      _snack(newValue ? "Dipendente attivato" : "Dipendente disattivato");
      await _loadAll();
    } catch (e) {
      _snack("Errore aggiornamento stato: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePersonale(Map<String, dynamic> dip) async {
    final hard = await _confirm(
      title: "Elimina dipendente",
      message:
          "Vuoi eliminare ANCHE l'accesso Supabase?\n\n• Elimina tutto = dipendente + login\n• Mantieni riga = scollega login",
      confirmLabel: "Elimina TUTTO",
      danger: true,
    );

    var userId = (dip["user_id"] ?? "").toString().trim();
    final id = dip["id"];
    final email = (dip["email"] ?? "").toString().trim();
    final fullName = (dip["full_name"] ?? "").toString().trim();

    setState(() => _loading = true);
    try {
      if (userId.isEmpty && (email.isNotEmpty || fullName.isNotEmpty)) {
        try {
          var q = SupabaseService.client
              .from("users")
              .select("auth_id, email, full_name")
              .not("auth_id", "is", null);
          if (email.isNotEmpty) {
            q = q.ilike("email", email);
          } else {
            q = q.ilike("full_name", fullName);
          }
          final row = await q.maybeSingle();
          final auth = (row?["auth_id"] ?? "").toString().trim();
          if (auth.isNotEmpty) userId = auth;
        } catch (_) {}
      }

      if (userId.isNotEmpty) {
        await _adminDeleteUser(authId: userId, personaleId: id, hard: hard);
        try {
          await SupabaseService.client.from("personale").delete().eq("id", id);
        } catch (_) {}
        try {
          final u = await SupabaseService.client
              .from("users")
              .select("id")
              .eq("auth_id", userId)
              .maybeSingle();
          final uid = (u?["id"] as num?)?.toInt();
          if (uid != null) {
            try {
              await SupabaseService.client
                  .from("device_tokens")
                  .delete()
                  .eq("user_id", uid);
            } catch (_) {}
          }
          await SupabaseService.client.from("users").delete().eq("auth_id", userId);
        } catch (_) {}
      } else {
        if (hard) {
          await SupabaseService.client.from("personale").delete().eq("id", id);
        } else {
          await SupabaseService.client
              .from("personale")
              .update({"user_id": null}).eq("id", id);
        }
      }

      _snack(hard ? "Dipendente eliminato" : "Login eliminato");
      if (userId.isEmpty) {
        await AppActivityLogService.recordUserDelete(
          fullName: fullName,
          email: email,
        );
      }
      await _loadAll();
    } catch (e) {
      try {
        final stillExists = await SupabaseService.client
            .from("personale")
            .select("id")
            .eq("id", id)
            .maybeSingle();
        if (stillExists == null) {
          _snack("Dipendente già eliminato su Supabase. Lista aggiornata.");
          await _loadAll();
          return;
        }
      } catch (_) {
        // Se anche il check fallisce, lasciamo l'errore originale.
      }
      _snack("Errore eliminazione: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword(String authUserId, String? email) async {
    if (email == null || email.trim().isEmpty) {
      final newPw = await _askText("Nuova password provvisoria",
          hint: PasswordPolicy.rulesText, obscure: true);
      if (newPw == null || PasswordPolicy.validate(newPw) != null) {
        _snack(newPw == null ? "Annullato" : PasswordPolicy.validate(newPw)!, error: true);
        return;
      }
      setState(() => _loading = true);
      try {
        await _adminSetPassword(authId: authUserId, newPassword: newPw);
        _snack("Password aggiornata");
      } catch (e) {
        _snack("Errore reset: $e", error: true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    // Scelta flusso
    final choice = await _resetPasswordChoice();
    if (choice == null) return;

    if (choice == 'email') {
      try {
        setState(() => _loading = true);
        await _adminJwt();
        final redirect = 'https://gestopro360.it/password-recovery';
        await _invokeAdminFn(
          "admin-reset-password",
          body: {"email": email, "redirectTo": redirect},
        );
        _snack("Email di reset inviata");
      } catch (e) {
        _snack("Errore reset email: $e", error: true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final newPw = await _askText("Nuova password provvisoria",
        hint: PasswordPolicy.rulesText, obscure: true);
    if (newPw == null || PasswordPolicy.validate(newPw) != null) {
      _snack(newPw == null ? "Annullato" : PasswordPolicy.validate(newPw)!, error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await _adminSetPassword(authId: authUserId, newPassword: newPw);
      _snack("Password aggiornata");
    } catch (e) {
      _snack("Errore reset: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askText(String title,
      {String? hint, bool obscure = false}) async {
    final ctrl = TextEditingController();
    return await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: TextStyle(color: _kText.withValues(alpha: 0.9))),
        content: _NeoTextField(
            controller: ctrl, label: hint ?? '', obscure: obscure),
        actions: [
          _NeoButton(
              onTap: () => Navigator.pop(context),
              child: const Text("Annulla")),
          _NeoButton(
              onTap: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text("OK")),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compactAppBar = useUltraCompactAppBar(context);
    final filtered = _filteredPersonale();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: wrapClassicAppBarChrome(context, AppBar(
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            AppLogo(size: compactAppBar ? 28 : 44),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
              "Admin — Dipendenti",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _kText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            ),
          ],
        ),
        actions: compactAppBar
            ? [
                PopupMenuButton<String>(
                  tooltip: "Azioni",
                  onSelected: (v) {
                    if (v == 'refresh') _loadAll();
                    if (v == 'pw') _provisionDefaultPasswordForMissingLogins();
                    if (v == 'csv') _exportPersonaleCsv();
                    if (v == 'rubrica') {
                      exportPersonaleContactsForPhone(
                        context,
                        personaleRows: _personale,
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'csv',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.download_outlined),
                        title: Text('Export CSV anagrafica'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'rubrica',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.contact_phone_outlined),
                        title: Text('Esporta rubrica'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.refresh),
                        title: Text('Aggiorna'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pw',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.password, color: Color(0xFF9B1C1C)),
                        title: Text('PW 12345678'),
                      ),
                    ),
                  ],
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NeoButton(
                    onTap: _exportPersonaleCsv,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_outlined, size: 20, color: _kText),
                        SizedBox(width: 8),
                        Text("CSV"),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NeoButton(
                    onTap: () => exportPersonaleContactsForPhone(
                      context,
                      personaleRows: _personale,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.contact_phone_outlined,
                            size: 20, color: _kText),
                        SizedBox(width: 8),
                        Text("Rubrica"),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NeoButton(
                    onTap: _loadAll,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 20, color: _kText),
                        SizedBox(width: 8),
                        Text("Aggiorna"),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _NeoButton(
                    color: const Color(0xFFFFE6E6),
                    onTap: _provisionDefaultPasswordForMissingLogins,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.password, size: 20, color: Color(0xFF9B1C1C)),
                        SizedBox(width: 8),
                        Text("PW 12345678"),
                      ],
                    ),
                  ),
                ),
              ],
      )),
      floatingActionButton: _NeoFab(
        icon: Icons.person_add,
        label: "Nuovo",
        onTap: _addPersonale,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : PageWithTopLogo(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _SearchBarNeo(
                      value: _search,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _NeoButton(
                        onTap: _openCustomRolesManager,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_outlined, size: 18, color: _kText),
                            SizedBox(width: 8),
                            Text(
                              'Ruoli personalizzati e pagine visibili',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text("Nessun dipendente trovato"))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final dip = filtered[i];
                              final hasLogin =
                                  (dip["user_id"] ?? "").toString().isNotEmpty;

                              return _NeoContainer(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _kText,
                                      child: Text(
                                        dip["full_name"]
                                            .toString()
                                            .substring(0, 1)
                                            .toUpperCase(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            dip["full_name"].toString(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                    color: _kText,
                                                    fontWeight:
                                                        FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (dip["email"] ?? '—').toString(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: _kText
                                                        .withValues(alpha: 0.7)),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Tesserino: ${((dip["numero_tesserino"] ?? "").toString().trim().isEmpty) ? "—" : dip["numero_tesserino"]}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: _kText
                                                        .withValues(alpha: 0.7)),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            hasLogin
                                                ? "Login associato"
                                                : "Nessun login associato",
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: hasLogin
                                                        ? Colors.green.shade700
                                                        : Colors
                                                            .orange.shade700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: "Azioni",
                                      onPressed: () => _showActionsSheet(dip),
                                      icon: const Icon(Icons.more_vert,
                                          color: _kText),
                                    ),
                                  ],
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

  // Bottom sheet con azioni riga (mobile-friendly)
  Future<void> _showActionsSheet(Map<String, dynamic> dip) async {
    final hasLogin = (dip["user_id"] ?? "").toString().isNotEmpty;
    final isActive = dip["active"] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.of(sheetCtx).viewPadding.bottom;
        return SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomInset + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined, color: _kText),
                  title: const Text("DPI"),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openDpiManager(dip);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.checkroom_outlined, color: _kText),
                  title: const Text("Vestiario"),
                  subtitle: const Text("Misure vestiario del dipendente"),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openVestiarioEditor(dip);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: _kText),
                  title: const Text("Modifica"),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _editPersonaleFull(dip);
                  },
                ),
                ListTile(
                  leading: Icon(
                      isActive ? Icons.visibility_off : Icons.visibility,
                      color: _kText),
                  title: Text(isActive ? "Disattiva" : "Attiva"),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _toggleActivePersonale(dip);
                  },
                ),
                ListTile(
                  enabled: hasLogin,
                  leading: const Icon(Icons.lock_reset, color: _kText),
                  title: const Text("Reset password"),
                  onTap: hasLogin
                      ? () {
                          Navigator.pop(context);
                          _resetPassword(
                            dip["user_id"]?.toString() ?? "",
                            dip["email"]?.toString(),
                          );
                        }
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text("Elimina"),
                  onTap: () {
                    Navigator.pop(context);
                    _deletePersonale(dip);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // Bottom sheet con form (create/edit) — versione compatta/adattiva
  Future<_DipFullData?> _showDipSheet({
    required bool isEdit,
    required bool hasLogin,
    required _DipFullData initial,
    int? personaleId,
    String? personaleIdUuid,
  }) async {
    final mq = MediaQuery.of(context);
    final isPhone = mq.size.shortestSide < 600; // telefono vs tablet

    // Altezza iniziale + massima più basse su phone; più generose su tablet
    final double initialFactor = isPhone ? 0.76 : 0.90;
    final double maxFactor = isPhone ? 0.90 : 0.98;

    return await showModalBottomSheet<_DipFullData?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: _DipFullSheet(
            isEdit: isEdit,
            hasLogin: hasLogin,
            roleOptions: _roleOptions,
            personaleId: personaleId,
            personaleIdUuid: personaleIdUuid,
            initial: initial,
            initialChildSize: initialFactor,
            maxChildSize: maxFactor,
          ),
        );
      },
    );
  }
}

/// Ricerca Neumorfica
class _SearchBarNeo extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchBarNeo({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return _NeoContainer(
      child: Row(
        children: [
          const Icon(Icons.search, color: _kText),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "Cerca per nome o email",
              ),
            ),
          ),
          if (value.isNotEmpty)
            InkWell(
              onTap: () => onChanged(""),
              child: const Icon(Icons.close, color: _kText),
            ),
        ],
      ),
    );
  }
}

/// FAB rotondo Neumorphic
class _NeoFab extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _NeoFab({
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _neoDecoration(radius: 28),
      child: FloatingActionButton.extended(
        backgroundColor: _kBg,
        foregroundColor: _kText,
        elevation: 0,
        icon: Icon(icon),
        label: Text(label ?? "Nuovo"),
        onPressed: onTap,
      ),
    );
  }
}

/// DTO
class _DipFullData {
  final String nome;
  final String cognome;
  final bool attivo;
  final String cameraTipoDefault;
  final String matricola;
  final String telefono;
  final String dataAssunzione;
  final String dataNascita;
  final String numeroTesserino;
  final String fotoTesserinoPath;
  final String ruoloAziendale;
  final bool creaLogin;
  final String? username;
  final String? email;
  final String? ruolo;
  final String? ruoloSecondario;
  final String? passwordProvvisoria;
  final String? urlFormazioni;
  final int? adminType;
  final int? adminTypeSecondario;

  const _DipFullData({
    required this.nome,
    required this.cognome,
    required this.attivo,
    required this.cameraTipoDefault,
    this.matricola = '',
    this.telefono = '',
    this.dataAssunzione = '',
    this.dataNascita = '',
    this.numeroTesserino = '',
    this.fotoTesserinoPath = '',
    this.ruoloAziendale = '',
    required this.creaLogin,
    this.username,
    this.email,
    this.ruolo,
    this.ruoloSecondario,
    this.passwordProvvisoria,
    this.urlFormazioni,
    this.adminType,
    this.adminTypeSecondario,
  });
}

/// Bottom Sheet: Create/Edit Dipendente (layout mobile) — COMPATTO/ADATTIVO
class _DipFullSheet extends StatefulWidget {
  final _DipFullData initial;
  final bool isEdit;
  final bool hasLogin;
  final List<String> roleOptions;
  final int? personaleId;
  final String? personaleIdUuid;

  // ➜ fattori per altezza adattiva
  final double initialChildSize;
  final double maxChildSize;

  const _DipFullSheet({
    required this.initial,
    required this.isEdit,
    required this.hasLogin,
    required this.roleOptions,
    this.personaleId,
    this.personaleIdUuid,
    this.initialChildSize = 0.86,
    this.maxChildSize = 0.96,
  });

  @override
  State<_DipFullSheet> createState() => _DipFullSheetState();
}

class _DipFullSheetState extends State<_DipFullSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nome;
  late TextEditingController _cognome;
  late TextEditingController _username;
  late TextEditingController _email;
  late TextEditingController _password;
  late TextEditingController _urlForm;
  late TextEditingController _numeroTesserino;
  late TextEditingController _matricola;
  late TextEditingController _telefono;
  late TextEditingController _dataAssunzione;
  late TextEditingController _dataNascita;
  late TextEditingController _ruoloAziendale;

  String _fotoTesserinoPath = '';
  bool _fotoUploading = false;

  bool _attivo = true;
  String _cameraTipoDefault = "doppia";
  bool _creaLogin = true;
  String _ruolo = "user";
  String _ruoloSecondario = "";
  int _adminType = 1;
  int _adminTypeSecondario = 1;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nome = TextEditingController(text: i.nome);
    _cognome = TextEditingController(text: i.cognome);
    _attivo = i.attivo;
    _cameraTipoDefault = (i.cameraTipoDefault.trim().toLowerCase() == "singola")
        ? "singola"
        : "doppia";
    _matricola = TextEditingController(text: i.matricola);
    _telefono = TextEditingController(text: i.telefono);
    _dataAssunzione =
        TextEditingController(text: formatDateDdMmYyyy(i.dataAssunzione));
    _dataNascita =
        TextEditingController(text: formatDateDdMmYyyy(i.dataNascita));
    _ruoloAziendale = TextEditingController(text: i.ruoloAziendale);
    _fotoTesserinoPath = i.fotoTesserinoPath.trim();
    _creaLogin = i.creaLogin;
    _username = TextEditingController(text: i.username ?? "");
    _email = TextEditingController(text: i.email ?? "");
    _ruolo = i.ruolo ?? "user";
    _ruoloSecondario = i.ruoloSecondario ?? "";
    _password = TextEditingController(text: i.passwordProvvisoria ?? "");
    _urlForm = TextEditingController(text: i.urlFormazioni ?? "");
    _numeroTesserino = TextEditingController(text: i.numeroTesserino.trim());
    _adminType = i.adminType ?? 1;
    _adminTypeSecondario = i.adminTypeSecondario ?? 1;
    if (!widget.isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTesserinoPreview());
    }
  }

  void _refreshTesserinoPreview() {
    if (widget.isEdit) return;
    final prefix = tesserinoPrefixFromParts(
      cognome: _cognome.text.trim(),
      nome: _nome.text.trim(),
    );
    _numeroTesserino.text = (_cognome.text.trim().isEmpty && _nome.text.trim().isEmpty)
        ? ''
        : '$prefix… (al salvataggio)';
  }

  Future<void> _pickAndUploadFoto() async {
    final pid = widget.personaleId;
    final uuid = (widget.personaleIdUuid ?? '').trim();
    if (pid == null || uuid.isEmpty) return;

    TesserinoPickedImage? picked;
    try {
      picked = await pickTesserinoImageInteractive(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Elaborazione foto: $e')),
        );
      }
      return;
    }
    if (picked == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuna foto selezionata.')),
        );
      }
      return;
    }

    setState(() => _fotoUploading = true);
    try {
      final path = await runWithTesserinoPhotoBusy(
        context,
        () => uploadTesserinoFotoForPersonale(
          supa: SupabaseService.client,
          personaleId: pid,
          personaleIdUuid: uuid,
          image: picked!,
          existingStoragePath: _fotoTesserinoPath,
        ),
        message: 'Caricamento foto…',
      );
      if (!mounted) return;
      if (path == null || path.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caricamento foto non riuscito.')),
        );
        return;
      }
      setState(() => _fotoTesserinoPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto aggiornata')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload fallito: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _fotoUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogin = widget.hasLogin;
    final ruoloValue =
        widget.roleOptions.contains(_ruolo) ? _ruolo : "user";
    final ruoloSecondarioValue = _ruoloSecondario.isEmpty
        ? "__none__"
        : (widget.roleOptions.contains(_ruoloSecondario)
            ? _ruoloSecondario
            : "__none__");

    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: widget.initialChildSize,
      minChildSize: 0.60,
      maxChildSize: widget.maxChildSize,
      builder: (ctx, controller) {
        return SingleChildScrollView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // maniglia
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _kText.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              // titolo
              Text(
                widget.isEdit ? "Modifica Dipendente" : "Nuovo Dipendente",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),

              // FORM (gap compatti)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _NeoTextField(
                            controller: _cognome,
                            label: "Cognome",
                            onChanged: _refreshTesserinoPreview,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NeoTextField(
                            controller: _nome,
                            label: "Nome",
                            onChanged: _refreshTesserinoPreview,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _NeoContainer(
                      child: SwitchListTile(
                        value: _attivo,
                        onChanged: (v) => setState(() => _attivo = v),
                        title: const Text("Attivo",
                            style: TextStyle(color: _kText)),
                        activeThumbColor: _kAccent,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _NeoContainer(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          labelText: "Tipo camera default",
                        ),
                        initialValue: _cameraTipoDefault,
                        items: const [
                          DropdownMenuItem(value: "singola", child: Text("Singola")),
                          DropdownMenuItem(value: "doppia", child: Text("Doppia")),
                        ],
                        onChanged: (v) =>
                            setState(() => _cameraTipoDefault = v ?? "doppia"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _matricola,
                      label: "Matricola",
                    ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _ruoloAziendale,
                      label: "Ruolo in azienda",
                    ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _telefono,
                      label: "Telefono",
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _dataAssunzione,
                      label: "Data assunzione (GG/MM/AAAA)",
                    ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _numeroTesserino,
                      label: "N. tesserino",
                      readOnly: true,
                    ),
                    if (!widget.isEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Assegnato al salvataggio (es. PATGIU01001).',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: _kText.withValues(alpha: 0.55),
                                ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    _NeoTextField(
                      controller: _dataNascita,
                      label: "Data di nascita (GG/MM/AAAA)",
                    ),
                    const SizedBox(height: 10),
                    PersonaleTesserinoFotoSection(
                      fotoPath: _fotoTesserinoPath,
                      canUpload: widget.isEdit &&
                          widget.personaleId != null &&
                          (widget.personaleIdUuid ?? '').trim().isNotEmpty,
                      uploading: _fotoUploading,
                      onUpload: _pickAndUploadFoto,
                      textColor: _kText,
                    ),
                    const SizedBox(height: 10),
                    if (!widget.hasLogin)
                      _NeoContainer(
                        child: SwitchListTile(
                          value: _creaLogin,
                          onChanged: (v) => setState(() => _creaLogin = v),
                          title: const Text("Crea login",
                              style: TextStyle(color: _kText)),
                          activeThumbColor: _kAccent,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (_creaLogin || widget.hasLogin) ...[
                      const SizedBox(height: 10),
                      _NeoTextField(
                        controller: _username,
                        label: widget.hasLogin
                            ? "Username (opzionale)"
                            : "Username",
                      ),
                      const SizedBox(height: 10),
                      _NeoTextField(
                        controller: _email,
                        label: "Email",
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 10),
                      _NeoContainer(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            labelText: "Ruolo",
                          ),
                          initialValue: ruoloValue,
                          items: widget.roleOptions
                              .map((r) =>
                                  DropdownMenuItem(value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _ruolo = v ?? "user"),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _NeoContainer(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            labelText: "Ruolo secondario (opzionale)",
                          ),
                          initialValue: ruoloSecondarioValue,
                          items: <String>["__none__", ...widget.roleOptions]
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(
                                        r == "__none__" ? "Nessuno" : r),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            final next = v ?? "__none__";
                            _ruoloSecondario =
                                next == "__none__" ? "" : next;
                            if (_normalizeRole(_ruoloSecondario) ==
                                _normalizeRole(_ruolo)) {
                              _ruoloSecondario = "";
                            }
                          }),
                        ),
                      ),
                      if (_ruolo.toLowerCase() == "admin") ...[
                        const SizedBox(height: 10),
                        _NeoContainer(
                          child: DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              labelText: "Tipo admin (chi riceve notifiche)",
                            ),
                            initialValue: _adminType,
                            items: const [
                              DropdownMenuItem(
                                  value: 1, child: Text("Nessuna notifica")),
                              DropdownMenuItem(
                                  value: 2,
                                  child: Text("Admin pernottamenti")),
                              DropdownMenuItem(
                                  value: 3,
                                  child: Text("Admin treni/aerei")),
                            ],
                            onChanged: (v) =>
                                setState(() => _adminType = v ?? 1),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _NeoTextField(
                        controller: _password,
                        label: widget.hasLogin
                            ? "Nuova password (opzionale)"
                            : "Password provvisoria",
                        obscure: true,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _NeoTextField(
                        controller: _urlForm,
                        label: "URL Formazioni (opzionale)"),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Bottoni azione
              Row(
                children: [
                  Expanded(
                    child: _NeoButton(
                      onTap: () => Navigator.pop(context),
                      child: const Center(child: Text("Annulla")),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NeoButton(
                      onTap: () {
                        // Validazioni (identiche alla tua versione)
                        if (_nome.text.trim().isEmpty ||
                            _cognome.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text("Nome e Cognome sono obbligatori")),
                          );
                          return;
                        }

                        final emailTxt = _email.text.trim();
                        final emailOk = emailTxt.isEmpty ||
                            RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(emailTxt);
                        if (!emailOk) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Email non valida")),
                          );
                          return;
                        }

                        final dataAssunzioneTxt = _dataAssunzione.text.trim();
                        final dataAssunzioneIso =
                            parseFlexibleDateToIsoDate(dataAssunzioneTxt);
                        if (dataAssunzioneTxt.isNotEmpty &&
                            dataAssunzioneIso == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  "Data assunzione non valida. Usa GG/MM/AAAA"),
                            ),
                          );
                          return;
                        }
                        final dataNascitaTxt = _dataNascita.text.trim();
                        final dataNascitaIso =
                            parseFlexibleDateToIsoDate(dataNascitaTxt);
                        if (dataNascitaTxt.isNotEmpty && dataNascitaIso == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  "Data di nascita non valida. Usa GG/MM/AAAA"),
                            ),
                          );
                          return;
                        }

                        if (!widget.hasLogin && _creaLogin) {
                          final u = _username.text.trim();
                          final p = _password.text.trim();
                          final mustEmailOk = RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                              .hasMatch(emailTxt);
                          if (u.isEmpty || !mustEmailOk || p.length < 8) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Per creare il login servono Username, Email valida e Password (min 8)",
                                ),
                              ),
                            );
                            return;
                          }
                        }

                        Navigator.pop(
                          context,
                          _DipFullData(
                            nome: _nome.text.trim(),
                            cognome: _cognome.text.trim(),
                            attivo: _attivo,
                            cameraTipoDefault: _cameraTipoDefault,
                            matricola: _matricola.text.trim(),
                            telefono: _telefono.text.trim(),
                            dataAssunzione: dataAssunzioneIso ?? "",
                            dataNascita: dataNascitaIso ?? "",
                            fotoTesserinoPath: _fotoTesserinoPath,
                            ruoloAziendale: _ruoloAziendale.text.trim(),
                            creaLogin: hasLogin ? false : _creaLogin,
                            username: _username.text.trim(),
                            email: _email.text.trim(),
                            ruolo: _ruolo,
                            ruoloSecondario: _ruoloSecondario.trim().isEmpty
                                ? null
                                : _ruoloSecondario.trim(),
                            passwordProvvisoria: _password.text.trim(),
                            urlFormazioni: _urlForm.text.trim(),
                            numeroTesserino: _numeroTesserino.text.trim(),
                            adminType: _adminTypeForRole(_ruolo) ??
                                (_ruolo.toLowerCase() == "admin"
                                    ? _adminType
                                    : null),
                            adminTypeSecondario:
                                _ruoloSecondario.trim().isEmpty
                                    ? null
                                    : (_adminTypeForRole(_ruoloSecondario) ??
                                        (_normalizeRole(_ruoloSecondario) ==
                                                "admin"
                                            ? _adminTypeSecondario
                                            : null)),
                          ),
                        );
                      },
                      child: Center(
                        child: Text(
                          widget.isEdit ? "Salva" : "Crea",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Supporto nome/cognome
class _NamePair {
  final String nome;
  final String cognome;
  const _NamePair(this.nome, this.cognome);
}
