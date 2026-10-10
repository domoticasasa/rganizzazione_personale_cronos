import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tesserino_foto.dart';
import '../utils/personale_profile_resolver.dart';

/// Avatar con foto tesserino da Storage o iniziale.
class UserProfileAvatar extends StatefulWidget {
  final double radius;
  final String initial;
  final String? fotoPath;

  const UserProfileAvatar({
    super.key,
    required this.radius,
    required this.initial,
    this.fotoPath,
  });

  @override
  State<UserProfileAvatar> createState() => _UserProfileAvatarState();
}

class _UserProfileAvatarState extends State<UserProfileAvatar> {
  /// Cache globale dei bytes per path: la foto tesserino è la stessa in tutta
  /// l'app, così non rilampeggia e non ricade sull'iniziale tra una pagina e
  /// l'altra.
  static final Map<String, Uint8List> _bytesCache = <String, Uint8List>{};

  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoPath != widget.fotoPath) _load();
  }

  Future<void> _load() async {
    final path = (widget.fotoPath ?? '').trim();
    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = false;
          _bytes = null;
        });
      }
      return;
    }

    final cached = _bytesCache[path];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final bytes = await loadTesserinoFotoBytes(path);
    if (bytes != null) _bytesCache[path] = bytes;
    if (!mounted) return;
    setState(() {
      // In caso di errore transitorio mantiene l'eventuale foto già mostrata.
      _bytes = bytes ?? _bytes;
      _loading = false;
      _failed = _bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    if (_loading) {
      return CircleAvatar(
        radius: r,
        child: SizedBox(
          width: r,
          height: r,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null && !_failed) {
      return CircleAvatar(
        radius: r,
        backgroundImage: MemoryImage(_bytes!),
      );
    }
    return CircleAvatar(
      radius: r,
      child: Text(
        widget.initial.isNotEmpty ? widget.initial[0].toUpperCase() : '?',
        style: TextStyle(fontSize: r * 0.85),
      ),
    );
  }
}

/// Foto dell'utente che ha effettuato l'accesso (anagrafica personale collegata).
class SessionUserAvatar extends StatefulWidget {
  final double radius;
  final String displayName;
  final String username;
  /// `users.id` dalla sessione GESTOPRO (fallback collegamento personale).
  final int? usersTableId;

  const SessionUserAvatar({
    super.key,
    this.radius = 18,
    required this.displayName,
    this.username = '',
    this.usersTableId,
  });

  /// Aggiorna la cache dopo un upload foto (es. prompt all’accesso).
  static void rememberFotoPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId == null) return;
    _SessionUserAvatarState._fotoPathCache[authId] = trimmed;
  }

  @override
  State<SessionUserAvatar> createState() => _SessionUserAvatarState();
}

class _SessionUserAvatarState extends State<SessionUserAvatar> {
  /// Path foto tesserino già risolto per l'utente loggato (per auth id):
  /// così l'avatar mostra subito la foto del tesserino in ogni pagina.
  static final Map<String, String> _fotoPathCache = <String, String>{};

  String? _fotoPath;

  @override
  void initState() {
    super.initState();
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null) _fotoPath = _fotoPathCache[authId];
    _load();
  }

  @override
  void didUpdateWidget(covariant SessionUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usersTableId != widget.usersTableId) _load();
  }

  Future<void> _load() async {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final path = await resolveMyFotoTesserinoPath(
        usersTableId: widget.usersTableId,
      );
      final trimmed = (path ?? '').trim();
      if (trimmed.isNotEmpty && authId != null) {
        _fotoPathCache[authId] = trimmed;
      }
      if (!mounted) return;
      // Non azzerare una foto già nota se la risoluzione non la trova
      // (errore transitorio / sessione non ancora pronta): riprova al refresh.
      setState(() => _fotoPath = trimmed.isNotEmpty ? trimmed : _fotoPath);
    } catch (_) {
      // Mantiene l'eventuale path in cache.
    }
  }

  String get _initial {
    final n = widget.displayName.trim();
    if (n.isNotEmpty) return n[0];
    final u = widget.username.trim();
    if (u.isNotEmpty) return u[0];
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return UserProfileAvatar(
      radius: widget.radius,
      initial: _initial,
      fotoPath: _fotoPath,
    );
  }
}
