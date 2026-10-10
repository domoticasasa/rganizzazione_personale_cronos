import '../utils/password_policy.dart';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/admin_vista_guard.dart';
import '../utils/excel_export_helper.dart';
import '../services/app_activity_log_service.dart';
import '../services/supabase_service.dart';
import '../services/formazioni_repository.dart';
import '../services/numero_tesserino_service.dart';
import '../utils/numero_tesserino_generator.dart';
import '../services/confirm_sound_service.dart';
import '../utils/date_formatters.dart';
import '../utils/responsive.dart';
import '../services/tesserino_foto.dart';
import '../widgets/admin_custom_roles_dialog.dart';
import '../widgets/personale_tesserino_foto_section.dart';
import '../utils/personale_contacts_export.dart';
import '../utils/personale_data_export.dart';
import '../utils/users_directory.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../theme/cronos_app_themes.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/futuristic/futuristic_inline_toolbar.dart';
import '../widgets/futuristic/futuristic_shell_scope.dart';

bool _isGestopro(BuildContext context) =>
    FuturisticShellScope.hideChromeOf(context);

class _DipPageColors {
  const _DipPageColors({
    required this.bg,
    required this.text,
    required this.accent,
    required this.panel,
    required this.useNeumorph,
  });

  final Color bg;
  final Color text;
  final Color accent;
  final Color panel;
  final bool useNeumorph;

  factory _DipPageColors.of(BuildContext context) {
    if (_isGestopro(context)) {
      return _DipPageColors(
        bg: Colors.transparent,
        text: CronosFuturisticTheme.textPrimary,
        accent: CronosFuturisticTheme.electricBright,
        panel: CronosFuturisticTheme.glassPanel.withValues(alpha: 0.9),
        useNeumorph: false,
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _DipPageColors(
      bg: dark ? CronosAppThemes.darkCanvas : _kBg,
      text: dark ? CronosAppThemes.darkSidebarFg : _kText,
      accent: _kAccent,
      panel: dark ? CronosAppThemes.darkSurface : _kBg,
      useNeumorph: !dark,
    );
  }
}

BoxDecoration _panelDecoration(
  BuildContext context, {
  double radius = 14,
  bool inset = false,
  Color? color,
}) {
  final c = _DipPageColors.of(context);
  if (!c.useNeumorph) {
    return BoxDecoration(
      color: color ?? c.panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: CronosFuturisticTheme.electricBright.withValues(alpha: 0.22),
      ),
    );
  }
  return _neoDecoration(radius: radius, inset: inset, color: color ?? c.bg);
}
///  Neumorphism Soft (Light) – Palette & Helpers
/// ─────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFFECECEC); // sfondo principale (Neumorphism Light)
const _kShadowDark = Color(0xFFBEBEBE);
const _kShadowLight = Color(0xFFFFFFFF);
const _kText = Color(0xFF222222);
const _kAccent = Color(0xFF2F6FED);

BoxDecoration _neoDecoration({
  double radius = 14,
  bool inset = false,
  Color? color,
}) {
  return BoxDecoration(
    color: color ?? _kBg,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: _kShadowDark.withValues(alpha: 0.6),
        offset: const Offset(6, 6),
        blurRadius: 12,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: _kShadowLight.withValues(alpha: 0.9),
        offset: const Offset(-6, -6),
        blurRadius: 12,
        spreadRadius: 0,
      ),
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
    this.margin = EdgeInsets.zero,
  })  : radius = 14,
        color = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: _panelDecoration(context, radius: radius, color: color),
      child: Padding(
        padding: padding,
        child: child,
      ),
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
    final colors = _DipPageColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: _panelDecoration(
          context,
          radius: radius,
          color: color ??
              (enabled
                  ? null
                  : colors.panel.withValues(alpha: colors.useNeumorph ? 0.6 : 0.5)),
        ),
        padding: padding,
        child: DefaultTextStyle(
          style: Theme.of(context)
              .textTheme
              .labelLarge!
              .copyWith(
                color: enabled ? colors.text : colors.text.withValues(alpha: 0.4),
              ),
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
    final colors = _DipPageColors.of(context);
    return _NeoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        readOnly: readOnly,
        onChanged: onChanged == null ? null : (_) => onChanged!(),
        keyboardType: keyboardType,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.text.withValues(alpha: 0.7)),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Ruoli (UI vs DB)
/// ─────────────────────────────────────────────────────────────────────────

/// Ruoli disponibili per UI (label)
const kRuoliUtenteBase = <String>[
  "Admin generale",
  "Admin vista",
  "Admin pernottamenti",
  "Admin treni/aerei",
  "Admin DPI",
  "Admin Formazione",
  "admin",
  "Caposquadra",
  "DT",
  "Assistente DT",
  "user",
  "dipendente",
];

/// UI → DB (sempre lowercase)
String _normalizeRole(String r) {
  final t = r.trim().toLowerCase().replaceAll(' ', '_').replaceAll('/', '_');
  if (t == "admin_generale") return "admin_generale";
  if (t == "admin_vista" ||
      t == "admin_readonly" ||
      t == "admin_sola_lettura" ||
      t == "admin_sola_vista") {
    return "admin_vista";
  }
  if (t == "admin_pernottamenti") return "admin_pernottamenti";
  if (t == "admin_treni/aerei" || t == "admin_treni_aerei") {
    return "admin_trenoaereo";
  }
  if (t == "admin_dpi" || t == "admin_dpe") return "admin_dpi";
  if (t == "admin_formazione" || t == "admin_training") {
    return "admin_formazione";
  }
  if (t == "caposquadra") return "caposquadra";
  if (t == "admin") return "admin";
  if (t == "user") return "user";
  if (t == "dt") return "dt";
  if (t == "assistente_dt") return "assistente_dt";
  return t;
}

/// DB → UI
String _roleDbToUi(String r) {
  final t = r.trim().toLowerCase().replaceAll(' ', '_');
  if (t == "admin_generale") return "Admin generale";
  if (t == "admin_vista") return "Admin vista";
  if (t == "admin_pernottamenti") return "Admin pernottamenti";
  if (t == "admin_trenoaereo") return "Admin treni/aerei";
  if (t == "admin_dpi") return "Admin DPI";
  if (t == "admin_formazione") return "Admin Formazione";
  if (t == "caposquadra") return "Caposquadra";
  if (t == "admin") return "admin";
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
  } catch (_) {
    // Best effort: the edge function remains the source of truth.
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Pagina
/// ─────────────────────────────────────────────────────────────────────────

class AdminGestioneDipendentiPage extends StatefulWidget {
  const AdminGestioneDipendentiPage({super.key});

  @override
  State<AdminGestioneDipendentiPage> createState() =>
      _AdminGestioneDipendentiPageState();
}

class _AdminGestioneDipendentiPageState
    extends State<AdminGestioneDipendentiPage> {
  final _supa = SupabaseService.client;
  List<Map<String, dynamic>> _personale = [];
  List<String> _roleOptions = [...kRuoliUtenteBase];
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
      final customRoleKeys = await fetchCustomRoleKeys(_supa);
      if (!mounted) return;
      setState(() {
        _roleOptions = [...kRuoliUtenteBase, ...customRoleKeys];
      });
    } catch (_) {
      // No-op: keep base roles if tables are not available yet.
    }
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
        final personaleId = dip["id"] as int;
        final email = (dip["email"] ?? "").toString().trim();
        final fullName = (dip["full_name"] ?? "").toString().trim();
        final username = buildUsername(fullName, email);
        final roleUi = "user";

        try {
          final authId = await _adminCreateUser(
            personaleId: personaleId,
            email: email,
            password: pw,
            username: username,
            fullName: fullName.isNotEmpty ? fullName : email,
            ruolo: roleUi,
            adminType: null,
          );

          if (authId == null || authId.isEmpty) {
            failedCount++;
            failures.add('$email: login non creato (risposta vuota)');
            continue;
          }

          // Password e must_change_password già impostati da admin-create-user.
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

  /// Notifiche UI
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
        content: Text(msg),
      ),
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
      'Data produzione: ${_safeText((row['data_produzione'] ?? '').toString())}',
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
      'Dt:${_fit((row['data_produzione'] ?? '').toString(), 10)}',
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
    const categorie = <String>[
      'Elmetto',
      'Imbracatura',
      'Cordino',
      'Guanti',
      'Occhiali',
      'Scarpe',
    ];

    final personaleUuid = (dip['id_uuid'] ?? '').toString().trim();
    if (personaleUuid.isEmpty) {
      _snack('ID UUID personale mancante', error: true);
      return;
    }

    List<Map<String, dynamic>> rows = [];
    bool saveDpiInFlight = false;

    Future<void> loadRows(StateSetter setSt) async {
      try {
        final res = await SupabaseService.client
            .from('dpi_dotazioni')
            .select(
                'id, categoria, quantita_assegnata, marca, data_produzione, data_consegna, data_revisione, matricola, modello, created_at')
            .eq('personale_id', personaleUuid)
            .order('categoria')
            .order('created_at');
        rows = List<Map<String, dynamic>>.from(res as List);
        setSt(() {});
      } catch (e) {
        _snack('Errore caricamento DPI: $e', error: true);
      }
    }

    Future<void> saveForm(StateSetter setSt,
        {Map<String, dynamic>? current}) async {
      if (saveDpiInFlight) return;
      String categoria = (current?['categoria'] ?? categorie.first).toString();
      final qCtrl = TextEditingController(
          text: (current?['quantita_assegnata'] ?? 1).toString());
      final marcaCtrl =
          TextEditingController(text: (current?['marca'] ?? '').toString());
      final dataCtrl = TextEditingController(
          text: (current?['data_produzione'] ?? '').toString());
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
                        labelText: 'Data produzione (GG/MM/AAAA)',
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
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salva'),
              ),
            ],
          ),
        ),
      );

      if (ok != true) return;
      saveDpiInFlight = true;
      final quantita = int.tryParse(qCtrl.text.trim());
      if (quantita == null || quantita < 0) {
        _snack('Quantita assegnata non valida.', error: true);
        return;
      }
      final dataStr = dataCtrl.text.trim();
      final dataProduzioneIso = parseFlexibleDateToIsoDate(dataStr);
      if (dataStr.isNotEmpty && dataProduzioneIso == null) {
        _snack('Data produzione non valida. Usa formato GG/MM/AAAA.',
            error: true);
        return;
      }

      try {
        final payload = {
          'personale_id': personaleUuid,
          'categoria': categoria,
          'quantita_assegnata': quantita,
          'marca': marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
          'data_produzione': dataProduzioneIso,
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
        await loadRows(setSt);
      } catch (e) {
        _snack('Errore salvataggio DPI: $e', error: true);
      } finally {
        saveDpiInFlight = false;
      }
    }

    Future<void> exportDpiIIIExcel(StateSetter setSt) async {
      if (rows.isEmpty) {
        await loadRows(setSt);
      }
      if (rows.isEmpty) {
        _snack('Nessun DPI da esportare.', error: true);
        return;
      }
      try {
        final excel = Excel.createExcel();
        final sheet = excel['DPI III Cat'];
        sheet.appendRow(const <String>[
          'Categoria',
          'Qta',
          'Marca',
          'Modello',
          'Matricola',
          'Data produzione',
          'Data consegna',
          'Data revisione',
        ]);
        for (final r in rows) {
          sheet.appendRow(<Object?>[
            (r['categoria'] ?? '').toString(),
            int.tryParse((r['quantita_assegnata'] ?? '').toString()) ?? 0,
            (r['marca'] ?? '').toString(),
            (r['modello'] ?? '').toString(),
            (r['matricola'] ?? '').toString(),
            (r['data_produzione'] ?? '').toString(),
            (r['data_consegna'] ?? '').toString(),
            (r['data_revisione'] ?? '').toString(),
          ]);
        }
        final bytes = excel.encode();
        if (bytes == null || bytes.isEmpty) {
          _snack('Impossibile generare il file Excel.', error: true);
          return;
        }
        final fullName = (dip['full_name'] ?? '').toString().trim();
        final safeName = fullName.isEmpty
            ? 'dipendente'
            : fullName.replaceAll(RegExp(r'[^\w\-]+'), '_');
        final ok = await ExcelExportHelper.saveAndReveal(
          pageName: 'DPI_III_$safeName',
          bytes: Uint8List.fromList(bytes),
          extension: 'xlsx',
          openFile: true,
        );
        if (ok) {
          _snack('Export Excel completato.');
        } else {
          _snack('Export annullato.');
        }
      } catch (e) {
        _snack('Errore export Excel DPI: $e', error: true);
      }
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          if (rows.isEmpty) {
            loadRows(setSt);
          }
          return AlertDialog(
            title: Text('DPI - ${(dip['full_name'] ?? '').toString()}'),
            content: SizedBox(
              width: 980,
              child: rows.isEmpty
                  ? const Center(child: Text('Nessun DPI assegnato'))
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Categoria')),
                            DataColumn(label: Text('Qta')),
                            DataColumn(label: Text('Marca')),
                            DataColumn(label: Text('Data prod.')),
                            DataColumn(label: Text('Matricola')),
                            DataColumn(label: Text('Modello')),
                            DataColumn(label: Text('NFC')),
                            DataColumn(label: Text('Azioni')),
                          ],
                          rows: rows.map(
                            (r) {
                              final dt = DateTime.tryParse(
                                  (r['created_at'] ?? '').toString());
                              final insertedAt =
                                  dt == null ? '—' : formatDateTimeIt(dt);
                              return DataRow(
                                cells: [
                                  DataCell(
                                      Text((r['categoria'] ?? '').toString())),
                                  DataCell(Text((r['quantita_assegnata'] ?? '')
                                      .toString())),
                                  DataCell(Text((r['marca'] ?? '').toString())),
                                  DataCell(Text(
                                      (r['data_produzione'] ?? '').toString())),
                                  DataCell(
                                      Text((r['matricola'] ?? '').toString())),
                                  DataCell(
                                      Text((r['modello'] ?? '').toString())),
                                  DataCell(
                                    FilledButton.tonalIcon(
                                      onPressed: () => _writeDpiToNfc(
                                        fullName:
                                            (dip['full_name'] ?? '').toString(),
                                        row: r,
                                      ),
                                      icon: const Icon(Icons.nfc),
                                      label: const Text('Scrivi su NFC'),
                                    ),
                                  ),
                                  DataCell(
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        IconButton(
                                          icon:
                                              const Icon(Icons.edit, size: 18),
                                          onPressed: () =>
                                              saveForm(setSt, current: r),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            await SupabaseService.client
                                                .from('dpi_dotazioni')
                                                .delete()
                                                .eq('id', r['id']);
                                            _snack('DPI eliminato');
                                            await loadRows(setSt);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ]
                                    .map((c) => DataCell(
                                          Tooltip(
                                            message: 'Inserita il: $insertedAt',
                                            waitDuration: const Duration(
                                                milliseconds: 220),
                                            child: c.child,
                                          ),
                                        ))
                                    .toList(),
                              );
                            },
                          ).toList(),
                        ),
                      ),
                    ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => exportDpiIIIExcel(setSt),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export Excel'),
              ),
              FilledButton.icon(
                onPressed: () => saveForm(setSt),
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

  /// Conferma azioni importanti
  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmLabel = "Conferma",
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content:
            Text(message),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          _NeoButton(
            onTap: () => Navigator.pop(context, false),
            child: const Text("Annulla"),
          ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          "Reset Password",
        ),
        content: const Text(
          "Come vuoi procedere con il reset della password?",
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  /// Filtro ricerca
  bool _matchesSearch(Map<String, dynamic> dip) {
    final q = _search.toLowerCase().trim();
    if (q.isEmpty) return true;

    return dip["full_name"].toString().toLowerCase().contains(q) ||
        (dip["matricola"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["ruolo_aziendale"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["numero_tesserino"] ?? "").toString().toLowerCase().contains(q) ||
        (dip["telefono"] ?? "").toString().toLowerCase().contains(q) ||
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
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw Exception("Sessione admin scaduta");

    final normRole = _normalizeRole(ruolo);
    final resolvedAdminType = adminType ?? _adminTypeForRole(ruolo);
    final res = await Supabase.instance.client.functions.invoke(
      "admin-create-user",
      body: {
        "email": email.trim(),
        "password": password.trim(),
        "username": username.trim(),
        "full_name": fullName,
        "role": normRole,
        "admin_type": ?resolvedAdminType,
        if ((secondaryRole ?? '').trim().isNotEmpty)
          "secondary_role": _normalizeRole(secondaryRole!),
        "secondary_admin_type": ?secondaryAdminType,
        "personale_id": personaleId,
      },
      headers: {"Authorization": "Bearer $jwt"},
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
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw Exception("Sessione scaduta");

    await Supabase.instance.client.functions.invoke(
      "admin-set-password",
      body: {
        "auth_id": authId,
        "new_password": newPassword,
      },
      headers: {"Authorization": "Bearer $jwt"},
    );
  }

  Future<void> _adminDeleteUser({
    required String authId,
    required int personaleId,
    required bool hard,
  }) async {
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw Exception("Sessione scaduta");

    await Supabase.instance.client.functions.invoke(
      "admin-delete-user",
      body: {
        "auth_id": authId,
        "personale_id": personaleId,
        "mode": hard ? "hard" : "soft",
      },
      headers: {"Authorization": "Bearer $jwt"},
    );
  }

  Future<void> _adminUpdateEmployee({
    String? authId,
    int? userId,
    int? personaleId, // ← FIX: supporto per personale_id
    String? email,
    String? fullName,
    String? username,
    bool? active,
    String? role,
    String? secondaryRole,
    String? password, // opzionale
    bool notify = false, // opzionale
    int? adminType,
    int? secondaryAdminType,
  }) async {
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw Exception("Sessione scaduta");

    final body = <String, dynamic>{};

    if (authId != null && authId.trim().isNotEmpty) {
      body['auth_id'] = authId.trim();
    }
    if (userId != null) body['user_id'] = userId;
    if (personaleId != null) {
      body['personale_id'] = personaleId; // ← FIX nel payload
    }

    if (email != null && email.trim().isNotEmpty) {
      body['email'] = email.trim();
    }
    if (fullName != null && fullName.trim().isNotEmpty) {
      body['full_name'] = fullName.trim();
    }
    if (username != null && username.trim().isNotEmpty) {
      body['username'] = username.trim();
    }
    if (active != null) body['active'] = active;
    if (role != null && role.trim().isNotEmpty) {
      final normRole = _normalizeRole(role);
      final resolvedAdminType = adminType ?? _adminTypeForRole(role);
      body['role'] = normRole;
      if (resolvedAdminType != null) body['admin_type'] = resolvedAdminType;
    } else if (adminType != null) {
      body['admin_type'] = adminType;
    }
    if (secondaryRole != null) {
      final t = secondaryRole.trim();
      body['secondary_role'] = t.isEmpty ? null : _normalizeRole(t);
      body['secondary_admin_type'] =
          t.isEmpty ? null : (secondaryAdminType ?? _adminTypeForRole(t));
    } else if (secondaryAdminType != null) {
      body['secondary_admin_type'] = secondaryAdminType;
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (notify) body['notify'] = true;

    final res = await Supabase.instance.client.functions.invoke(
      "admin-update-employee",
      headers: {"Authorization": "Bearer $jwt"},
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
    if (_addPersonaleInFlight) return;
    if (!await ensureCanPersist(context)) return;
    final res = await showDialog<_DipFullData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DipFullDialog(
        isEdit: false,
        hasLogin: false,
        roleOptions: _roleOptions,
        initial: _DipFullData(
          nome: '',
          cognome: '',
          attivo: true,
          cameraTipoDefault: 'doppia',
          matricola: '',
          telefono: '',
          dataAssunzione: '',
          dataNascita: '',
          numeroTesserino: '',
          fotoTesserinoPath: '',
          ruoloAziendale: '',
          creaLogin: kIsWeb ? false : true,
          username: '',
          email: '',
          ruolo: 'user',
          passwordProvvisoria: '',
          urlFormazioni: '',
          adminType: 1,
        ),
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
          error: true,
        );
        return;
      }
    }

    _addPersonaleInFlight = true;
    setState(() => _loading = true);
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
      String? loginWarn;
      if (res.creaLogin) {
        try {
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
            loginWarn = "Dipendente creato, ma login non creato.";
          } else {
            await _persistSecondaryRole(
              authId: authId,
              secondaryRole: res.ruoloSecondario,
              secondaryAdminType: res.adminTypeSecondario ??
                  _adminTypeForRole(res.ruoloSecondario ?? ''),
            );
          }
        } catch (e) {
          loginWarn = "Dipendente creato, ma login non creato: $e";
        }
      }

      // 3) Formazioni (se presente e se ho authId)
      if ((res.urlFormazioni ?? '').trim().isNotEmpty &&
          (authId ?? '').isNotEmpty) {
        await FormazioniRepository.setForUser(
            authId!, res.urlFormazioni!.trim());
      }

      await _loadAll();
      if ((loginWarn ?? '').isNotEmpty) {
        _snack(loginWarn!, error: true);
      } else {
        _snack("Dipendente creato");
      }
      if (!(res.creaLogin && (authId ?? '').isNotEmpty)) {
        await AppActivityLogService.recordUserCreate(
          fullName: fullName,
          email: (res.email ?? '').trim(),
          login: false,
        );
      }
    } catch (e) {
      _snack("Errore creazione: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
      _addPersonaleInFlight = false;
    }
  }

  Future<void> _editPersonaleFull(Map<String, dynamic> dip) async {
    if (!await ensureCanPersist(context)) return;
    final parsed = _splitFullName(dip["full_name"]);
    final userIdUuid = (dip["user_id"] ?? "").toString();
    final hasLogin = userIdUuid.isNotEmpty;

    // ruolo + username attuali (se login presente)
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

    // url formazioni
    String? formazioneUrl =
        hasLogin ? await FormazioniRepository.getForUser(userIdUuid) : null;

    // dialog
    final res = await showDialog<_DipFullData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DipFullDialog(
        isEdit: true,
        hasLogin: hasLogin,
        roleOptions: _roleOptions,
        personaleId: dip["id"] as int?,
        personaleIdUuid: (dip["id_uuid"] ?? '').toString(),
        initial: _DipFullData(
          nome: parsed.nome,
          cognome: parsed.cognome,
          attivo: dip["active"] == true,
          cameraTipoDefault:
              ((dip["camera_tipo_default"] ?? "doppia").toString().trim() ==
                      "singola")
                  ? "singola"
                  : "doppia",
          matricola: (dip["matricola"] ?? '').toString(),
          telefono: (dip["telefono"] ?? '').toString(),
          dataAssunzione: (dip["data_assunzione"] ?? '').toString(),
          dataNascita: (dip["data_nascita"] ?? '').toString(),
          numeroTesserino: (dip["numero_tesserino"] ?? '').toString(),
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
          urlFormazioni: formazioneUrl,
          adminType: currentAdminTypeDb,
          adminTypeSecondario: currentSecondaryAdminTypeDb,
        ),
      ),
    );
    if (res == null) return;

    setState(() => _loading = true);
    try {
      final newFullName = _composeFullName(res.nome, res.cognome);
      final dataAssunzioneIso = parseFlexibleDateToIsoDate(res.dataAssunzione);
      final dataNascitaIso = parseFlexibleDateToIsoDate(res.dataNascita);
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

      // 1) Aggiorna anagrafica (mantiene numero_tesserino → niente rigenerazione PATGIU01001)
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

      // 2) Crea login se mancava (con validazioni minime)
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

      // 3) Reset password (se richiesto)
      if (hasLogin && (res.passwordProvvisoria ?? "").isNotEmpty) {
        await _adminSetPassword(
          authId: userIdUuid,
          newPassword: res.passwordProvvisoria!.trim(),
        );
      }

      // 4) Modifica dati login esistente — ORA con personale_id
      if (hasLogin) {
        final bool roleChanged = (res.ruolo ?? "").trim().isNotEmpty &&
            _normalizeRole(res.ruolo!) != _normalizeRole(currentRoleDb ?? "");

        await _adminUpdateEmployee(
          authId: userIdUuid,
          personaleId: dip["id"], // ← FIX CRITICO: passiamo personale_id
          email: (res.email ?? '').trim().isNotEmpty ? res.email!.trim() : null,
          fullName: newFullName,
          username: (res.username ?? '').trim().isNotEmpty
              ? res.username!.trim()
              : null,
          active: res.attivo,
          role: roleChanged ? res.ruolo : null,
          secondaryRole: res.ruoloSecondario,
          adminType: res.adminType ??
              _adminTypeForRole(res.ruolo ?? '') ??
              (roleChanged ? null : currentAdminTypeDb),
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? '') ??
              currentSecondaryAdminTypeDb,
        );
        await _persistSecondaryRole(
          authId: userIdUuid,
          secondaryRole: res.ruoloSecondario,
          secondaryAdminType: res.adminTypeSecondario ??
              _adminTypeForRole(res.ruoloSecondario ?? '') ??
              currentSecondaryAdminTypeDb,
        );
      }

      // 5) Formazioni
      if (hasLogin && (res.urlFormazioni ?? "").isNotEmpty) {
        await FormazioniRepository.setForUser(
          userIdUuid,
          res.urlFormazioni!.trim(),
        );
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
      title: "Elimina definitivamente dipendente",
      message:
          "Questa azione rimuove definitivamente il dipendente dalla lista.\n"
          "Se esiste un login collegato, verrà eliminato anche l'accesso.",
      confirmLabel: "Elimina definitivamente",
      danger: true,
    );
    if (!hard) return;

    var userId = (dip["user_id"] ?? "").toString().trim();
    final id = dip["id"];
    final email = (dip["email"] ?? "").toString().trim();
    final fullName = (dip["full_name"] ?? "").toString().trim();

    setState(() => _loading = true);
    try {
      // Se personale non ha user_id, cerca comunque un login collegato.
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
        await _adminDeleteUser(
          authId: userId,
          personaleId: id,
          hard: hard,
        );
        // Safety net: se la Edge Function non elimina la riga personale,
        // forziamo qui la rimozione definitiva dal DB.
        try {
          await SupabaseService.client.from("personale").delete().eq("id", id);
        } catch (_) {}
        // Safety net: login orfano in public.users (+ token push)
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
        await SupabaseService.client.from("personale").delete().eq("id", id);
      }

      _snack("Dipendente eliminato definitivamente");
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
        // Se anche il check fallisce, manteniamo il messaggio di errore originale.
      }
      _snack("Errore eliminazione: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword(String authUserId, String? email) async {
    // Se non c'è email → password diretta
    if (email == null || email.trim().isEmpty) {
      final newPw = await _askText(
        "Nuova password provvisoria",
        hint: PasswordPolicy.rulesText,
        obscure: true,
      );
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

    // Scelta: email di reset, password diretta o annulla
    final choice = await _resetPasswordChoice();
    if (choice == null) return;

    if (choice == 'email') {
      try {
        setState(() => _loading = true);
        final redirect =
            'https://gestopro360.it/password-recovery';
        await Supabase.instance.client.functions.invoke(
          "admin-reset-password",
          body: {"email": email, "redirectTo": redirect},
          headers: {
            "Authorization":
                "Bearer ${Supabase.instance.client.auth.currentSession?.accessToken}"
          },
        );
        _snack("Email di reset inviata");
      } catch (e) {
        _snack("Errore reset email: $e", error: true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final newPw = await _askText(
      "Nuova password provvisoria",
      hint: PasswordPolicy.rulesText,
      obscure: true,
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content: _NeoTextField(
          controller: ctrl,
          label: hint ?? '',
          obscure: obscure,
        ),
        actions: [
          _NeoButton(
            onTap: () => Navigator.pop(context),
            child: const Text("Annulla"),
          ),
          _NeoButton(
            onTap: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UI — LISTA DIPENDENTI / APP BAR / SEARCH BAR
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCompact = useCompactPageLayout(context);
    final gestopro = _isGestopro(context);
    final colors = _DipPageColors.of(context);
    final filtered = _filteredPersonale();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 18, color: colors.text),
                        const SizedBox(width: 8),
                        Text(
                          "Ruoli personalizzati e pagine visibili",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_personale.any((dip) =>
                  (dip["user_id"] ?? "").toString().trim().isEmpty &&
                  (dip["email"] ?? "").toString().trim().isNotEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _NeoButton(
                    color: gestopro
                        ? CronosFuturisticTheme.neonRed.withValues(alpha: 0.15)
                        : const Color(0xFFFFE6E6),
                    onTap: _provisionDefaultPasswordForMissingLogins,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.password,
                            size: 18,
                            color: gestopro
                                ? CronosFuturisticTheme.neonRed
                                : const Color(0xFF9B1C1C)),
                        const SizedBox(width: 8),
                        Text(
                          "Crea login base (12345678)",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: gestopro
                                ? CronosFuturisticTheme.neonRed
                                : const Color(0xFF9B1C1C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          "Nessun dipendente trovato",
                          style: TextStyle(color: colors.text.withValues(alpha: 0.7)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final dip = filtered[i];
                          final hasLogin =
                              (dip["user_id"] ?? "").toString().isNotEmpty;

                          return _NeoContainer(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: isCompact
                                ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: gestopro
                                                  ? CronosFuturisticTheme
                                                      .electricBlue
                                                      .withValues(alpha: 0.35)
                                                  : Colors.white,
                                              foregroundColor: colors.text,
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
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          color: colors.text,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    (dip["email"] ?? '—')
                                                        .toString(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: colors.text
                                                              .withValues(
                                                                  alpha: 0.65),
                                                        ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    hasLogin
                                                        ? "Login associato"
                                                        : "Nessun login associato",
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: hasLogin
                                                              ? (gestopro
                                                                  ? CronosFuturisticTheme
                                                                      .neonGreen
                                                                  : Colors.green
                                                                      .shade700)
                                                              : (gestopro
                                                                  ? CronosFuturisticTheme
                                                                      .neonOrange
                                                                  : Colors.orange
                                                                      .shade700),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              tooltip: 'Azioni',
                                              icon: Icon(Icons.more_vert,
                                                  color: colors.text),
                                              onSelected: (v) {
                                                if (v == 'dpi') {
                                                  _openDpiManager(dip);
                                                } else if (v == 'edit') {
                                                  _editPersonaleFull(dip);
                                                } else if (v == 'toggle') {
                                                  _toggleActivePersonale(dip);
                                                } else if (v == 'reset') {
                                                  _resetPassword(
                                                    dip["user_id"]
                                                            ?.toString() ??
                                                        "",
                                                    dip["email"]?.toString(),
                                                  );
                                                } else if (v == 'delete') {
                                                  _deletePersonale(dip);
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                const PopupMenuItem<String>(
                                                  value: 'dpi',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(
                                                        Icons.shield_outlined),
                                                    title: Text('DPI'),
                                                  ),
                                                ),
                                                const PopupMenuItem<String>(
                                                  value: 'edit',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(
                                                        Icons.edit_outlined),
                                                    title: Text('Modifica'),
                                                  ),
                                                ),
                                                PopupMenuItem<String>(
                                                  value: 'toggle',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(
                                                      dip["active"] == true
                                                          ? Icons
                                                              .visibility_off_outlined
                                                          : Icons
                                                              .visibility_outlined,
                                                    ),
                                                    title: Text(
                                                      dip["active"] == true
                                                          ? 'Disattiva'
                                                          : 'Attiva',
                                                    ),
                                                  ),
                                                ),
                                                if (hasLogin)
                                                  const PopupMenuItem<String>(
                                                    value: 'reset',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(
                                                          Icons.lock_reset),
                                                      title: Text(
                                                          'Reset password'),
                                                    ),
                                                  ),
                                                PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(
                                                      Icons.delete_forever,
                                                      color:
                                                          Colors.red.shade700,
                                                    ),
                                                    title: Text(
                                                      'Elimina',
                                                      style: TextStyle(
                                                        color:
                                                            Colors.red.shade700,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: gestopro
                                              ? CronosFuturisticTheme
                                                  .electricBlue
                                                  .withValues(alpha: 0.35)
                                              : Colors.white,
                                          foregroundColor: colors.text,
                                          child: Text(
                                            dip["full_name"]
                                                .toString()
                                                .substring(0, 1)
                                                .toUpperCase(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: _employeeInfo(
                                                context, dip, hasLogin)),
                                        const SizedBox(width: 10),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            _NeoButton(
                                              onTap: () => _openDpiManager(dip),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.shield_outlined,
                                                      size: 18,
                                                      color: colors.text),
                                                  const SizedBox(width: 6),
                                                  Text("DPI",
                                                      style: TextStyle(
                                                          color: colors.text)),
                                                ],
                                              ),
                                            ),
                                            _RowActionsNeo(
                                              isActive: dip["active"] == true,
                                              hasLogin: hasLogin,
                                              onEdit: () =>
                                                  _editPersonaleFull(dip),
                                              onToggle: () =>
                                                  _toggleActivePersonale(dip),
                                              onReset: hasLogin
                                                  ? () => _resetPassword(
                                                        dip["user_id"]
                                                                ?.toString() ??
                                                            "",
                                                        dip["email"]
                                                            ?.toString(),
                                                      )
                                                  : null,
                                              onDelete: () =>
                                                  _deletePersonale(dip),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                ),
              ],
            );

    if (gestopro) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addPersonale,
          backgroundColor: CronosFuturisticTheme.electricBright,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add),
          label: const Text('Nuovo'),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FuturisticInlineToolbar(
              title: 'Gestione Dipendenti',
              actions: [
                IconButton(
                  tooltip: 'Export CSV anagrafica',
                  onPressed: _exportPersonaleCsv,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'Esporta rubrica',
                  onPressed: () => exportPersonaleContactsForPhone(
                    context,
                    personaleRows: _personale,
                  ),
                  icon: const Icon(Icons.contact_phone_outlined),
                ),
                IconButton(
                  tooltip: 'Aggiorna elenco',
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _DipPageColors.of(context).bg,
      appBar: _NeoAppBar(
        title: "Admin — Gestione Dipendenti",
        onRefresh: _loadAll,
        onExportCsv: _exportPersonaleCsv,
        onExportContacts: () => exportPersonaleContactsForPhone(
          context,
          personaleRows: _personale,
        ),
      ),
      floatingActionButton: _NeoFab(
        icon: Icons.person_add,
        label: "Nuovo",
        onTap: _addPersonale,
      ),
      body: body,
    );
  }

  Widget _employeeInfo(
      BuildContext context, Map<String, dynamic> dip, bool hasLogin) {
    final colors = _DipPageColors.of(context);
    final gestopro = _isGestopro(context);
    final muted = colors.text.withValues(alpha: 0.7);
    final loginColor = hasLogin
        ? (gestopro
            ? CronosFuturisticTheme.neonGreen
            : Colors.green.shade700)
        : (gestopro
            ? CronosFuturisticTheme.neonOrange
            : Colors.orange.shade700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dip["full_name"].toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          (dip["email"] ?? '—').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Matricola: ${((dip["matricola"] ?? "").toString().trim().isEmpty) ? "—" : dip["matricola"]}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ruolo: ${((dip["ruolo_aziendale"] ?? "").toString().trim().isEmpty) ? "—" : dip["ruolo_aziendale"]}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          'N. tesserino: ${((dip["numero_tesserino"] ?? "").toString().trim().isEmpty) ? "—" : dip["numero_tesserino"]}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          'Telefono: ${((dip["telefono"] ?? "").toString().trim().isEmpty) ? "—" : dip["telefono"]}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          'Data assunzione: ${((dip["data_assunzione"] ?? "").toString().trim().isEmpty) ? "—" : formatDateDdMmYyyy(dip["data_assunzione"])}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          hasLogin ? "Login associato" : "Nessun login associato",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: loginColor,
              ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  AppBar Flat Neumorphic
/// ─────────────────────────────────────────────────────────────────────────
class _NeoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onRefresh;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportContacts;

  const _NeoAppBar({
    required this.title,
    required this.onRefresh,
    this.onExportCsv,
    this.onExportContacts,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    Widget actionChip({
      required IconData icon,
      required String label,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      // Stesso look HUD dell'orologio (NexusClock compact).
      const radius = 10.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CronosFuturisticTheme.electricBlue
                              .withValues(alpha: 0.22),
                          CronosFuturisticTheme.voidBg.withValues(alpha: 0.65),
                        ],
                      ),
                      border: Border.all(
                        color: CronosFuturisticTheme.neonCyan
                            .withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: CronosFuturisticTheme.neonCyan
                              .withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return wrapClassicAppBarChrome(
      context,
      AppBar(
        elevation: 0,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: kClassicAppBarForeground,
              ),
        ),
        actions: [
          if (onExportCsv != null)
            actionChip(
              icon: Icons.download_outlined,
              label: 'CSV',
              tooltip: 'Export CSV anagrafica',
              onTap: onExportCsv!,
            ),
          if (onExportContacts != null)
            actionChip(
              icon: Icons.contact_phone_outlined,
              label: 'Rubrica',
              tooltip: 'Esporta rubrica',
              onTap: onExportContacts!,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: actionChip(
              icon: Icons.refresh_rounded,
              label: 'Aggiorna',
              tooltip: 'Aggiorna elenco',
              onTap: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Ricerca Neumorfica
/// ─────────────────────────────────────────────────────────────────────────
class _SearchBarNeo extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchBarNeo({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = _DipPageColors.of(context);
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return _NeoContainer(
      child: Row(
        children: [
          Icon(Icons.search, color: colors.text),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(color: colors.text),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Cerca per nome o email",
                hintStyle: TextStyle(
                  color: colors.text.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          if (value.isNotEmpty)
            InkWell(
              onTap: () => onChanged(""),
              child: Icon(Icons.close, color: colors.text),
            ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Row Azioni (Edit / Toggle / Reset / Delete) – Neumorphic Buttons
/// ─────────────────────────────────────────────────────────────────────────
class _RowActionsNeo extends StatelessWidget {
  final bool isActive;
  final bool hasLogin;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onReset;
  final VoidCallback onDelete;

  const _RowActionsNeo({
    required this.isActive,
    required this.hasLogin,
    required this.onEdit,
    required this.onToggle,
    required this.onReset,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _DipPageColors.of(context);
    final gestopro = _isGestopro(context);
    final btnStyle = Theme.of(context)
        .textTheme
        .labelLarge!
        .copyWith(color: colors.text, fontWeight: FontWeight.w600);
    final deleteBg = gestopro
        ? CronosFuturisticTheme.neonRed.withValues(alpha: 0.15)
        : const Color(0xFFFFE6E6);
    final deleteFg =
        gestopro ? CronosFuturisticTheme.neonRed : Colors.red.shade700;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _NeoButton(
          onTap: onEdit,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit, size: 18, color: colors.text),
              const SizedBox(width: 6),
              Text("Modifica", style: btnStyle),
            ],
          ),
        ),
        _NeoButton(
          onTap: onToggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: colors.text,
              ),
              const SizedBox(width: 6),
              Text(isActive ? "Disattiva" : "Attiva", style: btnStyle),
            ],
          ),
        ),
        _NeoButton(
          onTap: onReset,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_reset, size: 18, color: colors.text),
              const SizedBox(width: 6),
              Text("Reset", style: btnStyle),
            ],
          ),
        ),
        _NeoButton(
          color: deleteBg,
          onTap: onDelete,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_forever, size: 18, color: deleteFg),
              const SizedBox(width: 6),
              Text(
                "Elimina",
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: deleteFg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  FAB rotondo Neumorphic
/// ─────────────────────────────────────────────────────────────────────────
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
        backgroundColor: _DipPageColors.of(context).panel,
        foregroundColor: _DipPageColors.of(context).text,
        elevation: 0,
        icon: Icon(icon),
        label: Text(label ?? "Nuovo"),
        onPressed: onTap,
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  Dialog DTO
/// ─────────────────────────────────────────────────────────────────────────
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
    required this.matricola,
    required this.telefono,
    required this.dataAssunzione,
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

/// ─────────────────────────────────────────────────────────────────────────
///  Dialog create/edit (Modifica Dipendente)
/// ─────────────────────────────────────────────────────────────────────────
class _DipFullDialog extends StatefulWidget {
  final _DipFullData initial;
  final bool isEdit;
  final bool hasLogin;
  final List<String> roleOptions;
  final int? personaleId;
  final String? personaleIdUuid;

  const _DipFullDialog({
    required this.initial,
    required this.isEdit,
    required this.hasLogin,
    required this.roleOptions,
    this.personaleId,
    this.personaleIdUuid,
  });

  @override
  State<_DipFullDialog> createState() => _DipFullDialogState();
}

class _DipFullDialogState extends State<_DipFullDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nome;
  late TextEditingController _cognome;
  late TextEditingController _username;
  late TextEditingController _email;
  late TextEditingController _password;
  late TextEditingController _urlForm;
  late TextEditingController _matricola;
  late TextEditingController _telefono;
  late TextEditingController _dataAssunzione;
  late TextEditingController _dataNascita;
  late TextEditingController _numeroTesserino;
  late TextEditingController _ruoloAziendale;

  String _fotoTesserinoPath = '';
  bool _fotoUploading = false;

  bool _attivo = true;
  String _cameraTipoDefault = "doppia";
  bool _creaLogin = true;
  String _ruolo = "user";
  String _ruoloSecondario = "";
  int _adminType =
      1; // 1 = nessuna notifica, 2 = pernottamenti, 3 = treni/aerei
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
    _numeroTesserino = TextEditingController(text: i.numeroTesserino.trim());
    _ruoloAziendale = TextEditingController(text: i.ruoloAziendale);
    _fotoTesserinoPath = i.fotoTesserinoPath.trim();
    _creaLogin = i.creaLogin;
    _username = TextEditingController(text: i.username ?? "");
    _email = TextEditingController(text: i.email ?? "");
    _ruolo = i.ruolo ?? "user";
    _ruoloSecondario = i.ruoloSecondario ?? "";
    _password = TextEditingController(text: i.passwordProvvisoria ?? "");
    _urlForm = TextEditingController(text: i.urlFormazioni ?? "");
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
        : '$prefix… (assegnato al salvataggio)';
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
    final ruoloValue = widget.roleOptions.contains(_ruolo) ? _ruolo : "user";
    final ruoloSecondarioValue = _ruoloSecondario.isEmpty
        ? "__none__"
        : (widget.roleOptions.contains(_ruoloSecondario)
            ? _ruoloSecondario
            : "__none__");

    return Dialog(
      backgroundColor: _DipPageColors.of(context).panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isEdit ? "Modifica Dipendente" : "Nuovo Dipendente",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 14),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Nome / Cognome
                      Row(
                        children: [
                          Expanded(
                            child: _NeoTextField(
                              controller: _cognome,
                              label: "Cognome",
                              onChanged: _refreshTesserinoPreview,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NeoTextField(
                              controller: _nome,
                              label: "Nome",
                              onChanged: _refreshTesserinoPreview,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Attivo
                      Row(
                        children: [
                          Expanded(
                            child: _NeoContainer(
                              child: SwitchListTile(
                                value: _attivo,
                                onChanged: (v) => setState(() => _attivo = v),
                                title: const Text("Attivo",
                                    style: TextStyle(color: _kText)),
                                activeThumbColor: _kAccent,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _NeoContainer(
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  labelText: "Tipo camera default",
                                ),
                                initialValue: _cameraTipoDefault,
                                items: const [
                                  DropdownMenuItem(
                                      value: "singola", child: Text("Singola")),
                                  DropdownMenuItem(
                                      value: "doppia", child: Text("Doppia")),
                                ],
                                onChanged: (v) => setState(
                                    () => _cameraTipoDefault = v ?? "doppia"),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _matricola,
                        label: "Matricola",
                      ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _ruoloAziendale,
                        label: "Ruolo in azienda",
                      ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _telefono,
                        label: "Telefono",
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _dataAssunzione,
                        label: "Data assunzione (GG/MM/AAAA)",
                      ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _numeroTesserino,
                        label: "N. tesserino",
                        readOnly: true,
                      ),
                      if (!widget.isEdit)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Generato automaticamente (es. PATGIU01001; omònimi PATGIU02001).',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _kText.withValues(alpha: 0.55),
                                  ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _dataNascita,
                        label: "Data di nascita (GG/MM/AAAA)",
                      ),
                      const SizedBox(height: 12),
                      PersonaleTesserinoFotoSection(
                        fotoPath: _fotoTesserinoPath,
                        canUpload: widget.isEdit &&
                            widget.personaleId != null &&
                            (widget.personaleIdUuid ?? '').trim().isNotEmpty,
                        uploading: _fotoUploading,
                        onUpload: _pickAndUploadFoto,
                        textColor: _kText,
                      ),
                      const SizedBox(height: 12),

                      // Crea login (solo se non c'è)
                      if (!hasLogin)
                        Row(
                          children: [
                            Expanded(
                              child: _NeoContainer(
                                child: SwitchListTile(
                                  value: _creaLogin,
                                  onChanged: (v) =>
                                      setState(() => _creaLogin = v),
                                  title: const Text("Crea login",
                                      style: TextStyle(color: _kText)),
                                  activeThumbColor: _kAccent,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),

                      // Campi login/identità (anche con login esistente)
                      if (_creaLogin || hasLogin) ...[
                        const SizedBox(height: 12),
                        _NeoTextField(
                          controller: _username,
                          label: hasLogin ? "Username (opzionale)" : "Username",
                        ),
                        const SizedBox(height: 12),
                        _NeoTextField(
                          controller: _email,
                          label: "Email",
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _NeoContainer(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              labelText: "Ruolo",
                            ),
                            initialValue: ruoloValue,
                            items: widget.roleOptions
                                .map((r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(r),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _ruolo = v ?? "user"),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                      child:
                                          Text(r == "__none__" ? "Nessuno" : r),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() {
                              final next = v ?? "__none__";
                              _ruoloSecondario = next == "__none__" ? "" : next;
                              if (_normalizeRole(_ruoloSecondario) ==
                                  _normalizeRole(_ruolo)) {
                                _ruoloSecondario = "";
                              }
                            }),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tipo admin (solo se ruolo=admin)
                        if (_ruolo.toLowerCase() == "admin")
                          _NeoContainer(
                            child: DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                labelText: "Tipo admin (chi riceve notifiche)",
                              ),
                              initialValue: _adminType,
                              items: const [
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text("Nessuna notifica"),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Text("Admin pernottamenti"),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text("Admin treni/aerei"),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _adminType = v ?? 1),
                            ),
                          ),
                        if (_ruoloSecondario.trim().isNotEmpty &&
                            _normalizeRole(_ruoloSecondario) == "admin")
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _NeoContainer(
                              child: DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  labelText: "Tipo admin ruolo secondario",
                                ),
                                initialValue: _adminTypeSecondario,
                                items: const [
                                  DropdownMenuItem(
                                      value: 1,
                                      child: Text("Nessuna notifica")),
                                  DropdownMenuItem(
                                      value: 2,
                                      child: Text("Admin pernottamenti")),
                                  DropdownMenuItem(
                                      value: 3,
                                      child: Text("Admin treni/aerei")),
                                  DropdownMenuItem(
                                      value: 4, child: Text("Admin DPI")),
                                  DropdownMenuItem(
                                      value: 5,
                                      child: Text("Admin Formazione")),
                                ],
                                onChanged: (v) => setState(
                                    () => _adminTypeSecondario = v ?? 1),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        _NeoTextField(
                          controller: _password,
                          label: hasLogin
                              ? "Nuova password (opzionale)"
                              : "Password provvisoria",
                          obscure: true,
                        ),
                      ],

                      const SizedBox(height: 12),
                      _NeoTextField(
                        controller: _urlForm,
                        label: "URL Formazioni (opzionale)",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _NeoButton(
                        onTap: () => Navigator.pop(context),
                        child: const Center(child: Text("Annulla")),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NeoButton(
                        onTap: () {
                          // Validazioni base
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
                              RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                                  .hasMatch(emailTxt);
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
                                    "Data assunzione non valida. Usa formato GG/MM/AAAA"),
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
                                    "Data di nascita non valida. Usa formato GG/MM/AAAA"),
                              ),
                            );
                            return;
                          }

                          if (!hasLogin && _creaLogin) {
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
          ),
        ),
      ),
    );
  }
}

/// Supporto nome/cognome
class _NamePair {
  final String nome;
  final String cognome;
  const _NamePair(this.nome, this.cognome);
}
