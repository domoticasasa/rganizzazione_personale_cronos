import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/notification_service.dart';

void main() {
  test('shouldSuppressExternalNotification dedupes rapid duplicates', () {
    expect(
      NotificationService.shouldSuppressExternalNotification('A', 'body'),
      isFalse,
    );
    expect(
      NotificationService.shouldSuppressExternalNotification('A', 'body'),
      isTrue,
    );
  });
}
