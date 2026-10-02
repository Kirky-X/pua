-- Migration 0003: feedback table + per-IP write rate limiting (issue #159).
--
-- Idempotent on purpose: production D1 databases predate this repository's
-- wrangler migration journal (0001/0002 were applied remotely long ago), so
-- `wrangler d1 migrations apply --remote` may replay migrations on databases
-- that already have the objects. Every CREATE here uses IF NOT EXISTS —
-- a bare CREATE INDEX previously made the apply fail on 0001 before newer
-- migrations could run.

CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rating TEXT NOT NULL,
  pua_count INTEGER NOT NULL DEFAULT 0,
  flavor TEXT NOT NULL DEFAULT '',
  task_summary TEXT NOT NULL DEFAULT '',
  session_object_key TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback (created_at);

CREATE TABLE IF NOT EXISTS feedback_rate_limits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ip_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feedback_rate_limits_lookup ON feedback_rate_limits (ip_hash, created_at);
