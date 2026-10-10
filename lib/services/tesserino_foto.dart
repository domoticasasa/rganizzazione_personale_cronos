import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/device.dart';
import '../utils/mobile_navigation.dart';
import '../widgets/web_in_app_camera.dart';
import 'app_device_unlock_gate.dart';
import 'supabase_service.dart';
import 'tesserino_foto_processing.dart';
import 'tesserino_web_image_pick.dart';

/// Immagine selezionata per upload foto tesserino.
class TesserinoPickedImage {
  final Uint8List bytes;
  final String ext;
  final String mimeType;

  const TesserinoPickedImage({
    required this.bytes,
    required this.ext,
    required this.mimeType,
  });
}

/// Telefono (app o browser stretto): fotocamera / galleria. Desktop: file.
Future<TesserinoPickedImage?> pickTesserinoImageInteractive(
  BuildContext context,
) async {
  final mobileUi = isMobileDevice() || (kIsWeb && useMobileUi(context));
  if (!mobileUi) {
    return pickTesserinoImageFile();
  }

  if (kIsWeb) {
    return _pickTesserinoImageWebMobile(context);
  }

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Scatta foto'),
            subtitle: const Text('Sfondo bianco automatico'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Scegli dalla galleria'),
            subtitle: const Text('Sfondo bianco automatico'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Scegli file'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return null;

  if (action == 'file') {
    return pickTesserinoImageFile();
  }

  return _pickTesserinoFromImagePicker(
    action == 'camera' ? ImageSource.camera : ImageSource.gallery,
  );
}

/// Apre subito la fotocamera (stesso gesto del tap: necessario sul web).
Future<TesserinoPickedImage?> pickTesserinoImageFromCamera(
  BuildContext context,
) async {
  if (kIsWeb) {
    final bytes = await capturePhotoInApp(
      context,
      title: 'Foto tesserino',
      hint: 'Inquadra il viso e tocca Scatta. Resta in CRONOS.',
    );
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return await _bytesToTesserinoPicked(bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto non elaborata: $e')),
        );
      }
      return null;
    }
  }

  return _pickTesserinoFromImagePicker(ImageSource.camera);
}

/// Web mobile: il click file input deve partire nel [onTap] (stesso gesto utente).
Future<TesserinoPickedImage?> _pickTesserinoImageWebMobile(
  BuildContext context,
) async {
  final raw = await showModalBottomSheet<Uint8List?>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Scatta foto'),
            subtitle: const Text('Resta in CRONOS, senza aprire la Camera'),
            onTap: () => unawaited(_webCaptureTesserinoInApp(sheetCtx)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Scegli dalla galleria'),
            subtitle: const Text('Sfondo bianco automatico'),
            onTap: () => _webPickFromSheet(sheetCtx, camera: false),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || raw == null || raw.isEmpty) return null;

  try {
    return await runWithTesserinoPhotoBusy(
      context,
      () => _bytesToTesserinoPicked(raw),
      message: 'Elaborazione foto…',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto non elaborata: $e')),
      );
    }
    return null;
  }
}

void _webPickFromSheet(BuildContext sheetCtx, {required bool camera}) {
  pickTesserinoWebImageOnUserGesture(
    camera: camera,
    onDone: (bytes) {
      if (!sheetCtx.mounted) return;
      Navigator.pop(
        sheetCtx,
        (bytes == null || bytes.isEmpty) ? null : bytes,
      );
    },
  );
}

Future<void> _webCaptureTesserinoInApp(BuildContext sheetCtx) async {
  final bytes = await capturePhotoInApp(
    sheetCtx,
    title: 'Foto tesserino',
    hint: 'Inquadra il viso e tocca Scatta. Resta in CRONOS.',
  );
  if (!sheetCtx.mounted) return;
  Navigator.pop(
    sheetCtx,
    (bytes == null || bytes.isEmpty) ? null : bytes,
  );
}

/// Overlay durante pick/upload (evita schermata “bloccata” senza feedback).
Future<T?> runWithTesserinoPhotoBusy<T>(
  BuildContext context,
  Future<T?> Function() action, {
  String message = 'Elaborazione foto in corso…',
}) async {
  if (!context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

Future<TesserinoPickedImage?> _bytesToTesserinoPicked(Uint8List? raw) async {
  if (raw == null || raw.isEmpty) return null;
  final processed = await processTesserinoPhotoBytes(raw);
  return TesserinoPickedImage(
    bytes: processed,
    ext: 'jpg',
    mimeType: 'image/jpeg',
  );
}

/// Elabora bytes grezzi (es. foto recuperata dopo reload mobile web).
Future<TesserinoPickedImage?> tesserinoPickedFromRawBytes(Uint8List raw) =>
    _bytesToTesserinoPicked(raw);

Future<TesserinoPickedImage?> _pickTesserinoFromImagePicker(
  ImageSource source,
) {
  return AppDeviceUnlockGate.runWithExternalPicker(() async {
  final picker = ImagePicker();
  final xfile = await picker.pickImage(
    source: source,
    preferredCameraDevice: CameraDevice.front,
    imageQuality: 85,
    maxWidth: 1280,
    maxHeight: 1280,
  );
  if (xfile == null) return null;
  Uint8List rawBytes;
  try {
    rawBytes = await xfile.readAsBytes();
  } catch (_) {
    return null;
  }

  if (rawBytes.isEmpty) return null;
  try {
    final processed = await processTesserinoPhotoBytes(rawBytes);
    return TesserinoPickedImage(
      bytes: processed,
      ext: 'jpg',
      mimeType: 'image/jpeg',
    );
  } catch (e) {
    debugPrint('processTesserinoPhotoBytes: $e');
    rethrow;
  }
  });
}

/// Apre il selettore file (jpg/png/webp) e applica sfondo bianco.
Future<TesserinoPickedImage?> pickTesserinoImageFile() {
  return AppDeviceUnlockGate.runWithExternalPicker(() async {
  const group = XTypeGroup(
    label: 'Immagini',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  try {
    final bytes = await file.readAsBytes();
    final processed = await processTesserinoPhotoBytes(bytes);
    return TesserinoPickedImage(
      bytes: processed,
      ext: 'jpg',
      mimeType: 'image/jpeg',
    );
  } catch (e) {
    debugPrint('pickTesserinoImageFile: $e');
    rethrow;
  }
  });
}

String tesserinoFotoObjectPath(String personaleIdUuid, String ext) {
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  return '$personaleIdUuid/foto_$ts.$ext';
}

bool _isStorageBucketNotFound(Object e) {
  if (e is! StorageException) return false;
  final msg = e.message.toLowerCase();
  return e.statusCode == '404' || msg.contains('bucket not found');
}

/// Ordine tentativi upload: bucket della foto esistente, poi alias noti.
List<String> tesserinoUploadBucketCandidates({String? existingStoragePath}) {
  final ordered = <String>[];
  final ref = parseTesserinoStorageRef((existingStoragePath ?? '').trim());
  if (ref != null && ref.bucket.isNotEmpty) {
    ordered.add(ref.bucket);
  }
  for (final bucket in kTesseriniFotoBuckets) {
    if (!ordered.contains(bucket)) ordered.add(bucket);
  }
  return ordered;
}

/// Bucket dove la foto è già presente (stessa logica del download).
Future<String?> detectTesserinoFotoBucket(
  SupabaseClient supa,
  String storagePath,
) async {
  final ref = parseTesserinoStorageRef(storagePath);
  if (ref == null || ref.objectPath.isEmpty) return null;
  for (final bucket in tesserinoUploadBucketCandidates(
    existingStoragePath: storagePath,
  )) {
    try {
      final bytes = await supa.storage.from(bucket).download(ref.objectPath);
      if (bytes.isNotEmpty) return bucket;
    } catch (_) {}
  }
  return null;
}

/// Carica su Storage e aggiorna `personale.foto_tesserino_path`.
Future<String> uploadTesserinoFotoForPersonale({
  required SupabaseClient supa,
  required int personaleId,
  required String personaleIdUuid,
  required TesserinoPickedImage image,
  String? existingStoragePath,
}) async {
  final uuid = personaleIdUuid.trim();
  if (uuid.isEmpty) {
    throw Exception('UUID personale mancante');
  }
  final objectPath = tesserinoFotoObjectPath(uuid, image.ext);
  final existing = (existingStoragePath ?? '').trim();

  var buckets = tesserinoUploadBucketCandidates(existingStoragePath: existing);
  final detected = existing.isEmpty
      ? null
      : await detectTesserinoFotoBucket(supa, existing);
  if (detected != null && detected.isNotEmpty) {
    buckets = [detected, ...buckets.where((b) => b != detected)];
  }

  StorageException? lastError;
  String? usedBucket;
  for (final bucket in buckets) {
    try {
      await supa.storage.from(bucket).uploadBinary(
            objectPath,
            image.bytes,
            fileOptions: FileOptions(
              contentType: image.mimeType,
              upsert: true,
            ),
          );
      usedBucket = bucket;
      break;
    } catch (e) {
      if (_isStorageBucketNotFound(e)) {
        lastError = e is StorageException ? e : lastError;
        continue;
      }
      rethrow;
    }
  }

  if (usedBucket == null) {
    if (lastError != null) throw lastError;
    throw Exception(
      'Nessun bucket foto tesserino trovato (${buckets.join(', ')}).',
    );
  }

  await supa.from('personale').update({
    'foto_tesserino_path': objectPath,
  }).eq('id', personaleId);
  return objectPath;
}

/// Bucket predefinito (path DB senza prefisso); il download prova tutti [kTesseriniFotoBuckets].
const String kTesseriniFotoBucket = 'tesserini_foto';

/// Nomi bucket su Supabase (produzione usa spesso `tesserini_foto`).
const List<String> kTesseriniFotoBuckets = [
  'tesserini_foto',
  'tesserini-foto',
  'tesserini',
];

/// Riferimento oggetto in Storage (bucket + path relativo).
class TesserinoStorageRef {
  final String bucket;
  final String objectPath;

  const TesserinoStorageRef({
    required this.bucket,
    required this.objectPath,
  });
}

/// Estrae bucket e path da valore DB (path relativo, prefisso bucket o URL Supabase).
TesserinoStorageRef? parseTesserinoStorageRef(String raw) {
  var path = raw.trim();
  if (path.isEmpty) return null;

  for (final bucket in kTesseriniFotoBuckets) {
    final prefix = '$bucket/';
    if (path.startsWith(prefix)) {
      return TesserinoStorageRef(
        bucket: bucket,
        objectPath: path.substring(prefix.length),
      );
    }
  }

  if (path.startsWith('http://') || path.startsWith('https://')) {
    final uri = Uri.tryParse(path);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    // /storage/v1/object/public|sign|authenticated/{bucket}/{path...}
    for (var i = 0; i < segments.length - 2; i++) {
      if (segments[i] != 'object') continue;
      final kind = segments[i + 1];
      if (kind != 'public' &&
          kind != 'sign' &&
          kind != 'authenticated' &&
          kind != 'private') {
        continue;
      }
      if (i + 3 < segments.length) {
        final bucket = segments[i + 2];
        final objectPath = segments.sublist(i + 3).join('/');
        if (objectPath.isNotEmpty) {
          return TesserinoStorageRef(bucket: bucket, objectPath: objectPath);
        }
      }
    }
    for (final bucket in kTesseriniFotoBuckets) {
      final bucketIdx = segments.indexOf(bucket);
      if (bucketIdx >= 0 && bucketIdx < segments.length - 1) {
        return TesserinoStorageRef(
          bucket: bucket,
          objectPath: segments.sublist(bucketIdx + 1).join('/'),
        );
      }
    }
    return null;
  }

  return TesserinoStorageRef(
    bucket: kTesseriniFotoBucket,
    objectPath: path,
  );
}

/// Path oggetto (senza bucket) per compatibilità con chiamate esistenti.
String? normalizeTesserinoStoragePath(String raw) {
  return parseTesserinoStorageRef(raw)?.objectPath;
}

Future<Uint8List?> _downloadRef(TesserinoStorageRef ref) async {
  final buckets = <String>[
    ref.bucket,
    ...kTesseriniFotoBuckets.where((b) => b != ref.bucket),
  ];
  for (final bucket in buckets) {
    try {
      final bytes = await SupabaseService.client.storage
          .from(bucket)
          .download(ref.objectPath);
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {}
  }
  return null;
}

/// URL firmato (bucket privato) o null se assente / non accessibile.
Future<String?> loadTesserinoFotoUrl(String storagePath) async {
  final ref = parseTesserinoStorageRef(storagePath);
  if (ref == null || ref.objectPath.isEmpty) return null;

  final buckets = <String>[
    ref.bucket,
    ...kTesseriniFotoBuckets.where((b) => b != ref.bucket),
  ];
  for (final bucket in buckets) {
    final storage = SupabaseService.client.storage.from(bucket);
    try {
      return await storage.createSignedUrl(ref.objectPath, 3600);
    } catch (_) {
      try {
        await storage.download(ref.objectPath);
        return await storage.createSignedUrl(ref.objectPath, 3600);
      } catch (_) {}
    }
  }
  return null;
}

/// Bytes immagine (affidabile su bucket privato con sessione attiva).
Future<Uint8List?> loadTesserinoFotoBytes(String storagePath) async {
  final ref = parseTesserinoStorageRef(storagePath);
  if (ref == null || ref.objectPath.isEmpty) return null;
  return _downloadRef(ref);
}

/// Carica l'immagine profilo (prima download, poi URL firmato).
Future<ImageProvider?> loadTesserinoFotoImageProvider(String storagePath) async {
  final bytes = await loadTesserinoFotoBytes(storagePath);
  if (bytes != null) return MemoryImage(bytes);

  final url = await loadTesserinoFotoUrl(storagePath);
  if (url != null && url.isNotEmpty) return NetworkImage(url);
  return null;
}
