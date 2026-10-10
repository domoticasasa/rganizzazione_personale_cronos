import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/date_formatters.dart';
import '../utils/tesserino_helpers.dart';
import 'cronos_tesserino_style.dart';
import 'tesserino_foto_image.dart';

/// Dati visibili sul tesserino (layout allineato a `tes2.xlsx`).
class CronosTesserinoViewData {
  final String nome;
  final String cognome;
  final String natoIl;
  final String assuntoDal;
  final String numeroTesserino;
  final ImageProvider? foto;
  final String? fotoStoragePath;
  final int fotoReloadToken;
  final Uint8List? fotoPreviewBytes;
  final String? _rigaExtraEtichetta;
  final String? _rigaExtraTesto;
  final List<String> righeExtra;

  const CronosTesserinoViewData({
    required this.nome,
    required this.cognome,
    required this.natoIl,
    required this.assuntoDal,
    required this.numeroTesserino,
    this.foto,
    this.fotoStoragePath,
    this.fotoReloadToken = 0,
    this.fotoPreviewBytes,
    this._rigaExtraEtichetta,
    this._rigaExtraTesto,
    List<String>? righeExtra,
  })  : righeExtra = righeExtra ?? const [];

  /// Righe libere in fondo all’anagrafica.
  bool get hasRigaExtra => righeExtra.isNotEmpty;

  int get extraLineCount => righeExtra.length;

  String get rigaExtraEtichetta => _rigaExtraEtichetta ?? '';

  String get rigaExtraTesto =>
      righeExtra.isNotEmpty ? righeExtra.first : (_rigaExtraTesto ?? '');
}

String _fmtPersonaleDate(dynamic raw) {
  if (raw == null) return '—';
  final s = raw.toString().trim();
  if (s.isEmpty) return '—';
  final dt = DateTime.tryParse(s);
  if (dt != null) return formatDateDdMmYyyyFromDate(dt.toLocal());
  return s;
}

CronosTesserinoViewData cronosTesserinoDataFromPersonale(
  Map<String, dynamic> row, {
  ImageProvider? foto,
  int fotoReloadToken = 0,
  Uint8List? fotoPreviewBytes,
  List<String>? righeExtraOverride,
}) {
  final full = (row['full_name'] ?? '').toString().trim();
  final parts = splitPersonaleFullName(full);
  final nt = (row['numero_tesserino'] ?? '').toString().trim();
  final righeExtra = righeExtraOverride ?? tesserinoRigheExtraFromPersonale(row);
  final fotoPath = (row['foto_tesserino_path'] ?? '').toString().trim();

  return CronosTesserinoViewData(
    nome: parts.nome.isEmpty ? '—' : parts.nome,
    cognome: parts.cognome.isEmpty ? '—' : parts.cognome,
    natoIl: _fmtPersonaleDate(row['data_nascita']),
    assuntoDal: _fmtPersonaleDate(row['data_assunzione']),
    numeroTesserino: nt.isEmpty ? '—' : nt,
    foto: foto,
    fotoStoragePath: fotoPath.isEmpty ? null : fotoPath,
    fotoReloadToken: fotoReloadToken,
    fotoPreviewBytes: fotoPreviewBytes,
    righeExtra: righeExtra,
  );
}

/// Fascia superiore con logo CRONOS (proporzioni `tes2`, non deformata).
class _TesserinoHeaderBand extends StatelessWidget {
  final double cardWidth;

  const _TesserinoHeaderBand({required this.cardWidth});

  double get _bandH => cardWidth * CronosTesserinoStyle.id1HeaderHeightOverWidth;

  double get _logoW => cardWidth * CronosTesserinoStyle.headerLogoScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _bandH,
      width: cardWidth,
      child: Center(
        child: Image.asset(
          CronosTesserinoStyle.assetHeaderPng,
          width: _logoW,
          height: _bandH,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => Image.asset(
            CronosTesserinoStyle.assetHeaderFallback,
            width: _logoW,
            height: _bandH,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => Text(
              'CRONOS',
              style: TextStyle(
                fontFamily: CronosTesserinoStyle.fontFamily,
                fontSize:
                    cardWidth * 0.055 * CronosTesserinoStyle.headerLogoScale,
                fontWeight: FontWeight.w900,
                color: CronosTesserinoStyle.borderBlack,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CronosTesserinoCard extends StatelessWidget {
  final CronosTesserinoViewData data;
  final double width;

  const CronosTesserinoCard({
    super.key,
    required this.data,
    this.width = 360,
  });

  /// Proporzioni simili al foglio (banner 512×122 nel template).
  double get _headerH => width * (122 / 512);

  double get _barH => width * 0.036;

  /// Altezza complessiva carta (portrait contenuto).
  double get _cardH => _headerH + width * 0.42 + _barH;

  Widget _buildFotoSlot(double cardWidth) {
    final preview = data.fotoPreviewBytes;
    if (preview != null && preview.isNotEmpty) {
      return Image.memory(
        preview,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
      );
    }
    final path = (data.fotoStoragePath ?? '').trim();
    if (path.isNotEmpty) {
      return TesserinoFotoImage(
        key: ValueKey('$path-${data.fotoReloadToken}'),
        storagePath: path,
        reloadToken: data.fotoReloadToken,
        placeholderIconSize: cardWidth * 0.12,
      );
    }
    if (data.foto != null) {
      return Image(
        image: data.foto!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
      );
    }
    return Icon(
      Icons.person_outline,
      size: cardWidth * 0.12,
      color: Colors.black26,
    );
  }

  @override
  Widget build(BuildContext context) {
    final extra = data.hasRigaExtra;
    final extraCount = data.extraLineCount;
    final stL = CronosTesserinoStyle.fontLabel(
      width,
      hasExtraLine: extra,
    );
    final stV = CronosTesserinoStyle.fontValue(
      width,
      hasExtraLine: extra,
    );
    final stExtra = TextStyle(
      fontFamily: CronosTesserinoStyle.fontFamily,
      fontSize: CronosTesserinoStyle.valueFontSizeForCount(width, extraCount),
      fontWeight: FontWeight.w700,
      height: extraCount > 2 ? 1.05 : 1.12,
      color: CronosTesserinoStyle.borderBlack,
    );
    final linePad = extra ? 1.0 : 2.0;

    Widget line(String label, String value) {
      final v = value.isEmpty ? '—' : value;
      return Padding(
        padding: EdgeInsets.only(bottom: linePad),
        child: RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: stV,
            children: [
              TextSpan(text: label, style: stL),
              TextSpan(text: v, style: stV),
            ],
          ),
        ),
      );
    }

    Widget extraLines() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in data.righeExtra)
            Padding(
              padding: EdgeInsets.only(bottom: linePad),
              child: Text(
                line.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: stExtra,
              ),
            ),
        ],
      );
    }

    return Center(
      child: SizedBox(
        width: width,
        height: _cardH,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: CronosTesserinoStyle.borderBlack,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TesserinoHeaderBand(cardWidth: width),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(width * 0.028, 4, width * 0.022, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 100,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: width * 0.68,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(CronosTesserinoStyle.via, style: stL),
                                Text(CronosTesserinoStyle.cf, style: stL),
                                SizedBox(
                                  height: CronosTesserinoStyle
                                      .blockGapBeforeAnagrafica(
                                    width,
                                    hasExtraLine: extra,
                                  ),
                                ),
                                line(CronosTesserinoStyle.lblNome, data.nome),
                                line(
                                  CronosTesserinoStyle.lblCognome,
                                  data.cognome,
                                ),
                                line(CronosTesserinoStyle.lblNato, data.natoIl),
                                line(
                                  CronosTesserinoStyle.lblAssunto,
                                  data.assuntoDal,
                                ),
                                line(
                                  CronosTesserinoStyle.lblTess,
                                  data.numeroTesserino,
                                ),
                                if (extra) extraLines(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: width * 0.018),
                      SizedBox(
                        width: width * 0.26,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: CronosTesserinoStyle.photoBg,
                            border: Border.all(
                              color: CronosTesserinoStyle.borderBlack,
                              width: 0.75,
                            ),
                          ),
                          child: AspectRatio(
                            aspectRatio: CronosTesserinoStyle.photoAspectRatio,
                            child: _buildFotoSlot(width),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: _barH,
                color: CronosTesserinoStyle.barFill,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
