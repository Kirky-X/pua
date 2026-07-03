#!/usr/bin/env bash
# Verifies pua-loop Oracle hook behavior without relying on Claude CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

cwd_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$1" | md5sum | cut -c1-8
  else
    printf '%s' "$1" | md5 | cut -c1-8
  fi
}

record_pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
record_fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

make_transcript() {
  local path="$1"
  local text="$2"
  python3 - "$path" "$text" <<'PY'
import json, sys
path, text = sys.argv[1], sys.argv[2]
with open(path, 'w', encoding='utf-8') as f:
    f.write(json.dumps({"role":"assistant","message":{"content":[{"type":"text","text":text}]}}, separators=(",",":")) + "\n")
PY
}

run_hook() {
  local home="$1"
  local project="$2"
  local transcript="$3"
  local session_id="${4:-test-session}"
  local input
  input=$(jq -nc --arg transcript_path "$transcript" --arg session_id "$session_id" '{hook_event_name:"Stop",transcript_path:$transcript_path,session_id:$session_id}')
  (cd "$project" && HOME="$home" bash "$PLUGIN_DIR/hooks/pua-loop-hook.sh" <<<"$input")
}

create_state() {
  local home="$1"
  local project="$2"
  local verify_command="$3"
  local hash state
  hash=$(cwd_hash "$project")
  mkdir -p "$home/.claude/pua" "$project/.claude"
  state="$home/.claude/pua/loop-${hash}.md"
  cat > "$state" <<STATE
---
active: true
iteration: 1
session_id: test-session
max_iterations: 0
completion_promise: "DONE"
verify_command: "$verify_command"
promise_rejections: 0
started_cwd: "$project"
---

Test prompt
STATE
  printf '%s\n' "$state"
}

echo "=== PUA Loop Hook Oracle Tests ==="

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# Success path: verified promise removes state.
HOME1="$TMP_ROOT/home-success"
PROJ1="$TMP_ROOT/project-success"
mkdir -p "$HOME1" "$PROJ1"
STATE1=$(create_state "$HOME1" "$PROJ1" "true")
TRANSCRIPT1="$PROJ1/transcript.jsonl"
make_transcript "$TRANSCRIPT1" '<promise>DONE</promise>'
OUT1=$(run_hook "$HOME1" "$PROJ1" "$TRANSCRIPT1")
if grep -q 'verified by Oracle' <<<"$OUT1" && [ ! -f "$STATE1" ]; then
  record_pass "verified promise exits and removes state"
else
  record_fail "verified promise exits and removes state"
  printf '%s\n' "$OUT1"
fi

# Failure path: rejected promise blocks Stop and increments counters.
HOME2="$TMP_ROOT/home-fail"
PROJ2="$TMP_ROOT/project-fail"
mkdir -p "$HOME2" "$PROJ2"
STATE2=$(create_state "$HOME2" "$PROJ2" "false")
TRANSCRIPT2="$PROJ2/transcript.jsonl"
make_transcript "$TRANSCRIPT2" '<promise>DONE</promise>'
OUT2=$(run_hook "$HOME2" "$PROJ2" "$TRANSCRIPT2")
if grep -q '"decision": "block"' <<<"$OUT2" && grep -q '^iteration: 2$' "$STATE2" && grep -q '^promise_rejections: 1$' "$STATE2"; then
  record_pass "failed verify blocks and records rejection"
else
  record_fail "failed verify blocks and records rejection"
  printf '%s\n' "$OUT2"
  cat "$STATE2" || true
fi

# Setup integration: quoted verify commands from the documented examples remain executable.
HOME3="$TMP_ROOT/home-quoted"
PROJ3="$TMP_ROOT/project-quoted"
mkdir -p "$HOME3" "$PROJ3"
(
  cd "$PROJ3"
  HOME="$HOME3" CLAUDE_CODE_SESSION_ID="test-session" bash "$PLUGIN_DIR/scripts/setup-pua-loop.sh" \
    'quoted verify smoke' \
    --completion-promise 'DONE' \
    --verify 'python3 -c "print(123)"' >/tmp/pua-loop-setup-test.out
)
HASH3=$(cwd_hash "$PROJ3")
STATE3="$HOME3/.claude/pua/loop-${HASH3}.md"
TRANSCRIPT3="$PROJ3/transcript.jsonl"
make_transcript "$TRANSCRIPT3" '<promise>DONE</promise>'
OUT3=$(run_hook "$HOME3" "$PROJ3" "$TRANSCRIPT3")
if grep -q 'verified by Oracle' <<<"$OUT3" && [ ! -f "$STATE3" ]; then
  record_pass "setup-created quoted verify command executes"
else
  record_fail "setup-created quoted verify command executes"
  printf '%s\n' "$OUT3"
  cat "$STATE3" || true
fi

echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
