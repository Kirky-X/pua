#!/usr/bin/env bash
# Regression coverage for the open-issue sweep after #159.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
assert_file() { local p="$1" n="$2"; [ -f "$ROOT/$p" ] && pass "$n" || fail "$n"; }
assert_grep() { local pat="$1" file="$2" n="$3"; grep -qE "$pat" "$ROOT/$file" && pass "$n" || fail "$n"; }
assert_not_grep() { local pat="$1" file="$2" n="$3"; ! grep -qE "$pat" "$ROOT/$file" && pass "$n" || fail "$n"; }

run_hook() {
  local input="$1" out="$2"
  HOME="$TMP/home" PUA_CONFIG="$TMP/home/.pua/config.json" bash "$ROOT/hooks/frustration-trigger.sh" <<<"$input" >"$out" 2>"$out.err" || true
}

mkdir -p "$TMP/home/.pua"
printf '%s\n' '{"always_on":true,"feedback_frequency":5}' > "$TMP/home/.pua/config.json"

echo "=== Issue Regression Sweep ==="

# #120/#111: UserPromptSubmit matcher is ignored by Claude Code, so the script
# itself must filter neutral prompts and phrase hook output as installed user
# context rather than a coercive prompt-injection-looking command.
run_hook '{"prompt":"Help me write a sort function"}' "$TMP/neutral.out"
if [ ! -s "$TMP/neutral.out" ]; then pass "neutral UserPromptSubmit prompt is silent"; else fail "neutral UserPromptSubmit prompt is silent"; cat "$TMP/neutral.out"; fi
run_hook '{"prompt":"你怎么又失败了？再试试"}' "$TMP/frustrated.out"
if grep -qE 'PUA Skill Context|User Frustration Signal|PUA生效|PUA ACTIVATED' "$TMP/frustrated.out"; then pass "frustrated UserPromptSubmit prompt still injects context"; else fail "frustrated UserPromptSubmit prompt still injects context"; cat "$TMP/frustrated.out"; fi
if grep -qE 'MUST:|MUST invoke|PUA behavioral enforcement|prompt injection' "$TMP/frustrated.out"; then fail "frustration hook avoids coercive injection wording"; cat "$TMP/frustrated.out"; else pass "frustration hook avoids coercive injection wording"; fi

# #153 PR #151: no world-writable /tmp plugin-root rendezvous.
assert_not_grep '/tmp/pua-plugin-root|cat /tmp/pua-plugin-root' hooks/stop-feedback.sh "stop-feedback avoids /tmp plugin-root TOCTOU"

# #109: offline mode must prevent network/feedback prompt emission.
printf '%s\n' '{"always_on":true,"offline":true,"feedback_frequency":1}' > "$TMP/home/.pua/config.json"
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"PUA生效"}]}}' > "$TMP/transcript.jsonl"
HOME="$TMP/home" PUA_CONFIG="$TMP/home/.pua/config.json" bash "$ROOT/hooks/stop-feedback.sh" <<<"{\"hook_event_name\":\"Stop\",\"transcript_path\":\"$TMP/transcript.jsonl\"}" >"$TMP/stop.out" 2>"$TMP/stop.err" || true
if [ ! -s "$TMP/stop.out" ]; then pass "offline mode suppresses feedback network flow"; else fail "offline mode suppresses feedback network flow"; cat "$TMP/stop.out"; fi
assert_file commands/offline.md "offline command exists"

# #107: Codex subcommand aliases.
for alias in pua-on pua-off pua-p7 pua-p9 pua-p10 pua-pro pua-loop; do
  assert_file "codex/$alias/SKILL.md" "Codex alias $alias exists"
done

# #160/#93: platform packs.
assert_file pi/pua/index.ts "Pi extension entrypoint exists"
assert_file pi/pua/INSTALL.md "Pi install guide exists"
assert_file pi/package/package.json "pi.dev package manifest exists"
assert_file pi/package/extensions/pua/index.ts "pi.dev package extension entrypoint exists"
assert_file pi/package/skills/pua/SKILL.md "pi.dev package skill exists"
assert_file trae/INSTALL.md "Trae install guide exists"
assert_file trae/DIFF.md "Trae/Claude Code difference doc exists"
assert_file trae/pua.md "Trae Chinese prompt exists"
assert_file .trae/skills/pua/SKILL.md "Trae SKILL.md pack exists"
assert_file .trae/skills/pua-en/SKILL.md "Trae English SKILL.md pack exists"
assert_file .trae/skills/pua-trae/SKILL.md "Trae npx skills optimized pack exists"

# #84/#77/#157/#96 static gates.
assert_grep '\[PUA-DIAGNOSIS\]|诊断先行' skills/pua/SKILL.md "diagnosis-first anti-overcaution rule exists"
assert_grep '军令状|交账|只对自己加压' skills/pua/references/methodology-huawei.md "Huawei military-order mode exists"
if grep -RIn "下场" "$ROOT/agents" "$ROOT/commands" "$ROOT/skills/pua/references" "$ROOT/README.zh-CN.md" >/tmp/pua-ambiguous-xiachang.txt 2>/dev/null; then
  fail "ambiguous 下场 wording removed"
  cat /tmp/pua-ambiguous-xiachang.txt
else
  pass "ambiguous 下场 wording removed"
fi
assert_grep 'MAX_BODY_BYTES|MAX_SESSION_DATA_BYTES|RATE_LIMIT' landing/functions/api/feedback.ts "feedback endpoint has abuse limits"
assert_grep 'getSession\\(request, env\\.SESSION_SECRET\\)|Login required for session upload' landing/functions/api/feedback.ts "feedback session upload requires authentication"
assert_not_grep "json\\.dumps\\(\\{'rating': 'session_upload', 'session_data': data\\}\\)" hooks/stop-feedback.sh "stop-feedback does not anonymously upload session_data"
assert_grep 'X-PUA-Upload-Consent|--data-binary @|/api/upload' hooks/stop-feedback.sh "stop-feedback uploads sanitized session directly after consent"
assert_not_grep 'GitHub login|登录后上传' hooks/stop-feedback.sh "stop-feedback no longer requires GitHub login"
assert_grep 'upload_rate_limits' landing/migrations/0005_upload_rate_limits.sql "anonymous upload rate-limit migration exists"
assert_grep 'feedback_rate_limits' landing/migrations/0003_feedback_rate_limits.sql "feedback rate-limit migration exists"

echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="
[ "$FAIL" -eq 0 ] || exit 1
