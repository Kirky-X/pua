// /api/heartbeat — install telemetry for the silent SessionStart heartbeat.
//
// POST: hooks/heartbeat.sh posts {"install_id", "plugin_version", "platform",
// "event_name", "flavor"}. Privacy rules:
//  - install_id never lands in D1; only sha256Hex(install_id) is stored, so the
//    aggregate cannot be reversed into a machine identity.
//  - No IP, no UA fingerprinting, no cookies on this path.
//
// GET: admin-only stats for the landing page (/api/heartbeat). Requires a valid
// signed session cookie whose GitHub login appears in ADMIN_GITHUB_LOGINS.

import { getSession } from "./_session";
import { sha256Hex } from "./_session";

export interface Env {
  DB: D1Database;
  SESSION_SECRET: string;
  ADMIN_GITHUB_LOGINS?: string;
}

const MAX_HEARTBEAT_BODY_BYTES = 2048;
const ACTIVE_WINDOW_SECONDS = 30 * 24 * 3600;
const INSTALL_ID_PATTERN = /^[A-Za-z0-9_.:-]{8,128}$/;

interface HeartbeatPayload {
  install_id?: unknown;
  plugin_version?: unknown;
  platform?: unknown;
  event_name?: unknown;
  flavor?: unknown;
}

function boundedString(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_HEARTBEAT_BODY_BYTES) {
    return jsonResponse({ error: "Heartbeat payload too large" }, 413);
  }
  let payload: HeartbeatPayload;
  try {
    payload = JSON.parse(raw) as HeartbeatPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const installId = boundedString(payload.install_id, 128);
  if (!INSTALL_ID_PATTERN.test(installId)) {
    return jsonResponse({ error: "install_id is required (8-128 chars of [A-Za-z0-9_.:-])" }, 400);
  }
  const installIdHash = await sha256Hex(installId);

  const now = Math.floor(Date.now() / 1000);
  const version = boundedString(payload.plugin_version, 64) || "unknown";
  const platform = boundedString(payload.platform, 64) || "unknown";
  const eventName = boundedString(payload.event_name, 64) || "session_start";
  const flavor = boundedString(payload.flavor, 64) || "unknown";

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO heartbeat_installs
         (install_id_hash, first_seen_at, last_seen_at, first_version, last_version, first_flavor, last_flavor, total_events)
       VALUES (?1, ?2, ?2, ?3, ?3, ?4, ?4, 1)
       ON CONFLICT(install_id_hash) DO UPDATE SET
         last_seen_at = excluded.last_seen_at,
         last_version = excluded.last_version,
         last_flavor = excluded.last_flavor,
         total_events = heartbeat_installs.total_events + 1`,
    ).bind(installIdHash, now, version, flavor),
    env.DB.prepare(
      "INSERT INTO heartbeat_events (install_id_hash, event_name, platform, plugin_version, flavor, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
    ).bind(installIdHash, eventName, platform, version, flavor, now),
  ]);

  return jsonResponse({ ok: true }, 202);
};

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const session = await getSession(request, env.SESSION_SECRET);
  if (!session) {
    return jsonResponse({ error: "Admin login required" }, 401);
  }
  const adminLogins = (env.ADMIN_GITHUB_LOGINS ?? "")
    .split(",")
    .map((login) => login.trim())
    .filter(Boolean);
  if (!adminLogins.includes(session.login)) {
    return jsonResponse({ error: "Login is not in the ADMIN_GITHUB_LOGINS allowlist" }, 403);
  }

  const since = Math.floor(Date.now() / 1000) - ACTIVE_WINDOW_SECONDS;
  const active = await env.DB.prepare(
    "SELECT COUNT(DISTINCT install_id_hash) AS installs FROM heartbeat_installs WHERE last_seen_at > ?1",
  )
    .bind(since)
    .first<{ installs: number }>();
  const total = await env.DB.prepare(
    "SELECT COUNT(DISTINCT install_id_hash) AS installs FROM heartbeat_installs",
  ).first<{ installs: number }>();
  const byFlavor = await env.DB.prepare(
    "SELECT flavor, COUNT(DISTINCT install_id_hash) AS installs FROM heartbeat_events WHERE created_at > ?1 GROUP BY flavor ORDER BY installs DESC LIMIT 20",
  )
    .bind(since)
    .all<{ flavor: string; installs: number }>();
  const byPlatform = await env.DB.prepare(
    "SELECT platform, COUNT(DISTINCT install_id_hash) AS installs FROM heartbeat_events WHERE created_at > ?1 GROUP BY platform ORDER BY installs DESC LIMIT 20",
  )
    .bind(since)
    .all<{ platform: string; installs: number }>();
  const byVersion = await env.DB.prepare(
    "SELECT plugin_version, COUNT(DISTINCT install_id_hash) AS installs FROM heartbeat_events WHERE created_at > ?1 GROUP BY plugin_version ORDER BY installs DESC LIMIT 20",
  )
    .bind(since)
    .all<{ plugin_version: string; installs: number }>();

  return jsonResponse(
    {
      window_days: 30,
      active_installs: active?.installs ?? 0,
      total_installs: total?.installs ?? 0,
      by_flavor: byFlavor.results,
      by_platform: byPlatform.results,
      by_version: byVersion.results,
    },
    200,
  );
};
