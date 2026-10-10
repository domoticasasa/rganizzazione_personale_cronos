import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../theme/cronos_futuristic_theme.dart';
import '../utils/admin_vista_guard.dart';
import '../utils/date_formatters.dart';
import '../utils/personale_profile_resolver.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';
import '../widgets/classic_app_bar_chrome.dart';
import '../widgets/futuristic/gestopro_session_scope.dart';
import '../widgets/passkey_security_section.dart';
import '../widgets/tesserino_foto_image.dart';
import '../widgets/user_profile_avatar.dart';

/// Colori card profilo (stile esempio dark + cyan).
abstract final class _ProfileCardTheme {
  static const bg = Color(0xFF0E1520);
  static const panel = Color(0xFF151D2B);
  static const panelSoft = Color(0xFF1A2436);
  static const border = Color(0xFF2A3A52);
  static const cyan = Color(0xFF3DDCFF);
  static const text = Color(0xFFF2F6FC);
  static const muted = Color(0xFF9AA8BC);
}

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({
    super.key,
    this.expandEditOnOpen = false,
  });

  /// Apre già la sezione «Modifica dati» (utile dall'Area dipendente).
  final bool expandEditOnOpen;

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  final _telefonoCtrl = TextEditingController();
  final _dataNascitaCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  late bool _editExpanded;

  Map<String, dynamic>? _usersRow;
  Map<String, dynamic>? _personaleRow;
  User? _authUser;
  String _initialTelefono = '';
  String _initialDataNascitaIso = '';

  @override
  void initState() {
    super.initState();
    _editExpanded = widget.expandEditOnOpen;
    _loadProfile();
  }

  @override
  void dispose() {
    _telefonoCtrl.dispose();
    _dataNascitaCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _loadProfile() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    final authId = authUser?.id;
    if (authId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final bundle = await resolveMyProfileBundle();
      final usersRow = bundle.users;
      final personaleRow = bundle.personale == null
          ? null
          : Map<String, dynamic>.from(bundle.personale!);

      final telefono = _s(personaleRow?['telefono']);
      final nascitaIso =
          parseFlexibleDateToIsoDate(_s(personaleRow?['data_nascita'])) ?? '';

      if (!mounted) return;
      setState(() {
        _authUser = authUser;
        _usersRow = usersRow;
        _personaleRow = personaleRow;
        _initialTelefono = telefono;
        _initialDataNascitaIso = nascitaIso;
        _telefonoCtrl.text = telefono;
        _dataNascitaCtrl.text =
            nascitaIso.isEmpty ? '' : formatDateDdMmYyyy(nascitaIso);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento profilo: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!await ensureCanPersist(context)) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    final telefono = _telefonoCtrl.text.trim();
    final dataNascitaIso =
        parseFlexibleDateToIsoDate(_dataNascitaCtrl.text.trim()) ?? '';

    final telefonoChanged = telefono != _initialTelefono;
    final nascitaChanged = dataNascitaIso != _initialDataNascitaIso;
    if (!telefonoChanged && !nascitaChanged) {
      _toast('Nessuna modifica da salvare.');
      return;
    }
    if (_personaleRow == null) {
      _toast(
        'Account non collegato a Gestione dipendenti: '
        'impossibile aggiornare telefono o data di nascita.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      try {
        await saveMyPersonaleProfile(
          telefono: telefonoChanged ? telefono : null,
          dataNascitaIso: nascitaChanged ? dataNascitaIso : null,
        );
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
        final personalePayload = <String, dynamic>{};
        if (telefonoChanged) {
          personalePayload['telefono'] = telefono.isEmpty ? null : telefono;
        }
        if (nascitaChanged) {
          personalePayload['data_nascita'] =
              dataNascitaIso.isEmpty ? null : dataNascitaIso;
        }
        if (personalePayload.isNotEmpty) {
          final idUuid = _s(_personaleRow?['id_uuid']);
          if (idUuid.isNotEmpty) {
            await SupabaseService.client
                .from('personale')
                .update(personalePayload)
                .eq('id_uuid', idUuid);
          } else if (_personaleRow?['id'] != null) {
            await SupabaseService.client
                .from('personale')
                .update(personalePayload)
                .eq('id', _personaleRow!['id']);
          }
        }
      }

      if (!mounted) return;
      _toast('Profilo salvato.');
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      _toast('Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _profileInitial(String fullName, String loginAssociato) {
    final n = fullName.trim();
    if (n.isNotEmpty) return n[0];
    final login = loginAssociato.trim();
    if (login.isNotEmpty) return login[0];
    return '?';
  }

  Widget _avatar({
    required String fotoPath,
    required String initial,
    required double radius,
  }) {
    final path = fotoPath.trim();
    final size = radius * 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _ProfileCardTheme.cyan.withValues(alpha: 0.65),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: _ProfileCardTheme.cyan.withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: path.isNotEmpty
          ? SizedBox.expand(
              child: TesserinoFotoImage(
                storagePath: path,
                fit: BoxFit.cover,
                // Centro il volto nel cerchio (non tagliare in alto).
                alignment: Alignment.center,
                placeholderIconSize: radius,
              ),
            )
          : Center(
              child: UserProfileAvatar(
                radius: radius - 3,
                initial: initial,
                fotoPath: null,
              ),
            ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ProfileCardTheme.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _ProfileCardTheme.cyan.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, size: 18, color: _ProfileCardTheme.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _ProfileCardTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    color: _ProfileCardTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _darkFieldDecoration({
    required String label,
    String? hint,
    String? helper,
    IconData? icon,
  }) {
    OutlineInputBorder border([Color? c]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: c ?? _ProfileCardTheme.border,
          ),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      helperStyle: TextStyle(
        color: _ProfileCardTheme.muted.withValues(alpha: 0.9),
        fontSize: 12,
      ),
      labelStyle: const TextStyle(color: _ProfileCardTheme.muted),
      hintStyle: TextStyle(
        color: _ProfileCardTheme.muted.withValues(alpha: 0.7),
      ),
      filled: true,
      fillColor: _ProfileCardTheme.bg.withValues(alpha: 0.65),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: _ProfileCardTheme.cyan.withValues(alpha: 0.85)),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(_ProfileCardTheme.cyan.withValues(alpha: 0.75)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = GestoproSessionScope.maybeOf(context);
    final personale = _personaleRow;
    final users = _usersRow;
    final authEmail = _s(_authUser?.email);
    final authName = _s((_authUser?.userMetadata?['full_name'] ??
            _authUser?.userMetadata?['name']))
        .trim();
    final sessionName = _s(session?.fullName);
    final sessionLogin = _s(session?.username);
    final fullName = _s(personale?['full_name']).isNotEmpty
        ? _s(personale?['full_name'])
        : (_s(users?['full_name']).isNotEmpty
            ? _s(users?['full_name'])
            : (sessionName.isNotEmpty ? sessionName : authName));
    final matricola = _s(personale?['matricola']);
    final tesserino = _s(personale?['numero_tesserino']);
    final dataAss = formatDateDdMmYyyy(_s(personale?['data_assunzione']));
    final loginAssociato = _s(users?['username']).isNotEmpty
        ? _s(users?['username'])
        : (_s(users?['email']).isNotEmpty
            ? _s(users?['email'])
            : (sessionLogin.isNotEmpty ? sessionLogin : authEmail));
    final fotoPath = _s(personale?['foto_tesserino_path']);
    final profileInitial = _profileInitial(fullName, loginAssociato);
    final telefono = _telefonoCtrl.text.trim();
    final email = _s(personale?['email']).isNotEmpty
        ? _s(personale?['email'])
        : (_s(users?['email']).isNotEmpty
            ? _s(users?['email'])
            : authEmail);
    final dataNascita = _dataNascitaCtrl.text.trim();
    final ruoloAziendale = _s(personale?['ruolo_aziendale']);
    final badge =
        ruoloAziendale.isNotEmpty ? ruoloAziendale : 'Ruolo non indicato';
    final mobile = useMobileUi(context);
    final pageBg = Theme.of(context).brightness == Brightness.dark
        ? CronosFuturisticTheme.deepSpace
        : const Color(0xFFE8EEF6);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: wrapClassicAppBarChrome(
        context,
        AppBar(
          title: const ResponsiveAppBarTitle(title: 'I miei dati'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 12 : 20,
                    16,
                    mobile ? 12 : 20,
                    24,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _ProfileCardTheme.panel,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _ProfileCardTheme.cyan.withValues(alpha: 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: _ProfileCardTheme.cyan.withValues(alpha: 0.08),
                          blurRadius: 40,
                          spreadRadius: -4,
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _ProfileCardTheme.panelSoft,
                          _ProfileCardTheme.panel,
                          _ProfileCardTheme.bg,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(mobile ? 16 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profilo personale',
                            style: TextStyle(
                              fontSize: mobile ? 18 : 20,
                              fontWeight: FontWeight.w800,
                              color: _ProfileCardTheme.text,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Header stile esempio: avatar + nome + email + badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _avatar(
                                fotoPath: fotoPath,
                                initial: profileInitial,
                                radius: mobile ? 58 : 72,
                              ),
                              SizedBox(width: mobile ? 18 : 22),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName.isEmpty ? '—' : fullName,
                                      style: TextStyle(
                                        color: _ProfileCardTheme.text,
                                        fontSize: mobile ? 20 : 24,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      email.isEmpty ? '—' : email,
                                      style: const TextStyle(
                                        color: _ProfileCardTheme.muted,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _ProfileCardTheme.cyan
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                          color: _ProfileCardTheme.cyan
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _ProfileCardTheme.cyan,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _ProfileCardTheme.cyan
                                                      .withValues(alpha: 0.7),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 7),
                                          Text(
                                            badge,
                                            style: const TextStyle(
                                              color: _ProfileCardTheme.cyan,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (personale == null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A1D1D),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFF8A80)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Text(
                                'Collega il tuo account al record in Gestione dipendenti '
                                '(login associato) per sincronizzare matricola e tesserino.',
                                style: TextStyle(
                                  color: Color(0xFFFFCDD2),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          Divider(
                            height: 1,
                            color: _ProfileCardTheme.border.withValues(
                              alpha: 0.85,
                            ),
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;
                              final left = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _infoTile(
                                    icon: Icons.badge_outlined,
                                    label: 'Matricola',
                                    value: matricola,
                                  ),
                                  _infoTile(
                                    icon: Icons.credit_card_outlined,
                                    label: 'N. tesserino',
                                    value: tesserino,
                                  ),
                                  _infoTile(
                                    icon: Icons.event_available_outlined,
                                    label: 'Data assunzione',
                                    value: dataAss,
                                  ),
                                  _infoTile(
                                    icon: Icons.person_outline,
                                    label: 'Login associato',
                                    value: loginAssociato,
                                  ),
                                ],
                              );
                              final right = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _infoTile(
                                    icon: Icons.phone_outlined,
                                    label: 'Telefono',
                                    value: telefono,
                                  ),
                                  _infoTile(
                                    icon: Icons.mail_outline,
                                    label: 'Email',
                                    value: email,
                                  ),
                                  _infoTile(
                                    icon: Icons.cake_outlined,
                                    label: 'Data di nascita',
                                    value: dataNascita,
                                  ),
                                  _infoTile(
                                    icon: Icons.photo_camera_outlined,
                                    label: 'Foto tesserino',
                                    value: fotoPath.isNotEmpty
                                        ? 'Presente'
                                        : 'Non disponibile',
                                  ),
                                ],
                              );
                              if (narrow) {
                                return Column(
                                  children: [left, right],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: left),
                                  const SizedBox(width: 18),
                                  Expanded(child: right),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Divider(
                            height: 1,
                            color: _ProfileCardTheme.border.withValues(
                              alpha: 0.85,
                            ),
                          ),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                              splashColor: _ProfileCardTheme.cyan
                                  .withValues(alpha: 0.12),
                              highlightColor: _ProfileCardTheme.cyan
                                  .withValues(alpha: 0.06),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: _editExpanded,
                              onExpansionChanged: (v) =>
                                  setState(() => _editExpanded = v),
                              tilePadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              childrenPadding: const EdgeInsets.only(
                                top: 4,
                                bottom: 8,
                              ),
                              iconColor: _ProfileCardTheme.cyan,
                              collapsedIconColor: _ProfileCardTheme.muted,
                              title: const Text(
                                'Modifica dati',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _ProfileCardTheme.text,
                                ),
                              ),
                              subtitle: const Text(
                                'Sostituisci telefono e data di nascita',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: _ProfileCardTheme.muted,
                                ),
                              ),
                              children: [
                                TextField(
                                  controller: _telefonoCtrl,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(
                                    color: _ProfileCardTheme.text,
                                  ),
                                  cursorColor: _ProfileCardTheme.cyan,
                                  decoration: _darkFieldDecoration(
                                    label: 'Telefono',
                                    hint: 'Es. 3331234567',
                                    helper:
                                        'Inserisci il nuovo numero e premi Salva per sostituirlo.',
                                    icon: Icons.phone_outlined,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _dataNascitaCtrl,
                                  style: const TextStyle(
                                    color: _ProfileCardTheme.text,
                                  ),
                                  cursorColor: _ProfileCardTheme.cyan,
                                  decoration: _darkFieldDecoration(
                                    label: 'Data di nascita',
                                    hint: 'gg/mm/aaaa',
                                    icon: Icons.cake_outlined,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _ProfileCardTheme.cyan,
                                      foregroundColor: const Color(0xFF06202A),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _saving ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF06202A),
                                            ),
                                          )
                                        : const Icon(Icons.save_outlined),
                                    label: Text(
                                      _saving ? 'Salvataggio...' : 'Salva',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PasskeySecuritySection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
