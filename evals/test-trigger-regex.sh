#!/usr/bin/env bash
# Fast hook-level trigger regression test. Does not call Claude model.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/frustration-trigger.sh"
TMP_CONFIG="${TMPDIR:-/tmp}/pua-trigger-regex-config-$$.json"
printf '%s\n' '{"always_on":false,"feedback_frequency":0}' > "$TMP_CONFIG"
trap 'rm -f "$TMP_CONFIG"' EXIT

PASS=0
FAIL=0

json_prompt() {
  python3 -c 'import json,sys; print(json.dumps({"prompt":sys.argv[1]}, ensure_ascii=False))' "$1"
}

check_one() {
  local prompt="$1" expected="$2" label="$3"
  local out triggered
  out=$(json_prompt "$prompt" | PUA_FORCE_ON=1 PUA_CONFIG="$TMP_CONFIG" bash "$HOOK" 2>/dev/null || true)
  if [ -n "$out" ]; then triggered=yes; else triggered=no; fi
  if [ "$triggered" = "$expected" ]; then
    printf '  ✅ %s: %s\n' "$label" "$prompt"
    PASS=$((PASS+1))
  else
    printf '  ❌ %s: expected=%s got=%s prompt=%s\n' "$label" "$expected" "$triggered" "$prompt"
    FAIL=$((FAIL+1))
  fi
}

while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  check_one "$line" yes should-trigger
done < "$SCRIPT_DIR/trigger-prompts/should-trigger.txt"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  check_one "$line" no should-not-trigger
done < "$SCRIPT_DIR/trigger-prompts/should-not-trigger.txt"

printf '\nPassed: %d\nFailed: %d\nTotal:  %d\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
