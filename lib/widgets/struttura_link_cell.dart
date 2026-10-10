import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// True per URL Google Maps / link brevi di posizione.
bool looksLikeMapUrl(String url) {
  final u = url.trim().toLowerCase();
  if (u.isEmpty) return false;
  return u.contains('maps.') ||
      u.contains('google.com/maps') ||
      u.contains('maps.app.goo.gl') ||
      u.contains('goo.gl/maps');
}

/// Apre link http(s) nel browser/app di sistema.
Future<bool> openExternalUrl(String url) async {
  final t = url.trim();
  if (t.isEmpty) return false;
  final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Pulsante «Maps» / «Apri» per colonna Struttura / Link.
class StrutturaLinkCell extends StatelessWidget {
  const StrutturaLinkCell({
    super.key,
    required this.link,
    this.onOpenFailed,
    this.compact = false,
  });

  final String link;
  final VoidCallback? onOpenFailed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = link.trim();
    if (t.isEmpty) return const Text('—');
    final mapLike = looksLikeMapUrl(t);
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size(compact ? 0 : 48, compact ? 32 : 36),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () async {
        final ok = await openExternalUrl(t);
        if (!ok) onOpenFailed?.call();
      },
      icon: Icon(
        mapLike ? Icons.map_outlined : Icons.open_in_new,
        size: compact ? 18 : 20,
      ),
      label: Text(mapLike ? 'Maps' : 'Apri'),
    );
  }
}
