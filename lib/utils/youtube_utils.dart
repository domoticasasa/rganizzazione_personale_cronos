/// Utility per URL e thumbnail YouTube.
abstract final class YoutubeUtils {
  static final RegExp _idPatterns = RegExp(
    r'(?:youtu\.be/|youtube\.com/(?:embed/|v/|shorts/|live/|watch\?v=|watch\?.+&v=))([A-Za-z0-9_-]{11})',
    caseSensitive: false,
  );

  static String? extractVideoId(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final m = _idPatterns.firstMatch(text);
    if (m != null) return m.group(1);
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text)) return text;
    return null;
  }

  static String thumbnailUrl(String videoId, {String quality = 'hqdefault'}) =>
      'https://img.youtube.com/vi/$videoId/$quality.jpg';

  static String embedUrl(String videoId, {bool autoplay = false}) {
    final ap = autoplay ? '1' : '0';
    return 'https://www.youtube.com/embed/$videoId?autoplay=$ap&rel=0';
  }

  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';
}
