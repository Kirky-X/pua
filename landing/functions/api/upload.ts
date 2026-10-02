// POST /api/upload — sanitized session transcript uploads.
//
// Contract (kept compatible with hooks/stop-feedback.sh):
//  - Raw body path: Content-Type: application/jsonl, transcript as the request
//    body, metadata in X-PUA-File-Name / X-PUA-Wechat-Id, and the mandatory
//    X-PUA-Upload-Consent: explicit header. This is the path the Stop hook uses.
//  - JSON envelope path: {"file_data": "<jsonl text>", "file_name": ...} kept
//    for older clients.
//  - multipart/form-data path kept for browser fallbacks (field "file").
//
// Login is optional: requests carrying a valid session cookie are recorded with
// source "github", everything else is an anonymous upload and gets the tight
// upload_rate_limits window. Every body is re-sanitized server-side before it
// lands in R2, and the upload is recorded in the uploads table.

import { getSession, hashIp, sha256Hex } from "./_session";
import { clientIp, enforceWriteRateLimit } from "./_ratelimit";
import { sanitize } from "./_sanitize";

export interface Env {
  DB: D1Database;
  UPLOADS: R2Bucket;
  SESSION_SECRET: string;
}

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
const UPLOAD_RATE_LIMIT_WINDOW_SECONDS = 3600;
const RATE_LIMIT_MAX_ANONYMOUS = 5;
const RATE_LIMIT_MAX_AUTHENTICATED = 30;

interface UploadEnvelope {
  file_data?: unknown;
  file_name?: unknown;
  wechat_id?: unknown;
}

interface JsonInit {
  status: number;
}

function jsonResponse(body: unknown, init: JsonInit): Response {
  return new Response(JSON.stringify(body), {
    status: init.status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function byteLength(text: string): number {
  return new TextEncoder().encode(text).length;
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  if (!env.SESSION_SECRET) {
    return jsonResponse({ error: "SESSION_SECRET binding is not configured" }, { status: 500 });
  }

  const consent = request.headers.get("X-PUA-Upload-Consent");
  if (consent !== "explicit") {
    return jsonResponse({ error: "Upload rejected: X-PUA-Upload-Consent: explicit header is required" }, { status: 403 });
  }

  const contentType = (request.headers.get("Content-Type") ?? "").toLowerCase();
  let fileName = request.headers.get("X-PUA-File-Name")?.trim() ?? "";
  let wechatId = request.headers.get("X-PUA-Wechat-Id")?.trim() ?? "";
  let raw: string;

  if (contentType.startsWith("application/jsonl") || contentType.startsWith("text/plain")) {
    raw = await request.text();
    if (!fileName) fileName = "session.jsonl";
  } else if (contentType.includes("application/json")) {
    let envelope: UploadEnvelope;
    try {
      envelope = (await request.json()) as UploadEnvelope;
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, { status: 400 });
    }
    if (typeof envelope.file_data !== "string" || !envelope.file_data.trim()) {
      return jsonResponse({ error: "JSON uploads require a non-empty file_data string" }, { status: 400 });
    }
    raw = envelope.file_data;
    if (!fileName && typeof envelope.file_name === "string") fileName = envelope.file_name.trim();
    if (!wechatId && typeof envelope.wechat_id === "string") wechatId = envelope.wechat_id.trim();
  } else if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const part = form.get("file") ?? form.get("file_data");
    if (!(part instanceof File)) {
      return jsonResponse({ error: "Multipart uploads require a 'file' part" }, { status: 400 });
    }
    raw = await part.text();
    if (!fileName && fileShortName(part)) fileName = fileShortName(part);
    if (!fileName) fileName = "session.jsonl";
  } else {
    return jsonResponse(
      { error: "Unsupported Media Type: send application/jsonl, application/json or multipart/form-data" },
      { status: 415 },
    );
  }

  if (!raw.trim()) {
    return jsonResponse({ error: "Empty upload body" }, { status: 400 });
  }
  const size = byteLength(raw);
  if (size > MAX_UPLOAD_BYTES) {
    return jsonResponse({ error: "Upload too large" }, { status: 413 });
  }

  const session = await getSession(request, env.SESSION_SECRET);
  const source = session ? "github" : "anonymous";

  const ipHash = await hashIp(clientIp(request));
  const now = Math.floor(Date.now() / 1000);
  const allowed = await enforceWriteRateLimit(
    env.DB,
    "upload_rate_limits",
    ipHash,
    now,
    UPLOAD_RATE_LIMIT_WINDOW_SECONDS,
    session ? RATE_LIMIT_MAX_AUTHENTICATED : RATE_LIMIT_MAX_ANONYMOUS,
  );
  if (!allowed) {
    return jsonResponse({ error: "Too many uploads, slow down" }, { status: 429 });
  }

  const clean = sanitize(raw);
  const digest = await sha256Hex(clean);
  const objectKey = `sessions/${new Date().toISOString().slice(0, 10)}/${digest}.jsonl`;
  const existing = await env.UPLOADS.head(objectKey);
  if (!existing) {
    await env.UPLOADS.put(objectKey, clean, {
      httpMetadata: { contentType: "application/jsonl; charset=utf-8" },
    });
  }

  const lineCount = clean.split("\n").filter((line) => line.trim().length > 0).length;
  await env.DB.prepare(
    "INSERT INTO uploads (file_name, object_key, sha256, size_bytes, line_count, wechat_id, source, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
  )
    .bind(
      fileName.slice(0, 255),
      objectKey,
      digest,
      size,
      lineCount,
      wechatId ? wechatId.slice(0, 128) : null,
      source,
      now,
    )
    .run();

  return jsonResponse(
    { ok: true, key: objectKey, source, deduplicated: existing !== null, sanitized: true },
    { status: 201 },
  );
};

function fileShortName(part: File): string {
  const slash = part.name.lastIndexOf("/");
  return slash >= 0 ? part.name.slice(slash + 1) : part.name;
}
