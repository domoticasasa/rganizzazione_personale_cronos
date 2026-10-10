import 'package:flutter/material.dart';

import '../../services/app_chat_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/cronos_futuristic_theme.dart';
import '../../utils/date_formatters.dart';
import '../tesserino_foto_image.dart';
import '../user_profile_avatar.dart';

abstract final class _PeerProfileTheme {
  static const bg = Color(0xFF0E1520);
  static const panel = Color(0xFF151D2B);
  static const panelSoft = Color(0xFF1A2436);
  static const border = Color(0xFF2A3A52);
  static const cyan = Color(0xFF3DDCFF);
  static const text = Color(0xFFF2F6FC);
  static const muted = Color(0xFF9AA8BC);
}

/// Card profilo collega (stile Profilo personale), sola lettura.
class AppChatPeerProfileSheet extends StatefulWidget {
  const AppChatPeerProfileSheet({
    super.key,
    required this.userId,
    required this.authId,
    required this.fallbackName,
    required this.onClose,
    this.showOpenChat = true,
    this.openChatLabel = 'Chat privata',
    this.onOpenPrivateChat,
  });

  final int userId;
  final String authId;
  final String fallbackName;
  final VoidCallback onClose;

  /// Mostra il pulsante per aprire/riprendere la chat privata.
  final bool showOpenChat;
  final String openChatLabel;
  final void Function(AppChatPeer peer)? onOpenPrivateChat;

  @override
  State<AppChatPeerProfileSheet> createState() =>
      _AppChatPeerProfileSheetState();
}

class _AppChatPeerProfileSheetState extends State<AppChatPeerProfileSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _users;
  Map<String, dynamic>? _personale;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await SupabaseService.client.rpc(
        'get_app_chat_peer_profile',
        params: {
          if (widget.userId > 0) 'p_user_id': widget.userId,
          if (widget.authId.trim().isNotEmpty)
            'p_auth_id': widget.authId.trim(),
        },
      );
      Map<String, dynamic>? users;
      Map<String, dynamic>? personale;
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final u = map['users'];
        final p = map['personale'];
        if (u is Map) users = Map<String, dynamic>.from(u);
        if (p is Map) personale = Map<String, dynamic>.from(p);
      }
      if (!mounted) return;
      setState(() {
        _users = users;
        _personale = personale;
        _loading = false;
        if (users == null && personale == null) {
          _error = 'Profilo non trovato.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossibile caricare il profilo.';
      });
    }
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
              color: _PeerProfileTheme.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _PeerProfileTheme.cyan.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, size: 18, color: _PeerProfileTheme.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _PeerProfileTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    color: _PeerProfileTheme.text,
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

  @override
  Widget build(BuildContext context) {
    final personale = _personale;
    final users = _users;
    final fullName = _s(personale?['full_name']).isNotEmpty
        ? _s(personale?['full_name'])
        : (_s(users?['full_name']).isNotEmpty
            ? _s(users?['full_name'])
            : widget.fallbackName);
    final email = _s(personale?['email']).isNotEmpty
        ? _s(personale?['email'])
        : _s(users?['email']);
    final login = _s(users?['username']).isNotEmpty
        ? _s(users?['username'])
        : email;
    final fotoPath = _s(personale?['foto_tesserino_path']);
    final ruoloAziendale = _s(personale?['ruolo_aziendale']);
    final badge =
        ruoloAziendale.isNotEmpty ? ruoloAziendale : 'Ruolo non indicato';
    final initial = fullName.isNotEmpty ? fullName[0] : '?';
    final screenH = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + keyboard),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: (screenH * 0.88).clamp(360.0, 720.0),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _PeerProfileTheme.cyan.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _PeerProfileTheme.panelSoft,
                      _PeerProfileTheme.panel,
                      _PeerProfileTheme.bg,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Profilo personale',
                              style: TextStyle(
                                color: _PeerProfileTheme.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onClose,
                            icon: const Icon(
                              Icons.close,
                              color: _PeerProfileTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: _PeerProfileTheme.cyan,
                              ),
                            )
                          : (_error != null && _users == null)
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: _PeerProfileTheme.muted,
                                      ),
                                    ),
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    20,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 118,
                                            height: 118,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: _PeerProfileTheme.cyan
                                                    .withValues(alpha: 0.7),
                                                width: 3,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _PeerProfileTheme.cyan
                                                      .withValues(alpha: 0.28),
                                                  blurRadius: 18,
                                                ),
                                              ],
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: fotoPath.isNotEmpty
                                                ? TesserinoFotoImage(
                                                    storagePath: fotoPath,
                                                    fit: BoxFit.cover,
                                                    alignment:
                                                        Alignment.center,
                                                    placeholderIconSize: 48,
                                                  )
                                                : Center(
                                                    child: UserProfileAvatar(
                                                      radius: 52,
                                                      initial: initial,
                                                    ),
                                                  ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fullName.isEmpty
                                                      ? '—'
                                                      : fullName,
                                                  style: const TextStyle(
                                                    color:
                                                        _PeerProfileTheme.text,
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  email.isEmpty ? '—' : email,
                                                  style: const TextStyle(
                                                    color: _PeerProfileTheme
                                                        .muted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _PeerProfileTheme
                                                        .cyan
                                                        .withValues(
                                                            alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            99),
                                                    border: Border.all(
                                                      color: _PeerProfileTheme
                                                          .cyan
                                                          .withValues(
                                                              alpha: 0.45),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 7,
                                                        height: 7,
                                                        decoration:
                                                            BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color:
                                                              _PeerProfileTheme
                                                                  .cyan,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color:
                                                                  _PeerProfileTheme
                                                                      .cyan
                                                                      .withValues(
                                                                          alpha:
                                                                              0.7),
                                                              blurRadius: 6,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 7),
                                                      Text(
                                                        badge,
                                                        style: const TextStyle(
                                                          color:
                                                              _PeerProfileTheme
                                                                  .cyan,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
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
                                      const SizedBox(height: 20),
                                      Divider(
                                        height: 1,
                                        color: _PeerProfileTheme.border
                                            .withValues(alpha: 0.85),
                                      ),
                                      const SizedBox(height: 16),
                                      LayoutBuilder(
                                        builder: (context, c) {
                                          final narrow = c.maxWidth < 420;
                                          final left = Column(
                                            children: [
                                              _infoTile(
                                                icon: Icons.badge_outlined,
                                                label: 'Matricola',
                                                value: _s(
                                                    personale?['matricola']),
                                              ),
                                              _infoTile(
                                                icon: Icons
                                                    .credit_card_outlined,
                                                label: 'N. tesserino',
                                                value: _s(personale?[
                                                    'numero_tesserino']),
                                              ),
                                              _infoTile(
                                                icon: Icons
                                                    .event_available_outlined,
                                                label: 'Data assunzione',
                                                value: formatDateDdMmYyyy(
                                                  _s(personale?[
                                                      'data_assunzione']),
                                                ),
                                              ),
                                              _infoTile(
                                                icon: Icons.person_outline,
                                                label: 'Login associato',
                                                value: login,
                                              ),
                                            ],
                                          );
                                          final right = Column(
                                            children: [
                                              _infoTile(
                                                icon: Icons.phone_outlined,
                                                label: 'Telefono',
                                                value: _s(
                                                    personale?['telefono']),
                                              ),
                                              _infoTile(
                                                icon: Icons.mail_outline,
                                                label: 'Email',
                                                value: email,
                                              ),
                                              _infoTile(
                                                icon: Icons.cake_outlined,
                                                label: 'Data di nascita',
                                                value: formatDateDdMmYyyy(
                                                  _s(personale?[
                                                      'data_nascita']),
                                                ),
                                              ),
                                              _infoTile(
                                                icon: Icons
                                                    .photo_camera_outlined,
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: left),
                                              const SizedBox(width: 12),
                                              Expanded(child: right),
                                            ],
                                          );
                                        },
                                      ),
                                      if (personale == null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Anagrafica dipendenti non collegata a questo account.',
                                          style: TextStyle(
                                            color: CronosFuturisticTheme
                                                .textMuted
                                                .withValues(alpha: 0.95),
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                      if (widget.showOpenChat &&
                                          widget.onOpenPrivateChat != null) ...[
                                        const SizedBox(height: 18),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  _PeerProfileTheme.cyan,
                                              foregroundColor:
                                                  const Color(0xFF06202A),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 14,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: () {
                                              final uid =
                                                  (users?['id'] as num?)
                                                          ?.toInt() ??
                                                      widget.userId;
                                              final aid = _s(users?['auth_id'])
                                                      .isNotEmpty
                                                  ? _s(users?['auth_id'])
                                                  : widget.authId;
                                              if (uid <= 0 && aid.isEmpty) {
                                                return;
                                              }
                                              widget.onOpenPrivateChat!(
                                                AppChatPeer(
                                                  userId: uid,
                                                  authId: aid,
                                                  displayName: fullName.isEmpty
                                                      ? widget.fallbackName
                                                      : fullName,
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.chat_bubble_outline,
                                            ),
                                            label: Text(
                                              widget.openChatLabel,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                    ),
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
