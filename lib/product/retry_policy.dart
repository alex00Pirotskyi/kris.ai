enum WorkflowFailureClass {
  providerTransient,
  schemaProtocol,
  toolInput,
  projectStateConflict,
  verification,
  resourceUnavailable,
  policyRejection,
  deterministicBug,
  cancellation,
  unknown,
}

enum RetryDisposition {
  retrySameAttempt,
  retryNewAttempt,
  inspectThenRetry,
  awaitResource,
  requireUser,
  never,
}

class RetryClassification {
  const RetryClassification({
    required this.failureClass,
    required this.disposition,
    required this.retryability,
  });

  final WorkflowFailureClass failureClass;
  final RetryDisposition disposition;
  final String retryability;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'failureClass': failureClass.name,
        'disposition': disposition.name,
        'retryability': retryability,
      };
}

class WorkflowRetryTaxonomy {
  const WorkflowRetryTaxonomy();

  RetryClassification classify(String code) {
    if (code == 'cancelled') {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.cancellation,
        disposition: RetryDisposition.never,
        retryability: 'never',
      );
    }
    if (code.startsWith('budget_') ||
        const <String>{
          'permission_scope_missing',
          'permission_scope_unrequested',
          'permission_read_required',
          'path_outside_project',
          'self_project_target_rejected',
          'network_disabled',
          'secret_reference_required',
          'operation_recovery_required',
          'run_claimed',
          'run_lease_lost',
        }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.policyRejection,
        disposition: RetryDisposition.requireUser,
        retryability: 'never',
      );
    }
    if (const <String>{
      'argument_required',
      'argument_type_invalid',
      'argument_unknown',
      'argument_format_invalid',
      'argument_value_invalid',
      'argument_alias_conflict',
      'agent_action_invalid',
      'agent_action_parse_failed',
      'agent_decision_invalid',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.schemaProtocol,
        disposition: RetryDisposition.retrySameAttempt,
        retryability: 'model_correction',
      );
    }
    if (const <String>{
      'path_missing',
      'replacement_not_found',
      'replacement_ambiguous',
      'patch_hunk_not_found',
      'patch_hunk_ambiguous',
      'base64_invalid',
      'tool_not_allowed',
      'tool_unknown',
      'executable_missing',
      'working_directory_invalid',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.toolInput,
        disposition: RetryDisposition.retrySameAttempt,
        retryability: 'model_correction',
      );
    }
    if (const <String>{
      'stale_content',
      'stale_existence',
      'operation_in_flight',
      'idempotency_lease_lost',
      'run_state_invalid',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.projectStateConflict,
        disposition: RetryDisposition.inspectThenRetry,
        retryability: 'state_conflict',
      );
    }
    if (const <String>{
      'verification_failed',
      'artifact_scope_incomplete',
      'artifact_scope_mismatch',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.verification,
        disposition: RetryDisposition.retryNewAttempt,
        retryability: 'verification',
      );
    }
    if (const <String>{
      'model_not_installed',
      'model_load_timeout',
      'model_load_failed',
      'model_load_response_invalid',
      'provider_timeout',
      'provider_unavailable',
      'network_timeout',
      'resource_unavailable',
      'managed_process_missing',
    }.contains(code)) {
      return RetryClassification(
        failureClass: code.startsWith('model_load') || code.startsWith('provider_')
            ? WorkflowFailureClass.providerTransient
            : WorkflowFailureClass.resourceUnavailable,
        disposition: RetryDisposition.awaitResource,
        retryability: 'resource',
      );
    }
    if (const <String>{
      'workflow_integrity_failed',
      'workflow_migration_drift',
      'workflow_schema_version_mismatch',
      'idempotency_key_collision',
      'idempotency_result_conflict',
      'transaction_recovery_required',
      'checkpoint_missing',
      'tool_output_invalid',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.deterministicBug,
        disposition: RetryDisposition.never,
        retryability: 'never',
      );
    }
    if (const <String>{
      'provider_http_error',
      'provider_connection_failed',
      'research_fetch_failed',
    }.contains(code)) {
      return const RetryClassification(
        failureClass: WorkflowFailureClass.providerTransient,
        disposition: RetryDisposition.retryNewAttempt,
        retryability: 'transient',
      );
    }
    return const RetryClassification(
      failureClass: WorkflowFailureClass.unknown,
      disposition: RetryDisposition.retryNewAttempt,
      retryability: 'transient',
    );
  }
}
