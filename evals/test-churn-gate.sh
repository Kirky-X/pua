#!/usr/bin/env bash
# Verifies churn-gate.sh: deterministic review gating on large/thrashing diffs.
# Fixture: tmp git repo; threshold firing requires changes to TRACKED files
# (git diff does not cover untracked files — by design, the gate only counts
# real worktree diffs against the baseline commit).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/churn-gate.sh"

PASS=0
FAIL=0
record_pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
record_fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_T="$TMP_ROOT/home"
PROJ="$TMP_ROOT/proj"
NOPROJ="$TMP_ROOT/nogit"
mkdir -p "$HOME_T/.pua" "$PROJ" "$NOPROJ"
printf '%s\n' '{"always_on":true}' > "$HOME_T/.pua/config.json"

git -C "$PROJ" init -q
echo base > "$PROJ/f.txt"
git -C "$PROJ" add f.txt
git -C "$PROJ" -c user.email=test@test -c user.name=test commit -q -m base

make_input() {
  local session="$1" cwd="$2"
  printf '%s' '{"hook_event_name":"PostToolUse","session_id":"'"$session"'","cwd":"'"$cwd"'","tool_name":"Edit","tool_input":{"file_path":"f.txt"}}'
}

run_gate() {
  local session="$1" cwd="$2"
  (cd "$cwd" && HOME="$HOME_T" bash "$HOOK" <<<"$(make_input "$session" "$cwd")")
}

echo "=== PUA Churn Gate Tests ==="

# Non-git directory: silent fail-open.
OUT=$(run_gate "nongit-session" "$NOPROJ")
if [ -z "$OUT" ]; then
  record_pass "non-git directory stays silent"
else
  record_fail "non-git directory stays silent"
  printf '%s\n' "$OUT"
fi

# First sighting: arms the session, stays silent.
OUT=$(run_gate "churn-session" "$PROJ")
if [ -z "$OUT" ]; then
  record_pass "first sighting arms silently"
else
  record_fail "first sighting arms silently"
  printf '%s\n' "$OUT"
fi

# 400+ net lines in one window: fires the review injection exactly once.
seq 1 450 >> "$PROJ/f.txt"
OUT=$(run_gate "churn-session" "$PROJ")
if grep -q '\[PUA Churn Gate\]' <<<"$OUT" && grep -q '三维审查' <<<"$OUT"; then
  record_pass "450-line net churn fires review gate"
else
  record_fail "450-line net churn fires review gate"
  printf '%s\n' "$OUT"
fi

# Re-arm: second event with no new churn must NOT repeat.
OUT=$(run_gate "churn-session" "$PROJ")
if [ -z "$OUT" ]; then
  record_pass "re-arm prevents immediate repeat"
else
  record_fail "re-arm prevents immediate repeat"
  printf '%s\n' "$OUT"
fi

# Gross thrashing: +200/-200 cycles stay under net threshold but accumulate
# gross ≥ 800 → fires (catches write-delete-write-delete churn).
run_gate "thrash-session" "$PROJ" >/dev/null
seq 1 200 >> "$PROJ/f.txt"
run_gate "thrash-session" "$PROJ" >/dev/null
head -1 "$PROJ/f.txt" > "$PROJ/.trim" && mv "$PROJ/.trim" "$PROJ/f.txt"
run_gate "thrash-session" "$PROJ" >/dev/null
seq 1 200 >> "$PROJ/f.txt"
run_gate "thrash-session" "$PROJ" >/dev/null
head -1 "$PROJ/f.txt" > "$PROJ/.trim" && mv "$PROJ/.trim" "$PROJ/f.txt"
run_gate "thrash-session" "$PROJ" >/dev/null
seq 1 200 >> "$PROJ/f.txt"
run_gate "thrash-session" "$PROJ" >/dev/null
head -1 "$PROJ/f.txt" > "$PROJ/.trim" && mv "$PROJ/.trim" "$PROJ/f.txt"
OUT=$(run_gate "thrash-session" "$PROJ")
if grep -q '\[PUA Churn Gate\]' <<<"$OUT"; then
  record_pass "gross thrashing (4x200 churn) fires review gate"
else
  record_fail "gross thrashing (4x200 churn) fires review gate"
  printf '%s\n' "$OUT"
  cat "$HOME_T/.pua/churn-thrash-session.json" 2>/dev/null || true
fi

# Thresholds configurable via ~/.pua/config.json (review_net_threshold=1).
printf '%s\n' '{"always_on":true,"review_net_threshold":1}' > "$HOME_T/.pua/config.json"
run_gate "config-session" "$PROJ" >/dev/null
echo tiny >> "$PROJ/f.txt"
OUT=$(run_gate "config-session" "$PROJ")
if grep -q '\[PUA Churn Gate\]' <<<"$OUT"; then
  record_pass "review_net_threshold override honored"
else
  record_fail "review_net_threshold override honored"
  printf '%s\n' "$OUT"
fi

# always_on=false: gate disabled entirely.
printf '%s\n' '{"always_on":false}' > "$HOME_T/.pua/config.json"
run_gate "off-session" "$PROJ" >/dev/null
echo more >> "$PROJ/f.txt"
OUT=$(run_gate "off-session" "$PROJ")
if [ -z "$OUT" ]; then
  record_pass "always_on=false disables gate"
else
  record_fail "always_on=false disables gate"
  printf '%s\n' "$OUT"
fi

echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
