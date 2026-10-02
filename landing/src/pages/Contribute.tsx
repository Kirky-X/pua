// Upload page: sends the sanitized .jsonl transcript as a raw JSONL body with
// metadata in headers — never as base64-in-JSON and never as multipart — so
// multi-MB session files do not bloat 33% in transit.

import { t } from "../i18n";
import { el } from "../dom";

export function renderContribute(root: HTMLElement): void {
  const params = new URLSearchParams(window.location.search);

  root.append(el({ tag: "h2", text: t("contributeTitle") }));
  root.append(el({ tag: "p", className: "muted", text: t("contributeIntro") }));
  root.append(el({ tag: "p", className: "muted", text: t("sanitizeNote") }));

  const notice =
    params.get("login") === "success"
      ? t("loginSuccess")
      : params.get("login") === "invalid_state"
        ? t("loginInvalidState")
        : params.get("logout") !== null
          ? t("logoutDone")
          : "";
  if (notice) {
    root.append(el({ tag: "p", className: "notice", text: notice }));
  }

  const status = el({ tag: "p", className: "status", attrs: { role: "status" } });
  const fileInput = el({
    tag: "input",
    attrs: { type: "file", accept: ".jsonl,application/jsonl,text/plain" },
  }) as HTMLInputElement;
  const wechatInput = el({
    tag: "input",
    attrs: { type: "text", name: "wechat_id", maxlength: "128", placeholder: t("wechatIdPlaceholder") },
  }) as HTMLInputElement;
  const consentInput = el({ tag: "input", attrs: { type: "checkbox", id: "upload-consent" } }) as HTMLInputElement;
  const submit = el({ tag: "button", attrs: { type: "submit" }, text: t("uploadButton") }) as HTMLButtonElement;

  const form = el({
    tag: "form",
    className: "upload-form",
    children: [
      el({ tag: "label", text: t("chooseFileLabel") }),
      fileInput,
      el({ tag: "label", text: t("wechatIdLabel") }),
      wechatInput,
      el({ tag: "label", className: "consent", children: [consentInput, t("consentLabel")] }),
      submit,
    ],
  });
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    void handleUpload();
  });
  root.append(form, status);

  async function handleUpload(): Promise<void> {
    status.textContent = "";
    const file = fileInput.files && fileInput.files.length > 0 ? fileInput.files[0] : null;
    if (!file) {
      status.textContent = t("chooseFileFirst");
      return;
    }
    if (!consentInput.checked) {
      status.textContent = t("consentRequired");
      return;
    }
    const text = await file.text();
    status.textContent = t("uploading");
    submit.disabled = true;
    try {
      const response = await fetch("/api/upload", {
        method: "POST",
        headers: {
          "Content-Type": "application/jsonl",
          "X-PUA-File-Name": file.name,
          "X-PUA-Wechat-Id": wechatInput.value.trim() || "not-provided",
          "X-PUA-Upload-Consent": "explicit",
        },
        body: text,
      });
      if (response.ok) {
        const result = (await response.json().catch(() => ({}))) as { source?: string };
        status.textContent = `${t("uploadSuccess")} (${result.source ?? "anonymous"})`;
      } else if (response.status === 429) {
        status.textContent = t("rateLimited");
      } else if (response.status === 401) {
        status.textContent = t("loginRequired");
      } else if (response.status === 403) {
        status.textContent = t("consentRequired");
      } else {
        status.textContent = t("uploadFailed");
      }
    } catch {
      status.textContent = t("uploadFailed");
    } finally {
      submit.disabled = false;
    }
  }
}
