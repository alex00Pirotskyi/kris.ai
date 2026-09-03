import 'dart:convert';

import '../crypto_utils.dart';
import 'browser_runtime.dart';

final class P3BrowserReplayLimits {
  const P3BrowserReplayLimits({
    this.maxTraceEntries = 128,
    this.maxConsoleEntries = 100,
    this.maxNetworkEntries = 200,
    this.maxStringBytes = 2048,
    this.maxBundleBytes = 1024 * 1024,
  });

  final int maxTraceEntries;
  final int maxConsoleEntries;
  final int maxNetworkEntries;
  final int maxStringBytes;
  final int maxBundleBytes;

  void validate() {
    if (maxTraceEntries < 1 ||
        maxTraceEntries > 1024 ||
        maxConsoleEntries < 1 ||
        maxConsoleEntries > 1024 ||
        maxNetworkEntries < 1 ||
        maxNetworkEntries > 4096 ||
        maxStringBytes < 128 ||
        maxStringBytes > 16 * 1024 ||
        maxBundleBytes < 16 * 1024 ||
        maxBundleBytes > 8 * 1024 * 1024) {
      throw StateError('browser_replay_limits_invalid');
    }
  }
}

final class P3BrowserReplayBundle {
  const P3BrowserReplayBundle._(this.json, this.canonicalJson);

  final Map<String, Object?> json;
  final String canonicalJson;

  String get bundleHash => json['bundleHash']! as String;
  int get bytes => utf8.encode(canonicalJson).length;
}

final class P3BrowserReplayRecorder {
  P3BrowserReplayRecorder({
    required this.runId,
    required this.sessionId,
    this.limits = const P3BrowserReplayLimits(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (runId.trim().isEmpty || sessionId.trim().isEmpty) {
      throw StateError('browser_replay_identity_invalid');
    }
    limits.validate();
  }

  final String runId;
  final String sessionId;
  final P3BrowserReplayLimits limits;
  final DateTime Function() _clock;

  final List<Map<String, Object?>> _trace = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _console = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _network = <Map<String, Object?>>[];
  int _traceDropped = 0;
  int _consoleDropped = 0;
  int _networkDropped = 0;
  Map<String, Object?>? _failure;

  String _timestamp() => _clock().toUtc().toIso8601String();

  String _boundedString(Object? value) {
    final raw = value?.toString() ?? '';
    final result = StringBuffer();
    var bytes = 0;
    for (final rune in raw.runes) {
      final character = String.fromCharCode(rune);
      final encodedBytes = utf8.encode(character).length;
      if (bytes + encodedBytes > limits.maxStringBytes) break;
      result.write(character);
      bytes += encodedBytes;
    }
    return result.toString();
  }

  void _push(
    List<Map<String, Object?>> target,
    Map<String, Object?> value,
    int maximum,
    void Function() dropped,
  ) {
    if (target.length >= maximum) {
      dropped();
      return;
    }
    target.add(Map<String, Object?>.unmodifiable(value));
  }

  void _requireSession(String value) {
    if (value != sessionId) throw StateError('browser_replay_session_mismatch');
  }

  void recordObservation(P3BrowserPageObservation observation) {
    recordObservationSnapshot(
      sessionId: observation.sessionId,
      pageId: observation.pageId,
      observationHash: observation.observationHash,
      observation: observation.observation,
    );
  }

  void recordObservationSnapshot({
    required String sessionId,
    required String pageId,
    required String observationHash,
    required Map<String, Object?> observation,
  }) {
    _requireSession(sessionId);
    if (pageId.trim().isEmpty || observationHash.trim().isEmpty) {
      throw StateError('browser_replay_observation_identity_invalid');
    }
    final rawScreenshot = observation['screenshot'];
    final screenshot = rawScreenshot is Map
        ? Map<String, Object?>.from(rawScreenshot)
        : const <String, Object?>{};
    _push(
      _trace,
      <String, Object?>{
        'kind': 'observation',
        'at': _timestamp(),
        'pageId': pageId,
        'observationHash': observationHash,
        'url': _boundedString(observation['url']),
        'title': _boundedString(observation['title']),
        'screenshotSha256': _boundedString(screenshot['sha256']),
        'screenshotBytes': screenshot['bytes'] is int ? screenshot['bytes'] : 0,
      },
      limits.maxTraceEntries,
      () => _traceDropped += 1,
    );

    final rawConsole = observation['console'];
    if (rawConsole is Map) {
      final console = Map<String, Object?>.from(rawConsole);
      final entries = console['entries'];
      if (entries is List) {
        for (final rawEntry in entries) {
          if (rawEntry is! Map) {
            _consoleDropped += 1;
            continue;
          }
          final entry = Map<String, Object?>.from(rawEntry);
          _push(
            _console,
            <String, Object?>{
              'at': _timestamp(),
              'pageId': pageId,
              'type': _boundedString(entry['type']),
              'text': _boundedString(entry['text']),
            },
            limits.maxConsoleEntries,
            () => _consoleDropped += 1,
          );
        }
      }
      final dropped = console['dropped'];
      if (dropped is int && dropped > 0) _consoleDropped += dropped;
    }

    final rawNetwork = observation['network'];
    if (rawNetwork is Map) {
      final network = Map<String, Object?>.from(rawNetwork);
      _recordNetworkEntries(pageId, network['requests'], 'request');
      _recordNetworkEntries(pageId, network['responses'], 'response');
      for (final key in const <String>['requestsDropped', 'responsesDropped']) {
        final dropped = network[key];
        if (dropped is int && dropped > 0) _networkDropped += dropped;
      }
    }
  }

  void _recordNetworkEntries(String pageId, Object? rawEntries, String phase) {
    if (rawEntries is! List) return;
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map) {
        _networkDropped += 1;
        continue;
      }
      final entry = Map<String, Object?>.from(rawEntry);
      _push(
        _network,
        <String, Object?>{
          'at': _timestamp(),
          'pageId': pageId,
          'phase': phase,
          'url': _boundedString(entry['url']),
          'method': _boundedString(entry['method']),
          'resourceType': _boundedString(entry['resourceType']),
          if (phase == 'response')
            'status': entry['status'] is int ? entry['status'] : 0,
        },
        limits.maxNetworkEntries,
        () => _networkDropped += 1,
      );
    }
  }

  void recordAction(P3BrowserActionResult result) {
    recordActionSnapshot(
      sessionId: result.sessionId,
      pageId: result.pageId,
      action: result.action.name,
      locatorStrategy: result.locatorStrategy,
      locatorIndex: result.locatorIndex,
      targetLocatorStrategy: result.targetLocatorStrategy,
      targetLocatorIndex: result.targetLocatorIndex,
      sensitiveInputProvided: result.sensitiveInputProvided,
      beforeObservationHash: result.beforeObservationHash,
      afterObservationHash: result.afterObservationHash,
      observationChanged: result.observationChanged,
    );
  }

  void recordActionSnapshot({
    required String sessionId,
    required String pageId,
    required String action,
    required String locatorStrategy,
    required int locatorIndex,
    String? targetLocatorStrategy,
    int? targetLocatorIndex,
    required bool sensitiveInputProvided,
    required String beforeObservationHash,
    required String afterObservationHash,
    required bool observationChanged,
  }) {
    _requireSession(sessionId);
    _push(
      _trace,
      <String, Object?>{
        'kind': 'action',
        'at': _timestamp(),
        'pageId': pageId,
        'action': _boundedString(action),
        'locatorStrategy': _boundedString(locatorStrategy),
        'locatorIndex': locatorIndex,
        'targetLocatorStrategy': targetLocatorStrategy == null
            ? null
            : _boundedString(targetLocatorStrategy),
        'targetLocatorIndex': targetLocatorIndex,
        'sensitiveInputProvided': sensitiveInputProvided,
        'beforeObservationHash': _boundedString(beforeObservationHash),
        'afterObservationHash': _boundedString(afterObservationHash),
        'observationChanged': observationChanged,
      },
      limits.maxTraceEntries,
      () => _traceDropped += 1,
    );
  }

  void recordFailure({required String code, String? detail, String? pageId}) {
    if (code.trim().isEmpty) {
      throw StateError('browser_replay_failure_code_invalid');
    }
    final failure = <String, Object?>{
      'at': _timestamp(),
      'code': _boundedString(code),
      'detail': detail == null ? null : _boundedString(detail),
      'pageId': pageId == null ? null : _boundedString(pageId),
    };
    _failure = Map<String, Object?>.unmodifiable(failure);
    _push(
      _trace,
      <String, Object?>{'kind': 'failure', ...failure},
      limits.maxTraceEntries,
      () => _traceDropped += 1,
    );
  }

  P3BrowserReplayBundle exportFailedRun() {
    final failure = _failure;
    if (failure == null) throw StateError('browser_replay_failure_required');

    final trace = _trace.map(Map<String, Object?>.from).toList();
    final console = _console.map(Map<String, Object?>.from).toList();
    final network = _network.map(Map<String, Object?>.from).toList();
    var exportDropped = 0;

    Map<String, Object?> base() => <String, Object?>{
      'schemaVersion': '1.0.0',
      'bundleType': 'kristin-p3-browser-failure-replay-v1',
      'runId': runId,
      'sessionId': sessionId,
      'failed': true,
      'failure': Map<String, Object?>.from(failure),
      'trace': trace,
      'console': console,
      'network': network,
      'dropped': <String, Object?>{
        'trace': _traceDropped,
        'console': _consoleDropped,
        'network': _networkDropped,
        'export': exportDropped,
      },
    };

    Map<String, Object?> finalize() {
      final withoutHash = base();
      final canonicalWithoutHash = _canonicalJson(withoutHash);
      return <String, Object?>{
        ...withoutHash,
        'bundleHash': Sha256.text(canonicalWithoutHash),
      };
    }

    var finalJson = finalize();
    var canonical = _canonicalJson(finalJson);
    while (utf8.encode(canonical).length > limits.maxBundleBytes) {
      if (network.isNotEmpty) {
        network.removeLast();
      } else if (console.isNotEmpty) {
        console.removeLast();
      } else if (trace.length > 1) {
        trace.removeAt(trace.length - 2);
      } else {
        throw StateError('browser_replay_bundle_cannot_fit');
      }
      exportDropped += 1;
      finalJson = finalize();
      canonical = _canonicalJson(finalJson);
    }
    return P3BrowserReplayBundle._(
      Map<String, Object?>.unmodifiable(finalJson),
      canonical,
    );
  }
}

final class P3RecordedBrowserSession {
  P3RecordedBrowserSession({required this.process, required this.recorder});

  final P3BrowserSessionProcess process;
  final P3BrowserReplayRecorder recorder;

  Future<P3BrowserPageObservation> observePage(
    String sessionId,
    String pageId,
  ) async {
    try {
      final observation = await process.observePage(sessionId, pageId);
      recorder.recordObservation(observation);
      return observation;
    } catch (error) {
      recorder.recordFailure(
        code: error is P3BrowserRuntimeException
            ? error.code
            : 'browser_observe_failed',
        detail: error.toString(),
        pageId: pageId,
      );
      rethrow;
    }
  }

  Future<P3BrowserActionResult> performAction(
    String sessionId,
    String pageId,
    P3BrowserActionRequest action,
  ) async {
    try {
      final result = await process.performAction(sessionId, pageId, action);
      recorder.recordAction(result);
      return result;
    } catch (error) {
      recorder.recordFailure(
        code: error is P3BrowserRuntimeException
            ? error.code
            : 'browser_action_failed',
        detail: error.toString(),
        pageId: pageId,
      );
      rethrow;
    }
  }
}

Object? _canonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_canonicalValue).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  throw StateError('browser_replay_non_json_value');
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));
