#!/usr/bin/env bash
# Verifies pua-loop Oracle hook behavior without relying on Claude CLI.
#
# 行为变更说明（v3.3，prove_it 语义）：
#   verify_command 从「Stop hook 内同步执行」改为「spawn 后台任务 + 下次 Stop
#   结算」。原断言（单次调用即见 verified/rejected）改为两阶段：run1 断言
#   spawn+block（iteration 不变），等待 verify-<hash>.result 落盘后 run2 断言
#   结算结果。其余新增：证据赎回（软通过/拒绝）、partial 头、孤儿归档。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

cwd_hash() {
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$1" | md5sum | cut -c1-8
  else
    printf '%s' "$1" | md5 | cut -c1-8
  fi
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

record_pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
record_fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }

make_transcript() {
  local path="$1"
  local text="$2"
  python3 - "$path" "$text" <<'PY'
import json, sys
path, text = sys.argv[1], sys.argv[2]
with open(path, 'w', encoding='utf-8') as f:
    f.write(json.dumps({"role":"assistant","message":{"content":[{"type":"text","text":text}]}}, separators=(",",":")) + "\n")
PY
}

run_hook() {
  local home="$1"
  local project="$2"
  local transcript="$3"
  local session_id="${4:-test-session}"
  local input
  input=$(jq -nc --arg transcript_path "$transcript" --arg session_id "$session_id" '{hook_event_name:"Stop",transcript_path:$transcript_path,session_id:$session_id}')
  (cd "$project" && HOME="$home" bash "$PLUGIN_DIR/hooks/pua-loop-hook.sh" <<<"$input")
}

create_state() {
  local home="$1"
  local project="$2"
  local verify_command="$3"
  local session_id="${4:-test-session}"
  local hash state verify_line
  hash=$(cwd_hash "$project")
  mkdir -p "$home/.claude/pua" "$project/.claude"
  state="$home/.claude/pua/loop-${hash}.md"
  if [ "$verify_command" = "null" ]; then
    verify_line="verify_command: null"
  else
    verify_line="verify_command: \"$verify_command\""
  fi
  cat > "$state" <<STATE
---
active: true
iteration: 1
session_id: $session_id
max_iterations: 0
completion_promise: "DONE"
$verify_line
promise_rejections: 0
started_cwd: "$project"
---

Test prompt
STATE
  printf '%s\n' "$state"
}

# Wait for the async verify result file (spawned by run #1) to settle.
await_result() {
  local result="$1"
  local i=0
  while [ "$i" -lt 50 ]; do
    [ -f "$result" ] && return 0
    sleep 0.2
    i=$((i+1))
  done
  return 1
}

echo "=== PUA Loop Hook Oracle Tests ==="

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# ── Async Oracle: verified promise settles on the NEXT Stop ──────────────
# 行为变更：run1 只 spawn 后台验证并 block（iteration 不变）；结果落盘后
# run2 收割：exit 0 → PROMISE ACCEPTED → state removed。
HOME1="$TMP_ROOT/home-success"
PROJ1="$TMP_ROOT/project-success"
mkdir -p "$HOME1" "$PROJ1"
STATE1=$(create_state "$HOME1" "$PROJ1" "true")
TRANSCRIPT1="$PROJ1/transcript.jsonl"
make_transcript "$TRANSCRIPT1" '<promise>DONE</promise>'
HASH1=$(cwd_hash "$PROJ1")
RESULT1="$HOME1/.claude/pua/verify-${HASH1}.result"
# 断言 a) spawn 分支必须 touch 刷新 state mtime（fix：异步 spawn 后 state 不再
# 被写，等待结算的合法等待 >30min 会被孤儿归档误杀）。先把 mtime 调回 2 分钟
# 前，spawn run 后 mtime 必须恢复为当前时间。
touch -d '2 minutes ago' "$STATE1" 2>/dev/null || touch -A -000200 "$STATE1"
MTIME1_BEFORE=$(file_mtime "$STATE1")
OUT1A=$(run_hook "$HOME1" "$PROJ1" "$TRANSCRIPT1")
MTIME1_AFTER=$(file_mtime "$STATE1")
if grep -q 'Oracle 验证已后台运行' <<<"$OUT1A" && grep -q '"decision": "block"' <<<"$OUT1A" && [ -f "$STATE1" ] && grep -q '^iteration: 1$' "$STATE1"; then
  record_pass "async spawn blocks once with iteration unchanged"
else
  record_fail "async spawn blocks once with iteration unchanged"
  printf '%s\n' "$OUT1A"
fi
if [ "$MTIME1_AFTER" -gt "$MTIME1_BEFORE" ]; then
  record_pass "spawn refreshes state file mtime before blocking"
else
  record_fail "spawn refreshes state file mtime before blocking"
  echo "    mtime before=$MTIME1_BEFORE after=$MTIME1_AFTER"
fi
if await_result "$RESULT1"; then
  record_pass "async verify writes result file atomically"
else
  record_fail "async verify writes result file atomically"
fi
# 断言 c) complete 终止路径必须一并清理 started_cwd 匹配的 legacy 副本
# （fix：setup 每次同步写 .claude/pua-loop.local.md，canonical 终止后副本残留
# active:true + 旧 session，之后每个新会话都会把它误归档）。既有断言
# 「verified promise exits and removes state」扩展了 legacy 副本删除检查，
# 原因：complete 路径语义随 fix 3 扩展。
cp "$STATE1" "$PROJ1/.claude/pua-loop.local.md"
OUT1B=$(run_hook "$HOME1" "$PROJ1" "$TRANSCRIPT1")
if grep -q 'verified by Oracle' <<<"$OUT1B" && [ ! -f "$STATE1" ] && [ ! -f "$PROJ1/.claude/pua-loop.local.md" ]; then
  record_pass "verified promise exits and removes state + matching legacy copy"
else
  record_fail "verified promise exits and removes state + matching legacy copy"
  printf '%s\n' "$OUT1B"
fi
if grep -q '"status":"complete"' "$PROJ1/.claude/pua-loop-history.jsonl" 2>/dev/null; then
  record_pass "accepted promise logged as complete"
else
  record_fail "accepted promise logged as complete"
fi

# ── Async Oracle: failed verify rejects on the NEXT Stop ─────────────────
# 行为变更：拒绝同样发生在 run2（收割 exit≠0），iteration/rejections 在
# 收割时递增。
HOME2="$TMP_ROOT/home-fail"
PROJ2="$TMP_ROOT/project-fail"
mkdir -p "$HOME2" "$PROJ2"
STATE2=$(create_state "$HOME2" "$PROJ2" "false")
TRANSCRIPT2="$PROJ2/transcript.jsonl"
make_transcript "$TRANSCRIPT2" '<promise>DONE</promise>'
HASH2=$(cwd_hash "$PROJ2")
RESULT2="$HOME2/.claude/pua/verify-${HASH2}.result"
OUT2A=$(run_hook "$HOME2" "$PROJ2" "$TRANSCRIPT2")
await_result "$RESULT2" || true
OUT2B=$(run_hook "$HOME2" "$PROJ2" "$TRANSCRIPT2")
if grep -q '"decision": "block"' <<<"$OUT2B" && grep -q 'PROMISE 被 Oracle 拒绝' <<<"$OUT2B" && \
   grep -q '^iteration: 2$' "$STATE2" && grep -q '^promise_rejections: 1$' "$STATE2"; then
  record_pass "failed verify blocks on next Stop and records rejection"
else
  record_fail "failed verify blocks on next Stop and records rejection"
  printf '%s\n' "$OUT2A" "$OUT2B"
  cat "$STATE2" || true
fi
if [ ! -f "$RESULT2" ]; then
  record_pass "result file removed after harvest"
else
  record_fail "result file removed after harvest"
fi

# ── Setup integration: quoted verify commands remain executable (async) ──
HOME3="$TMP_ROOT/home-quoted"
PROJ3="$TMP_ROOT/project-quoted"
mkdir -p "$HOME3" "$PROJ3"
(
  cd "$PROJ3"
  HOME="$HOME3" CLAUDE_CODE_SESSION_ID="test-session" bash "$PLUGIN_DIR/scripts/setup-pua-loop.sh" \
    'quoted verify smoke' \
    --completion-promise 'DONE' \
    --verify 'python3 -c "print(123)"' >/tmp/pua-loop-setup-test.out
)
HASH3=$(cwd_hash "$PROJ3")
STATE3="$HOME3/.claude/pua/loop-${HASH3}.md"
RESULT3="$HOME3/.claude/pua/verify-${HASH3}.result"
TRANSCRIPT3="$PROJ3/transcript.jsonl"
make_transcript "$TRANSCRIPT3" '<promise>DONE</promise>'
run_hook "$HOME3" "$PROJ3" "$TRANSCRIPT3" >/dev/null
await_result "$RESULT3" || true
OUT3=$(run_hook "$HOME3" "$PROJ3" "$TRANSCRIPT3")
if grep -q 'verified by Oracle' <<<"$OUT3" && [ ! -f "$STATE3" ]; then
  record_pass "setup-created quoted verify command executes"
else
  record_fail "setup-created quoted verify command executes"
  printf '%s\n' "$OUT3"
  cat "$STATE3" || true
fi

# ── Evidence redemption (no verify): soft pass on deterministic evidence ──
HOME4="$TMP_ROOT/home-evidence"
PROJ4="$TMP_ROOT/project-evidence"
mkdir -p "$HOME4" "$PROJ4"
STATE4=$(create_state "$HOME4" "$PROJ4" "null" "evidence-session")
TRANSCRIPT4="$PROJ4/transcript.jsonl"
make_transcript "$TRANSCRIPT4" '任务完成。<promise>DONE</promise> commands run: `npm test` 全部绿'
OUT4=$(run_hook "$HOME4" "$PROJ4" "$TRANSCRIPT4" "evidence-session")
if grep -q '证据赎回通过' <<<"$OUT4" && [ ! -f "$STATE4" ] && \
   grep -q '"status":"complete_evidence_redeemed"' "$PROJ4/.claude/pua-loop-history.jsonl" 2>/dev/null; then
  record_pass "evidence redemption accepts with soft-pass notice"
else
  record_fail "evidence redemption accepts with soft-pass notice"
  printf '%s\n' "$OUT4"
  cat "$PROJ4/.claude/pua-loop-history.jsonl" 2>/dev/null || true
fi

# ── Evidence redemption (no verify): bare self-report still blocked ──────
HOME5="$TMP_ROOT/home-noevidence"
PROJ5="$TMP_ROOT/project-noevidence"
mkdir -p "$HOME5" "$PROJ5"
STATE5=$(create_state "$HOME5" "$PROJ5" "null" "noevidence-session")
TRANSCRIPT5="$PROJ5/transcript.jsonl"
make_transcript "$TRANSCRIPT5" '我觉得差不多了 <promise>DONE</promise>'
OUT5=$(run_hook "$HOME5" "$PROJ5" "$TRANSCRIPT5" "noevidence-session")
if grep -q '未配置 --verify 验证命令' <<<"$OUT5" && [ -f "$STATE5" ] && \
   grep -q '^iteration: 2$' "$STATE5"; then
  record_pass "self-report without evidence stays blocked"
else
  record_fail "self-report without evidence stays blocked"
  printf '%s\n' "$OUT5"
fi

# ── Honest partial header: legal wrap-up, normal continue path ───────────
HOME6="$TMP_ROOT/home-partial"
PROJ6="$TMP_ROOT/project-partial"
mkdir -p "$HOME6" "$PROJ6"
STATE6=$(create_state "$HOME6" "$PROJ6" "null" "partial-session")
TRANSCRIPT6="$PROJ6/transcript.jsonl"
make_transcript "$TRANSCRIPT6" 'Status: partial
核心逻辑完成，文档未写。<promise>DONE</promise>'
OUT6=$(run_hook "$HOME6" "$PROJ6" "$TRANSCRIPT6" "partial-session")
if grep -q 'partial 是合法收尾' <<<"$OUT6" && grep -q '"decision": "block"' <<<"$OUT6" && \
   [ -f "$STATE6" ] && grep -q '^iteration: 2$' "$STATE6"; then
  record_pass "partial header takes continue path with guidance"
else
  record_fail "partial header takes continue path with guidance"
  printf '%s\n' "$OUT6"
  cat "$STATE6" || true
fi

# ── Orphan recovery: stale state is ARCHIVED, not deleted ────────────────
HOME7="$TMP_ROOT/home-orphan"
PROJ7="$TMP_ROOT/project-orphan"
mkdir -p "$HOME7/.claude/pua" "$PROJ7/.claude"
HASH7=$(cwd_hash "$PROJ7")
STATE7="$HOME7/.claude/pua/loop-${HASH7}.md"
cat > "$STATE7" <<STATE
---
active: true
iteration: 3
session_id: orphan-session
max_iterations: 0
completion_promise: "DONE"
verify_command: null
promise_rejections: 0
started_cwd: "$PROJ7"
---

Old reflection content that must survive
STATE
touch -d '40 minutes ago' "$STATE7" 2>/dev/null || touch -A -020000 "$STATE7"
OUT7=$(run_hook "$HOME7" "$PROJ7" "$PROJ7/transcript.jsonl" "orphan-session")
ARCHIVE7="$HOME7/.claude/pua/archived"
if [ ! -f "$STATE7" ] && compgen -G "$ARCHIVE7/loop-${HASH7}-*.md" >/dev/null && \
   grep -q 'Old reflection content' "$ARCHIVE7"/loop-${HASH7}-*.md; then
  record_pass "orphan state archived with content preserved"
else
  record_fail "orphan state archived with content preserved"
  printf '%s\n' "$OUT7"
  ls -la "$ARCHIVE7" 2>/dev/null || true
fi
if grep -q '"status":"orphan_archived"' "$HOME7/.claude/pua/loop-history.jsonl" 2>/dev/null || \
   grep -q '"status":"orphan_archived"' "$PROJ7/.claude/pua-loop-history.jsonl" 2>/dev/null; then
  record_pass "orphan archive logged in history"
else
  record_fail "orphan archive logged in history"
fi

# ── Settlement protection: stale state + FRESH verify result is NOT archived ─
# 断言 b1)（fix：归档分支遇新鲜 verify-<hash>.result/.pending 必须跳过归档等
# 结算，否则 promise 后合法等待 >30min 的活跃 loop 被归档、verify 永不结算）。
# result 内容为 0 → 跳过归档后走收割 → PROMISE ACCEPTED。
HOME8="$TMP_ROOT/home-settle-protect"
PROJ8="$TMP_ROOT/project-settle-protect"
mkdir -p "$HOME8/.claude/pua" "$PROJ8/.claude"
HASH8=$(cwd_hash "$PROJ8")
STATE8=$(create_state "$HOME8" "$PROJ8" "null" "settle-session")
touch -d '40 minutes ago' "$STATE8" 2>/dev/null || touch -A -020000 "$STATE8"
printf '0' > "$HOME8/.claude/pua/verify-${HASH8}.result"
TRANSCRIPT8="$PROJ8/transcript.jsonl"
make_transcript "$TRANSCRIPT8" '<promise>DONE</promise>'
OUT8=$(run_hook "$HOME8" "$PROJ8" "$TRANSCRIPT8" "settle-session")
if ! compgen -G "$HOME8/.claude/pua/archived/loop-${HASH8}-*.md" >/dev/null && \
   [ ! -f "$STATE8" ] && \
   grep -q '"status":"complete"' "$PROJ8/.claude/pua-loop-history.jsonl" 2>/dev/null && \
   ! grep -q '"status":"orphan_archived"' "$HOME8/.claude/pua/loop-history.jsonl" 2>/dev/null; then
  record_pass "stale state with fresh verify result settles instead of archiving"
else
  record_fail "stale state with fresh verify result settles instead of archiving"
  printf '%s\n' "$OUT8"
  ls "$HOME8/.claude/pua/archived" 2>/dev/null || true
fi

# ── Settlement protection: fresh .pending also blocks archiving ───────────
# 断言 b2) pending（verify 正在后台跑）同样触发保护；收割只认 .result，故
# 跳过归档后走 continue 路径，state 保留且 iteration 递增。
HOME8P="$TMP_ROOT/home-pending-protect"
PROJ8P="$TMP_ROOT/project-pending-protect"
mkdir -p "$HOME8P/.claude/pua" "$PROJ8P/.claude"
HASH8P=$(cwd_hash "$PROJ8P")
STATE8P=$(create_state "$HOME8P" "$PROJ8P" "null" "pending-session")
touch -d '40 minutes ago' "$STATE8P" 2>/dev/null || touch -A -020000 "$STATE8P"
printf '0' > "$HOME8P/.claude/pua/verify-${HASH8P}.pending"
TRANSCRIPT8P="$PROJ8P/transcript.jsonl"
make_transcript "$TRANSCRIPT8P" '继续推进任务，暂无 promise'
OUT8P=$(run_hook "$HOME8P" "$PROJ8P" "$TRANSCRIPT8P" "pending-session")
if ! compgen -G "$HOME8P/.claude/pua/archived/loop-${HASH8P}-*.md" >/dev/null && \
   [ -f "$STATE8P" ] && grep -q '^iteration: 2$' "$STATE8P"; then
  record_pass "fresh pending verify blocks orphan archiving and continues"
else
  record_fail "fresh pending verify blocks orphan archiving and continues"
  printf '%s\n' "$OUT8P"
  ls "$HOME8P/.claude/pua/archived" 2>/dev/null || true
fi

# ── Legacy copy cleanup must NOT delete copies from other project dirs ────
# 断言 c2) cleanup 只删 started_cwd 匹配当前 pwd 的 legacy 副本；指向其他
# 项目目录的副本必须保留（legacy 是相对路径文件名，多项目可能各有一份）。
HOME9="$TMP_ROOT/home-legacy-nomatch"
PROJ9="$TMP_ROOT/project-legacy-nomatch"
mkdir -p "$HOME9" "$PROJ9"
STATE9=$(create_state "$HOME9" "$PROJ9" "null" "legacy-session")
mkdir -p "$PROJ9/.claude"
cat > "$PROJ9/.claude/pua-loop.local.md" <<'LEGACY'
---
active: true
iteration: 2
session_id: legacy-session
max_iterations: 0
completion_promise: "DONE"
verify_command: null
promise_rejections: 0
started_cwd: "/some/other/project"
---

Other project reflection
LEGACY
TRANSCRIPT9="$PROJ9/transcript.jsonl"
make_transcript "$TRANSCRIPT9" '任务完成。<promise>DONE</promise> commands run: `npm test` 全部绿'
OUT9=$(run_hook "$HOME9" "$PROJ9" "$TRANSCRIPT9" "legacy-session")
if grep -q '证据赎回通过' <<<"$OUT9" && [ -f "$PROJ9/.claude/pua-loop.local.md" ] && \
   ! grep -q '^started_cwd: "'"$PROJ9"'"$' "$PROJ9/.claude/pua-loop.local.md"; then
  record_pass "legacy copy with non-matching started_cwd is preserved"
else
  record_fail "legacy copy with non-matching started_cwd is preserved"
  printf '%s\n' "$OUT9"
  cat "$PROJ9/.claude/pua-loop.local.md" 2>/dev/null || echo "    legacy copy was deleted"
fi

# ── Session injection tolerates / & \\ in session_id ──────────────────────
# 断言 d)（fix：原 sed 替换串未转义，session_id 含 / 或 & 时替换报错/产出坏值，
# 改为 awk match+substr 重组，无替换串转义层）。state 的 session_id 为空触发
# 注入路径。
HOME10="$TMP_ROOT/home-session-inject"
PROJ10="$TMP_ROOT/project-session-inject"
mkdir -p "$HOME10" "$PROJ10"
STATE10=$(create_state "$HOME10" "$PROJ10" "null" "inject-session")
# create_state 的 ${4:-} 对空串取默认值，这里显式清空 session_id 触发注入路径
TEMP_S10="${STATE10}.prep"
sed 's/^session_id:.*/session_id: /' "$STATE10" > "$TEMP_S10" && mv "$TEMP_S10" "$STATE10"
TRANSCRIPT10="$PROJ10/transcript.jsonl"
make_transcript "$TRANSCRIPT10" '继续推进任务，暂无 promise'
OUT10=$(run_hook "$HOME10" "$PROJ10" "$TRANSCRIPT10" 'sess/abc&def\ghi')
if grep -q '"decision": "block"' <<<"$OUT10" && [ -f "$STATE10" ] && \
   grep -Fqx 'session_id: sess/abc&def\ghi' "$STATE10"; then
  record_pass "session injection survives / & backslash in session id"
else
  record_fail "session injection survives / & backslash in session id"
  printf '%s\n' "$OUT10"
  grep '^session_id:' "$STATE10" 2>/dev/null || true
fi

echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
