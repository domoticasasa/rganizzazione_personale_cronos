import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/formazione_programmazione_config_service.dart';
import 'package:organizzazione_personale_cronos/services/formazione_programmazione_service.dart';

void main() {
  test('shouldHideRfiRowAfterCourseEnd rispetta flag disattivato', () {
    final end = DateTime(2026, 6, 20);
    final after = DateTime(2026, 6, 22);
    final row = <String, dynamic>{
      'prima_data': '2026-06-18',
      'seconda_data': '2026-06-20',
    };

    expect(
      FormazioneProgrammazioneService.shouldClearAfterCourseEnd(end, after),
      isTrue,
    );
    expect(
      FormazioneProgrammazioneConfigService.shouldHideRfiRowAfterCourseEnd(
        row,
        after,
      ),
      isTrue,
    );

    FormazioneProgrammazioneConfigService.setRfiAutoPurgeForTests(false);
    expect(
      FormazioneProgrammazioneConfigService.shouldHideRfiRowAfterCourseEnd(
        row,
        after,
      ),
      isFalse,
    );
    FormazioneProgrammazioneConfigService.setRfiAutoPurgeForTests(true);
  });
}
