// GET /api/auth/github — start the GitHub OAuth dance.
// Redirects to github.com/login/oauth/authorize with a signed, stateless
// anti-CSRF state (see _session.createOAuthState). The redirect_uri points back
// at /api/auth/callback on the same origin.

import { createOAuthState } from "../_session";

export interface Env {
  GITHUB_CLIENT_ID: string;
  SESSION_SECRET: string;
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  if (!env.GITHUB_CLIENT_ID || !env.SESSION_SECRET) {
    return new Response("GitHub login is not configured on this deployment", { status: 500 });
  }
  const url = new URL(request.url);
  const state = await createOAuthState(env.SESSION_SECRET);
  const authorizeUrl = new URL("https://github.com/login/oauth/authorize");
  authorizeUrl.searchParams.set("client_id", env.GITHUB_CLIENT_ID);
  authorizeUrl.searchParams.set("scope", "read:user");
  authorizeUrl.searchParams.set("state", state);
  authorizeUrl.searchParams.set("redirect_uri", `${url.origin}/api/auth/callback`);
  return new Response(null, {
    status: 302,
    headers: { Location: authorizeUrl.toString() },
  });
};
