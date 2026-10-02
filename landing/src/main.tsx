// Browser entry point: mounts the SPA router into #app once the DOM is ready.

import { mountApp } from "./App";

const root = document.getElementById("app");
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => mountApp(root));
} else {
  mountApp(root);
}
