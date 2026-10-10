import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/hub/admin_hub_nav_item.dart';
import 'package:organizzazione_personale_cronos/hub/impostazioni_hub_nav_items.dart';
import 'package:organizzazione_personale_cronos/utils/pulizia_dati_dialog.dart';

void main() {
  group('showPuliziaDatiDialog', () {
    testWidgets('opens dialog with four cleanup actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => showPuliziaDatiDialog(context),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Pulizia Dati'), findsOneWidget);
      expect(find.text('Pernottamenti'), findsOneWidget);
      expect(find.text('Aereo'), findsOneWidget);
      expect(find.text('Treni'), findsOneWidget);
      expect(find.text('Notifiche'), findsOneWidget);
    });
  });

  group('buildImpostazioniHubNavItems pulizia_dati', () {
    testWidgets('uses default dialog when callback is null', (tester) async {
      final items = buildImpostazioniHubNavItems(adminId: 1);
      final pulizia = items.firstWhere((i) => i.layoutKey == 'pulizia_dati');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    final dest = pulizia.onTap(context);
                    expect(dest, isA<AdminHubActionOnly>());
                  },
                  child: const Text('pulizia'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('pulizia'));
      await tester.pumpAndSettle();

      expect(find.text('Pulizia Dati'), findsOneWidget);
    });

    testWidgets('uses custom callback when provided', (tester) async {
      var customCalled = false;
      final items = buildImpostazioniHubNavItems(
        adminId: 1,
        onPuliziaDati: (_) => customCalled = true,
      );
      final pulizia = items.firstWhere((i) => i.layoutKey == 'pulizia_dati');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => pulizia.onTap(context),
                  child: const Text('pulizia'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('pulizia'));
      await tester.pump();

      expect(customCalled, isTrue);
      expect(find.text('Pulizia Dati'), findsNothing);
    });
  });
}
