import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Pure result of resolving a human timezone/location token.
class KristinTimeZoneResolution {
  const KristinTimeZoneResolution({
    required this.query,
    required this.candidates,
  });

  final String query;
  final List<String> candidates;

  bool get resolved => candidates.length == 1;
  bool get ambiguous => candidates.length > 1;
  String? get locationName => resolved ? candidates.single : null;
}

class KristinTimeResult {
  const KristinTimeResult({
    required this.locationName,
    required this.localTime,
  });

  final String locationName;
  final tz.TZDateTime localTime;

  String get zoneName => localTime.timeZoneName;
  Duration get offset => localTime.timeZoneOffset;

  String get offsetText {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes < 0 ? '-' : '+';
    final absolute = totalMinutes.abs();
    final hours = (absolute ~/ 60).toString().padLeft(2, '0');
    final minutes = (absolute % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  String get clockText {
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    final second = localTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String get dateText {
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    return '${localTime.year}-$month-$day';
  }
}

/// Deterministic current-time utility with an injectable UTC clock.
///
/// Resolution is intentionally conservative. Exact IANA ids win; otherwise a
/// human city token must identify exactly one IANA location tail. Ambiguous
/// names are surfaced to the caller instead of selecting the first database
/// entry.
class KristinTimeUtility {
  KristinTimeUtility({DateTime Function()? nowUtc})
      : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()) {
    _ensureInitialized();
  }

  final DateTime Function() _nowUtc;
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  KristinTimeZoneResolution resolve(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const KristinTimeZoneResolution(query: '', candidates: <String>[]);
    }
    final normalized = _normalize(query);
    if (const <String>{'utc', 'gmt', 'etc-utc', 'etc-gmt'}
        .contains(normalized)) {
      return KristinTimeZoneResolution(
        query: query,
        candidates: const <String>['Etc/UTC'],
      );
    }

    final names = tz.timeZoneDatabase.locations.keys.toList(growable: false);
    final exact =
        names.where((name) => _normalize(name) == normalized).toList();
    if (exact.length == 1) {
      return KristinTimeZoneResolution(query: query, candidates: exact);
    }

    final tail = names.where((name) {
      final segment = name.split('/').last;
      return _normalize(segment) == normalized;
    }).toList()
      ..sort();
    return KristinTimeZoneResolution(
      query: query,
      candidates: List<String>.unmodifiable(tail),
    );
  }

  KristinTimeResult? currentTime(String locationQuery) {
    final resolution = resolve(locationQuery);
    final name = resolution.locationName;
    if (name == null) return null;
    final utc = _nowUtc().toUtc();
    return KristinTimeResult(
      locationName: name,
      localTime: tz.TZDateTime.from(utc, tz.getLocation(name)),
    );
  }

  /// Extracts the location from ordinary time questions. Returns an empty
  /// string for a local-device question and null when the message is not a
  /// time question at all.
  static String? locationQueryFromMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^/time\s*[?.!]*$', caseSensitive: false).hasMatch(text)) {
      return '';
    }
    final explicit = RegExp(
      r'^(?:/time)\s+(.+?)\s*[?.!]*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (explicit != null) return explicit.group(1)?.trim() ?? '';

    final located = RegExp(
      r"^(?:what(?:'s| is)?\s+)?(?:the\s+)?(?:current\s+)?time(?:\s+is\s+it)?\s+(?:in|at)\s+(.+?)\s*[?.!]*$",
      caseSensitive: false,
    ).firstMatch(text);
    if (located != null) return located.group(1)?.trim() ?? '';

    if (RegExp(
      r"^(?:what(?:'s| is)?\s+)?(?:the\s+)?(?:current\s+)?time(?:\s+is\s+it)?\s*[?.!]*$",
      caseSensitive: false,
    ).hasMatch(text)) {
      return '';
    }
    return null;
  }

  String answerFor(String rawMessage) {
    final locationQuery = locationQueryFromMessage(rawMessage);
    if (locationQuery == null) return '';
    if (locationQuery.isEmpty) {
      final now = _nowUtc().toLocal();
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      final second = now.second.toString().padLeft(2, '0');
      return 'The current device-local time is $hour:$minute:$second '
          '(${now.timeZoneName}, UTC${_offsetText(now.timeZoneOffset)}).';
    }

    final resolution = resolve(locationQuery);
    if (!resolution.resolved) {
      if (resolution.ambiguous) {
        return 'That location name is ambiguous. Please use an IANA timezone: '
            '${resolution.candidates.take(6).join(', ')}.';
      }
      return 'I could not map "$locationQuery" to an IANA timezone. '
          'Please use a timezone such as America/New_York or Europe/London.';
    }
    final result = currentTime(locationQuery)!;
    return 'The current time in ${result.locationName} is '
        '${result.dateText} ${result.clockText} '
        '(${result.zoneName}, ${result.offsetText}).';
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\\/_\s]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static String _offsetText(Duration offset) {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes < 0 ? '-' : '+';
    final absolute = totalMinutes.abs();
    final hours = (absolute ~/ 60).toString().padLeft(2, '0');
    final minutes = (absolute % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }
}
