
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';

/// Immagini incorporate in Mod.RFP_03.xlsx (logo, firma datore, loghi footer).
class Rfp03TemplateImages {
  const Rfp03TemplateImages({
    required this.headerLogo,
    required this.footerStrip,
    required this.firmaDatore,
    required this.footerCertLogos,
  });

  final Uint8List headerLogo;
  final Uint8List footerStrip;
  final Uint8List firmaDatore;
  /// Loghi certificazioni in basso a destra (RFI, ISO, …).
  final List<Uint8List> footerCertLogos;
}

Uint8List? _tryReadMedia(Archive archive, String fileName) {
  final needle = fileName.toLowerCase();
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    if (name.toLowerCase().endsWith('/$needle') ||
        name.toLowerCase() == 'xl/media/$needle') {
      return Uint8List.fromList(List<int>.from(f.content as List));
    }
  }
  return null;
}

Uint8List _readMedia(Archive archive, List<String> candidates) {
  for (final fileName in candidates) {
    final bytes = _tryReadMedia(archive, fileName);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }
  throw StateError(
    'Media mancante nel template (cercati: ${candidates.join(", ")})',
  );
}

Future<Rfp03TemplateImages> loadRfp03TemplateImages() async {
  final bd = await rootBundle.load(ExcelTemplateAssets.modRfp03);
  final templateBytes =
      bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  final archive = ZipDecoder().decodeBytes(templateBytes);
  // Ancore drawing1.xml (template attuale):
  // - image8.png  → logo header (riga 3)
  // - image9.jpeg → firma «Per accettazione» (riga 47)
  // - image10.png → striscia footer (riga 52)
  // - image1–7    → loghi certificazioni
  final certs = <Uint8List>[];
  for (final name in const [
    'image1.jpeg',
    'image2.png',
    'image3.jpeg',
    'image4.jpeg',
    'image5.jpeg',
    'image6.png',
    'image7.jpeg',
  ]) {
    final b = _tryReadMedia(archive, name);
    if (b != null && b.isNotEmpty) certs.add(b);
  }

  return Rfp03TemplateImages(
    headerLogo: _readMedia(archive, const [
      'image8.png',
      'image8.jpeg',
      'image8.jpg',
    ]),
    firmaDatore: _readMedia(archive, const [
      'image9.jpeg',
      'image9.png',
      'image9.jpg',
    ]),
    footerStrip: _readMedia(archive, const [
      'image10.png',
      'image10.jpeg',
      'image10.jpg',
    ]),
    footerCertLogos: certs,
  );
}
