import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Campi minimi per avatar / path foto in home dipendente.
const kPersonaleProfileMinimalSelect =
    'id_uuid, user_id, foto_tesserino_path';

/// Campi profilo completo (allineati a Gestione personale).
const kPersonaleProfileFullSelect =
    'id,id_uuid,user_id,full_name,email,telefono,matricola,'
    'numero_tesserino,data_assunzione,data_nascita,foto_tesserino_path';

/// Campi per anteprima e PDF tesserino.
const kPersonaleTesserinoSelect =
    'id, id_uuid, full_name, data_assunzione, data_nascita, '
    'numero_tesserino, foto_tesserino_path, user_id, '
    'tesserino_extra_etichetta, tesserino_extra_testo, '
    'tesserino_righe_extra, tesserino_commessa_id_uuid';

class MyProfileBundle {
  const MyProfileBundle({
    this.users,
    this.personale,
  });

  final Map<String, dynamic>? users;
  final Map<String, dynamic>? personale;
}

List<String> _selectVariants(String select) {
  final variants = <String>[
    select,
    kPersonaleProfileFullSelect,
    'id,id_uuid,user_id,full_name,email,telefono,matricola,'
        'numero_tesserino,data_assunzione',
    kPersonaleProfileMinimalSelect,
  ];
  return variants
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

Future<Map<String, dynamic>?> _fetchPersonaleRow(
  String column,
  String value, {
  required String select,
}) async {
  for (final cols in _selectVariants(select)) {
    try {
      final rows = await SupabaseService.client
          .from('personale')
          .select(cols)
          .eq(column, value)
          .order('id', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
    }
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchUsersRow({
  required String column,
  required String value,
}) async {
  try {
    final rows = await SupabaseService.client
        .from('users')
        .select('id, id_uuid, auth_id, email, full_name, username, role')
        .eq(column, value)
        .order('id', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  } on PostgrestException catch (e) {
    if (e.code == '42703') return null;
    rethrow;
  }
}

Future<Map<String, dynamic>?> _fetchPersonaleByEmailIlike(String email) async {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final cols in _selectVariants(kPersonaleProfileFullSelect)) {
    try {
      final rows = await SupabaseService.client
          .from('personale')
          .select(cols)
          .ilike('email', normalized)
          .limit(1);
      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
    }
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchUsersRowForAuth({
  required String authId,
  required String authEmail,
}) async {
  try {
    final row = await _fetchUsersRow(column: 'auth_id', value: authId);
    if (row != null) return row;
    if (authEmail.isNotEmpty) {
      final byEmail = await SupabaseService.client
          .from('users')
          .select('id,id_uuid,auth_id,full_name,email,username,role')
          .ilike('email', authEmail)
          .order('id', ascending: false)
          .limit(1);
      if (byEmail.isNotEmpty) {
        return Map<String, dynamic>.from(byEmail.first);
      }
    }
  } on PostgrestException catch (_) {}
  return null;
}

bool _foundPersonaleRow(Map<String, dynamic>? row) {
  if (row == null) return false;
  if ((row['full_name'] ?? '').toString().trim().isNotEmpty) return true;
  if ((row['email'] ?? '').toString().trim().isNotEmpty) return true;
  if ((row['id_uuid'] ?? '').toString().trim().isNotEmpty) return true;
  if ((row['id'] ?? '').toString().trim().isNotEmpty) return true;
  return false;
}

Map<String, dynamic>? _mapFromJsonValue(dynamic value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

bool _isRpcUnavailable(PostgrestException e) =>
    e.code == 'PGRST202' || e.code == '42883';

Future<MyProfileBundle?> _fetchProfileBundleFromRpc() async {
  try {
    final raw = await SupabaseService.client.rpc('get_my_personale_profile');
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return MyProfileBundle(
      users: _mapFromJsonValue(map['users']),
      personale: _mapFromJsonValue(map['personale']),
    );
  } on PostgrestException catch (e) {
    if (_isRpcUnavailable(e)) return null;
    rethrow;
  }
}

/// Risolve il record `personale` dell'utente loggato (stessa logica della home dipendente).
Future<Map<String, dynamic>?> resolveMyPersonaleRow({
  String select = kPersonaleProfileFullSelect,
}) async {
  final fromRpc = await _fetchProfileBundleFromRpc();
  final rpcPersonale = fromRpc?.personale;
  if (_foundPersonaleRow(rpcPersonale)) {
    return Map<String, dynamic>.from(rpcPersonale!);
  }

  final authUser = Supabase.instance.client.auth.currentUser;
  if (authUser == null) return null;
  final authId = authUser.id;
  final authEmail = (authUser.email ?? '').trim().toLowerCase();

  final byAuth = await _fetchPersonaleRow(
    'user_id',
    authId,
    select: select,
  );
  if (_foundPersonaleRow(byAuth)) return byAuth;

  Map<String, dynamic>? usersRow =
      await _fetchUsersRow(column: 'auth_id', value: authId);

  usersRow ??= await _fetchUsersRow(column: 'id_uuid', value: authId);

  if (usersRow == null && authEmail.isNotEmpty) {
    final byEmail = await SupabaseService.client
        .from('users')
        .select('id, id_uuid, auth_id, email')
        .ilike('email', authEmail)
        .order('id', ascending: false)
        .limit(1);
    if (byEmail.isNotEmpty) {
      usersRow = Map<String, dynamic>.from(byEmail.first);
    }
  }
  if (usersRow != null) {
    usersRow = Map<String, dynamic>.from(usersRow);
  }

  final uid = (usersRow?['id'] ?? '').toString();
  final uuid = (usersRow?['id_uuid'] ?? '').toString();
  final linkedAuthId = (usersRow?['auth_id'] ?? '').toString();

  for (final candidate in <String>{
    if (uid.isNotEmpty) uid,
    if (uuid.isNotEmpty) uuid,
    if (linkedAuthId.isNotEmpty) linkedAuthId,
  }) {
    final row = await _fetchPersonaleRow('user_id', candidate, select: select);
    if (_foundPersonaleRow(row)) return row;
  }

  if (authEmail.isNotEmpty) {
    final byEmail = await _fetchPersonaleByEmailIlike(authEmail);
    if (_foundPersonaleRow(byEmail)) return byEmail;
  }

  final usersEmail = (usersRow?['email'] ?? '').toString().trim().toLowerCase();
  if (usersEmail.isNotEmpty && usersEmail != authEmail) {
    final byUsersEmail = await _fetchPersonaleByEmailIlike(usersEmail);
    if (_foundPersonaleRow(byUsersEmail)) return byUsersEmail;
  }

  return null;
}

/// Profilo completo (users + personale) via RPC sicura, con fallback client.
Future<MyProfileBundle> resolveMyProfileBundle({
  String select = kPersonaleProfileFullSelect,
}) async {
  final fromRpc = await _fetchProfileBundleFromRpc();
  if (fromRpc != null) return fromRpc;

  final authUser = Supabase.instance.client.auth.currentUser;
  if (authUser == null) {
    return const MyProfileBundle();
  }

  final authEmail = (authUser.email ?? '').trim().toLowerCase();
  final personale = await resolveMyPersonaleRow(select: select);
  final users = await _fetchUsersRowForAuth(
    authId: authUser.id,
    authEmail: authEmail,
  );

  return MyProfileBundle(
    users: users,
    personale: personale == null ? null : Map<String, dynamic>.from(personale),
  );
}

/// Path foto tesserino dell'utente loggato (RPC sicura + fallback client).
Future<String?> resolveMyFotoTesserinoPath({int? usersTableId}) async {
  final bundle = await resolveMyProfileBundle(
    select: kPersonaleProfileMinimalSelect,
  );
  var path = (bundle.personale?['foto_tesserino_path'] ?? '')
      .toString()
      .trim();
  if (path.isNotEmpty) return path;

  final candidates = <String>{
    if (usersTableId != null && usersTableId > 0) usersTableId.toString(),
    (bundle.users?['id'] ?? '').toString(),
    (bundle.users?['id_uuid'] ?? '').toString(),
    (bundle.users?['auth_id'] ?? '').toString(),
  }..removeWhere((v) => v.trim().isEmpty);

  for (final candidate in candidates) {
    final row = await _fetchPersonaleRow(
      'user_id',
      candidate,
      select: kPersonaleProfileMinimalSelect,
    );
    path = (row?['foto_tesserino_path'] ?? '').toString().trim();
    if (path.isNotEmpty) return path;
  }

  return null;
}

/// Salva telefono/email/data nascita sul record personale collegato.
Future<MyProfileBundle> saveMyPersonaleProfile({
  String? email,
  String? telefono,
  String? dataNascitaIso,
}) async {
  try {
    final params = <String, dynamic>{};
    if (email != null) {
      final emailNorm = email.trim().toLowerCase();
      if (emailNorm.isNotEmpty) {
        params['p_email'] = emailNorm;
      }
    }
    if (telefono != null) {
      params['p_telefono'] = telefono.trim();
    }
    if (dataNascitaIso != null) {
      final nascitaIso = dataNascitaIso.trim();
      if (nascitaIso.isNotEmpty) {
        params['p_data_nascita'] = nascitaIso;
      }
    }
    if (params.isEmpty) {
      return resolveMyProfileBundle();
    }

    final raw = await SupabaseService.client.rpc(
      'update_my_personale_profile',
      params: params,
    );
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      return MyProfileBundle(
        users: _mapFromJsonValue(map['users']),
        personale: _mapFromJsonValue(map['personale']),
      );
    }
  } on PostgrestException catch (e) {
    if (!_isRpcUnavailable(e)) rethrow;
  }

  return resolveMyProfileBundle();
}
