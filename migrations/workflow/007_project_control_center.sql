ALTER TABLE managed_project_processes ADD COLUMN launch_profile_id TEXT;
ALTER TABLE managed_project_processes ADD COLUMN kind TEXT;
ALTER TABLE managed_project_processes ADD COLUMN port INTEGER;
ALTER TABLE managed_project_processes ADD COLUMN health_state TEXT;
ALTER TABLE managed_project_processes ADD COLUMN process_identity TEXT;
ALTER TABLE managed_project_processes ADD COLUMN lifecycle TEXT NOT NULL DEFAULT 'ephemeral' CHECK(lifecycle IN ('ephemeral', 'persist_until_stopped'));

CREATE TABLE IF NOT EXISTS project_launch_profiles (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('desktop', 'web', 'server', 'command', 'other')),
  label TEXT NOT NULL,
  executable TEXT NOT NULL,
  arguments_json TEXT NOT NULL,
  working_directory TEXT NOT NULL,
  open_behavior TEXT NOT NULL CHECK(open_behavior IN ('focus_native_app', 'open_web_studio', 'open_external_browser', 'none')),
  preferred INTEGER NOT NULL DEFAULT 0 CHECK(preferred IN (0, 1)),
  ports_json TEXT NOT NULL DEFAULT '[]',
  health_checks_json TEXT NOT NULL DEFAULT '[]',
  source TEXT NOT NULL CHECK(source IN ('detected', 'learned', 'manual')),
  identity_sha256 TEXT NOT NULL CHECK(length(identity_sha256) = 64),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(project_id, identity_sha256)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_project_launch_profiles_project_updated
  ON project_launch_profiles(project_id, updated_at DESC, id);
CREATE INDEX IF NOT EXISTS idx_project_launch_profiles_project_preferred
  ON project_launch_profiles(project_id, preferred DESC, updated_at DESC);
