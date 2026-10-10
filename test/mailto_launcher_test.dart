import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/utils/mailto_launcher.dart';

void main() {
  test('buildMailtoUri codifica spazi con %20 non con +', () {
    final uri = buildMailtoUri(
      to: 'hotel@example.com',
      subject: 'Richiesta disponibilità camere',
      body: 'Buongiorno,\n\nLa presente per chiedere',
    );
    final s = uri.toString();
    expect(s, contains('%20'));
    expect(s, isNot(contains('Richiesta+disponibilit')));
    expect(s, isNot(contains('Buongiorno,+')));
  });
}
