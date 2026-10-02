#!/usr/bin/env bash
# PUA state-snapshot + session-restore recovery tests — CLI-independent
# Covers: state-snapshot.sh (PreCompact/PostCompact command hook) and the
# state-recovery half of session-restore.sh (CURRENT.md priority, legacy
# builder-journal fallback, degraded-hook announcement).
# Usage: bash evals/test-state-snapshot.sh

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

assert_contains() {
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

assert_not_contains() {
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

assert_file_contains() {
  local label="$1" pattern="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if [ -f "$file" ] && grep -qE "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" file="$2"
  TOTAL=$((TOTAL + 1))
  if [ -f "$file" ]; then
    echo "  ✅ PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $label (missing file: $file)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup: isolated PUA home ──────────────────────────────────────────────────

TEST_PUA_HOME=$(mktemp -d)
export HOME="$TEST_PUA_HOME"
export PUA_CONFIG="${TEST_PUA_HOME}/.pua/config.json"

cleanup() {
  rm -rf "$TEST_PUA_HOME"
}
trap cleanup EXIT

reset_pua_home() {
  mkdir -p "${TEST_PUA_HOME}/.pua"
  echo '{"always_on":true,"flavor":"alibaba"}' > "$PUA_CONFIG"
  rm -rf "${TEST_PUA_HOME}/.pua/state" "${TEST_PUA_HOME}/.pua/builder-journal.md" \
         "${TEST_PUA_HOME}/.pua/.hooks_degraded" "${TEST_PUA_HOME}/.pua/sessions"
}

set_age_seconds() {
  # mtime = now - $2, portable across GNU/BSD via python
  python3 -c "import os,sys,time; p=sys.argv[1]; t=time.time()-float(sys.argv[2]); os.utime(p,(t,t))" "$1" "$2"
}

run_snapshot() {
  bash "${HOOKS_DIR}/state-snapshot.sh" <<<"$1"
}

run_restore() {
  bash "${HOOKS_DIR}/session-restore.sh" <<<"$1" 2>/dev/null || true
}

STATE_DIR="${TEST_PUA_HOME}/.pua/state"
CURRENT_MD="${STATE_DIR}/CURRENT.md"
DEGRADED_FILE="${TEST_PUA_HOME}/.pua/.hooks_degraded"

# ══════════════════════════════════════════════════════════════════════════════
echo "═══ Test Group: state-snapshot.sh basic snapshot ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 1: compact_summary payload → CURRENT.md created and contains the summary
reset_pua_home
set +e
run_snapshot '{"hook_event_name":"PreCompact","session_id":"t1","compact_summary":"Implement foo parser, tests still pending"}'
EXIT=$?
set -e
assert_exit "PreCompact snapshot exits 0" 0 $EXIT
assert_file_exists "CURRENT.md generated" "$CURRENT_MD"
assert_file_contains "CURRENT.md contains compact summary" "Implement foo parser" "$CURRENT_MD"

# Test 1b: snapshot archive + event line are written
SNAPSHOT_COUNT=$(find "${STATE_DIR}/snapshots" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$SNAPSHOT_COUNT" -ge 1 ]]; then
  echo "  ✅ PASS: snapshot archived (${SNAPSHOT_COUNT} file)"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: no snapshot archive written"
  FAIL=$((FAIL + 1))
fi
TODAY=$(date -u +%Y-%m-%d)
assert_file_exists "events jsonl written" "${STATE_DIR}/events/${TODAY}.jsonl"
assert_file_contains "event line records PreCompact" '"event": *"PreCompact"' "${STATE_DIR}/events/${TODAY}.jsonl"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: state-snapshot.sh redaction + truncation ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 2: fake API key in payload → [REDACTED] in CURRENT.md
reset_pua_home
run_snapshot '{"hook_event_name":"PreCompact","session_id":"t2","compact_summary":"deploy key sk-abc123def456ghij789 must not leak"}'
assert_file_contains "secret replaced with [REDACTED]" "\[REDACTED\]" "$CURRENT_MD"
TOTAL=$((TOTAL + 1))
if grep -q "sk-abc123def456ghij789" "$CURRENT_MD" 2>/dev/null; then
  echo "  ❌ FAIL: raw secret still present in CURRENT.md"
  FAIL=$((FAIL + 1))
else
  echo "  ✅ PASS: raw secret absent from CURRENT.md"
  PASS=$((PASS + 1))
fi

# Test 2b: JWT / Bearer header / 40-char hex secrets → [REDACTED]
# 40 位 hex 样本实测熵 3.97 < 4.1，只能被「≥40 位纯 hex 直接替换」兜底规则命中，
# 因此本用例同时验证兜底路径本身。32-39 位 hex 保持熵判定（git 短 hash 不误伤）。
reset_pua_home
JWT_SAMPLE="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
HEX40_SAMPLE="a3f9c2e81b7d4f6095e8c1a2b3d4e5f6a7b8c9d0"
run_snapshot '{"hook_event_name":"PreCompact","session_id":"t2b","compact_summary":"Authorization: Bearer abc123def456ghij jwt='"${JWT_SAMPLE}"' hex='"${HEX40_SAMPLE}"'"}'
assert_file_contains "bearer value replaced with [REDACTED]" "Bearer \[REDACTED\]" "$CURRENT_MD"
for secret_label in "JWT:${JWT_SAMPLE}" "hex40:${HEX40_SAMPLE}"; do
  SECRET_NAME="${secret_label%%:*}"
  SECRET_VALUE="${secret_label#*:}"
  TOTAL=$((TOTAL + 1))
  if grep -qF "$SECRET_VALUE" "$CURRENT_MD" 2>/dev/null; then
    echo "  ❌ FAIL: raw ${SECRET_NAME} still present in CURRENT.md"
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ PASS: raw ${SECRET_NAME} absent from CURRENT.md"
    PASS=$((PASS + 1))
  fi
done

# Test 3: compact_summary over 3500 chars → truncated
reset_pua_home
LONG_SUMMARY="$(python3 -c "print('A'*3600 + 'TAILMARKER_9z')")"
run_snapshot "{\"hook_event_name\":\"PreCompact\",\"session_id\":\"t3\",\"compact_summary\":\"${LONG_SUMMARY}\"}"
assert_file_contains "long summary marked truncated" "\.\.\.\[truncated\]" "$CURRENT_MD"
assert_not_contains "content beyond limit dropped" "TAILMARKER_9z" "$(cat "$CURRENT_MD")"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: state-snapshot.sh fail-open ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 4a: empty stdin → exit 0, no crash
reset_pua_home
set +e
printf '' | bash "${HOOKS_DIR}/state-snapshot.sh" >/dev/null 2>&1
EXIT=$?
set -e
assert_exit "empty stdin exits 0" 0 $EXIT
assert_file_exists "empty stdin still writes snapshot" "$CURRENT_MD"

# Test 4b: invalid JSON stdin → exit 0, no degraded flag (normal tolerance)
reset_pua_home
set +e
printf 'not json {{{' | bash "${HOOKS_DIR}/state-snapshot.sh" >/dev/null 2>&1
EXIT=$?
set -e
assert_exit "invalid JSON stdin exits 0" 0 $EXIT
TOTAL=$((TOTAL + 1))
if [ -f "$DEGRADED_FILE" ]; then
  echo "  ❌ FAIL: invalid JSON wrongly recorded as degradation"
  FAIL=$((FAIL + 1))
else
  echo "  ✅ PASS: invalid JSON does not trigger degradation"
  PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: state-snapshot.sh content sources ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 5: transcript tail message captured into CURRENT.md
reset_pua_home
TRANSCRIPT="${TEST_PUA_HOME}/.pua/test-transcript.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"OLD_ASSISTANT_EARLIER"}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"TRANSCRIPT_TAIL_MARKER fix the parser now"}]}}' \
  > "$TRANSCRIPT"
run_snapshot "{\"hook_event_name\":\"PreCompact\",\"session_id\":\"t5\",\"transcript_path\":\"${TRANSCRIPT}\"}"
assert_file_contains "last transcript message captured" "TRANSCRIPT_TAIL_MARKER" "$CURRENT_MD"
assert_not_contains "older messages dropped" "OLD_ASSISTANT_EARLIER" "$(cat "$CURRENT_MD")"

# Test 6: pua runtime state (sessions/<sid>.json + loop-memory.json) captured
# 注：session 状态键与 failure-detector.sh 实际写入对齐（count/score/peak_level，
# 无 level 键）；loop-memory.json 顶层为 {"patterns": {...}}，条目数按 patterns 计。
reset_pua_home
mkdir -p "${TEST_PUA_HOME}/.pua/sessions"
echo '{"count":3,"score":7,"peak_level":2}' > "${TEST_PUA_HOME}/.pua/sessions/t6.json"
echo '{"patterns":{"sig-a":{"count":1},"sig-b":{"count":2}}}' > "${TEST_PUA_HOME}/.pua/loop-memory.json"
run_snapshot '{"hook_event_name":"PostCompact","session_id":"t6"}'
assert_file_contains "session state (count/score) captured" "count=3" "$CURRENT_MD"
assert_file_contains "pressure level (peak_level) captured" "peak_level=2" "$CURRENT_MD"
assert_file_contains "loop-memory patterns count captured" "loop-memory entries: 2" "$CURRENT_MD"
assert_file_contains "PostCompact event recorded" '"event": *"PostCompact"' "${STATE_DIR}/events/$(date -u +%Y-%m-%d).jsonl"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: state-snapshot.sh snapshot/events pruning ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 6b: snapshots capped at 20, events capped at 30 date files.
# 假快照文件名沿用真实命名格式（UTC 时间戳开头，字典序=时间序）。
reset_pua_home
mkdir -p "${STATE_DIR}/snapshots" "${STATE_DIR}/events"
for i in $(seq -w 1 25); do
  printf 'fake snapshot %s\n' "$i" > "${STATE_DIR}/snapshots/20250101T0000${i}Z-fake-${i}.md"
done
for i in $(seq -w 1 32); do
  printf '{"ts":"fake-%s"}\n' "$i" > "${STATE_DIR}/events/2025-01-${i}.jsonl"
done
run_snapshot '{"hook_event_name":"PreCompact","session_id":"t6b"}'
SNAP_AFTER=$(find "${STATE_DIR}/snapshots" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$SNAP_AFTER" -eq 20 ]]; then
  echo "  ✅ PASS: snapshots pruned to 20 (got ${SNAP_AFTER})"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: expected 20 snapshots after pruning, got ${SNAP_AFTER}"
  FAIL=$((FAIL + 1))
fi
assert_not_contains "oldest snapshot (fake-01) removed" "fake-01" "$(ls "${STATE_DIR}/snapshots" 2>/dev/null)"
TOTAL=$((TOTAL + 1))
if [ -f "${STATE_DIR}/snapshots/20250101T000025Z-fake-25.md" ]; then
  echo "  ✅ PASS: newest fake snapshot (fake-25) retained"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: newest fake snapshot (fake-25) was wrongly pruned"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
FRESH_SNAPSHOTS=$(ls "${STATE_DIR}/snapshots" 2>/dev/null | grep -cv '^20250101' || true)
if [[ "$FRESH_SNAPSHOTS" -eq 1 ]]; then
  echo "  ✅ PASS: freshly written snapshot survived pruning"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: expected exactly 1 fresh snapshot, got ${FRESH_SNAPSHOTS}"
  FAIL=$((FAIL + 1))
fi
EVENTS_AFTER=$(find "${STATE_DIR}/events" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$EVENTS_AFTER" -eq 30 ]]; then
  echo "  ✅ PASS: events pruned to 30 date files (got ${EVENTS_AFTER})"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: expected 30 event files after pruning, got ${EVENTS_AFTER}"
  FAIL=$((FAIL + 1))
fi
assert_not_contains "oldest event file (2025-01-01) removed" "2025-01-01" "$(ls "${STATE_DIR}/events" 2>/dev/null)"
assert_file_exists "today's event file survived pruning" "${STATE_DIR}/events/$(date -u +%Y-%m-%d).jsonl"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: session-restore.sh state recovery ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 7: CURRENT.md → additionalContext contains its content
reset_pua_home
mkdir -p "$STATE_DIR"
printf '# PUA State Snapshot\nMARKER_CURRENT_XYZ resume data' > "$CURRENT_MD"
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_contains "restore injects CURRENT.md content" "MARKER_CURRENT_XYZ" "$OUTPUT"
assert_contains "restore uses recovery header" "PUA State Recovery" "$OUTPUT"

# Test 8: fresh journal must NOT win when CURRENT.md is present
printf '# PUA Builder Journal\njournal note' > "${TEST_PUA_HOME}/.pua/builder-journal.md"
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_contains "CURRENT.md still injected with fresh journal present" "MARKER_CURRENT_XYZ" "$OUTPUT"
assert_not_contains "legacy journal branch skipped" "builder-journal\.md" "$OUTPUT"

# Test 9: stale CURRENT.md (>7d) → falls back to fresh journal legacy branch
set_age_seconds "$CURRENT_MD" 691200
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_not_contains "stale CURRENT.md skipped" "MARKER_CURRENT_XYZ" "$OUTPUT"
assert_contains "fresh journal legacy fallback works" "builder-journal\.md" "$OUTPUT"

# Test 9b: journal older than 2h → no recovery at all
set_age_seconds "${TEST_PUA_HOME}/.pua/builder-journal.md" 10800
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_not_contains "stale journal produces no recovery" "PUA State Recovery" "$OUTPUT"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══ Test Group: session-restore.sh degraded announcement ═══"
# ══════════════════════════════════════════════════════════════════════════════

# Test 10: fresh .hooks_degraded → announcement at the front of additionalContext
reset_pua_home
printf '2026-10-01T00:00:00Z state-snapshot: event append failed\n2026-10-02T00:00:00Z state-snapshot: snapshot archive failed\n' > "$DEGRADED_FILE"
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_contains "degradation announced" "PUA hooks 本会话降级" "$OUTPUT"
assert_contains "latest degradation reason surfaced" "snapshot archive failed" "$OUTPUT"
assert_contains "removal hint included" "修复问题后删除该文件可清除此提示" "$OUTPUT"
TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | grep -q "本会话降级"; then
  PREFIX=$(echo "$OUTPUT" | sed 's/.*"additionalContext":"//' | cut -c1-40)
  case "$PREFIX" in
    "[PUA hooks"*)
      echo "  ✅ PASS: announcement leads additionalContext"
      PASS=$((PASS + 1))
      ;;
    *)
      echo "  ❌ FAIL: announcement does not lead additionalContext (prefix: ${PREFIX})"
      FAIL=$((FAIL + 1))
      ;;
  esac
fi

# Test 11: .hooks_degraded older than 24h → suppressed
set_age_seconds "$DEGRADED_FILE" 90000
OUTPUT=$(run_restore '{"hook_event_name":"SessionStart"}')
assert_not_contains "expired degradation suppressed" "本会话降级" "$OUTPUT"

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════"
echo "  State Snapshot Tests: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
  echo "  ⚠️  $FAIL test(s) FAILED"
  echo "═══════════════════════════════════════"
  exit 1
else
  echo "  ✅ All tests passed"
  echo "═══════════════════════════════════════"
  exit 0
fi
