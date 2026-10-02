-- Migration 0004: silent install heartbeat storage (privacy-preserving).
--
-- hooks/heartbeat.sh posts an anonymous install_id; the endpoint stores only
-- sha256Hex(install_id), so neither table can be reversed into a machine
-- identity. Idempotent for the same reason as 0003: remote databases may
-- predate the migration journal.

CREATE TABLE IF NOT EXISTS heartbeat_installs (
  install_id_hash TEXT PRIMARY KEY,
  first_seen_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  first_version TEXT NOT NULL DEFAULT 'unknown',
  last_version TEXT NOT NULL DEFAULT 'unknown',
  first_flavor TEXT NOT NULL DEFAULT 'unknown',
  last_flavor TEXT NOT NULL DEFAULT 'unknown',
  total_events INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_heartbeat_installs_last_seen ON heartbeat_installs (last_seen_at);

CREATE TABLE IF NOT EXISTS heartbeat_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id_hash TEXT NOT NULL,
  event_name TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'unknown',
  plugin_version TEXT NOT NULL DEFAULT 'unknown',
  flavor TEXT NOT NULL DEFAULT 'unknown',
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_heartbeat_events_install ON heartbeat_events (install_id_hash, created_at);

CREATE INDEX IF NOT EXISTS idx_heartbeat_events_flavor ON heartbeat_events (flavor, created_at);
