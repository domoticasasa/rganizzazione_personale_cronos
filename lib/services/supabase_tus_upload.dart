import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'supabase_service.dart';

/// Upload TUS (resumable) verso Supabase Storage.
/// Obbligatorio per file grandi: l'upload standard spesso fallisce con 413
/// (limite gateway / payload), mentre TUS invia chunk da 6 MiB.
class SupabaseTusUpload {
  SupabaseTusUpload._();

  static const int chunkSize = 6 * 1024 * 1024; // richiesto da Supabase

  static Uri get _endpoint {
    final host = Uri.parse(SupabaseService.supabaseUrl).host;
    final projectRef = host.split('.').first;
    return Uri.parse(
      'https://$projectRef.storage.supabase.co/storage/v1/upload/resumable',
    );
  }

  static String _encodeMetadata(Map<String, String> meta) {
    return meta.entries
        .map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}')
        .join(',');
  }

  static Future<void> uploadBinary({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
    bool upsert = false,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('File vuoto');
    }

    final session = SupabaseService.client.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Sessione mancante: effettua di nuovo l\'accesso');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer $accessToken',
      'apikey': SupabaseService.anonKey,
      'Tus-Resumable': '1.0.0',
      'Upload-Length': '${bytes.length}',
      'Upload-Metadata': _encodeMetadata({
        'bucketName': bucket,
        'objectName': objectPath,
        'contentType': contentType,
        'cacheControl': '3600',
      }),
      if (upsert) 'x-upsert': 'true',
    };

    final create = await http.post(_endpoint, headers: headers);
    if (create.statusCode != 201 && create.statusCode != 200) {
      throw StateError(
        'Creazione upload fallita (${create.statusCode}): ${create.body}',
      );
    }

    final locationRaw = create.headers['location'] ?? create.headers['Location'];
    if (locationRaw == null || locationRaw.isEmpty) {
      throw StateError('Upload URL mancante nella risposta TUS');
    }
    final uploadUrl = Uri.parse(locationRaw).isAbsolute
        ? Uri.parse(locationRaw)
        : _endpoint.resolve(locationRaw);

    var offset = 0;
    onProgress?.call(offset, bytes.length);

    while (offset < bytes.length) {
      final end = (offset + chunkSize < bytes.length)
          ? offset + chunkSize
          : bytes.length;
      final chunk = bytes.sublist(offset, end);

      final patch = await http.patch(
        uploadUrl,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseService.anonKey,
          'Tus-Resumable': '1.0.0',
          'Upload-Offset': '$offset',
          'Content-Type': 'application/offset+octet-stream',
          'Content-Length': '${chunk.length}',
          if (upsert) 'x-upsert': 'true',
        },
        body: chunk,
      );

      if (patch.statusCode != 204 && patch.statusCode != 200) {
        throw StateError(
          'Upload chunk fallito (${patch.statusCode}): ${patch.body}',
        );
      }

      final newOffsetHeader =
          patch.headers['upload-offset'] ?? patch.headers['Upload-Offset'];
      final parsed = int.tryParse(newOffsetHeader ?? '');
      offset = parsed ?? end;
      onProgress?.call(offset, bytes.length);
    }
  }
}
