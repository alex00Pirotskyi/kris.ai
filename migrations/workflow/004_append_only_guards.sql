CREATE TRIGGER IF NOT EXISTS trg_run_events_append_only_update
BEFORE UPDATE ON run_events
BEGIN
  SELECT RAISE(ABORT, 'run_events_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_run_events_append_only_delete
BEFORE DELETE ON run_events
BEGIN
  SELECT RAISE(ABORT, 'run_events_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_idempotency_completed_requires_result_insert
BEFORE INSERT ON idempotency_records
WHEN NEW.status = 'completed'
  AND (NEW.result_json IS NULL OR NEW.result_sha256 IS NULL)
BEGIN
  SELECT RAISE(ABORT, 'idempotency_completed_result_required');
END;

CREATE TRIGGER IF NOT EXISTS trg_idempotency_completed_requires_result_update
BEFORE UPDATE OF status, result_json, result_sha256 ON idempotency_records
WHEN NEW.status = 'completed'
  AND (NEW.result_json IS NULL OR NEW.result_sha256 IS NULL)
BEGIN
  SELECT RAISE(ABORT, 'idempotency_completed_result_required');
END;

CREATE TRIGGER IF NOT EXISTS trg_idempotency_completed_immutable
BEFORE UPDATE ON idempotency_records
WHEN OLD.status = 'completed'
  AND (
    NEW.result_json IS NOT OLD.result_json OR
    NEW.result_sha256 IS NOT OLD.result_sha256 OR
    NEW.normalized_arguments_sha256 IS NOT OLD.normalized_arguments_sha256 OR
    NEW.operation IS NOT OLD.operation
  )
BEGIN
  SELECT RAISE(ABORT, 'idempotency_completed_immutable');
END;
