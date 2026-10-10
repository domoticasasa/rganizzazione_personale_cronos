import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Fuori dal web la fotocamera in-pagina non è usata.
Future<Uint8List?> capturePhotoInApp(
  BuildContext context, {
  String title = 'Fotocamera',
  String hint = 'Inquadra e tocca Scatta',
}) async {
  return null;
}
