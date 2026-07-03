#!/usr/bin/env bash
# Feedback endpoint security gates: anonymous score allowed, session upload authenticated.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
assert_grep() { local pat="$1" file="$2" n="$3"; grep -qE "$pat" "$ROOT/$file" && pass "$n" || fail "$n"; }
assert_not_grep() { local pat="$1" file="$2" n="$3"; ! grep -qE "$pat" "$ROOT/$file" && pass "$n" || fail "$n"; }

echo "=== Feedback Auth Gates ==="
assert_grep 'import \{ getSession \} from "\./_session"' landing/functions/api/feedback.ts "feedback endpoint imports session verifier"
assert_grep 'SESSION_SECRET: string' landing/functions/api/feedback.ts "feedback endpoint env requires SESSION_SECRET"
assert_grep 'body\.session_data' landing/functions/api/feedback.ts "feedback endpoint branches on session_data"
assert_grep 'getSession\(request, env\.SESSION_SECRET\)' landing/functions/api/feedback.ts "session upload validates signed cookie"
assert_grep 'Login required for session upload|status: 401' landing/functions/api/feedback.ts "unauthenticated session upload returns 401"
assert_grep 'INSERT INTO feedback' landing/functions/api/feedback.ts "anonymous rating insert path remains"
assert_not_grep "json\.dumps\(\{'rating': 'session_upload', 'session_data': data\}\)" hooks/stop-feedback.sh "Stop hook no longer posts session_data to feedback anonymously"
assert_grep 'X-PUA-Upload-Consent|--data-binary @|/api/upload' hooks/stop-feedback.sh "Stop hook directly uploads sanitized session after explicit consent"
assert_grep '仅上传评分' hooks/stop-feedback.sh "anonymous score-only feedback remains available"
assert_not_grep 'GitHub login|登录后上传' hooks/stop-feedback.sh "Stop hook no longer requires GitHub login for session upload"

echo "==========================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================="
[ "$FAIL" -eq 0 ] || exit 1
