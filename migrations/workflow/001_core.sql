CREATE TABLE IF NOT EXISTS workflow_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS entity_records (
  collection TEXT NOT NULL,
  id TEXT NOT NULL,
  record_json TEXT NOT NULL,
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (collection, id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_entity_records_collection_updated
  ON entity_records(collection, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS documents (
  key TEXT PRIMARY KEY,
  document_json TEXT NOT NULL,
  document_sha256 TEXT NOT NULL CHECK(length(document_sha256) = 64),
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  source_run_id TEXT,
  state TEXT NOT NULL,
  state_version INTEGER NOT NULL CHECK(state_version >= 1),
  run_json TEXT NOT NULL,
  snapshot_sha256 TEXT NOT NULL CHECK(length(snapshot_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  failure TEXT
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_runs_project_updated
  ON runs(project_id, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_runs_state_updated
  ON runs(state, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_runs_command
  ON runs(command_id, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS run_events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  correlation_id TEXT NOT NULL,
  run_id TEXT,
  type TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256) = 64),
  causation_id TEXT,
  idempotency_key TEXT,
  state_version INTEGER
);

CREATE INDEX IF NOT EXISTS idx_run_events_correlation_sequence
  ON run_events(correlation_id, sequence);
CREATE INDEX IF NOT EXISTS idx_run_events_run_sequence
  ON run_events(run_id, sequence);
CREATE INDEX IF NOT EXISTS idx_run_events_type_sequence
  ON run_events(type, sequence);
CREATE INDEX IF NOT EXISTS idx_run_events_idempotency
  ON run_events(idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS task_attempts (
  run_id TEXT NOT NULL,
  work_item_id TEXT NOT NULL,
  attempt INTEGER NOT NULL CHECK(attempt >= 1),
  state TEXT NOT NULL,
  error_class TEXT,
  error_code TEXT,
  retry_disposition TEXT,
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  details_sha256 TEXT NOT NULL DEFAULT '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
  PRIMARY KEY (run_id, work_item_id, attempt)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_task_attempts_run_state
  ON task_attempts(run_id, state, work_item_id, attempt);

CREATE TABLE IF NOT EXISTS run_leases (
  run_id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  acquired_at TEXT NOT NULL,
  renewed_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
) WITHOUT ROWID;
