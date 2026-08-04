import 'dart:convert';

import 'p2_automation_host.dart';
import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';
import 'p2_host_operations.dart';

abstract interface class P2HostBindingProvider {
  P2EffectBinding bindingFor(String operation);
}

/// Product-facing host operations routed through the authenticated supervised
/// executor. Direct shell smoke helpers are supplementary only and are never
/// accepted as product behavioral proof for this adapter.
final class P2AutomationHostOperations
    implements
        P2PackageSdkAdapter,
        P2ServiceApplicationAdapter,
        P2ClipboardScreenAdapter {
  P2AutomationHostOperations({
    required this.host,
    required this.authority,
    required this.journal,
    required this.bindingProvider,
  });

  final P2SupervisedAutomationHost host;
  final P2AutomationEnvelopeAuthority authority;
  final P2EffectJournal journal;
  final P2HostBindingProvider bindingProvider;
  final Map<String, P2EffectReceipt> _lastReceipts =
      <String, P2EffectReceipt>{};

  P2EffectReceipt? receiptFor(String operation) => _lastReceipts[operation];

  P2EffectBinding _exact(P2EffectBinding source, String operation) =>
      P2EffectBinding(
        runId: source.runId,
        taskId: source.taskId,
        actorId: source.actorId,
        toolId: source.toolId,
        accessProfileId: source.accessProfileId,
        capabilityId: source.capabilityId,
        operation: operation,
      );

  Future<Map<String, Object?>> _call(
    P2EffectBinding source,
    String operation,
    Map<String, Object?> payload, {
    Duration deadline = const Duration(seconds: 30),
  }) async {
    final binding = _exact(source, operation);
    final envelope = await authority.issue(
      binding: binding,
      operation: operation,
      payload: <String, Object?>{'operation': operation, ...payload},
      deadline: deadline,
    );
    final response = await host.execute(envelope);
    if (response['status'] == 'error') {
      throw StateError(response['code']?.toString() ?? 'host_operation_failed');
    }
    final rawReceipt = response['receipt'];
    if (rawReceipt is Map) {
      final receipt = P2EffectReceipt.fromJson(
        Map<String, Object?>.from(rawReceipt),
      );
      if (receipt.runId != binding.runId ||
          receipt.taskId != binding.taskId ||
          receipt.operation != operation) {
        throw StateError('host_effect_receipt_binding_mismatch');
      }
      _lastReceipts[operation] = receipt;
      await journal.append(receipt);
    }
    return response;
  }

  Future<Map<String, Object?>> _bound(
    String operation,
    Map<String, Object?> payload, {
    Duration deadline = const Duration(seconds: 30),
  }) =>
      _call(
        bindingProvider.bindingFor(operation),
        operation,
        payload,
        deadline: deadline,
      );

  P2OperationSupport _support(Object? raw) {
    if (raw is! Map) {
      return const P2OperationSupport(
        P2SupportStatus.unknown,
        'support_not_reported',
      );
    }
    final value = Map<String, Object?>.from(raw);
    final name = value['status']?.toString() ?? 'unknown';
    final status = P2SupportStatus.values.firstWhere(
      (candidate) => candidate.name == name,
      orElse: () => P2SupportStatus.unknown,
    );
    return P2OperationSupport(
      status,
      value['reason']?.toString() ?? 'unspecified',
      requiresElevation: value['requiresElevation'] == true,
    );
  }

  P2HostOperationResult _result(
    Map<String, Object?> response,
    String operation,
  ) {
    final raw = response['receipt'];
    if (raw is! Map) throw StateError('host_effect_receipt_missing');
    final receipt = P2EffectReceipt.fromJson(Map<String, Object?>.from(raw));
    final output = response['output'];
    return P2HostOperationResult(
      status: receipt.status,
      receipt: receipt,
      support: _support(response['support']),
      output: output is Map
          ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(output))
          : const <String, Object?>{},
    );
  }

  @override
  Future<P2OperationSupport> support(String operation) async {
    final response = await _bound('host.support', <String, Object?>{
      'queriedOperation': operation,
    });
    return _support(response['support']);
  }

  @override
  Future<Map<String, Object?>> plan(
    String manager,
    String operation,
    List<String> packages,
    P2EffectBinding binding,
  ) async {
    final response = await _call(binding, 'package.plan', <String, Object?>{
      'manager': manager,
      'packageOperation': operation,
      'packages': List<String>.unmodifiable(packages),
    });
    final output = response['output'];
    if (output is! Map) throw StateError('package_plan_missing');
    return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(output));
  }

  @override
  Future<P2HostOperationResult> apply(
    Map<String, Object?> plan,
    P2EffectBinding binding,
  ) async {
    final response = await _call(binding, 'package.apply', <String, Object?>{
      'plan': plan,
    });
    return _result(response, 'package.apply');
  }

  @override
  Future<List<Map<String, Object?>>> discoverSdks(
    P2EffectBinding binding,
  ) async {
    final response = await _call(
      binding,
      'sdk.discover',
      const <String, Object?>{},
    );
    final output = response['output'];
    final raw = output is Map ? output['sdks'] : null;
    if (raw is! List) throw StateError('sdk_discovery_result_invalid');
    return List<Map<String, Object?>>.unmodifiable(
      raw.map<Map<String, Object?>>((Object? value) {
        if (value is! Map) throw StateError('sdk_discovery_row_invalid');
        return Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(value),
        );
      }),
    );
  }

  @override
  Future<Map<String, P2OperationSupport>> supportMatrix() async {
    final response = await _bound(
      'host.supportMatrix',
      const <String, Object?>{},
    );
    final raw = response['supportMatrix'];
    if (raw is! Map) throw StateError('host_support_matrix_missing');
    return Map<String, P2OperationSupport>.unmodifiable(
      <String, P2OperationSupport>{
        for (final entry in raw.entries)
          entry.key.toString(): _support(entry.value),
      },
    );
  }

  Future<P2HostOperationResult> _effect(
    P2EffectBinding binding,
    String operation,
    Map<String, Object?> payload,
  ) async {
    final response = await _call(binding, operation, payload);
    return _result(response, operation);
  }

  @override
  Future<P2HostOperationResult> serviceStatus(
    String id,
    P2EffectBinding binding,
  ) =>
      _effect(binding, 'service.status', <String, Object?>{'serviceId': id});

  @override
  Future<P2HostOperationResult> serviceStart(
    String id,
    P2EffectBinding binding,
  ) =>
      _effect(binding, 'service.start', <String, Object?>{'serviceId': id});

  @override
  Future<P2HostOperationResult> serviceStop(
    String id,
    P2EffectBinding binding,
  ) =>
      _effect(binding, 'service.stop', <String, Object?>{'serviceId': id});

  @override
  Future<P2HostOperationResult> applicationOpen(
    String target,
    P2EffectBinding binding,
  ) =>
      _effect(binding, 'application.open', <String, Object?>{
        'target': target,
        'arguments': const <String>[],
      });

  Future<P2HostOperationResult> applicationOpenExecutable(
    String executable,
    List<String> arguments,
    P2EffectBinding binding, {
    String? cwd,
  }) =>
      _effect(binding, 'application.open', <String, Object?>{
        'target': executable,
        'arguments': arguments,
        if (cwd != null) 'cwd': cwd,
      });

  @override
  Future<P2HostOperationResult> applicationClose(
    String identity,
    P2EffectBinding binding,
  ) =>
      _effect(binding, 'application.close', <String, Object?>{
        'identity': identity,
      });

  @override
  Future<P2OperationSupport> clipboardSupport() async =>
      const P2OperationSupport(
        P2SupportStatus.approvalRequired,
        'interactive_desktop_lane_required',
      );

  @override
  Future<P2OperationSupport> screenSupport() async => const P2OperationSupport(
        P2SupportStatus.approvalRequired,
        'interactive_desktop_lane_required',
      );

  @override
  Future<String> readClipboard(P2EffectBinding binding) async {
    final response = await _call(
      binding,
      'clipboard.read',
      const <String, Object?>{'ordinaryLogContent': false},
    );
    final output = response['output'];
    if (output is! Map || output['text'] is! String) {
      throw StateError('clipboard_response_invalid');
    }
    return output['text']! as String;
  }

  @override
  Future<void> writeClipboard(String text, P2EffectBinding binding) async {
    final response = await _call(binding, 'clipboard.write', <String, Object?>{
      'text': text,
      'ordinaryLogContent': false,
    });
    if (response['status'] != 'ok') throw StateError('clipboard_write_failed');
  }

  @override
  Future<List<int>> captureScreen(
    P2EffectBinding binding, {
    List<Map<String, int>> redactionZones = const <Map<String, int>>[],
  }) async {
    final response = await _call(
        binding,
        'screen.capture',
        <String, Object?>{
          'redactionZones': redactionZones,
          'ordinaryLogContent': false,
        },
        deadline: const Duration(seconds: 45));
    final output = response['output'];
    if (output is! Map || output['bytesBase64'] is! String) {
      throw StateError('screen_response_invalid');
    }
    final bytes = base64Decode(output['bytesBase64']! as String);
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw StateError('screen_response_budget_invalid');
    }
    return bytes;
  }

  @override
  Future<Map<String, Object?>> activeWindowMetadata(
    P2EffectBinding binding,
  ) async {
    final response = await _call(
      binding,
      'screen.activeWindowMetadata',
      const <String, Object?>{'ordinaryLogContent': false},
    );
    final output = response['output'];
    if (output is! Map) throw StateError('active_window_response_invalid');
    return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(output));
  }
}
