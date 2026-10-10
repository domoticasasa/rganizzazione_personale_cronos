import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/tesserino_foto.dart';

/// Foto tesserino caricata da Storage (bytes in memoria, adatta a bucket privati).
class TesserinoFotoImage extends StatefulWidget {
  final String storagePath;
  /// Incrementare dopo ogni upload (stesso path in DB → forza ricarico).
  final int reloadToken;
  final BoxFit fit;
  final Alignment alignment;
  final double? placeholderIconSize;

  const TesserinoFotoImage({
    super.key,
    required this.storagePath,
    this.reloadToken = 0,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.placeholderIconSize,
  });

  @override
  State<TesserinoFotoImage> createState() => _TesserinoFotoImageState();
}

class _TesserinoFotoImageState extends State<TesserinoFotoImage> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TesserinoFotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath ||
        oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _bytes = null;
    });
    final path = widget.storagePath.trim();
    if (path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final bytes = await loadTesserinoFotoBytes(path);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        key: ValueKey('${widget.storagePath}_${widget.reloadToken}_${_bytes!.length}'),
        fit: widget.fit,
        alignment: widget.alignment,
        gaplessPlayback: false,
        filterQuality: FilterQuality.medium,
      );
    }
    return Icon(
      Icons.person_outline,
      size: widget.placeholderIconSize ?? 48,
      color: Colors.black26,
    );
  }
}
