// Shared per-IP sliding-window write limiter backed by the *_rate_limits D1
// tables. Feedback writes and anonymous uploads share the same shape, so the
// check-and-record logic lives here instead of being duplicated per endpoint.
// Table names come only from the fixed allowlist below — never from request
// input — so the identifier interpolation is safe.

const RATE_LIMIT_TABLES = new Set(["feedback_rate_limits", "upload_rate_limits"]);

export function clientIp(request: Request): string {
  const forwarded = request.headers.get("X-Forwarded-For");
  return (
    request.headers.get("CF-Connecting-IP") ??
    (forwarded ? forwarded.split(",")[0]?.trim() : undefined) ??
    "unknown"
  );
}

export async function enforceWriteRateLimit(
  db: D1Database,
  table: string,
  ipHash: string,
  nowSeconds: number,
  windowSeconds: number,
  maxWrites: number,
): Promise<boolean> {
  if (!RATE_LIMIT_TABLES.has(table)) {
    throw new Error(`Unknown rate limit table: ${table}`);
  }
  const windowStart = nowSeconds - windowSeconds;
  const row = await db
    .prepare(`SELECT COUNT(*) AS writes FROM ${table} WHERE ip_hash = ?1 AND created_at >= ?2`)
    .bind(ipHash, windowStart)
    .first<{ writes: number }>();
  const writes = typeof row?.writes === "number" ? row.writes : 0;
  if (writes >= maxWrites) return false;
  await db
    .prepare(`INSERT INTO ${table} (ip_hash, created_at) VALUES (?1, ?2)`)
    .bind(ipHash, nowSeconds)
    .run();
  return true;
}
