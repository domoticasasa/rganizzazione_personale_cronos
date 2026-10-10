import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Carica MP3 dal bundle Flutter (evita 404 `assets/assets/...` su Web).
Future<void> loadBundledMp3(AudioPlayer player, String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  await player.setAudioSource(
    AudioSource.uri(
      Uri.dataFromBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        mimeType: 'audio/mpeg',
      ),
    ),
  );
}
