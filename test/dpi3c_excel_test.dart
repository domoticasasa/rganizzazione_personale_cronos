import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/dpi3c_excel.dart';
import 'package:organizzazione_personale_cronos/utils/excel_template_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  test('Dpi3cExcel.fill produces valid xlsx with payload cells', () async {
    final out = await Dpi3cExcel.fill({
      'I12': 'Mario Rossi',
      'S12': '12345',
      'E56': '12/06/2024',
      'P16': '1',
      'S16': 'X',
      'G17': '3M',
      'G18': '03/2024',
      'G19': 'SN-001',
    });

    expect(out.length, greaterThan(1000));
    expect(out[0], 0x50); // PK zip
    expect(out[1], 0x4B);

    final archive = ZipDecoder().decodeBytes(out);
    final sheetFile = archive.files.firstWhere(
      (f) => f.name.startsWith('xl/worksheets/sheet') && f.isFile,
    );
    final xml = utf8.decode(sheetFile.content as List<int>);
    expect(xml, contains('Mario Rossi'));
    expect(xml, contains('03/2024'));
    expect(xml, contains('3M'));
  });

  test('Mod.DPI3C template asset is bundled', () async {
    final bd = await rootBundle.load(ExcelTemplateAssets.modDpi3c);
    expect(bd.lengthInBytes, greaterThan(1000));
  });
}
