import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/utility_time.dart';

void main() {
  test('New York reflects DST for an injected summer clock', () {
    final service = UtilityTimeService(
      clock: FixedKristinClock(DateTime.utc(2026, 7, 1, 16)),
    );
    final result = service.currentTime('New York');
    expect(result.timeZoneId, 'America/New_York');
    expect(result.localTime.hour, 12);
    expect(result.utcOffset.inHours, -4);
  });

  test(
    'service initializes timezone data and resolves Bangkok without search',
    () {
      final service = UtilityTimeService(
        clock: FixedKristinClock(DateTime.utc(2026, 8, 31, 12)),
      );
      final result = service.currentTime('Bangkok');
      expect(result.timeZoneId, 'Asia/Bangkok');
      expect(result.localTime.hour, 19);
      expect(result.utcOffset.inHours, 7);
    },
  );

  test('ambiguous abbreviation is not guessed', () {
    final service = UtilityTimeService(
      clock: FixedKristinClock(DateTime.utc(2026, 1, 1)),
    );
    expect(
      () => service.currentTime('CST'),
      throwsA(
        isA<UtilityTimeException>().having(
          (error) => error.code,
          'code',
          'time_location_ambiguous',
        ),
      ),
    );
  });
}
