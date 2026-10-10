import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/qt_multicard_storico_assignee.dart';

void main() {
  QtMulticardAssigneeProfile profile({
    String attuale = 'Mario Rossi',
    List<QtMulticardAssigneePeriod> periods = const [],
  }) {
    return QtMulticardAssigneeProfile(
      cartaNorm: '1234567890',
      cartaRaw: '1234567890',
      assegnatarioAttuale: attuale,
      periods: periods,
    );
  }

  test('resolveAt usa passaggio storico se la data cade nel periodo', () {
    final p = profile(
      attuale: 'Luigi Verdi',
      periods: [
        const QtMulticardAssigneePeriod(
          nome: 'Pinco Palino',
          dal: '2025-10-10',
          al: '2025-12-12',
          isHistorical: true,
        ),
        const QtMulticardAssigneePeriod(
          nome: 'Luigi Verdi',
          dal: '2025-12-13',
          al: null,
          isHistorical: false,
        ),
      ],
    );

    final nov = p.resolveAt(DateTime(2025, 11, 1));
    expect(nov.responsabile, 'Pinco Palino');
    expect(nov.assegnatarioAttuale, 'Luigi Verdi');
    expect(nov.daStorico, isTrue);

    final dopo = p.resolveAt(DateTime(2026, 1, 5));
    expect(dopo.responsabile, 'Luigi Verdi');
    expect(dopo.daStorico, isFalse);
  });

  test('resolveAt prima dello storico usa assegnatario attuale', () {
    final p = profile(
      attuale: 'Luigi Verdi',
      periods: [
        const QtMulticardAssigneePeriod(
          nome: 'Pinco Palino',
          dal: '2025-10-10',
          al: '2025-12-12',
          isHistorical: true,
        ),
      ],
    );

    final prima = p.resolveAt(DateTime(2025, 9, 1));
    expect(prima.responsabile, 'Luigi Verdi');
    expect(prima.daStorico, isFalse);
  });

  test('containsIsoDate rispetta estremi inclusivi', () {
    const period = QtMulticardAssigneePeriod(
      nome: 'A',
      dal: '2025-10-10',
      al: '2025-12-12',
      isHistorical: true,
    );
    expect(period.containsIsoDate('2025-10-10'), isTrue);
    expect(period.containsIsoDate('2025-12-12'), isTrue);
    expect(period.containsIsoDate('2025-12-13'), isFalse);
    expect(period.containsIsoDate('2025-10-09'), isFalse);
  });
}
