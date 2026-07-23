/// Shared retry semantics for typed protocol and schema failures.
enum Retryability {
  /// Repeating the operation cannot safely repair the condition.
  never,

  /// The model may correct the same logical request without new project state.
  modelCorrection,

  /// The caller must first refresh project or artifact state.
  stateRefresh,

  /// The same operation may be retried after a bounded transient delay.
  transient,
}

extension RetryabilityWireName on Retryability {
  String get wireName => switch (this) {
        Retryability.never => 'never',
        Retryability.modelCorrection => 'model_correction',
        Retryability.stateRefresh => 'state_refresh',
        Retryability.transient => 'transient',
      };
}

class SchemaIssue {
  const SchemaIssue({
    required this.path,
    required this.keyword,
    required this.message,
    this.expected,
    this.actualType,
  });

  final String path;
  final String keyword;
  final String message;
  final Object? expected;
  final String? actualType;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'path': path,
        'keyword': keyword,
        'message': message,
        if (expected != null) 'expected': expected,
        if (actualType != null) 'actualType': actualType,
      };
}
