import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/logistica_assignee_at_date.dart';
import 'package:organizzazione_personale_cronos/services/mezzi_km_service.dart';
import 'package:organizzazione_personale_cronos/services/qt_multicard_storico_assignee.dart';

void main() {
  QtMulticardAssigneeProfile mezzoProfile({
    String targa = 'AB123CD',
    String attuale = 'Luigi Verdi',
    List<QtMulticardAssigneePeriod> periods = const [],
  }) {
    return QtMulticardAssigneeProfile(
      cartaNorm: targa.toLowerCase(),
      cartaRaw: targa,
      assegnatarioAttuale: attuale,
      targa: targa,
      periods: periods,
    );
  }

  test('wasMezzoAssigneeAtDate consente ex assegnatario per data storica', () {
    final profile = mezzoProfile(
      attuale: 'Luigi Verdi',
      periods: [
        const QtMulticardAssigneePeriod(
          nome: 'Mario Rossi',
          dal: '2026-05-01',
          al: '2026-05-31',
          isHistorical: true,
        ),
        const QtMulticardAssigneePeriod(
          nome: 'Luigi Verdi',
          dal: '2026-06-01',
          al: null,
          isHistorical: false,
        ),
      ],
    );
    final marioNorm = MezziKmService.normalizePersonName('Mario Rossi');

    expect(
      LogisticaAssigneeAtDate.wasMezzoAssigneeAtDate(
        profile: profile,
        date: DateTime(2026, 5, 15),
        nameNorm: marioNorm,
        userUuid: '',
        mezzoRow: const {'assegnatario_attuale': 'Luigi Verdi'},
      ),
      isTrue,
    );
    expect(
      LogisticaAssigneeAtDate.wasMezzoAssigneeAtDate(
        profile: profile,
        date: DateTime(2026, 5, 15),
        nameNorm: marioNorm,
        userUuid: '',
        mezzoRow: const {'assegnatario_attuale': 'Luigi Verdi'},
      ),
      isTrue,
    );
    expect(
      LogisticaAssigneeAtDate.wasMezzoAssigneeAtDate(
        profile: profile,
        date: DateTime(2026, 6, 10),
        nameNorm: marioNorm,
        userUuid: '',
        mezzoRow: const {'assegnatario_attuale': 'Luigi Verdi'},
      ),
      isFalse,
    );
  });
}
