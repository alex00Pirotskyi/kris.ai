CREATE TABLE IF NOT EXISTS project_profiles (
  project_id TEXT PRIMARY KEY,
  schema_version TEXT NOT NULL,
  profile_json TEXT NOT NULL,
  profile_sha256 TEXT NOT NULL CHECK(length(profile_sha256) = 64),
  source_path_hash TEXT NOT NULL CHECK(length(source_path_hash) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS workspace_sessions (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT,
  action TEXT NOT NULL,
  mode TEXT NOT NULL CHECK(mode IN ('read_only', 'snapshot_writable', 'git_worktree')),
  source_root_hash TEXT NOT NULL CHECK(length(source_root_hash) = 64),
  workspace_path TEXT NOT NULL,
  workspace_path_hash TEXT NOT NULL CHECK(length(workspace_path_hash) = 64),
  source_manifest_sha256 TEXT NOT NULL CHECK(length(source_manifest_sha256) = 64),
  workspace_manifest_sha256 TEXT,
  status TEXT NOT NULL CHECK(status IN ('preparing', 'ready', 'running', 'completed', 'failed', 'interrupted', 'discarded')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  details_sha256 TEXT NOT NULL DEFAULT '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a'
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_workspace_sessions_project_updated
  ON workspace_sessions(project_id, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_workspace_sessions_run
  ON workspace_sessions(run_id, updated_at DESC, id) WHERE run_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_workspace_sessions_status
  ON workspace_sessions(status, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS managed_project_processes (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT,
  workspace_id TEXT,
  action TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('starting', 'running', 'stopping', 'succeeded', 'failed', 'stopped', 'interrupted')),
  sandbox_backend TEXT NOT NULL,
  pid INTEGER,
  process_group_id INTEGER,
  command_sha256 TEXT NOT NULL CHECK(length(command_sha256) = 64),
  request_json TEXT NOT NULL,
  request_sha256 TEXT NOT NULL CHECK(length(request_sha256) = 64),
  result_json TEXT,
  result_sha256 TEXT,
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  exit_code INTEGER,
  failure_code TEXT
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_managed_project_processes_project_updated
  ON managed_project_processes(project_id, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_managed_project_processes_state
  ON managed_project_processes(state, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS artifact_records (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT,
  workspace_id TEXT,
  producer_action TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  logical_type TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64),
  byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
  validation_state TEXT NOT NULL CHECK(validation_state IN ('unvalidated', 'valid', 'invalid', 'blocked', 'preexisting_valid')),
  sensitivity TEXT NOT NULL DEFAULT 'project',
  record_json TEXT NOT NULL,
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(project_id, workspace_id, relative_path, content_sha256)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_artifact_records_project_updated
  ON artifact_records(project_id, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_artifact_records_run
  ON artifact_records(run_id, updated_at DESC, id) WHERE run_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS model_circuit_breakers (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('closed', 'open', 'half_open')),
  consecutive_failures INTEGER NOT NULL DEFAULT 0 CHECK(consecutive_failures >= 0),
  timeout_failures INTEGER NOT NULL DEFAULT 0 CHECK(timeout_failures >= 0),
  malformed_failures INTEGER NOT NULL DEFAULT 0 CHECK(malformed_failures >= 0),
  opened_at TEXT,
  cooldown_seconds INTEGER NOT NULL DEFAULT 120 CHECK(cooldown_seconds > 0),
  last_success_at TEXT,
  last_failure_at TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(provider, model)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS model_route_decisions (
  id TEXT PRIMARY KEY,
  run_id TEXT,
  work_item_id TEXT,
  role TEXT NOT NULL,
  request_sha256 TEXT NOT NULL CHECK(length(request_sha256) = 64),
  decision_json TEXT NOT NULL,
  decision_sha256 TEXT NOT NULL CHECK(length(decision_sha256) = 64),
  selected_provider TEXT,
  selected_model TEXT,
  approval_required INTEGER NOT NULL CHECK(approval_required IN (0, 1)),
  created_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_model_route_decisions_run
  ON model_route_decisions(run_id, work_item_id, created_at, id);

CREATE TABLE IF NOT EXISTS semantic_progress_records (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT NOT NULL,
  attempt INTEGER NOT NULL CHECK(attempt >= 1),
  turn INTEGER NOT NULL CHECK(turn >= 1),
  before_sha256 TEXT NOT NULL CHECK(length(before_sha256) = 64),
  after_sha256 TEXT NOT NULL CHECK(length(after_sha256) = 64),
  delta_json TEXT NOT NULL,
  delta_sha256 TEXT NOT NULL CHECK(length(delta_sha256) = 64),
  semantic_progress INTEGER NOT NULL CHECK(semantic_progress IN (0, 1)),
  strategy_action TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(run_id, work_item_id, attempt, turn)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_semantic_progress_run_work
  ON semantic_progress_records(run_id, work_item_id, attempt, turn);

CREATE TABLE IF NOT EXISTS verification_reports (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT NOT NULL,
  attempt INTEGER NOT NULL CHECK(attempt >= 1),
  verifier_role TEXT NOT NULL DEFAULT 'verifier',
  evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256) = 64),
  report_json TEXT NOT NULL,
  report_sha256 TEXT NOT NULL CHECK(length(report_sha256) = 64),
  passed INTEGER NOT NULL CHECK(passed IN (0, 1)),
  created_at TEXT NOT NULL,
  UNIQUE(run_id, work_item_id, attempt, report_sha256)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_verification_reports_run_work
  ON verification_reports(run_id, work_item_id, attempt, created_at);

CREATE TRIGGER IF NOT EXISTS trg_model_route_decisions_append_only_update
BEFORE UPDATE ON model_route_decisions
BEGIN
  SELECT RAISE(ABORT, 'model_route_decisions_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_model_route_decisions_append_only_delete
BEFORE DELETE ON model_route_decisions
BEGIN
  SELECT RAISE(ABORT, 'model_route_decisions_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_semantic_progress_append_only_update
BEFORE UPDATE ON semantic_progress_records
BEGIN
  SELECT RAISE(ABORT, 'semantic_progress_records_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_semantic_progress_append_only_delete
BEFORE DELETE ON semantic_progress_records
BEGIN
  SELECT RAISE(ABORT, 'semantic_progress_records_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_verification_reports_append_only_update
BEFORE UPDATE ON verification_reports
BEGIN
  SELECT RAISE(ABORT, 'verification_reports_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_verification_reports_append_only_delete
BEFORE DELETE ON verification_reports
BEGIN
  SELECT RAISE(ABORT, 'verification_reports_append_only');
END;
