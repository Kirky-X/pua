// GET /api/auth/logout — clears the session cookie and returns the visitor to
// the contribution page, which then shows the logged-out notice.

import { clearSessionCookieHeader } from "../_session";

export const onRequestGet: PagesFunction = async () => {
  return new Response(null, {
    status: 302,
    headers: {
      Location: "/contribute.html?logout=1",
      "Set-Cookie": clearSessionCookieHeader(),
    },
  });
};
