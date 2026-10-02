// Admin page: heartbeat stats behind the ADMIN_GITHUB_LOGINS allowlist.
// Anonymous visitors get the GitHub login entry point; non-admin logins get a
// clear 403 message from /api/heartbeat.

import { t } from "../i18n";
import { el } from "../dom";

interface HeartbeatStats {
  window_days: number;
  active_installs: number;
  total_installs: number;
  by_flavor: Array<{ flavor: string; installs: number }>;
  by_platform: Array<{ platform: string; installs: number }>;
  by_version: Array<{ plugin_version: string; installs: number }>;
}

export function renderAdminStats(root: HTMLElement): void {
  root.append(el({ tag: "h2", text: t("adminTitle") }));
  const status = el({ tag: "p", className: "muted" });
  root.append(status);

  void (async () => {
    try {
      const response = await fetch("/api/heartbeat", { credentials: "same-origin" });
      if (response.status === 401) {
        status.textContent = t("adminLoginPrompt");
        root.append(
          el({
            tag: "a",
            className: "button",
            text: t("adminLoginButton"),
            attrs: { href: "/api/auth/github" },
          }),
        );
        return;
      }
      if (response.status === 403) {
        status.textContent = t("adminForbidden");
        return;
      }
      if (!response.ok) {
        status.textContent = t("adminLoadFailed");
        return;
      }
      const stats = (await response.json()) as HeartbeatStats;
      status.remove();

      const cards = el({
        tag: "div",
        className: "stat-cards",
        children: [
          el({
            tag: "div",
            className: "stat-card",
            children: [
              el({ tag: "strong", text: String(stats.total_installs) }),
              el({ tag: "span", text: t("statTotalInstalls") }),
            ],
          }),
          el({
            tag: "div",
            className: "stat-card",
            children: [
              el({ tag: "strong", text: String(stats.active_installs) }),
              el({ tag: "span", text: `${t("statActiveInstalls")} · ${stats.window_days}d ${t("statWindowDays")}` }),
            ],
          }),
        ],
      });
      root.append(cards, breakdownTable(t("tableFlavor"), "flavor", stats.by_flavor));
      root.append(breakdownTable(t("tablePlatform"), "platform", stats.by_platform));
      root.append(breakdownTable(t("tableVersion"), "plugin_version", stats.by_version));
    } catch {
      status.textContent = t("adminLoadFailed");
    }
  })();
}

function breakdownTable(
  heading: string,
  key: "flavor" | "platform" | "plugin_version",
  rows: ReadonlyArray<Record<string, unknown>>,
): HTMLElement {
  const body = el({ tag: "tbody" });
  for (const row of rows) {
    body.append(
      el({
        tag: "tr",
        children: [
          el({ tag: "td", text: String(row[key] ?? "unknown") }),
          el({ tag: "td", text: String(row["installs"] ?? 0) }),
        ],
      }),
    );
  }
  return el({
    tag: "table",
    className: "breakdown",
    children: [
      el({
        tag: "thead",
        children: [
          el({
            tag: "tr",
            children: [el({ tag: "th", text: heading }), el({ tag: "th", text: t("tableInstalls") })],
          }),
        ],
      }),
      body,
    ],
  });
}
