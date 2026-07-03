#!/usr/bin/env bash
# Upload flow gates: contribution route, GitHub redirect, and JSON upload payload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
assert_grep() { local pat="$1" file="$2" name="$3"; grep -qE -- "$pat" "$ROOT/$file" && pass "$name" || fail "$name"; }
assert_not_grep() { local pat="$1" file="$2" name="$3"; ! grep -qE -- "$pat" "$ROOT/$file" && pass "$name" || fail "$name"; }

echo "=== Upload Flow Gates ==="
assert_grep 'window\.location\.pathname|location\.pathname' landing/src/App.tsx "SPA router reads pathname, not only hash"
assert_grep 'contribute\.html|/contribute' landing/src/App.tsx "SPA router handles /contribute.html deep link"
assert_grep 'contribute\.html|#/contribute' landing/functions/api/auth/callback.ts "GitHub callback redirects to contribution page"
assert_grep 'contribute\.html|#/contribute' landing/functions/api/auth/logout.ts "logout returns to contribution page"
assert_grep 'application/jsonl' landing/src/pages/Contribute.tsx "frontend sends raw JSONL upload body"
assert_grep 'file\.text\(\)' landing/src/pages/Contribute.tsx "frontend reads selected JSONL as text"
assert_grep 'X-PUA-File-Name' landing/src/pages/Contribute.tsx "frontend sends file metadata outside multipart body"
assert_grep 'X-PUA-Upload-Consent' landing/src/pages/Contribute.tsx "frontend marks explicit upload consent"
assert_not_grep 'readFileAsBase64|file_data: fileData' landing/src/pages/Contribute.tsx "frontend avoids base64 bloat for large JSONL files"
assert_not_grep 'new FormData\(\)' landing/src/pages/Contribute.tsx "frontend avoids multipart-only upload path"
assert_grep 'application/jsonl' landing/functions/api/upload.ts "upload endpoint accepts raw JSONL body"
assert_grep 'file_data' landing/functions/api/upload.ts "upload endpoint keeps JSON file_data compatibility"
assert_grep 'multipart/form-data' landing/functions/api/upload.ts "upload endpoint keeps multipart compatibility"
assert_grep 'sanitize\(raw\)' landing/functions/api/upload.ts "upload endpoint sanitizes before R2 put"
assert_grep 'UPLOADS\.put' landing/functions/api/upload.ts "upload endpoint writes sanitized data to R2"
assert_grep 'anonymous' landing/functions/api/upload.ts "upload endpoint supports anonymous direct upload path"
assert_grep 'upload_rate_limits|RATE_LIMIT' landing/functions/api/upload.ts "anonymous upload path has rate limiting"
assert_grep 'X-PUA-Upload-Consent' hooks/stop-feedback.sh "Stop hook directly uploads sanitized session after explicit consent"
assert_not_grep 'GitHub login|登录后上传|contribute\.html 登录' hooks/stop-feedback.sh "Stop hook no longer requires GitHub login for session upload"
assert_grep 'INSERT INTO uploads' landing/functions/api/upload.ts "upload endpoint records metadata in D1"

echo "========================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "========================="
[ "$FAIL" -eq 0 ] || exit 1
