import 'package:flutter/services.dart';

import '../utils/excel_template_assets.dart';
import 'template_xlsx_zip_fill.dart';

/// Riga DPI per una sezione del modulo III categoria.
class Dpi3cModuloRiga {
  final int quantita;
  final String marca;
  final String produzione;
  final String matricola;
  final String modello;
  final String fornitore;

  const Dpi3cModuloRiga({
    this.quantita = 0,
    this.marca = '',
    this.produzione = '',
    this.matricola = '',
    this.modello = '',
    this.fornitore = '',
  });
}

/// Compila [Mod.DPI3C_00.xlsx] preservando layout, immagini e XML del template (web-safe).
class Dpi3cExcel {
  Dpi3cExcel._();

  static const _sheetName = 'CONS DPI3';

  static Future<Uint8List> fill(Map<String, String> payload) async {
    final bd = await rootBundle.load(ExcelTemplateAssets.modDpi3c);
    final templateBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    if (templateBytes.isEmpty) {
      throw StateError('Template Mod.DPI3C_00.xlsx non disponibile negli asset.');
    }

    return TemplateXlsxZipFill.fill(
      templateBytes: templateBytes,
      sheetName: _sheetName,
      payload: payload,
    );
  }

  /// Payload celle foglio CONS DPI3 (Mod.DPI3C_00.xlsx).
  static Map<String, String> buildPayload({
    required String dipendente,
    required String matricolaDipendente,
    required String dataConsegna,
    Dpi3cModuloRiga elmetto = const Dpi3cModuloRiga(),
    Dpi3cModuloRiga imbracatura = const Dpi3cModuloRiga(),
    Dpi3cModuloRiga cordinoSingolo = const Dpi3cModuloRiga(),
    Dpi3cModuloRiga cordinoPosizionamento = const Dpi3cModuloRiga(),
    Dpi3cModuloRiga cordinoY = const Dpi3cModuloRiga(),
  }) {
    final payload = <String, String>{
      'I12': dipendente.trim(),
      'S12': matricolaDipendente.trim(),
      'E56': dataConsegna.trim(),
    };
    _writeSection(payload, 'P16', 'S16', 'U16', const ['G17', 'G18', 'G19', 'G20', 'G21'], elmetto);
    _writeSection(payload, 'P23', 'S23', 'U23', const ['G24', 'G25', 'G26', 'G27', 'G28'], imbracatura);
    _writeSection(payload, 'P30', 'S30', 'U30', const ['G31', 'G32', 'G33', 'G34', 'G35'], cordinoSingolo);
    _writeSection(payload, 'P37', 'S37', 'U37', const ['G38', 'G39', 'G40', 'G41', 'G42'], cordinoPosizionamento);
    _writeSection(payload, 'P44', 'S44', 'U44', const ['G45', 'G46', 'G47', 'G48', 'G49'], cordinoY);
    return payload;
  }

  /// Costruisce il payload da dotazioni con categoria testuale (DB / report).
  static Map<String, String> buildPayloadFromDpi({
    required String dipendente,
    required String matricolaDipendente,
    required String dataConsegna,
    required Iterable<({String categoria, Dpi3cModuloRiga riga})> dotazioni,
  }) {
    var elmetto = const Dpi3cModuloRiga();
    var imbracatura = const Dpi3cModuloRiga();
    var cordinoSingolo = const Dpi3cModuloRiga();
    var cordinoPosizionamento = const Dpi3cModuloRiga();
    var cordinoY = const Dpi3cModuloRiga();

    for (final d in dotazioni) {
      switch (_canonicalDpi3cCategory(d.categoria)) {
        case 'elmetto':
          elmetto = d.riga;
        case 'imbracatura':
          imbracatura = d.riga;
        case 'cordino_singolo':
          cordinoSingolo = d.riga;
        case 'cordino_pos':
          cordinoPosizionamento = d.riga;
        case 'cordino_y':
          cordinoY = d.riga;
        case null:
          break;
      }
    }

    return buildPayload(
      dipendente: dipendente,
      matricolaDipendente: matricolaDipendente,
      dataConsegna: dataConsegna,
      elmetto: elmetto,
      imbracatura: imbracatura,
      cordinoSingolo: cordinoSingolo,
      cordinoPosizionamento: cordinoPosizionamento,
      cordinoY: cordinoY,
    );
  }

  static String? _canonicalDpi3cCategory(String categoria) {
    final t = categoria.trim().toLowerCase();
    if (t == 'elmetto') return 'elmetto';
    if (t == 'imbracatura') return 'imbracatura';
    if (t == 'cordino singolo con dissipatore' || t == 'cordino') {
      return 'cordino_singolo';
    }
    if (t == 'cordino di posizionamento') return 'cordino_pos';
    if (t == 'cordino shock absorber doppio' ||
        t.contains('connessione a y')) {
      return 'cordino_y';
    }
    return null;
  }

  static void _writeSection(
    Map<String, String> payload,
    String qtyCell,
    String checkCell,
    String unusedCell,
    List<String> detailCells,
    Dpi3cModuloRiga riga,
  ) {
    final qty = riga.quantita;
    payload[qtyCell] = qty > 0 ? qty.toString() : '';
    payload[checkCell] = qty > 0 ? 'X' : '';
    payload[unusedCell] = '';
    payload[detailCells[0]] = riga.marca.trim();
    payload[detailCells[1]] = riga.produzione.trim();
    payload[detailCells[2]] = riga.matricola.trim();
    payload[detailCells[3]] = riga.modello.trim();
    payload[detailCells[4]] = riga.fornitore.trim();
  }
}