#!/usr/bin/env bash
# PUA test-first hook unit tests — CLI-independent
# Usage: bash evals/test-test-first.sh

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${PLUGIN_DIR}/hooks/test-first.sh"

PASS=0
FAIL=0
TOTAL=0

assert_output_contains() {
  local label="$1" pattern="$2" output="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qE "$pattern" 2>/dev/null; then
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (pattern '$pattern' not found)"
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

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  ✅ PASS: $label (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (expected exit=$expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

TEST_PUA_HOME=$(mktemp -d)
export HOME="$TEST_PUA_HOME"
export PUA_CONFIG="${TEST_PUA_HOME}/.pua/config.json"
mkdir -p "${TEST_PUA_HOME}/.pua"
echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"

TF_RUN() {
  echo "$1" | bash "$HOOK" 2>/dev/null || true
}
TF_CLEAN() {
  rm -rf "${TEST_PUA_HOME}/.pua/sessions"
}

echo "═══ Test Group: test-first.sh ═══"

# Test: non-code, non-test events are silent
OUTPUT=$(TF_RUN '{"tool_name":"Edit","tool_input":{"file_path":"/x/README.md"},"session_id":"tf0"}')
assert_output_not_contains "Docs edit is silent" "PUA" "$OUTPUT"

# Test: 3 source edits without tests → needs_test reminder
TF_CLEAN
OUTPUT=""
for i in 1 2 3; do
  OUTPUT=$(TF_RUN "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/app${i}.ts\"},\"session_id\":\"tf1\"}")
done
assert_output_contains "3rd source edit → test reminder" "PUA TDD" "$OUTPUT"

# Test: writing a test is a quiet transition
OUTPUT=$(TF_RUN '{"tool_name":"Write","tool_input":{"file_path":"/x/app.test.ts"},"session_id":"tf1"}')
assert_output_not_contains "Test write is quiet" "PUA" "$OUTPUT"

# Test: passing test in needs_red → vacuous test warning
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":0},"tool_input":{"command":"npm test"},"session_id":"tf1"}')
assert_output_contains "Green without red → vacuous warning" "空洞测试" "$OUTPUT"

# Test: failing test in needs_red → green phase message
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":1},"tool_input":{"command":"npm test"},"session_id":"tf1"}')
assert_output_contains "Red seen → implement phase" "红已见到" "$OUTPUT"

# Test: passing test in needs_green → loop closed
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":0},"tool_input":{"command":"npm test"},"session_id":"tf1"}')
assert_output_contains "Green after red → closed" "闭环完成" "$OUTPUT"

# Test: pytest and test_ prefix recognized (python project path)
TF_CLEAN
for i in 1 2 3; do
  TF_RUN "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/mod${i}.py\"},\"session_id\":\"tf2\"}" >/dev/null
done
TF_RUN '{"tool_name":"Write","tool_input":{"file_path":"/x/test_mod.py"},"session_id":"tf2"}' >/dev/null
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":1},"tool_input":{"command":"python3 -m pytest test_mod.py"},"session_id":"tf2"}')
assert_output_contains "pytest red → green phase" "红已见到" "$OUTPUT"

# Test: non-test command in tracking phases is silent
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":0},"tool_input":{"command":"ls -la"},"session_id":"tf2"}')
assert_output_not_contains "Non-test command silent" "PUA" "$OUTPUT"

# Test: session isolation — another session starts idle
OUTPUT=$(TF_RUN '{"tool_name":"Bash","tool_result":{"exit_code":0},"tool_input":{"command":"npm test"},"session_id":"tf_fresh"}')
assert_output_not_contains "Fresh session idle: silent" "PUA" "$OUTPUT"

# Test: always_on=false → silent
echo '{"always_on":false,"flavor":"alibaba"}' > "$PUA_CONFIG"
OUTPUT=$(TF_RUN '{"tool_name":"Edit","tool_input":{"file_path":"/x/a.rb"},"session_id":"tf3"}')
assert_output_not_contains "always_on=false silent" "PUA" "$OUTPUT"
echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"

# Test: invalid JSON → graceful exit
set +e
TF_RUN 'garbage' >/dev/null 2>&1
EXIT=$?
set -e
assert_exit "Invalid JSON: graceful exit" 0 "$EXIT"

# Cleanup
rm -rf "$TEST_PUA_HOME"

echo ""
echo "═══════════════════════════════════════"
echo "  test-first Tests: ${PASS}/${TOTAL} passed"
if [[ $FAIL -eq 0 ]]; then
  echo "  ✅ All tests passed"
else
  echo "  ❌ ${FAIL} tests failed"
  exit 1
fi
echo "═══════════════════════════════════════"
