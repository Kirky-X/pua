// Shared HMAC-SHA256 signed-cookie session helpers for the /api functions.
// The session cookie is stateless: "<login>|<exp>.<hmac>" — the HMAC proves the
// cookie was minted by this deployment (secret = SESSION_SECRET binding), the
// exp field keeps it short-lived.

const SESSION_COOKIE_NAME = "pua_session";
const SESSION_TTL_SECONDS = 7 * 24 * 3600;
const OAUTH_STATE_MAX_AGE_SECONDS = 600;

export interface SessionRecord {
  login: string;
  exp: number;
}

function toHex(bytes: Uint8Array): string {
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return toHex(new Uint8Array(digest));
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return toHex(new Uint8Array(signature));
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i += 1) {
    diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return diff === 0;
}

export async function createSessionToken(login: string, secret: string): Promise<string> {
  const exp = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
  const payload = `${login}|${exp}`;
  return `${payload}.${await hmacSha256Hex(secret, payload)}`;
}

// Reads and verifies the signed session cookie. Returns null for anonymous
// visitors, tampered cookies and expired sessions alike — callers only learn
// "logged in as X" or "anonymous".
export async function getSession(request: Request, secret: string): Promise<SessionRecord | null> {
  if (!secret) return null;
  const header = request.headers.get("Cookie");
  if (!header) return null;
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq <= 0) continue;
    if (part.slice(0, eq).trim() !== SESSION_COOKIE_NAME) continue;
    const value = part.slice(eq + 1).trim();
    const dot = value.lastIndexOf(".");
    if (dot <= 0) return null;
    const payload = value.slice(0, dot);
    const signature = value.slice(dot + 1);
    const expected = await hmacSha256Hex(secret, payload);
    if (!timingSafeEqual(signature, expected)) return null;
    const pipe = payload.indexOf("|");
    if (pipe <= 0) return null;
    const login = payload.slice(0, pipe);
    const exp = Number(payload.slice(pipe + 1));
    if (!login || !Number.isFinite(exp) || exp <= Math.floor(Date.now() / 1000)) return null;
    return { login, exp };
  }
  return null;
}

export function sessionCookieHeader(token: string): string {
  return `${SESSION_COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${SESSION_TTL_SECONDS}`;
}

export function clearSessionCookieHeader(): string {
  return `${SESSION_COOKIE_NAME}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

// Stateless OAuth state: "<ts>.<hmac(ts)>" — no KV needed to round-trip the
// authorize redirect through /api/auth/callback.
export async function createOAuthState(secret: string): Promise<string> {
  const ts = String(Math.floor(Date.now() / 1000));
  return `${ts}.${await hmacSha256Hex(secret, `pua-oauth-state:${ts}`)}`;
}

export async function verifyOAuthState(secret: string, state: string): Promise<boolean> {
  const dot = state.lastIndexOf(".");
  if (dot <= 0) return false;
  const ts = state.slice(0, dot);
  const signature = state.slice(dot + 1);
  if (!/^\d+$/.test(ts)) return false;
  const issued = Number(ts);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(issued) || now - issued > OAUTH_STATE_MAX_AGE_SECONDS) return false;
  const expected = await hmacSha256Hex(secret, `pua-oauth-state:${ts}`);
  return timingSafeEqual(signature, expected);
}

// Rate-limit buckets never store raw IPs: they store a salted SHA-256 digest.
export async function hashIp(ip: string): Promise<string> {
  return sha256Hex(`pua-ip:${ip}`);
}
