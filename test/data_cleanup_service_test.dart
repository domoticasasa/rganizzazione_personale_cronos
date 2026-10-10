import 'package:flutter_test/flutter_test.dart';
import 'package:organizzazione_personale_cronos/services/data_cleanup_service.dart';

void main() {
  group('DataCleanupService notification retention', () {
    test('notificationRetentionDays is 10 (aligned with cleanup_notifications RPC)', () {
      expect(DataCleanupService.notificationRetentionDays, 10);
    });

    test('notificationRetentionCutoffIso is roughly 10 days in the past', () {
      final cutoff = DateTime.parse(
        DataCleanupService.notificationRetentionCutoffIso(),
      );
      final now = DateTime.now().toUtc();
      final diff = now.difference(cutoff);
      expect(diff.inHours, greaterThanOrEqualTo(9 * 24));
      expect(diff.inHours, lessThanOrEqualTo(11 * 24));
    });
  });
}
