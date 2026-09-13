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

# 双条件门控：挫败词只有在 failure-detector 记录了失败信号时才注入。
# should-trigger 用带失败计数的受控 HOME；should-not-trigger 用无失败信号的受控 HOME
# （避免读取测试机真实 ~/.pua 状态导致结果不稳定）。
HOME_WITH_FAILURE="${TMPDIR:-/tmp}/pua-trigger-home-fail-$$.d"
HOME_NO_FAILURE="${TMPDIR:-/tmp}/pua-trigger-home-clean-$$.d"
mkdir -p "$HOME_WITH_FAILURE/.pua" "$HOME_NO_FAILURE"
printf '2\n' > "$HOME_WITH_FAILURE/.pua/.failure_count"
printf 'trigger-test-session\n' > "$HOME_WITH_FAILURE/.pua/.failure_session"
trap 'rm -rf "$HOME_WITH_FAILURE" "$HOME_NO_FAILURE" "$TMP_CONFIG"' EXIT

json_prompt() {
  python3 -c 'import json,sys; print(json.dumps({"prompt":sys.argv[1]}, ensure_ascii=False))' "$1"
}

check_one() {
  local prompt="$1" expected="$2" label="$3"
  local out triggered trigger_home
  if [ "$expected" = "yes" ]; then trigger_home="$HOME_WITH_FAILURE"; else trigger_home="$HOME_NO_FAILURE"; fi
  out=$(json_prompt "$prompt" | PUA_FORCE_ON=1 PUA_CONFIG="$TMP_CONFIG" HOME="$trigger_home" bash "$HOOK" 2>/dev/null || true)
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
