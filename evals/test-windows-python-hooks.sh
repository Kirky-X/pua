#!/usr/bin/env bash
# Regression tests for issue #159: Windows Git Bash uses POSIX-looking HOME
# paths (/c/Users/...) while native Windows Python expects C:\... paths, and
# some Windows setups provide `python` but not `python3`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

record_pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
record_fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN" "$TMP_ROOT/home/.pua"
CONFIG="$TMP_ROOT/home/.pua/config.json"
printf '%s\n' '{"always_on":false,"feedback_frequency":0,"flavor":"netflix","language":""}' > "$CONFIG"

cat > "$FAKE_BIN/python3" <<'PY3'
#!/usr/bin/env bash
exit 127
PY3
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/cygpath" <<'CYG'
#!/usr/bin/env bash
if [ "${1:-}" = "-w" ]; then
  shift
  # The exact drive is irrelevant to the hooks; the fake python below rejects
  # unconverted POSIX paths and accepts Windows-looking paths.
  printf 'C:\\pua-test%s\n' "${1//\//\\}"
else
  printf '%s\n' "$1"
fi
CYG
chmod +x "$FAKE_BIN/cygpath"

cat > "$FAKE_BIN/python" <<'PY'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-" ]; then
  # Simulate integrity-guard.py under always_on=false: parse succeeds and the
  # guard stays silent/inactive.
  cat >/dev/null
  exit 0
fi
if [ "${1:-}" = "-c" ]; then
  code="${2:-}"
  shift 2
  for arg in "$@"; do
    case "$arg" in
      /*)
        echo "native Windows python cannot open POSIX path: $arg" >&2
        exit 2
        ;;
    esac
  done
  args=" $* "
  case "$code $args" in
    *always_on*) printf 'False\n' ;;
    *feedback_frequency*) printf '0\n' ;;
    *flavor*) printf 'netflix\n' ;;
    *language*) printf '\n' ;;
    *session_id*) printf 'test-session\n' ;;
    *tool_name*) printf 'Bash\n' ;;
    *exit_code*) printf '1\n' ;;
    *tool_result*) printf 'Error: simulated failure\n' ;;
    *) printf '\n' ;;
  esac
  exit 0
fi
exit 0
PY
chmod +x "$FAKE_BIN/python"

RUN_ENV=(env PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$TMP_ROOT/home" PUA_CONFIG="$CONFIG")

assert_no_output_success() {
  local name="$1"; shift
  local outfile="$TMP_ROOT/out.txt"
  local errfile="$TMP_ROOT/err.txt"
  if "${RUN_ENV[@]}" "$@" >"$outfile" 2>"$errfile" && [ ! -s "$outfile" ]; then
    record_pass "$name"
  else
    record_fail "$name"
    echo "--- stdout ---"; cat "$outfile" || true
    echo "--- stderr ---"; cat "$errfile" || true
  fi
}

echo "=== Windows Python Hook Compatibility Tests ==="

assert_no_output_success "/pua:off suppresses UserPromptSubmit with python fallback" \
  bash "$PLUGIN_DIR/hooks/frustration-trigger.sh"

assert_no_output_success "SessionStart off config does not crash without python3" \
  bash "$PLUGIN_DIR/hooks/session-restore.sh" <<<'{"hook_event_name":"SessionStart"}'

HOOK_FAILURE_INPUT='{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":"win-test","tool_result":{"exit_code":1,"content":"Error: simulated failure"}}'
assert_no_output_success "PostToolUse failure detector respects /pua:off with python fallback" \
  bash "$PLUGIN_DIR/hooks/failure-detector.sh" <<<"$HOOK_FAILURE_INPUT"

TRANSCRIPT="$TMP_ROOT/transcript.jsonl"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"PUA生效"}]}}' > "$TRANSCRIPT"
printf '4' > "$TMP_ROOT/home/.pua/.stop_counter"
STOP_INPUT="{"hook_event_name":"Stop","transcript_path":"$TRANSCRIPT"}"
assert_no_output_success "Stop feedback respects feedback_frequency=0 with python fallback" \
  bash "$PLUGIN_DIR/hooks/stop-feedback.sh" <<<"$STOP_INPUT"

OUT=$("${RUN_ENV[@]}" bash -c 'source "$1/hooks/flavor-helper.sh"; get_flavor; printf "%s" "$PUA_FLAVOR"' bash "$PLUGIN_DIR" 2>"$TMP_ROOT/flavor.err" || true)
if [ "$OUT" = "netflix" ]; then
  record_pass "flavor-helper reads config using python fallback + cygpath"
else
  record_fail "flavor-helper reads config using python fallback + cygpath"
  echo "flavor=$OUT"; cat "$TMP_ROOT/flavor.err" || true
fi

HOOK_INPUT='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"tests/foo.test.ts"},"transcript_path":"/missing"}'
assert_no_output_success "Integrity guard honors always_on=false without python3" \
  bash "$PLUGIN_DIR/hooks/integrity-guard.sh" <<<"$HOOK_INPUT"

echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
