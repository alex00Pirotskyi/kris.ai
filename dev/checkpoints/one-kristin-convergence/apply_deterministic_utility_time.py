#!/usr/bin/env python3
"""Add deterministic utility.time using IANA timezone data and an injected clock.

Pins timezone 0.10.1 because the recovered repo supports Dart >=3.5, while newer
0.11.x releases require Dart 3.10. The service never guesses among colliding
location names.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = 'dd2f46ba6df3fb25adc2c8c927e807147b8f16f2'


def rep(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    n = text.count(old)
    if n != count:
        raise RuntimeError(f'{label}: expected {count} anchor(s), found {n}')
    return text.replace(old, new, count)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


UTILITY_SOURCE = r'''import 'package:timezone/data/latest.dart' as tzdata;
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
    if (const <String>{'utc', 'gmt', 'etc-utc', 'etc-gmt'}.contains(normalized)) {
      return KristinTimeZoneResolution(
        query: query,
        candidates: const <String>['Etc/UTC'],
      );
    }

    final names = tz.timeZoneDatabase.locations.keys.toList(growable: false);
    final exact = names.where((name) => _normalize(name) == normalized).toList();
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
'''


def pubspec(src: str) -> str:
    return rep(
        src,
        "  sqlite3_flutter_libs: 0.5.42\n",
        "  sqlite3_flutter_libs: 0.5.42\n  timezone: 0.10.1\n",
        'timezone dependency pin',
    )


def control_plane(src: str) -> str:
    src = rep(
        src,
        "  researchSearch,\n\n  projectAnalyze,\n",
        "  researchSearch,\n\n  /// Deterministic IANA timezone lookup; never delegated to a model.\n  utilityTime,\n\n  projectAnalyze,\n",
        'utility time route enum',
    )
    anchor = """  // Architectural Improvement #9: research must not require a project.\n"""
    capability = r'''  KristinCapability(
    id: 'utility.time',
    displayName: 'Time',
    description: 'Report deterministic current time from IANA timezone data.',
    category: ChatCapabilityCategory.understand,
    slashCommands: <String>['time'],
    mentionAliases: <String>['time'],
    acceptedTargetTypes: <ChatTargetType>{},
    actionClass: ChatActionClass.informational,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.utilityTime,
    preferredMode: CommandMode.ask,
  ),
'''
    src = rep(src, anchor, capability + anchor, 'utility time capability')
    src = rep(
        src,
        "      case 'research.search':\n"
        "        return argument.isEmpty\n"
        "            ? 'Search current public sources.'\n"
        "            : 'Search current public sources for \"$argument\" and summarize what is found.';\n",
        "      case 'research.search':\n"
        "        return argument.isEmpty\n"
        "            ? 'Search current public sources.'\n"
        "            : 'Search current public sources for \"$argument\" and summarize what is found.';\n"
        "      case 'utility.time':\n"
        "        return argument.isEmpty\n"
        "            ? 'Report the current device-local time.'\n"
        "            : 'Report the current time in $argument.';\n",
        'utility time interpreted goal',
    )
    return src


def studio(src: str) -> str:
    return rep(
        src,
        "import 'ui_components.dart';\n",
        "import 'ui_components.dart';\nimport 'utility_time.dart';\n",
        'utility time import',
    )


def actions(src: str) -> str:
    src = rep(
        src,
        "    if (id == 'system.help') {\n",
        "    if (id == 'utility.time') {\n"
        "      final answer = KristinTimeUtility().answerFor(\n"
        "        decision.parsed.originalText,\n"
        "      );\n"
        "      _finishDirectAction(answer.isEmpty\n"
        "          ? 'Tell me which timezone you want.'\n"
        "          : answer);\n"
        "      return;\n"
        "    }\n"
        "    if (id == 'system.help') {\n",
        'explicit utility time action',
    )
    # Natural-language time questions are deterministic local answers too.
    src = rep(
        src,
        "  Future<String?> _tryLocalAnswer(ChatInteractionDecision decision) async {\n"
        "    final text = decision.parsed.originalText.toLowerCase();\n",
        "  Future<String?> _tryLocalAnswer(ChatInteractionDecision decision) async {\n"
        "    final timeAnswer = KristinTimeUtility().answerFor(\n"
        "      decision.parsed.originalText,\n"
        "    );\n"
        "    if (timeAnswer.isNotEmpty) return timeAnswer;\n"
        "    final text = decision.parsed.originalText.toLowerCase();\n",
        'natural utility time local answer',
    )
    # Keep exhaustive route switch total even though informational time normally
    # exits through _handleImmediateCapability.
    src = rep(
        src,
        "      case ChatExecutionRoute.researchSearch:\n"
        "        await _runResearchSearch(decision, project: project);\n"
        "        return;\n",
        "      case ChatExecutionRoute.researchSearch:\n"
        "        await _runResearchSearch(decision, project: project);\n"
        "        return;\n"
        "      case ChatExecutionRoute.utilityTime:\n"
        "        final answer = KristinTimeUtility().answerFor(\n"
        "          decision.parsed.originalText,\n"
        "        );\n"
        "        _finishDirectAction(answer);\n"
        "        return;\n",
        'utility time route switch',
    )
    return src


TEST = r'''import 'package:flutter_test/flutter_test.dart';
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
    final clock =
        '${expected.hour.toString().padLeft(2, '0')}:'
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
'''



def source_contract(source: str) -> str:
    return rep(
        source,
        "        'lib/product/ui_components.dart',\n",
        "        'lib/product/ui_components.dart',\n        'lib/product/utility_time.dart',\n",
        'source contract utility time',
    )

def compute(root: Path):
    mapping = {
        root / 'pubspec.yaml': pubspec,
        root / 'lib/product/chat_control_plane.dart': control_plane,
        root / 'lib/product/chat_control_plane_studio.dart': studio,
        root / 'lib/product/chat_control_plane_studio_actions.dart': actions,
        root / 'test/product/source_contract_test.dart': source_contract,
    }
    out = {}
    for path, fn in mapping.items():
        if not path.exists():
            raise RuntimeError(f'missing {path}')
        before = path.read_text()
        out[path] = (before, fn(before))
    utility = root / 'lib/product/utility_time.dart'
    out[utility] = (utility.read_text() if utility.exists() else '', UTILITY_SOURCE)
    test = root / 'test/product/utility_time_test.dart'
    out[test] = (test.read_text() if test.exists() else '', TEST)
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('repo')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--diff', action='store_true')
    p.add_argument('--allow-head-drift', action='store_true')
    a = p.parse_args()
    root = Path(a.repo).resolve()
    current = head(root)
    if current and current != EXPECTED_HEAD and not a.allow_head_drift:
        raise SystemExit(f'refusing HEAD {current}; expected {EXPECTED_HEAD}')
    changes = compute(root)
    if a.diff or not a.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f'a/{rel}', tofile=f'b/{rel}',
            )), end='')
    if a.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
