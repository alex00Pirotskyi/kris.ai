CREATE TABLE IF NOT EXISTS compensation_records (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT,
  idempotency_key TEXT,
  mutation_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  before_sha256 TEXT,
  after_sha256 TEXT,
  backup_path TEXT,
  status TEXT NOT NULL CHECK(status IN (
    'prepared', 'applied', 'committed', 'abandoned',
    'rolled_back', 'rollback_failed'
  )),
  record_json TEXT NOT NULL,
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256) = 64),
  rollback_result_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(run_id, mutation_id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_compensation_run_status
  ON compensation_records(run_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_compensation_idempotency
  ON compensation_records(idempotency_key, status)
  WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS migration_imports (
  source_key TEXT PRIMARY KEY,
  source_path_hash TEXT NOT NULL,
  source_sha256 TEXT NOT NULL CHECK(length(source_sha256) = 64),
  backup_path TEXT NOT NULL,
  imported_records INTEGER NOT NULL DEFAULT 0,
  imported_at TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}'
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS recovery_actions (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  action TEXT NOT NULL,
  reason TEXT NOT NULL,
  before_state TEXT,
  after_state TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_recovery_actions_run
  ON recovery_actions(run_id, created_at DESC, id);
