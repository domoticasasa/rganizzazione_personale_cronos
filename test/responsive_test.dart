import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/responsive.dart';

Widget _wrap(double width, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: child,
  );
}

void main() {
  testWidgets('useMobileUi solo telefono nativo', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(500, 900)),
        child: Builder(
          builder: (context) {
            expect(useMobileUi(context), isTrue);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(900, 1200)),
        child: Builder(
          builder: (context) {
            // Viewport tablet: non mobile UI (su desktop/web).
            expect(useMobileUi(context), isFalse);
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('cronosFormFactor breakpoint', (tester) async {
    Future<CronosFormFactor> factor(double w) async {
      late CronosFormFactor f;
      await tester.pumpWidget(
        _wrap(
          w,
          Builder(
            builder: (context) {
              f = cronosFormFactor(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return f;
    }

    expect(await factor(400), CronosFormFactor.phone);
    expect(await factor(700), CronosFormFactor.tablet);
    expect(await factor(1100), CronosFormFactor.desktop);
    expect(await factor(1700), CronosFormFactor.wide);
  });

  testWidgets('useCompactPageLayout sotto desktop', (tester) async {
    await tester.pumpWidget(
      _wrap(
        850,
        Builder(
          builder: (context) {
            expect(useCompactPageLayout(context), isTrue);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        1000,
        Builder(
          builder: (context) {
            expect(useCompactPageLayout(context), isFalse);
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('cronosHubCrossAxisCount scala con larghezza', (tester) async {
    Future<int> cols(double w) async {
      late int c;
      await tester.pumpWidget(
        _wrap(
          w,
          Builder(
            builder: (context) {
              c = cronosHubCrossAxisCount(context: context, itemCount: 12);
              return const SizedBox();
            },
          ),
        ),
      );
      return c;
    }

    expect(await cols(320), 1);
    expect(await cols(1280) >= 4, isTrue);
  });
}
