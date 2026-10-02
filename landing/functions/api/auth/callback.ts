// GET /api/auth/callback — GitHub OAuth redirect URI.
// Exchanges the code for an access token, reads the GitHub login, mints the
// signed session cookie and returns the visitor to the contribution page.

import { createSessionToken, sessionCookieHeader, verifyOAuthState } from "../_session";

export interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  SESSION_SECRET: string;
}

function backToContribute(cookie: string | null, query: string): Response {
  const headers = new Headers({ Location: `/contribute.html?${query}` });
  if (cookie) headers.set("Set-Cookie", cookie);
  return new Response(null, { status: 302, headers });
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  if (!env.GITHUB_CLIENT_ID || !env.GITHUB_CLIENT_SECRET || !env.SESSION_SECRET) {
    return backToContribute(null, "login=unconfigured");
  }
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state || !(await verifyOAuthState(env.SESSION_SECRET, state))) {
    return backToContribute(null, "login=invalid_state");
  }

  const tokenResponse = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "User-Agent": "pua-skill-landing",
    },
    body: JSON.stringify({
      client_id: env.GITHUB_CLIENT_ID,
      client_secret: env.GITHUB_CLIENT_SECRET,
      code,
      redirect_uri: `${url.origin}/api/auth/callback`,
    }),
  });
  const tokenPayload = (await tokenResponse.json().catch(() => null)) as { access_token?: unknown } | null;
  const accessToken = typeof tokenPayload?.access_token === "string" ? tokenPayload.access_token : "";
  if (!accessToken) {
    return backToContribute(null, "login=token_exchange_failed");
  }

  const userResponse = await fetch("https://api.github.com/user", {
    headers: { Authorization: `Bearer ${accessToken}`, "User-Agent": "pua-skill-landing" },
  });
  const user = (await userResponse.json().catch(() => null)) as { login?: unknown } | null;
  const login = typeof user?.login === "string" ? user.login : "";
  if (!login) {
    return backToContribute(null, "login=profile_failed");
  }

  const token = await createSessionToken(login, env.SESSION_SECRET);
  return backToContribute(sessionCookieHeader(token), "login=success");
};
