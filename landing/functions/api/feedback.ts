// POST /api/feedback — anonymous star rating + authenticated session upload.
//
// Two paths, deliberately split (issue #159):
//  - Anonymous: {"rating": "很有用", "pua_count": 0, "flavor": "阿里", ...}
//    No login, no transcript — exactly what hooks/stop-feedback.sh posts.
//  - session_data branch: requires a signed session cookie. Anonymous callers
//    get 401 "Login required for session upload" instead of a silent dump of
//    conversation data into the public feedback table.
//
// Abuse control: strict body-size caps, CORS origin allowlist, and a per-IP
// sliding-window write limiter backed by feedback_rate_limits.

import { getSession } from "./_session";
import { hashIp } from "./_session";
import { clientIp, enforceWriteRateLimit } from "./_ratelimit";

export interface Env {
  DB: D1Database;
  UPLOADS: R2Bucket;
  SESSION_SECRET: string;
}

const ALLOWED_ORIGINS: ReadonlySet<string> = new Set([
  "https://pua-skill.pages.dev",
  "http://localhost:8788",
  "http://127.0.0.1:8788",
]);

const MAX_BODY_BYTES = 64 * 1024;
const MAX_SESSION_DATA_BYTES = 512 * 1024;
const RATE_LIMIT_WINDOW_SECONDS = 3600;
const RATE_LIMIT_MAX_WRITES = 10;

interface FeedbackBody {
  rating?: unknown;
  pua_count?: unknown;
  flavor?: unknown;
  task_summary?: unknown;
  session_data?: unknown;
}

interface JsonInit {
  status: number;
  origin: string | null;
}

function jsonResponse(body: unknown, init: JsonInit): Response {
  const headers = new Headers({ "Content-Type": "application/json; charset=utf-8" });
  if (init.origin && ALLOWED_ORIGINS.has(init.origin)) {
    headers.set("Access-Control-Allow-Origin", init.origin);
    headers.set("Vary", "Origin");
  }
  return new Response(JSON.stringify(body), { status: init.status, headers });
}

function byteLength(text: string): number {
  return new TextEncoder().encode(text).length;
}

export const onRequestOptions: PagesFunction<Env> = async ({ request }) => {
  const origin = request.headers.get("Origin");
  if (!origin || !ALLOWED_ORIGINS.has(origin)) {
    return new Response(null, { status: 204 });
  }
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Max-Age": "86400",
      Vary: "Origin",
    },
  });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const origin = request.headers.get("Origin");
  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return jsonResponse({ error: "Origin not allowed" }, { status: 403, origin: null });
  }
  // SESSION_SECRET is what makes the session_data branch verifiable; a missing
  // binding means the deployment is misconfigured, so fail closed.
  if (!env.SESSION_SECRET) {
    return jsonResponse({ error: "SESSION_SECRET binding is not configured" }, { status: 500, origin });
  }

  const raw = await request.text();
  if (byteLength(raw) > MAX_BODY_BYTES) {
    return jsonResponse({ error: "Feedback payload too large" }, { status: 413, origin });
  }
  let body: FeedbackBody;
  try {
    body = JSON.parse(raw) as FeedbackBody;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, { status: 400, origin });
  }

  const rating = typeof body.rating === "string" ? body.rating.trim().slice(0, 64) : "";
  if (!rating) {
    return jsonResponse({ error: "rating is required" }, { status: 400, origin });
  }

  // session_data branch — authenticated uploads only.
  let sessionObjectKey: string | null = null;
  if (body.session_data !== undefined && body.session_data !== null) {
    const session = await getSession(request, env.SESSION_SECRET);
    if (!session) {
      return jsonResponse({ error: "Login required for session upload" }, { status: 401, origin });
    }
    const serialized = JSON.stringify(body.session_data);
    if (byteLength(serialized) > MAX_SESSION_DATA_BYTES) {
      return jsonResponse({ error: "session_data too large" }, { status: 413, origin });
    }
    sessionObjectKey = `sessions/${new Date().toISOString().slice(0, 10)}/feedback-${crypto.randomUUID()}.jsonl`;
    await env.UPLOADS.put(sessionObjectKey, serialized, {
      httpMetadata: { contentType: "application/jsonl; charset=utf-8" },
    });
  }

  const ipHash = await hashIp(clientIp(request));
  const now = Math.floor(Date.now() / 1000);
  const allowed = await enforceWriteRateLimit(
    env.DB,
    "feedback_rate_limits",
    ipHash,
    now,
    RATE_LIMIT_WINDOW_SECONDS,
    RATE_LIMIT_MAX_WRITES,
  );
  if (!allowed) {
    return jsonResponse({ error: "Too many feedback writes, slow down" }, { status: 429, origin });
  }

  // Anonymous rating insert path — unchanged contract from the Stop hook.
  const puaCount =
    typeof body.pua_count === "number" && Number.isFinite(body.pua_count) ? Math.trunc(body.pua_count) : 0;
  const flavor = typeof body.flavor === "string" ? body.flavor.trim().slice(0, 64) : "";
  const taskSummary = typeof body.task_summary === "string" ? body.task_summary.trim().slice(0, 512) : "";
  await env.DB.prepare(
    "INSERT INTO feedback (rating, pua_count, flavor, task_summary, session_object_key, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
  )
    .bind(rating, puaCount, flavor, taskSummary, sessionObjectKey, now)
    .run();

  return jsonResponse({ ok: true, stored_session: sessionObjectKey !== null }, { status: 201, origin });
};
