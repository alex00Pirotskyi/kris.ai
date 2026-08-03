import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum P2EffectStatus {
  authorized,
  started,
  succeeded,
  failed,
  cancelled,
  killed,
  rolledBack,
  unknown,
  unsupported,
}

enum P2Reversibility { reversible, partiallyReversible, irreversible }

class P2EffectReceipt {
  P2EffectReceipt({
    required this.effectId,
    required this.runId,
    required this.taskId,
    required this.operation,
    required this.status,
    required this.reversibility,
    required this.startedAt,
    this.completedAt,
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(details);

  final String effectId;
  final String runId;
  final String taskId;
  final String operation;
  final P2EffectStatus status;
  final P2Reversibility reversibility;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Map<String, Object?> details;

  factory P2EffectReceipt.fromJson(Map<String, Object?> value) {
    final startedAt = DateTime.tryParse(
      value['startedAt']?.toString() ?? '',
    )?.toUtc();
    final completedAtValue = value['completedAt'];
    final completedAt = completedAtValue == null
        ? null
        : DateTime.tryParse(completedAtValue.toString())?.toUtc();
    final rawDetails = value['details'];
    if (value['schemaVersion'] != '1.0.0' ||
        startedAt == null ||
        (completedAtValue != null && completedAt == null) ||
        rawDetails is! Map) {
      throw const FormatException('p2_effect_receipt_invalid');
    }
    P2EffectStatus status;
    P2Reversibility reversibility;
    try {
      status = P2EffectStatus.values.byName(value['status']?.toString() ?? '');
      reversibility = P2Reversibility.values.byName(
        value['reversibility']?.toString() ?? '',
      );
    } on ArgumentError {
      throw const FormatException('p2_effect_receipt_enum_invalid');
    }
    return P2EffectReceipt(
      effectId: value['effectId']?.toString() ?? '',
      runId: value['runId']?.toString() ?? '',
      taskId: value['taskId']?.toString() ?? '',
      operation: value['operation']?.toString() ?? '',
      status: status,
      reversibility: reversibility,
      startedAt: startedAt,
      completedAt: completedAt,
      details: Map<String, Object?>.from(rawDetails),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1.0.0',
    'effectId': effectId,
    'runId': runId,
    'taskId': taskId,
    'operation': operation,
    'status': status.name,
    'reversibility': reversibility.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'details': P2Redactor.redact(details),
  };
}

class P2Redactor {
  static final RegExp _key = RegExp(
    r'(secret|token|password|credential|api.?key|private.?key)',
    caseSensitive: false,
  );
  static final RegExp _value = RegExp(
    r'(Bearer\s+[A-Za-z0-9._~+/=-]{8,}|sk-[A-Za-z0-9_-]{8,}|gh[opusr]_[A-Za-z0-9]{8,})',
    caseSensitive: false,
  );

  static Object? redact(Object? value) {
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(
          key,
          _key.hasMatch('$key') ? '[REDACTED]' : redact(nested),
        ),
      );
    }
    if (value is Iterable) {
      return value.map(redact).toList(growable: false);
    }
    if (value is String) {
      return value.replaceAll(_value, '[REDACTED]');
    }
    return value;
  }
}

abstract interface class P2EffectJournal {
  Future<void> append(P2EffectReceipt receipt);
}

class P2JsonlEffectJournal implements P2EffectJournal {
  P2JsonlEffectJournal(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> append(P2EffectReceipt receipt) {
    final next = _tail.then((_) async {
      await file.parent.create(recursive: true);
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(jsonEncode(receipt.toJson()));
      await sink.flush();
      await sink.close();
    });
    _tail = next.catchError((Object _) {});
    return next;
  }
}
