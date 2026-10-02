// Landing SPA router. Framework-free on purpose: the router resolves the route
// from window.location.pathname first (so /contribute.html and /admin.html are
// real deep links served by Pages) and falls back to the hash (#/contribute,
// #/admin/heartbeats) for static hosts without rewrite rules.
//
// The GitHub OAuth round-trip lands back here: /api/auth/callback and
// /api/auth/logout both redirect to /contribute.html with a ?login= / ?logout=
// query, and the contribute page turns those into status notices.

import { currentLocaleName, detectLocale, FLAVORS, t } from "./i18n";
import { el } from "./dom";
import { renderContribute } from "./pages/Contribute";
import { renderAdminStats } from "./pages/AdminStats";

export type RouteName = "home" | "contribute" | "admin";

export function resolveRoute(pathname: string, hash: string): RouteName {
  if (pathname === "/contribute" || pathname === "/contribute.html") return "contribute";
  if (pathname === "/admin" || pathname === "/admin.html" || pathname.startsWith("/admin/")) return "admin";
  if (hash.startsWith("#/contribute")) return "contribute";
  if (hash.startsWith("#/admin/heartbeats") || hash.startsWith("#/admin")) return "admin";
  return "home";
}

function navBar(): HTMLElement {
  return el({
    tag: "header",
    className: "topbar",
    children: [
      el({
        tag: "nav",
        className: "container nav",
        children: [
          el({ tag: "a", className: "brand", text: "PUA Skill", attrs: { href: "/" } }),
          el({ tag: "a", text: t("navHome"), attrs: { href: "/" } }),
          el({ tag: "a", text: t("navContribute"), attrs: { href: "/contribute.html" } }),
          el({ tag: "a", text: t("navAdmin"), attrs: { href: "/#/admin/heartbeats" } }),
        ],
      }),
    ],
  });
}

function footer(): HTMLElement {
  return el({
    tag: "footer",
    className: "footer",
    children: [el({ tag: "p", className: "container muted", text: t("footerNote") })],
  });
}

function renderHome(root: HTMLElement): void {
  root.append(el({ tag: "h1", text: "PUA Skill" }));
  root.append(el({ tag: "p", className: "tagline", text: t("tagline") }));
  root.append(el({ tag: "p", text: t("homeIntro") }));
  root.append(
    el({
      tag: "p",
      className: "cta",
      children: [el({ tag: "a", className: "button", text: t("homeCta"), attrs: { href: "/contribute.html" } })],
    }),
  );
  root.append(el({ tag: "h2", text: t("flavorsHeading") }));
  const locale = currentLocaleName();
  const grid = el({ tag: "ul", className: "flavor-grid" });
  for (const flavor of FLAVORS) {
    grid.append(
      el({
        tag: "li",
        className: `flavor-card flavor-${flavor.id}`,
        children: [
          el({ tag: "span", className: "flavor-icon", text: flavor.icon }),
          el({ tag: "p", className: "flavor-label", text: flavor.label[locale] }),
        ],
      }),
    );
  }
  root.append(grid);
}

function renderShell(route: RouteName): HTMLElement {
  const content = el({ tag: "main", className: "container" });
  if (route === "contribute") {
    renderContribute(content);
  } else if (route === "admin") {
    renderAdminStats(content);
  } else {
    renderHome(content);
  }
  return el({
    tag: "div",
    className: "shell",
    children: [navBar(), content, footer()],
  });
}

export function mountApp(root: HTMLElement | null): void {
  if (!root) return;
  detectLocale();
  const render = (): void => {
    root.textContent = "";
    root.append(renderShell(resolveRoute(window.location.pathname, window.location.hash)));
  };
  render();
  window.addEventListener("hashchange", render);
}
