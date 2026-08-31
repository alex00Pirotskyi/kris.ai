import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/utility_time.dart';

void main() {
  test('IANA conversion is deterministic under an injected UTC clock', () {
    final utility = KristinTimeUtility(
      nowUtc: () => DateTime.utc(2026, 1, 15, 12, 0, 0),
    );
    final newYork = utility.currentTime('America/New_York');
    expect(newYork, isNotNull);
    expect(newYork!.clockText, '07:00:00');
    expect(newYork.offsetText, 'UTC-05:00');

    final hoChiMinh = utility.currentTime('Asia/Ho_Chi_Minh');
    expect(hoChiMinh, isNotNull);
    expect(hoChiMinh!.clockText, '19:00:00');
    expect(hoChiMinh.offsetText, 'UTC+07:00');
  });

  test('device-local answer uses the injected instant too', () {
    final instant = DateTime.utc(2026, 2, 3, 4, 5, 6);
    final utility = KristinTimeUtility(nowUtc: () => instant);
    final expected = instant.toLocal();
    final clock = '${expected.hour.toString().padLeft(2, '0')}:'
        '${expected.minute.toString().padLeft(2, '0')}:'
        '${expected.second.toString().padLeft(2, '0')}';
    expect(utility.answerFor('what time is it?'), contains(clock));
  });

  test('human city tail resolves only when unique', () {
    final utility = KristinTimeUtility(
      nowUtc: () => DateTime.utc(2026, 6, 1),
    );
    final result = utility.resolve('New York');
    expect(result.resolved, isTrue);
    expect(result.locationName, 'America/New_York');
  });

  test('unknown locations fail closed instead of inventing an offset', () {
    final utility = KristinTimeUtility();
    final answer = utility.answerFor('what time is it in Atlantis?');
    expect(answer, contains('could not map'));
  });

  test('explicit /time uses the same deterministic parser', () {
    expect(KristinTimeUtility.locationQueryFromMessage('/time'), '');
    expect(
      KristinTimeUtility.locationQueryFromMessage('/time Europe/London'),
      'Europe/London',
    );
  });
}
