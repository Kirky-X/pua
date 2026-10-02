-- Migration 0005: direct anonymous session uploads + per-IP upload rate
-- limiting. The Stop hook uploads sanitized transcripts straight to
-- /api/upload after explicit consent, without requiring GitHub login —
-- anonymous uploads share the same uploads table, tagged source='anonymous',
-- and get the tight upload_rate_limits window.

CREATE TABLE IF NOT EXISTS uploads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name TEXT NOT NULL DEFAULT '',
  object_key TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  line_count INTEGER NOT NULL DEFAULT 0,
  wechat_id TEXT,
  source TEXT NOT NULL DEFAULT 'anonymous',
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_uploads_created_at ON uploads (created_at);

CREATE INDEX IF NOT EXISTS idx_uploads_sha256 ON uploads (sha256);

CREATE TABLE IF NOT EXISTS upload_rate_limits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ip_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_upload_rate_limits_lookup ON upload_rate_limits (ip_hash, created_at);
