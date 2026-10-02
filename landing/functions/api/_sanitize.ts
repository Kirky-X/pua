// Server-side defense-in-depth redaction for uploaded session transcripts.
// Clients (hooks/stop-feedback.sh → hooks/sanitize-session.sh) already sanitize
// locally before upload; this pass catches anything that slipped through and is
// kept deliberately conservative so real conversation text survives analysis.
// Placeholder vocabulary matches hooks/sanitize-session.sh so the dataset
// stays uniform.

const REDACTIONS: ReadonlyArray<readonly [RegExp, string]> = [
  [/\bsk-[A-Za-z0-9_-]{16,}\b/g, "[API_KEY]"],
  [/\bsk-ant-[A-Za-z0-9_-]{16,}\b/g, "[API_KEY]"],
  [/ghp_[A-Za-z0-9]{20,}/g, "[API_KEY]"],
  [/gho_[A-Za-z0-9]{20,}/g, "[API_KEY]"],
  [/github_pat_[A-Za-z0-9_]{20,}/g, "[API_KEY]"],
  [/AKIA[0-9A-Z]{16}/g, "[API_KEY]"],
  [/ASIA[0-9A-Z]{16}/g, "[API_KEY]"],
  [/xox[baprs]-[A-Za-z0-9-]{10,}/g, "[API_KEY]"],
  [/AIza[A-Za-z0-9_-]{30,}/g, "[API_KEY]"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED]"],
  [/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, "[EMAIL]"],
  [/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, "[IP]"],
  [/\b(?:[A-F0-9]{1,4}:){4,7}[A-F0-9]{1,4}\b/gi, "[IP]"],
  // Unknown-format high-entropy secrets: long mixed-case+digits runs that are
  // not plain English words (session ids, bearer leftovers, connection strings).
  [/\b(?=[A-Za-z0-9_/+-]{32,})(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z0-9_/+-]{32,}\b/g, "[HIGH_ENTROPY_SECRET]"],
];

export function sanitize(raw: string): string {
  let out = raw;
  for (const [pattern, replacement] of REDACTIONS) {
    out = out.replace(pattern, replacement);
  }
  return out;
}
