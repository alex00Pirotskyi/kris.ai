__RUNNER_ATTEMPT_LEDGER_FINALIZER_GUARD__
CREATE TABLE IF NOT EXISTS agent_action_attempts (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  work_item_id TEXT NOT NULL,
  work_item_attempt INTEGER NOT NULL CHECK(work_item_attempt >= 1),
  turn INTEGER NOT NULL CHECK(turn >= 1),
  request_number INTEGER NOT NULL CHECK(request_number >= 0),
  state_sha256 TEXT NOT NULL CHECK(length(state_sha256) = 64),
  decision_sha256 TEXT NOT NULL CHECK(length(decision_sha256) = 64),
  action_json TEXT,
  action_sha256 TEXT CHECK(action_sha256 IS NULL OR length(action_sha256) = 64),
  tool TEXT,
  outcome TEXT NOT NULL CHECK(outcome IN (
    'proposed',
    'protocol_error',
    'ok',
    'tool_error',
    'no_progress',
    'rejected',
    'complete',
    'declared_failure',
    'deterministic_proposed',
    'deterministic_ok',
    'deterministic_error'
  )),
  error_code TEXT,
  before_sha256 TEXT CHECK(before_sha256 IS NULL OR length(before_sha256) = 64),
  after_sha256 TEXT CHECK(after_sha256 IS NULL OR length(after_sha256) = 64),
  details_json TEXT NOT NULL DEFAULT '{}',
  details_sha256 TEXT NOT NULL DEFAULT '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(run_id, work_item_id, work_item_attempt, turn, request_number)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_agent_action_attempts_state
  ON agent_action_attempts(
    run_id,
    work_item_id,
    state_sha256,
    outcome,
    updated_at DESC
  );

CREATE INDEX IF NOT EXISTS idx_agent_action_attempts_action
  ON agent_action_attempts(action_sha256, outcome, updated_at DESC)
  WHERE action_sha256 IS NOT NULL;
