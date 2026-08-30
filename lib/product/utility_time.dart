import 'package:timezone/timezone.dart' as tz;

abstract interface class KristinClock {
  DateTime nowUtc();
}

class SystemKristinClock implements KristinClock {
  const SystemKristinClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FixedKristinClock implements KristinClock {
  const FixedKristinClock(this.instantUtc);

  final DateTime instantUtc;

  @override
  DateTime nowUtc() => instantUtc.toUtc();
}

class UtilityTimeException implements Exception {
  const UtilityTimeException(
    this.code,
    this.message, {
    this.candidates = const <String>[],
  });

  final String code;
  final String message;
  final List<String> candidates;

  @override
  String toString() => '$code: $message';
}

class UtilityTimeResult {
  const UtilityTimeResult({
    required this.requestedLocation,
    required this.timeZoneId,
    required this.instantUtc,
    required this.localTime,
  });

  final String requestedLocation;
  final String timeZoneId;
  final DateTime instantUtc;
  final tz.TZDateTime localTime;

  Duration get utcOffset => localTime.timeZoneOffset;
  String get abbreviation => localTime.timeZoneName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'requestedLocation': requestedLocation,
        'timeZoneId': timeZoneId,
        'instantUtc': instantUtc.toUtc().toIso8601String(),
        'localTime': localTime.toIso8601String(),
        'utcOffsetMinutes': utcOffset.inMinutes,
        'abbreviation': abbreviation,
      };
}

/// Deterministic utility.time implementation.
///
/// The caller must initialize the timezone database once during application
/// bootstrap. This class never uses the host's local timezone and never
/// guesses between ambiguous place names.
class UtilityTimeService {
  UtilityTimeService({
    this.clock = const SystemKristinClock(),
    Map<String, List<String>> aliases = const <String, List<String>>{},
    tz.Location Function(String id)? locationLoader,
  })  : aliases = <String, List<String>>{
          ..._defaultAliases,
          for (final entry in aliases.entries)
            _normalize(entry.key): List<String>.unmodifiable(entry.value),
        },
        _locationLoader = locationLoader ?? tz.getLocation;

  final KristinClock clock;
  final Map<String, List<String>> aliases;
  final tz.Location Function(String id) _locationLoader;

  static const Map<String, List<String>> _defaultAliases =
      <String, List<String>>{
    'new york': <String>['America/New_York'],
    'nyc': <String>['America/New_York'],
    'los angeles': <String>['America/Los_Angeles'],
    'san francisco': <String>['America/Los_Angeles'],
    'london': <String>['Europe/London'],
    'paris': <String>['Europe/Paris'],
    'berlin': <String>['Europe/Berlin'],
    'tokyo': <String>['Asia/Tokyo'],
    'seoul': <String>['Asia/Seoul'],
    'ho chi minh city': <String>['Asia/Ho_Chi_Minh'],
    'saigon': <String>['Asia/Ho_Chi_Minh'],
    'nha trang': <String>['Asia/Ho_Chi_Minh'],
    'sydney': <String>['Australia/Sydney'],
    'cst': <String>['America/Chicago', 'Asia/Shanghai'],
  };

  UtilityTimeResult currentTime(String requestedLocation) {
    final requested = requestedLocation.trim();
    if (requested.isEmpty) {
      throw const UtilityTimeException(
        'time_location_missing',
        'A location or IANA timezone id is required.',
      );
    }
    final timeZoneId = resolveTimeZoneId(requested);
    final location = _loadLocation(timeZoneId);
    final instant = clock.nowUtc().toUtc();
    return UtilityTimeResult(
      requestedLocation: requested,
      timeZoneId: timeZoneId,
      instantUtc: instant,
      localTime: tz.TZDateTime.from(instant, location),
    );
  }

  String resolveTimeZoneId(String requestedLocation) {
    final requested = requestedLocation.trim();
    final candidates = aliases[_normalize(requested)];
    if (candidates != null) {
      final unique = candidates
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (unique.length != 1) {
        throw UtilityTimeException(
          'time_location_ambiguous',
          '"$requested" can refer to more than one timezone. Choose an IANA timezone id.',
          candidates: unique,
        );
      }
      return unique.single;
    }

    if (requested.contains('/')) {
      _loadLocation(requested);
      return requested;
    }
    throw UtilityTimeException(
      'time_location_unknown',
      'I do not have an unambiguous timezone for "$requested". Use a city I know or an IANA timezone id such as America/New_York.',
    );
  }

  tz.Location _loadLocation(String id) {
    try {
      return _locationLoader(id);
    } catch (_) {
      throw UtilityTimeException(
        'time_zone_unknown',
        'Unknown IANA timezone id: $id',
      );
    }
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
