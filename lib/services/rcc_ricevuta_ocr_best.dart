import 'dart:typed_data';

import 'rcc_ricevuta_carburante_parser.dart';
import 'rcc_ricevuta_ocr_preprocess.dart';

class RicevutaOcrPass {
  const RicevutaOcrPass({this.cardFocus = false});
  final bool cardFocus;
}

typedef RicevutaOcrRecognize = Future<String?> Function(
  Uint8List bytes, {
  RicevutaOcrPass? pass,
});

/// Punteggio massimo: data(3)+carta(3)+litri(2)+euro(2)+km(1)+tipo(1)=12.
const int kRicevutaOcrGoodScore = 10;

/// Data + litri + importo: basta, poi al massimo un passaggio carta.
const int kRicevutaOcrUsableScore = 7;

int scoreRicevutaParse(RccRicevutaParsed parsed) {
  var score = 0;
  if ((parsed.dataGgMmAaaa ?? '').isNotEmpty) score += 3;
  if ((parsed.numeroCarta ?? '').isNotEmpty) score += 3;
  if ((parsed.litri ?? '').isNotEmpty) score += 2;
  if ((parsed.euro ?? '').isNotEmpty) score += 2;
  if ((parsed.km ?? '').isNotEmpty) score += 1;
  if ((parsed.tipoCarburante ?? '').isNotEmpty) score += 1;
  return score;
}

RccRicevutaParsed mergeRicevutaParsed(
  RccRicevutaParsed? base,
  RccRicevutaParsed next,
) {
  if (base == null) return next;
  String? pick(String? a, String? b) =>
      (a ?? '').trim().isNotEmpty ? a : ((b ?? '').trim().isNotEmpty ? b : null);

  final notes = <String>{
    ...base.note,
    ...next.note,
  }.toList(growable: false);

  return RccRicevutaParsed(
    dataGgMmAaaa: pick(base.dataGgMmAaaa, next.dataGgMmAaaa),
    numeroCarta: _pickCarta(base.numeroCarta, next.numeroCarta),
    litri: pick(base.litri, next.litri),
    euro: pick(base.euro, next.euro),
    km: pick(base.km, next.km),
    tipoCarburante: pick(base.tipoCarburante, next.tipoCarburante),
    prodottoOriginale: pick(base.prodottoOriginale, next.prodottoOriginale),
    note: notes,
  );
}

String? _pickCarta(String? a, String? b) {
  final na = (a ?? '').trim();
  final nb = (b ?? '').trim();
  if (na.isEmpty) return nb.isEmpty ? null : nb;
  if (nb.isEmpty) return na;
  final maskA = RccRicevutaCarburanteParser.isCartaMascherata(na);
  final maskB = RccRicevutaCarburanteParser.isCartaMascherata(nb);
  final da = na.replaceAll(RegExp(r'\D'), '');
  final db = nb.replaceAll(RegExp(r'\D'), '');
  if (da.length >= 16 && db.length < 16) return na;
  if (db.length >= 16 && da.length < 16) return nb;
  if (maskA && !maskB) return na;
  if (maskB && !maskA) return nb;
  return na;
}

/// Un passaggio sul ritaglio scontrino; carta solo se manca.
Future<RccRicevutaParsed?> recognizeBestRicevutaParsed(
  Uint8List bytes,
  RicevutaOcrRecognize recognize,
) async {
  final tried = <String>{};
  RccRicevutaParsed? merged;

  Future<void> tryBytes(
    Uint8List candidate, {
    RicevutaOcrPass? pass,
  }) async {
    final text = await recognize(candidate, pass: pass);
    if (text == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty || tried.contains(trimmed)) return;
    tried.add(trimmed);
    merged = mergeRicevutaParsed(
      merged,
      RccRicevutaCarburanteParser.parse(trimmed),
    );
  }

  final primary = await preparePrimaryOcrJpeg(bytes);
  await tryBytes(primary);
  if (merged != null &&
      scoreRicevutaParse(merged!) >= kRicevutaOcrGoodScore) {
    return merged!.hasAnyField ? merged : null;
  }

  final missingCard = (merged?.numeroCarta ?? '').trim().isEmpty;
  if (missingCard) {
    final band = await buildCardBandJpeg(primary);
    if (band != null) {
      await tryBytes(band, pass: const RicevutaOcrPass(cardFocus: true));
    }
  }

  final stillMissingCard = (merged?.numeroCarta ?? '').trim().isEmpty;
  final stillMissingTipo = (merged?.tipoCarburante ?? '').trim().isEmpty;
  if (merged != null &&
      scoreRicevutaParse(merged!) >= kRicevutaOcrUsableScore &&
      !stillMissingCard &&
      !stillMissingTipo) {
    return merged!.hasAnyField ? merged : null;
  }

  if (stillMissingCard || stillMissingTipo) {
    for (final variant in await buildRicevutaOcrVariants(primary)) {
      await tryBytes(variant);
      if (merged != null &&
          (merged!.numeroCarta ?? '').trim().isNotEmpty &&
          (merged!.tipoCarburante ?? '').trim().isNotEmpty) {
        break;
      }
    }
  }

  if (merged == null || !merged!.hasAnyField) return null;
  return merged;
}

/// Testo OCR migliore (per incolla / debug).
Future<String?> recognizeBestRicevutaText(
  Uint8List bytes,
  RicevutaOcrRecognize recognize,
) async {
  final parsed = await recognizeBestRicevutaParsed(bytes, recognize);
  if (parsed == null) return null;
  final parts = <String>[
    if ((parsed.dataGgMmAaaa ?? '').isNotEmpty) 'Data\n${parsed.dataGgMmAaaa}',
    if ((parsed.numeroCarta ?? '').isNotEmpty) 'Carta\n${parsed.numeroCarta}',
    if ((parsed.litri ?? '').isNotEmpty) 'Quantità\n${parsed.litri} L',
    if ((parsed.euro ?? '').isNotEmpty) 'Importo\n${parsed.euro} Euro',
    if ((parsed.km ?? '').isNotEmpty) 'KM percorsi\n${parsed.km}',
    if ((parsed.tipoCarburante ?? '').isNotEmpty)
      'Prodotto\n${parsed.tipoCarburante}',
  ];
  return parts.isEmpty ? null : parts.join('\n');
}
