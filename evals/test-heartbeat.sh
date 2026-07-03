#!/usr/bin/env bash
# Heartbeat telemetry gates: silent SessionStart hook + admin-only Cloudflare stats.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
assert_file() { local file="$1" name="$2"; [ -f "$ROOT/$file" ] && pass "$name" || fail "$name"; }
assert_grep() { local pat="$1" file="$2" name="$3"; grep -qE -- "$pat" "$ROOT/$file" 2>/dev/null && pass "$name" || fail "$name"; }
assert_not_grep() { local pat="$1" file="$2" name="$3"; ! grep -qE -- "$pat" "$ROOT/$file" 2>/dev/null && pass "$name" || fail "$name"; }

run_silence_check() {
  local label="$1"
  local home_dir="$2"
  local config_json="$3"
  local out err
  mkdir -p "$home_dir/.pua"
  printf '%s\n' "$config_json" > "$home_dir/.pua/config.json"
  out="$home_dir/out.txt"
  err="$home_dir/err.txt"
  HOME="$home_dir" \
  CLAUDE_PLUGIN_ROOT="$ROOT" \
  PUA_HEARTBEAT_ENDPOINT="http://127.0.0.1:9/api/heartbeat" \
  PUA_HEARTBEAT_INTERVAL_SECONDS=0 \
    bash "$ROOT/hooks/heartbeat.sh" >"$out" 2>"$err" || true
  sleep 0.2
  if [ ! -s "$out" ] && [ ! -s "$err" ]; then
    pass "$label emits no stdout/stderr"
  else
    fail "$label emits no stdout/stderr"
    sed 's/^/    stdout: /' "$out" || true
    sed 's/^/    stderr: /' "$err" || true
  fi
}

echo "=== Heartbeat Gates ==="
assert_file hooks/heartbeat.sh "heartbeat hook exists"
assert_file landing/functions/api/heartbeat.ts "Cloudflare heartbeat endpoint exists"
assert_file landing/migrations/0004_heartbeat.sql "D1 heartbeat migration exists"
assert_file landing/src/pages/AdminStats.tsx "admin heartbeat page exists"

if [ -f "$ROOT/hooks/heartbeat.sh" ]; then
  bash -n "$ROOT/hooks/heartbeat.sh" && pass "heartbeat hook has valid bash syntax" || fail "heartbeat hook has valid bash syntax"
  assert_grep '/api/heartbeat' hooks/heartbeat.sh "heartbeat hook posts to /api/heartbeat"
  assert_grep 'PUA_HEARTBEAT_ENDPOINT' hooks/heartbeat.sh "heartbeat endpoint is overrideable"
  assert_grep 'offline' hooks/heartbeat.sh "heartbeat respects offline config"
  assert_grep 'telemetry' hooks/heartbeat.sh "heartbeat respects telemetry opt-out"
  assert_grep 'feedback_frequency' hooks/heartbeat.sh "heartbeat respects feedback-off opt-out"
  assert_grep 'get_flavor' hooks/heartbeat.sh "heartbeat normalizes flavor aliases"
  assert_grep '--max-time' hooks/heartbeat.sh "heartbeat network call has timeout"
  assert_grep '>/dev/null 2>&1|> *"?/dev/null"? +2>&1|2> *"?/dev/null"?' hooks/heartbeat.sh "heartbeat suppresses curl output"
fi

python3 - "$ROOT" <<'PY' && pass "SessionStart registers silent heartbeat before context restore" || fail "SessionStart registers silent heartbeat before context restore"
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
data = json.loads((root / 'hooks/hooks.json').read_text())
items = data.get('hooks', {}).get('SessionStart', [])
if not items:
    raise SystemExit('no SessionStart hooks')
for item in items:
    commands = [hook.get('command','') for hook in item.get('hooks', [])]
    if not any('heartbeat.sh' in c for c in commands):
        raise SystemExit(f"missing heartbeat in matcher {item.get('matcher')}")
    hb = next(i for i,c in enumerate(commands) if 'heartbeat.sh' in c)
    restore = next((i for i,c in enumerate(commands) if 'session-restore.sh' in c), None)
    if restore is not None and hb > restore:
        raise SystemExit(f"heartbeat should run before session-restore in matcher {item.get('matcher')}")
PY

if [ -f "$ROOT/landing/functions/api/heartbeat.ts" ]; then
  assert_grep 'import \{ getSession \} from "\./_session"' landing/functions/api/heartbeat.ts "admin GET imports session verifier"
  assert_grep 'ADMIN_GITHUB_LOGINS' landing/functions/api/heartbeat.ts "admin allowlist is configurable"
  assert_grep 'heartbeat_installs' landing/functions/api/heartbeat.ts "endpoint writes install aggregate"
  assert_grep 'heartbeat_events' landing/functions/api/heartbeat.ts "endpoint writes event log"
  assert_grep 'COUNT\(DISTINCT install_id_hash\)' landing/functions/api/heartbeat.ts "stats count distinct active users"
  assert_grep 'sha256Hex' landing/functions/api/heartbeat.ts "endpoint hashes install identifiers"
fi

if [ -f "$ROOT/landing/src/App.tsx" ]; then
  assert_grep '#/admin/heartbeats' landing/src/App.tsx "admin hash route is registered"
fi
if [ -f "$ROOT/landing/src/pages/AdminStats.tsx" ]; then
  assert_grep '/api/heartbeat' landing/src/pages/AdminStats.tsx "admin page fetches heartbeat stats"
  assert_grep '/api/auth/github' landing/src/pages/AdminStats.tsx "admin page offers GitHub login"
fi

if [ -f "$ROOT/hooks/heartbeat.sh" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  run_silence_check "online heartbeat" "$tmp/online-home" '{"telemetry": true, "flavor": "microsoft"}'
  if [ -s "$tmp/online-home/.pua/install_id" ]; then
    pass "heartbeat creates stable local anonymous install id"
  else
    fail "heartbeat creates stable local anonymous install id"
  fi
  run_silence_check "offline heartbeat" "$tmp/offline-home" '{"offline": true, "telemetry": true}'
  if [ ! -e "$tmp/offline-home/.pua/install_id" ]; then
    pass "offline mode does not create telemetry identity"
  else
    fail "offline mode does not create telemetry identity"
  fi

  leak_home="$tmp/leak-home"
  mkdir -p "$leak_home/.pua"
  printf '%s\n' '{"always_on": true, "telemetry": true}' > "$leak_home/.pua/config.json"
  HOME="$leak_home" PUA_CONFIG="$leak_home/.pua/config.json" bash "$ROOT/hooks/session-restore.sh" > "$tmp/session.out" 2>/dev/null || true
  if grep -Eiq 'heartbeat|install_id|/api/heartbeat' "$tmp/session.out"; then
    fail "SessionStart context does not leak heartbeat implementation details"
  else
    pass "SessionStart context does not leak heartbeat implementation details"
  fi
fi

assert_not_grep 'heartbeat|install_id|/api/heartbeat' skills/pua/SKILL.md "main skill prompt does not mention heartbeat"

echo "======================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "======================="
[ "$FAIL" -eq 0 ] || exit 1
