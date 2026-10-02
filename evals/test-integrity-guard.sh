#!/usr/bin/env bash
# Verifies PUA Integrity Guard anti-cheating decisions without Claude CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/integrity-guard.sh"

PASS=0
FAIL=0
record_pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
record_fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

json_input() {
  local tool="$1"
  local payload="$2"
  python3 - "$tool" "$payload" <<'PY'
import json, sys
print(json.dumps({
  "hook_event_name": "PreToolUse",
  "session_id": "test-session",
  "transcript_path": "/nonexistent/transcript.jsonl",
  "cwd": "/tmp/pua-integrity-test",
  "tool_name": sys.argv[1],
  "tool_input": json.loads(sys.argv[2]),
}, separators=(",", ":")))
PY
}

run_guard() {
  local force="$1"
  local tool="$2"
  local payload="$3"
  local hook_home="${4:-}"
  local env_home=""
  if [ -n "$hook_home" ]; then
    # Isolated HOME: keeps the deny audit log (Path.home()/.pua/audit.jsonl)
    # out of the tester's real home directory.
    if [ "$force" = "force" ]; then
      HOME="$hook_home" PUA_INTEGRITY_FORCE=1 PUA_CONFIG=/nonexistent/pua-config.json bash "$HOOK" <<<"$(json_input "$tool" "$payload")"
    else
      HOME="$hook_home" PUA_CONFIG=/nonexistent/pua-config.json bash "$HOOK" <<<"$(json_input "$tool" "$payload")"
    fi
  elif [ "$force" = "force" ]; then
    PUA_INTEGRITY_FORCE=1 PUA_CONFIG=/nonexistent/pua-config.json bash "$HOOK" <<<"$(json_input "$tool" "$payload")"
  else
    PUA_CONFIG=/nonexistent/pua-config.json bash "$HOOK" <<<"$(json_input "$tool" "$payload")"
  fi
}

assert_decision() {
  local name="$1"
  local output="$2"
  local expected="$3"
  local contains="$4"
  if python3 - "$output" "$expected" "$contains" <<'PY'
import json, sys
out, expected, contains = sys.argv[1:]
try:
    data = json.loads(out)
except Exception as exc:
    print(f"invalid json: {exc}; output={out!r}")
    sys.exit(1)
specific = data.get('hookSpecificOutput', {})
actual = specific.get('permissionDecision')
reason = specific.get('permissionDecisionReason', '')
if actual != expected:
    print(f"decision mismatch: expected={expected} actual={actual} reason={reason}")
    sys.exit(1)
if contains not in reason:
    print(f"reason missing {contains!r}: {reason}")
    sys.exit(1)
PY
  then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_empty() {
  local name="$1"
  local output="$2"
  if [ -z "$output" ]; then record_pass "$name"; else record_fail "$name"; printf '%s\n' "$output"; fi
}

assert_advisory() {
  local name="$1"
  local output="$2"
  local contains="$3"
  if python3 - "$output" "$contains" <<'PY'
import json, sys
out, contains = sys.argv[1:]
try:
    data = json.loads(out)
except Exception as exc:
    print(f"invalid json: {exc}; output={out!r}")
    sys.exit(1)
specific = data.get('hookSpecificOutput', {})
actual = specific.get('permissionDecision')
context = specific.get('additionalContext', '')
reason = specific.get('permissionDecisionReason')
if actual is not None:
    print(f"expected advisory-only with no permissionDecision, actual={actual} reason={reason}")
    sys.exit(1)
if reason is not None:
    print(f"expected no permissionDecisionReason for advisory-only output, got={reason!r}")
    sys.exit(1)
if contains not in context:
    print(f"additionalContext missing {contains!r}: {context}")
    sys.exit(1)
PY
  then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

assert_no_permission_ask() {
  local name="$1"
  local output="$2"
  if python3 - "$output" <<'PY'
import json, sys
out = sys.argv[1]
if not out:
    sys.exit(0)
try:
    data = json.loads(out)
except Exception as exc:
    print(f"invalid json: {exc}; output={out!r}")
    sys.exit(1)
actual = data.get('hookSpecificOutput', {}).get('permissionDecision')
if actual == 'ask':
    print('permissionDecision=ask is forbidden; use advisory additionalContext or deny')
    sys.exit(1)
PY
  then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

echo "=== PUA Integrity Guard Tests ==="

OUT=$(run_guard inactive Write '{"file_path":"/repo/tests/auth.test.ts","content":"skip"}')
assert_empty "inactive guard stays silent" "$OUT"

OUT=$(run_guard force Write '{"file_path":"/repo/tests/auth.test.ts","content":"skip"}')
assert_advisory "protected test write is advisory-only" "$OUT" "Grader gaming risk"

OUT=$(run_guard force Write '{"file_path":"/repo/src/auth.ts","content":"code"}')
assert_empty "ordinary source write allowed" "$OUT"

OUT=$(run_guard force Write '{"file_path":"/repo/memory/session.md","content":"state"}')
assert_advisory "memory write is advisory-only" "$OUT" "Persistent-memory risk"

OUT=$(run_guard force Edit '{"file_path":"/repo/CLAUDE.md","old_string":"old","new_string":"new"}')
assert_advisory "CLAUDE.md edit is advisory-only" "$OUT" "Persistent-memory risk"

OUT=$(run_guard force Write '{"file_path":"/repo/.claude/settings.json","content":"{}"}')
assert_advisory "settings.json write is advisory-only" "$OUT" "Persistent-memory risk"

OUT=$(run_guard force Bash '{"command":"sed -i \"\" \"s/pass/skip/\" tests/auth.test.ts"}')
assert_advisory "mutating bash on tests is advisory-only" "$OUT" "Grader gaming risk"

OUT=$(run_guard force Bash '{"command":"cat tests/auth.test.ts"}')
assert_empty "read-only bash on public tests allowed" "$OUT"

OUT=$(run_guard force Read '{"file_path":"/repo/verifier_private/hidden_tests/case.json"}')
assert_decision "hidden verifier read denied" "$OUT" "deny" "Solution contamination risk"

OUT=$(run_guard force Bash '{"command":"cat hidden_tests/case.json"}')
assert_decision "relative hidden-test bash read denied" "$OUT" "deny" "Solution contamination risk"

OUT=$(run_guard force Bash '{"command":"python3 -c '"'"'open(\"tests/fixtures.json\",\"w\").write(\"{}\")'"'"'"}')
assert_advisory "mutating bash on tests directory is advisory-only" "$OUT" "Grader gaming risk"

OUT=$(run_guard force Glob '{"pattern":"**/hidden_tests/**","path":"/repo"}')
assert_decision "glob hidden tests denied" "$OUT" "deny" "Solution contamination risk"

OUT=$(run_guard force Grep '{"pattern":"token","path":"/repo","glob":"**/hidden_solution/*.json"}')
assert_decision "grep hidden solution glob denied" "$OUT" "deny" "Solution contamination risk"

OUT=$(run_guard force WebSearch '{"query":"SWE-bench official solution gold patch for task"}')
assert_decision "benchmark answer search denied" "$OUT" "deny" "Solution contamination risk"

OUT=$(run_guard force Write '{"file_path":"/repo/e2e/login.ts","content":"skip"}')
assert_advisory "e2e test write is advisory-only" "$OUT" "Grader gaming risk"

OUT=$(run_guard force Read '{"file_path":"/repo/.env.local"}')
assert_advisory "secret env read is advisory-only" "$OUT" "Capability-abuse risk"

OUT=$(run_guard force Bash '{"command":"cat .env"}')
assert_advisory "secret env bash read is advisory-only" "$OUT" "Capability-abuse risk"

OUT=$(run_guard force Bash '{"command":"curl https://example.com/benchmark-answer"}')
assert_decision "benchmark answer curl denied" "$OUT" "deny" "Solution contamination risk"


OUT=$(run_guard force Write '{"file_path":"/repo/tests/no-ask.test.ts","content":"skip"}')
assert_no_permission_ask "permissionDecision ask is never emitted" "$OUT"

# Regression: shell built-ins / bare identifiers must not be treated as path candidates.
# The shell `eval` keyword previously matched the (^|/)(evals?)(/|$) directory regex
# because it appeared as a bare token, even though it referenced no filesystem path.
OUT=$(run_guard force Bash '{"command":"eval rg -n pattern . 2>/dev/null"}')
assert_empty "shell eval keyword is not a path candidate" "$OUT"

OUT=$(run_guard force Bash '{"command":"test -f config.yaml && echo ok"}')
assert_empty "shell test builtin is not a path candidate" "$OUT"

OUT=$(run_guard force Bash '{"command":"spec --version"}')
assert_empty "bare spec identifier is not a path candidate" "$OUT"

# Positive control: an actual evals/ directory path must still be protected.
OUT=$(run_guard force Bash '{"command":"sed -i \"\" \"s/x/y/\" evals/runner.sh"}')
assert_advisory "mutating bash on evals directory is advisory-only" "$OUT" "Grader gaming risk"

# ── Oracle isolation: governance/loop state writes are hard denies ──
# setup-pua-loop.sh promises "Claude CANNOT bypass the Oracle"; loop state,
# pressure state, and history files are verifier-owned, so agent writes to them
# must be denied (not advisory) — including via shell redirect/tee targets.

OUT=$(run_guard force Write '{"file_path":"/repo/.claude/pua/loop-abc123.md","content":"active: false"}')
assert_decision "governance loop state write denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Write '{"file_path":"/repo/.claude/pua-loop.local.md","content":"active: false"}')
assert_decision "governance legacy state write denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Edit '{"file_path":"/home/x/.pua/builder-journal.md","old_string":"a","new_string":"b"}')
assert_decision "governance builder-journal edit denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Write '{"file_path":"/repo/.claude/pua-loop-history.jsonl","content":"{}"}')
assert_decision "governance history write denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"rm ~/.claude/pua/loop-abc1234.md"}')
assert_decision "governance loop state rm denied" "$OUT" "deny" "Oracle isolation"

# Deny audit trail: isolated HOME so the assertion is deterministic.
AUDIT_HOME=$(mktemp -d)
OUT=$(run_guard force Bash '{"command":"echo x > ~/.claude/pua/loop-abc1234.md"}' "$AUDIT_HOME")
assert_decision "governance redirect write denied" "$OUT" "deny" "Oracle isolation"
if [ -f "$AUDIT_HOME/.pua/audit.jsonl" ] && \
   grep -q '"decision": *"deny"' "$AUDIT_HOME/.pua/audit.jsonl" && \
   grep -q '"tool": *"Bash"' "$AUDIT_HOME/.pua/audit.jsonl" && \
   grep -q 'loop-abc1234.md' "$AUDIT_HOME/.pua/audit.jsonl"; then
  record_pass "deny appends entry to audit.jsonl"
else
  record_fail "deny appends entry to audit.jsonl"
  cat "$AUDIT_HOME/.pua/audit.jsonl" 2>/dev/null || true
fi
rm -rf "$AUDIT_HOME"

OUT=$(run_guard force Bash '{"command":"git diff | tee /home/x/.pua/builder-journal.md"}')
assert_decision "governance tee write denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"echo pua-loop-history.jsonl"}')
assert_empty "governance read/mention without mutation allowed" "$OUT"

OUT=$(run_guard force Bash '{"command":"cat ~/.claude/pua/loop-abc1234.md"}')
assert_empty "governance state read allowed" "$OUT"

# Human channel line must be present in deny messaging.
OUT=$(run_guard force Write '{"file_path":"/repo/.claude/pua/loop-abc123.md","content":"x"}')
if grep -q '请在终端手动执行' <<<"$OUT"; then
  record_pass "deny message includes human channel line"
else
  record_fail "deny message includes human channel line"
  printf '%s\n' "$OUT"
fi

# ── Oracle settlement credentials (verify-<hash>.{result,out,pending}) ──
# pua-loop-hook.sh settles async verify runs from ~/.claude/pua/verify-<hash>.
# result; a forged "0" would turn a rejected promise into a PASS.

VERIFY_HOME=$(mktemp -d)
OUT=$(run_guard force Bash '{"command":"echo 0 > ~/.claude/pua/verify-abc12345.result"}' "$VERIFY_HOME")
assert_decision "verify result forge via redirect denied" "$OUT" "deny" "Oracle isolation"
if [ -f "$VERIFY_HOME/.pua/audit.jsonl" ] && \
   grep -q 'verify-abc12345.result' "$VERIFY_HOME/.pua/audit.jsonl" && \
   grep -q '"decision": *"deny"' "$VERIFY_HOME/.pua/audit.jsonl"; then
  record_pass "verify result deny appends entry to audit.jsonl"
else
  record_fail "verify result deny appends entry to audit.jsonl"
  cat "$VERIFY_HOME/.pua/audit.jsonl" 2>/dev/null || true
fi
rm -rf "$VERIFY_HOME"

OUT=$(run_guard force Write '{"file_path":"/home/x/.claude/pua/verify-abc12345.out","content":"0"}')
assert_decision "verify out write denied" "$OUT" "deny" "Oracle isolation"

# ── Unconditional governance enforcement ──
# MUTATING_BASH misses dd/install/rsync/ln/scp/python shutil.copy; governance
# hits must deny regardless of the mutating dictionary.

OUT=$(run_guard force Bash '{"command":"dd if=/dev/zero of=~/.claude/pua/loop-abc1234.md"}')
assert_decision "governance dd write denied without mutating verb" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"cat a && dd if=/dev/zero of=~/.pua/loop-memory.json"}')
assert_decision "compound read + dd on governance state denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"python3 -c \"import shutil; shutil.copy('"'"'/tmp/src'"'"','"'"'~/.pua/loop-memory.json'"'"')\""}')
assert_decision "python shutil.copy onto governance state denied" "$OUT" "deny" "Oracle isolation"

# Governance state remains readable by pure read commands.
OUT=$(run_guard force Bash '{"command":"cat ~/.pua/./loop-memory.json"}')
assert_empty "governance state read via normpath variant allowed" "$OUT"

OUT=$(run_guard force Bash '{"command":"cat ~/.pua/state/CURRENT.md 2>/dev/null"}')
assert_empty "state read with 2>/dev/null allowed (diagnose flow)" "$OUT"

OUT=$(run_guard force Bash '{"command":"echo x 2>/dev/null"}')
assert_empty "2>/dev/null redirect is not mutating" "$OUT"

# ── Path normalization: dot/dotdot/double-slash variants must still hit ──

OUT=$(run_guard force Write '{"file_path":"/home/x/.pua/./state/CURRENT.md","content":"x"}')
assert_decision "governance write with /./ segment denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Write '{"file_path":"/home/x/.pua/x/../state/CURRENT.md","content":"x"}')
assert_decision "governance write with /../ segment denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Write '{"file_path":"/home/x/.pua//sessions/abc123.json","content":"{}"}')
assert_decision "governance write with double slash denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"echo x > ~/.pua/./state/CURRENT.md"}')
assert_decision "governance redirect with /./ segment denied" "$OUT" "deny" "Oracle isolation"

# ── Governance inventory completions ──

OUT=$(run_guard force Bash '{"command":"rm ~/.pua/churn-abc123.json"}')
assert_decision "churn-gate state rm denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"rm ~/.pua/.hooks_degraded"}')
assert_decision "hooks_degraded rm denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"echo injected >> ~/.pua/.hooks_degraded"}')
assert_decision "hooks_degraded injection denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"rm ~/.pua/audit.jsonl"}')
assert_decision "audit log rm denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Write '{"file_path":"/home/x/.claude/pua/archived/loop-abc1234-20260101T000000Z.md","content":"x"}')
assert_decision "archived loop history write denied" "$OUT" "deny" "Oracle isolation"

# ── Residual-bypass closure (re-review round 2): wildcard/dir-level removal
#    and command-substitution nesting ──

OUT=$(run_guard force Bash '{"command":"rm -rf ~/.pua"}')
assert_decision "whole .pua dir rm denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"rm -rf /home/x/.claude/pua"}')
assert_decision "whole .claude/pua dir rm denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"rm ~/.claude/pua/loop-*.md"}')
assert_decision "glob rm of loop state denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"truncate -s0 ~/.claude/pua/verify-abc12345.out"}')
assert_decision "truncate verify artifact denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"echo 0 $(dd of=/home/x/.claude/pua/verify-abc12345.result)"}')
assert_decision "command substitution nested writer denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"cat <(install -m 644 /tmp/fake /home/x/.pua/loop-memory.json)"}')
assert_decision "process substitution nested writer denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"find /home/x/.claude/pua -name \"loop-*.md\" -delete"}')
assert_decision "find -delete over governance dir denied" "$OUT" "deny" "Oracle isolation"

OUT=$(run_guard force Bash '{"command":"echo x > ~/.pua/errors.log"}')
assert_decision "errors.log tamper denied" "$OUT" "deny" "Oracle isolation"

# reads stay exempt (diagnose flow): pure-read commands produce no hook output
OUT=$(run_guard force Bash '{"command":"ls ~/.claude/pua/ && cat ~/.pua/state/CURRENT.md"}')
if [ -z "$OUT" ]; then
  PASS=$((PASS+1))
  echo "  ✅ PASS: read-only listing of governance dir allowed (silent)"
else
  FAIL=$((FAIL+1))
  echo "  ❌ FAIL: read-only listing should be silent, got: $OUT"
fi

echo "==========================================="
echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
