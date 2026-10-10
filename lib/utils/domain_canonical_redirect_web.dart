// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void redirectToCanonical({
  required String host,
  required String path,
  String? query,
  String? fragment,
}) {
  final uri = Uri(
    scheme: 'https',
    host: host,
    path: path.isEmpty ? '/' : path,
    query: (query == null || query.isEmpty) ? null : query,
    fragment: (fragment == null || fragment.isEmpty) ? null : fragment,
  );
  html.window.location.replace(uri.toString());
}
