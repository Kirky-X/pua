#!/usr/bin/env bash
# PUA Hook Unit Tests — CLI-independent
# Tests hooks by feeding mock JSON input and validating output/exit code.
# Usage: bash evals/test-hook-unit.sh
#
# These tests do NOT require the `claude` CLI. They directly invoke hook
# scripts with mock stdin payloads and verify stdout/exit-code behavior.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${PLUGIN_DIR}/hooks"

PASS=0
FAIL=0
TOTAL=0

# ── Test helpers ──────────────────────────────────────────────────────────────

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  ✅ PASS: $label (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (expected exit=$expected, got exit=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local label="$1" pattern="$2" output="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qE "$pattern" 2>/dev/null; then
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (pattern '$pattern' not found in output)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_not_contains() {
  local label="$1" pattern="$2" output="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qE "$pattern" 2>/dev/null; then
    echo "  ❌ FAIL: $label (pattern '$pattern' unexpectedly found)"
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# ── Setup: clean PUA state for isolated tests ────────────────────────────────

TEST_PUA_HOME=$(mktemp -d)
export HOME="$TEST_PUA_HOME"
export PUA_CONFIG="${TEST_PUA_HOME}/.pua/config.json"
mkdir -p "${TEST_PUA_HOME}/.pua"
echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"

cleanup() {
  rm -rf "$TEST_PUA_HOME"
}
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════
echo "═══ Test Group: flavor-helper.sh ═══"
# ══════════════════════════════════════════════════════════════════════════════

source "${HOOKS_DIR}/flavor-helper.sh"

# Test: default flavor (alibaba)
get_flavor
assert_exit "get_flavor default returns alibaba" 0 $?
TOTAL=$((TOTAL + 1))
if [[ "$PUA_FLAVOR" == "alibaba" ]]; then
  echo "  ✅ PASS: PUA_FLAVOR=alibaba"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: PUA_FLAVOR=$PUA_FLAVOR (expected alibaba)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [[ -n "$PUA_ICON" ]]; then
  echo "  ✅ PASS: PUA_ICON is set ($PUA_ICON)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: PUA_ICON is empty"
  FAIL=$((FAIL + 1))
fi

# Test: switch to musk flavor
echo '{"flavor":"musk"}' > "$PUA_CONFIG"
get_flavor
TOTAL=$((TOTAL + 1))
if [[ "$PUA_FLAVOR" == "musk" ]]; then
  echo "  ✅ PASS: PUA_FLAVOR=musk"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: PUA_FLAVOR=$PUA_FLAVOR (expected musk)"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
if [[ "$PUA_ICON" == "⬛" ]]; then
  echo "  ✅ PASS: Musk icon is ⬛"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Musk icon=$PUA_ICON (expected ⬛)"
  FAIL=$((FAIL + 1))
fi

# Test: Chinese language override for netflix
echo '{"flavor":"netflix","language":"zh"}' > "$PUA_CONFIG"
get_flavor
TOTAL=$((TOTAL + 1))
if echo "$PUA_L1" | grep -q "职业球队"; then
  echo "  ✅ PASS: Netflix zh override active"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Netflix zh override not applied (L1=$PUA_L1)"
  FAIL=$((FAIL + 1))
fi

# Test: unknown flavor falls back to alibaba
echo '{"flavor":"unknown_xyz"}' > "$PUA_CONFIG"
get_flavor
TOTAL=$((TOTAL + 1))
if [[ "$PUA_FLAVOR" == "alibaba" ]]; then
  echo "  ✅ PASS: Unknown flavor → alibaba fallback"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Unknown flavor=$PUA_FLAVOR (expected alibaba)"
  FAIL=$((FAIL + 1))
fi

# Test: Chinese alias flavors
echo '{"flavor":"字节"}' > "$PUA_CONFIG"
get_flavor
TOTAL=$((TOTAL + 1))
if [[ "$PUA_FLAVOR" == "bytedance" ]]; then
  echo "  ✅ PASS: 字节 → bytedance"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: 字节 → $PUA_FLAVOR (expected bytedance)"
  FAIL=$((FAIL + 1))
fi

# Restore default config
echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: failure-detector.sh ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test: non-Bash tool → silent exit
OUTPUT=$(echo '{"tool_name":"Read","tool_result":"content","session_id":"test"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_exit "Non-Bash tool exits silently" 0 ${#OUTPUT}
assert_output_not_contains "Non-Bash tool: no PUA output" "PUA" "$OUTPUT"

# Test: Bash tool with success → no pressure (first call)
OUTPUT=$(echo '{"tool_name":"Bash","tool_result":{"content":"ok","exit_code":0},"session_id":"test_fd"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_output_not_contains "Success: no pressure" "PUA L" "$OUTPUT"

# Test: Bash tool with error → first failure, no output (count=1 < 2)
# Clean state first
rm -f "${TEST_PUA_HOME}/.pua/.failure_count" "${TEST_PUA_HOME}/.pua/.failure_session"
OUTPUT=$(echo '{"tool_name":"Bash","tool_result":{"content":"error: command failed","exit_code":1},"session_id":"test_fd_err"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_output_not_contains "First failure: no intervention" "PUA L" "$OUTPUT"

# Test: 2 consecutive failures → L1 pressure
rm -f "${TEST_PUA_HOME}/.pua/.failure_count" "${TEST_PUA_HOME}/.pua/.failure_session"
echo '{"tool_name":"Bash","tool_result":{"content":"error: fail","exit_code":1},"session_id":"test_fd_l1"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" >/dev/null 2>&1 || true
OUTPUT=$(echo '{"tool_name":"Bash","tool_result":{"content":"error: fail again","exit_code":1},"session_id":"test_fd_l1"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_output_contains "2nd failure → L1 pressure" "PUA L1" "$OUTPUT"

# Test: always_on=false → skip injection
echo '{"always_on":false,"flavor":"alibaba"}' > "$PUA_CONFIG"
rm -f "${TEST_PUA_HOME}/.pua/.failure_count" "${TEST_PUA_HOME}/.pua/.failure_session"
echo '{"tool_name":"Bash","tool_result":{"content":"error","exit_code":1},"session_id":"test_off"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" >/dev/null 2>&1 || true
OUTPUT=$(echo '{"tool_name":"Bash","tool_result":{"content":"error","exit_code":1},"session_id":"test_off"}' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_output_not_contains "always_on=false: no output" "PUA" "$OUTPUT"
echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"

# Test: invalid JSON → graceful exit
OUTPUT=$(echo 'not json at all' | \
  bash "${HOOKS_DIR}/failure-detector.sh" 2>/dev/null || true)
assert_exit "Invalid JSON: graceful exit" 0 $?

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: timeout-helper.sh ═══"
# ══════════════════════════════════════════════════════════════════════════════

source "${HOOKS_DIR}/timeout-helper.sh"

# Test: command completes within timeout
OUTPUT=$(run_with_timeout 5 echo "hello" 2>/dev/null)
assert_output_contains "Timeout: echo completes" "hello" "$OUTPUT"

# Test: command killed by timeout
TOTAL=$((TOTAL + 1))
set +e
run_with_timeout 1 sleep 10 2>/dev/null
EXIT=$?
set -e
if [[ $EXIT -ne 0 ]]; then
  echo "  ✅ PASS: Timeout kills long-running command (exit=$EXIT)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: Timeout did not kill sleep (exit=$EXIT)"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: is_true / is_false helpers ═══"
# ══════════════════════════════════════════════════════════════════════════════

for val in true True TRUE 1 yes on; do
  TOTAL=$((TOTAL + 1))
  if is_true "$val" 2>/dev/null; then
    echo "  ✅ PASS: is_true('$val') = true"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: is_true('$val') should be true"
    FAIL=$((FAIL + 1))
  fi
done

for val in false False FALSE 0 no off; do
  TOTAL=$((TOTAL + 1))
  if is_false "$val" 2>/dev/null; then
    echo "  ✅ PASS: is_false('$val') = true"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: is_false('$val') should be true"
    FAIL=$((FAIL + 1))
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: flavors.json integrity ═══"
# ══════════════════════════════════════════════════════════════════════════════

FLAVORS_JSON="${HOOKS_DIR}/flavors.json"

# Test: valid JSON
TOTAL=$((TOTAL + 1))
if python3 -c "import json; json.load(open('$FLAVORS_JSON'))" 2>/dev/null; then
  echo "  ✅ PASS: flavors.json is valid JSON"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: flavors.json is invalid JSON"
  FAIL=$((FAIL + 1))
fi

# Test: all 15 flavors present
TOTAL=$((TOTAL + 1))
FLAVOR_COUNT=$(python3 -c "import json; d=json.load(open('$FLAVORS_JSON')); print(len([k for k in d if k != '_comment']))" 2>/dev/null)
if [[ "$FLAVOR_COUNT" == "15" ]]; then
  echo "  ✅ PASS: 15 flavors in JSON"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: $FLAVOR_COUNT flavors (expected 15)"
  FAIL=$((FAIL + 1))
fi

# Test: each flavor has required fields
TOTAL=$((TOTAL + 1))
MISSING=$(python3 -c "
import json
d = json.load(open('$FLAVORS_JSON'))
required = ['icon','l1','l2','l3','l4','keywords','instruction','methodology']
missing = []
for name, data in d.items():
    if name.startswith('_'): continue
    for field in required:
        if field not in data:
            missing.append(f'{name}.{field}')
print(len(missing))
" 2>/dev/null || echo "999")
if [[ "$MISSING" == "0" ]]; then
  echo "  ✅ PASS: All flavors have required fields"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: $MISSING missing fields"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════"
echo "  Hook Unit Tests: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
  echo "  ⚠️  $FAIL test(s) FAILED"
  echo "═══════════════════════════════════════"
  exit 1
else
  echo "  ✅ All tests passed"
  echo "═══════════════════════════════════════"
  exit 0
fi
