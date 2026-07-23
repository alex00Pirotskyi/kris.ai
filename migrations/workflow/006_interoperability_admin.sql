CREATE TABLE IF NOT EXISTS audit_records (
  id TEXT PRIMARY KEY,
  record_index INTEGER NOT NULL CHECK(record_index >= 1),
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256) = 64),
  previous_hash TEXT NOT NULL CHECK(length(previous_hash) = 64),
  record_hash TEXT NOT NULL CHECK(length(record_hash) = 64),
  signature_algorithm TEXT NOT NULL,
  signer_id TEXT NOT NULL,
  signature TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(record_index),
  UNIQUE(record_hash)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_audit_records_created
  ON audit_records(created_at, record_index, id);

CREATE TABLE IF NOT EXISTS capability_manifests (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK(kind IN ('plugin', 'skill', 'agent')),
  version INTEGER NOT NULL CHECK(version >= 1),
  manifest_json TEXT NOT NULL,
  manifest_sha256 TEXT NOT NULL CHECK(length(manifest_sha256) = 64),
  signer_id TEXT NOT NULL,
  signature_algorithm TEXT NOT NULL,
  signature TEXT NOT NULL,
  signed_at TEXT NOT NULL,
  trust_state TEXT NOT NULL CHECK(trust_state IN ('verified', 'revoked', 'unknown')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_capability_manifests_kind_updated
  ON capability_manifests(kind, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS mcp_server_registrations (
  id TEXT PRIMARY KEY,
  manifest_sha256 TEXT NOT NULL CHECK(length(manifest_sha256) = 64),
  project_id TEXT,
  transport TEXT NOT NULL CHECK(transport IN ('local_stdio', 'remote_https')),
  sandbox_required INTEGER NOT NULL CHECK(sandbox_required IN (0, 1)),
  state TEXT NOT NULL CHECK(state IN ('registered', 'trusted', 'revoked', 'blocked')),
  registration_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS a2a_delegation_records (
  id TEXT PRIMARY KEY,
  run_id TEXT,
  work_item_id TEXT,
  contract_sha256 TEXT NOT NULL CHECK(length(contract_sha256) = 64),
  contract_json TEXT NOT NULL,
  response_sha256 TEXT,
  response_json TEXT,
  state TEXT NOT NULL CHECK(state IN ('prepared', 'delegated', 'completed', 'failed', 'blocked')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_a2a_delegation_run
  ON a2a_delegation_records(run_id, work_item_id, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS update_channel_manifests (
  release_version TEXT PRIMARY KEY,
  channel TEXT NOT NULL,
  archive_sha256 TEXT NOT NULL CHECK(length(archive_sha256) = 64),
  package_root TEXT NOT NULL,
  parent_version TEXT NOT NULL,
  rollback_version TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  manifest_sha256 TEXT NOT NULL CHECK(length(manifest_sha256) = 64),
  verified INTEGER NOT NULL CHECK(verified IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS policy_profiles (
  id TEXT PRIMARY KEY,
  profile_json TEXT NOT NULL,
  profile_sha256 TEXT NOT NULL CHECK(length(profile_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS fleet_profiles (
  organization TEXT PRIMARY KEY,
  policy_profile_id TEXT NOT NULL,
  profile_json TEXT NOT NULL,
  profile_sha256 TEXT NOT NULL CHECK(length(profile_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(policy_profile_id) REFERENCES policy_profiles(id) ON DELETE RESTRICT
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS support_compatibility_policies (
  id TEXT PRIMARY KEY,
  policy_json TEXT NOT NULL,
  policy_sha256 TEXT NOT NULL CHECK(length(policy_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TRIGGER IF NOT EXISTS trg_audit_records_append_only_update
BEFORE UPDATE ON audit_records
BEGIN
  SELECT RAISE(ABORT, 'audit_records_append_only');
END;

CREATE TRIGGER IF NOT EXISTS trg_audit_records_append_only_delete
BEFORE DELETE ON audit_records
BEGIN
  SELECT RAISE(ABORT, 'audit_records_append_only');
END;
