CREATE TABLE IF NOT EXISTS idempotency_records (
  idempotency_key TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT NOT NULL,
  attempt INTEGER NOT NULL CHECK(attempt >= 1),
  operation TEXT NOT NULL,
  normalized_arguments_sha256 TEXT NOT NULL CHECK(length(normalized_arguments_sha256) = 64),
  status TEXT NOT NULL CHECK(status IN ('in_progress', 'completed', 'failed')),
  lease_owner TEXT NOT NULL,
  lease_expires_at TEXT NOT NULL,
  execution_generation INTEGER NOT NULL DEFAULT 1 CHECK(execution_generation >= 1),
  result_json TEXT,
  result_sha256 TEXT,
  error_class TEXT,
  error_code TEXT,
  retryability TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_idempotency_run_work
  ON idempotency_records(run_id, work_item_id, attempt, operation);
CREATE INDEX IF NOT EXISTS idx_idempotency_status_lease
  ON idempotency_records(status, lease_expires_at);

CREATE TABLE IF NOT EXISTS checkpoints (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT,
  kind TEXT NOT NULL,
  event_sequence INTEGER,
  state_json TEXT NOT NULL,
  state_sha256 TEXT NOT NULL CHECK(length(state_sha256) = 64),
  created_at TEXT NOT NULL,
  UNIQUE(run_id, kind, event_sequence, state_sha256)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_checkpoints_run_created
  ON checkpoints(run_id, created_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_checkpoints_run_kind
  ON checkpoints(run_id, kind, created_at DESC, id);
