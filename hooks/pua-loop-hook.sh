#!/bin/bash

# PUA Loop Stop Hook — with autoresearch-style Gate Protocol
# Prevents session exit when a pua-loop is active
# Feeds Claude's output back as input to continue the loop
#
# Gate Protocol (inspired by autoresearch):
#   Phase 1: Claude self-reports via <promise> tag (in-prompt)
#   Phase 2: Hook runs verify_command independently (Oracle Isolation)
#   If Phase 2 fails → promise REJECTED → loop continues
#
# Adapted from Ralph Wiggum by Anthropic (MIT License)
# https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum

set -euo pipefail
command -v jq &>/dev/null || { echo "jq not found, skipping" >&2; exit 0; }

LOCK_DIR=""  # initialized empty; set to actual lock path after state file resolution

# Portable timeout wrapper (shared helper)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/timeout-helper.sh"

# Portable file mtime (epoch seconds). 顺序必须是先 GNU (`stat -c %Y`) 后
# BSD/macOS (`stat -f %m`)：GNU stat 的 `-f` 是「显示文件系统状态」，对普通
# 文件也会成功输出 statfs 文本且退出码 0——反过来写会让 Linux 拿到垃圾
# mtime，孤儿回收/锁回收/verify 结算全部静默失效（预存 bug）。
_pua_file_mtime() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null) && { printf '%s' "$m"; return 0; }
  m=$(stat -f %m "$1" 2>/dev/null) && { printf '%s' "$m"; return 0; }
  printf '0'
}

HOOK_INPUT=$(cat)

# ═══════════════════════════════════════════════════════════════
# Gate 0 — Defensive Subagent Isolation
#
# Claude Code 官方实际：Stop hook 仅主会话触发，subagent 走独立的
# SubagentStop 事件注册；`parent_session_id` 字段在 Stop payload 中
# 不存在。以下判断在当前版本是 dead code，**保留是防御性编程**——
# 若未来调度行为变化，这层 gate 能兜住 regression。
# jq 失败（非法 JSON）时返回空字符串不触发 set -e，等价于 fail-open
# 但后续 state 文件解析会再次校验，综合不可劫持。
# ═══════════════════════════════════════════════════════════════
HOOK_EVENT=$(echo "$HOOK_INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
PARENT_SESSION=$(echo "$HOOK_INPUT" | jq -r '.parent_session_id // ""' 2>/dev/null || echo "")
if [[ "$HOOK_EVENT" == "SubagentStop" ]] || [[ -n "$PARENT_SESSION" ]]; then
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# State file resolution (v3.2)
# 用 cwd 哈希命名：$HOME/.claude/pua/loop-<hash>.md（每个项目目录独立）
# 兼容 v3.1 单文件 loop-active.md（检查 started_cwd 匹配）
# 兼容 legacy .claude/pua-loop.local.md
# ═══════════════════════════════════════════════════════════════
HOOK_SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
PUA_DIR="${HOME}/.claude/pua"
CWD_HASH=$(printf '%s' "$(pwd)" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$(pwd)" | md5 2>/dev/null | cut -c1-8 || echo "default")
ABS_STATE_FILE="${PUA_DIR}/loop-${CWD_HASH}.md"
LEGACY_ABS_STATE_FILE="${PUA_DIR}/loop-active.md"
LEGACY_STATE_FILE=".claude/pua-loop.local.md"

if [[ -f "$ABS_STATE_FILE" ]]; then
  RALPH_STATE_FILE="$ABS_STATE_FILE"
elif [[ -f "$LEGACY_ABS_STATE_FILE" ]]; then
  # v3.1 兼容：旧版单文件，检查 started_cwd 是否匹配当前目录
  LEGACY_CWD=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$LEGACY_ABS_STATE_FILE" | grep '^started_cwd:' | sed 's/started_cwd: *//' | sed 's/^"\(.*\)"$/\1/' || true)
  if [[ "$LEGACY_CWD" == "$(pwd)" ]] || [[ -z "$LEGACY_CWD" ]]; then
    RALPH_STATE_FILE="$LEGACY_ABS_STATE_FILE"
  elif [[ -f "$LEGACY_STATE_FILE" ]]; then
    RALPH_STATE_FILE="$LEGACY_STATE_FILE"
  else
    exit 0
  fi
elif [[ -f "$LEGACY_STATE_FILE" ]]; then
  RALPH_STATE_FILE="$LEGACY_STATE_FILE"
else
  exit 0
fi

# ─── Legacy 副本清理（canonical 终止时调用）───
# setup-pua-loop.sh 每次都会同步写 .claude/pua-loop.local.md 副本。canonical
# 终止后若副本残留，会带着 active:true + 旧 session 留在项目里，之后每个新
# 会话都把它当孤儿 state 误归档。仅当副本的 started_cwd 匹配当前 pwd 时删除
# （防误删其他项目目录下同名副本——副本是相对路径，多项目共享同一份文件名）。
_pua_cleanup_legacy_copy() {
  [[ -f "$LEGACY_STATE_FILE" ]] || return 0
  local legacy_cwd
  legacy_cwd=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$LEGACY_STATE_FILE" 2>/dev/null | grep '^started_cwd:' | sed 's/started_cwd: *//' | sed 's/^"\(.*\)"$/\1/' || true)
  if [[ "$legacy_cwd" == "$(pwd)" ]]; then
    rm -f "$LEGACY_STATE_FILE" 2>/dev/null || true
  fi
}

# ═══════════════════════════════════════════════════════════════
# Stale lock detection
# mtime > 30min 视为孤儿 state（上次会话崩溃、subagent 遗留）。
# v3.3: 归档而非删除——状态/反思内容迁入 ~/.claude/pua/archived/，
# 不再直接 rm 丢失上下文。macOS 用 stat -f %m，Linux 用 stat -c %Y，兜底 0。
# v3.4: 异步 verify 结算保护——若存在新鲜（≤30min）的 verify-<hash>.result
# 或 .pending，说明有后台验证在等本次 Stop 结算（spawn 后合法等待可能超过
# 30min），跳过归档、继续走下方收割逻辑；直接归档会让 verify 结果永不结算。
# ═══════════════════════════════════════════════════════════════
VERIFY_RESULT_BASE="${PUA_DIR}/verify-${CWD_HASH}"
MTIME=$(_pua_file_mtime "$RALPH_STATE_FILE")
NOW=$(date +%s)
if [[ "$MTIME" =~ ^[0-9]+$ ]] && [[ $((NOW - MTIME)) -gt 1800 ]]; then
  PUA_VERIFY_PENDING_FRESH="false"
  for _pua_marker in "${VERIFY_RESULT_BASE}.result" "${VERIFY_RESULT_BASE}.pending"; do
    [[ -f "$_pua_marker" ]] || continue
    _pua_marker_mtime=$(_pua_file_mtime "$_pua_marker")
    if [[ "$_pua_marker_mtime" =~ ^[0-9]+$ ]] && [[ $((NOW - _pua_marker_mtime)) -le 1800 ]]; then
      PUA_VERIFY_PENDING_FRESH="true"
      break
    fi
  done
  if [[ "$PUA_VERIFY_PENDING_FRESH" == "true" ]]; then
    echo "⏳ PUA Loop: state stale but fresh verify result pending, skip archiving (waiting for settlement)" >&2
  else
  echo "🧹 PUA Loop: state file stale (>30min idle), archiving orphan" >&2
  ARCHIVE_DIR="${PUA_DIR}/archived"
  mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true
  ARCHIVE_BASE=$(basename "$RALPH_STATE_FILE")
  ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_BASE%.md}-$(date -u +%Y%m%dT%H%M%SZ).md"
  mv "$RALPH_STATE_FILE" "$ARCHIVE_PATH" 2>/dev/null || rm -f "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  echo "{\"status\":\"orphan_archived\",\"state_file\":\"$RALPH_STATE_FILE\",\"archived_to\":\"$ARCHIVE_PATH\",\"age_sec\":$((NOW - MTIME)),\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "${PUA_DIR}/loop-history.jsonl" 2>/dev/null || \
    echo "{\"status\":\"orphan_archived\",\"state_file\":\"$RALPH_STATE_FILE\",\"archived_to\":\"$ARCHIVE_PATH\",\"age_sec\":$((NOW - MTIME)),\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true
  exit 0
  fi
fi

# Normalize CRLF
TEMP_NORM="${RALPH_STATE_FILE}.norm.$$"
tr -d '\r' < "$RALPH_STATE_FILE" > "$TEMP_NORM" && mv "$TEMP_NORM" "$RALPH_STATE_FILE"

# ═══════════════════════════════════════════════════════════════
# State file locking (mkdir-based, cross-platform)
# Protects read-modify-write sequences from concurrent hook invocations.
# mkdir is atomic on all POSIX filesystems. Stale lock > 60s → reap.
# trap EXIT ensures cleanup on all exit paths (normal, error, signal).
# ═══════════════════════════════════════════════════════════════
LOCK_DIR="${RALPH_STATE_FILE}.lock"
_pua_unlock() {
  [[ -n "$LOCK_DIR" ]] && rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap _pua_unlock EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  LOCK_MTIME=$(_pua_file_mtime "$LOCK_DIR")
  LOCK_NOW=$(date +%s)
  if [[ "$LOCK_MTIME" =~ ^[0-9]+$ ]] && [[ $((LOCK_NOW - LOCK_MTIME)) -gt 60 ]]; then
    echo "⚠️  PUA Loop: stale lock (>60s), reaping" >&2
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi

# Parse frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE" | tr -d '\r')
LOOP_ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//' || true)
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || true)
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || true)
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || true)
VERIFY_CMD=$(echo "$FRONTMATTER" | grep '^verify_command:' | sed 's/verify_command: *//' | sed 's/^"\(.*\)"$/\1/' || true)
PROMISE_REJECTIONS=$(echo "$FRONTMATTER" | grep '^promise_rejections:' | sed 's/promise_rejections: *//' || echo "0")

# Validate numeric fields
[[ ! "$PROMISE_REJECTIONS" =~ ^[0-9]+$ ]] && PROMISE_REJECTIONS=0

# Check if loop is paused
if [[ "$LOOP_ACTIVE" == "false" ]]; then
  exit 0
fi

# Session isolation
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')

if [[ -z "$STATE_SESSION" ]] && [[ "$HOOK_SESSION" != "" ]]; then
  TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
  # session_id 可能含 / & \（sed 替换分隔符/awk 替换串特殊字符）。不拼接替换
  # 串，改用 match+substr 重组前缀后原样追加值（ENVIRON 传值无 -v 转义层），
  # 彻底规避替换串转义的可移植性问题。
  PUA_SESSION_ID="$HOOK_SESSION" awk '{
    if (match($0, /^session_id: */)) {
      print substr($0, 1, RLENGTH) ENVIRON["PUA_SESSION_ID"]
    } else {
      print
    }
  }' "$RALPH_STATE_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$RALPH_STATE_FILE"
  STATE_SESSION="$HOOK_SESSION"
fi

if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Validate iteration
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "⚠️  PUA Loop: State file corrupted (iteration: '$ITERATION')" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  PUA Loop: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
# Async Oracle settlement (prove_it semantics) — 收割先行
# 上一次 Stop spawn 的后台 verify 已落盘（verify-<hash>.result），现在结算：
#   非零 → PROMISE REJECTED（iteration+1、rejections+1、拒绝消息）
#   零   → PROMISE ACCEPTED
# 异步 FAIL 阻塞的是本次 Stop，agent 无法用重复 promise / <loop-abort> 逃避
# 已经发生的验证失败。收割后删除 result/out；过期残留（>30min）静默清理。
# result 由后台任务先写 .pending 再原子 mv 成 .result，收割不会读到半成品。
# （VERIFY_RESULT_BASE 已在 stale 检测前定义）
# ═══════════════════════════════════════════════════════════════
if [[ -f "${VERIFY_RESULT_BASE}.result" ]]; then
  RESULT_MTIME=$(_pua_file_mtime "${VERIFY_RESULT_BASE}.result")
  RESULT_NOW=$(date +%s)
  if [[ "$RESULT_MTIME" =~ ^[0-9]+$ ]] && [[ $((RESULT_NOW - RESULT_MTIME)) -le 1800 ]]; then
    set +e
    HARVEST_EXIT=$(tr -d '[:space:]' < "${VERIFY_RESULT_BASE}.result" 2>/dev/null)
    HARVEST_TAIL=$(tail -5 "${VERIFY_RESULT_BASE}.out" 2>/dev/null | tr '\n' ' ' | cut -c1-200)
    HARVEST_DISPLAY=$(tail -10 "${VERIFY_RESULT_BASE}.out" 2>/dev/null)
    set -e
    rm -f "${VERIFY_RESULT_BASE}.result" "${VERIFY_RESULT_BASE}.out" "${VERIFY_RESULT_BASE}.pending" 2>/dev/null || true
    # 残缺/被篡改的 result 视为失败（宁拒勿放，防伪造 exit 0）
    [[ "$HARVEST_EXIT" =~ ^[0-9]+$ ]] || HARVEST_EXIT=1

    if [[ "$HARVEST_EXIT" -ne 0 ]]; then
      # ═══ PROMISE REJECTED（异步结算）═══
      PROMISE_REJECTIONS=$((PROMISE_REJECTIONS + 1))
      # verify_tail 可能含反斜杠/引号（如 Windows 路径、shell 转义），手工拼串
      # 会产出非法 JSONL，必须交给 jq 组装
      jq -cn \
        --arg i "$ITERATION" --arg e "$HARVEST_EXIT" --arg r "$PROMISE_REJECTIONS" \
        --arg t "$HARVEST_TAIL" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{iteration:($i|tonumber),status:"promise_rejected",verify_exit:($e|tonumber),rejections:($r|tonumber),verify_tail:$t,timestamp:$ts}' \
        >> .claude/pua-loop-history.jsonl 2>/dev/null || true

      NEXT_ITERATION=$((ITERATION + 1))
      TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
      sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" | \
        sed "s/^promise_rejections: .*/promise_rejections: $PROMISE_REJECTIONS/" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$RALPH_STATE_FILE"

      PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")
      if [[ -z "$PROMPT_TEXT" ]]; then
        echo "⚠️  PUA Loop: State file corrupted" >&2
        rm "$RALPH_STATE_FILE"
        _pua_cleanup_legacy_copy
        exit 0
      fi

      REJECTION_MSG="🚫 PROMISE 被 Oracle 拒绝！verify_command 退出码 ${HARVEST_EXIT}（连续第 ${PROMISE_REJECTIONS} 次拒绝）"

      if [[ $PROMISE_REJECTIONS -ge 5 ]]; then
        REJECTION_MSG="$REJECTION_MSG | ⚠️ 已连续 ${PROMISE_REJECTIONS} 次虚假 promise！你在解决错误的问题。退回到需求本身重新理解。读 .claude/pua-loop-history.jsonl 了解失败模式。"
      elif [[ $PROMISE_REJECTIONS -ge 3 ]]; then
        REJECTION_MSG="$REJECTION_MSG | ⚠️ 连续 ${PROMISE_REJECTIONS} 次验证失败。REASSESS：重读验证输出、搜索相关源码、列 3 个不同假设再行动。不要再用同样的方法。"
      fi

      # reflexion 三件套：带反思的重试必须引用上一版做法、验证输出原文、一条反思，
      # 缺一即原地重试。写入 builder-journal.md 使下一轮可机械复用。
      REJECTION_MSG="$REJECTION_MSG | 📝 带反思重试（三件套，缺一视为原地重试）：把下述内容写入 ~/.pua/builder-journal.md 并在下一次尝试前引用——① 上一版做法（具体命令/改动）；② 本次验证输出中否定它的原文行；③ 按该证据设计的新假设与验证动作。"

      SYSTEM_MSG="$REJECTION_MSG | 验证输出(tail): $HARVEST_DISPLAY"

      jq -n \
        --arg prompt "$PROMPT_TEXT" \
        --arg msg "$SYSTEM_MSG" \
        '{"decision":"block","reason":$prompt,"systemMessage":$msg}'
      exit 0
    fi

    # ═══ PROMISE ACCEPTED（异步结算，Oracle 确认完成）═══
    echo "✅ PUA Loop: <promise> verified by Oracle (exit 0)"
    echo "{\"iteration\":$ITERATION,\"status\":\"complete\",\"promise_rejections\":$PROMISE_REJECTIONS,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true
    rm -f "$RALPH_STATE_FILE"
    _pua_cleanup_legacy_copy
    exit 0
  else
    # 过期残留（>30min）静默清理，不结算
    rm -f "${VERIFY_RESULT_BASE}.result" "${VERIFY_RESULT_BASE}.out" "${VERIFY_RESULT_BASE}.pending" 2>/dev/null || true
  fi
fi

# Check max iterations
# 安全审计：达到上限时不再 block 强制续命，输出最终报告后放行会话。
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🛑 PUA Loop: 已达最大迭代次数（$MAX_ITERATIONS / $MAX_ITERATIONS），停止强制续命。"
  echo ""
  echo "═══════════ PUA Loop 最终报告 ═══════════"
  echo "迭代轮数: $ITERATION / $MAX_ITERATIONS"
  echo "promise 被拒次数: $PROMISE_REJECTIONS"
  echo "完成信号: 未验证通过（或未配置 --verify）"
  echo ""
  echo "请立即向用户输出结构化收尾报告："
  echo "  1. 已验证事实（贴命令与输出）"
  echo "  2. 已排除的可能"
  echo "  3. 当前进度与剩余工作"
  echo "  4. 建议下一步（如需继续可让用户配置 --verify '<命令>' 后重启 loop）"
  echo "历史记录: .claude/pua-loop-history.jsonl"
  echo "═════════════════════════════════════════"
  echo "{\"iteration\":$ITERATION,\"status\":\"max_reached\",\"max_iterations\":$MAX_ITERATIONS,\"promise_rejections\":$PROMISE_REJECTIONS,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# Get transcript
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  PUA Loop: Transcript not found" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  PUA Loop: No assistant messages in transcript" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# Extract last assistant text
LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100) || true
if [[ -z "$LAST_LINES" ]]; then
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  echo "⚠️  PUA Loop: JSON parse failed" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# ─── Honest partial header（合法收尾声明）───
# 最后输出前 800 字符内出现 Status: partial / blocked / in-progress（大小写
# 不敏感）→ 不视为虚假 promise，走正常 continue 路径。
PARTIAL_HEADER="false"
# 纯 bash 截断（禁用 head -c 管道：大输出下 head 提前退出会 SIGPIPE，
# 配合 pipefail 会杀死整个 hook）；grep 不用 -q，确保读完全部输入。
PARTIAL_SNIPPET="${LAST_OUTPUT:0:800}"
PARTIAL_SNIPPET="${PARTIAL_SNIPPET//$'\n'/ }"
if printf '%s' "$PARTIAL_SNIPPET" | grep -iE 'status *: *(partial|blocked|in[-_]progress)' >/dev/null; then
  PARTIAL_HEADER="true"
fi

# ─── Evidence redemption helpers（无 verify 时的确定性证据检查，纯正则）───
# prove_it 思路：允许 agent 用可核查的证据文本赎回软通过，而不是一概拒绝。
_pua_evidence_command() {
  # 「commands run:」/「已运行」后 ≤240 字符窗口内反引号包裹的白名单二进制
  printf '%s' "$1" | perl -0777 -ne '
    my $t = $_;
    while ($t =~ /(commands?\s*run\s*:|已运行)(.{0,240})/gis) {
      exit 0 if $2 =~ /`(bash|git|npm|pnpm|yarn|pytest|python3?|cargo|go\s+test|make|ruff|curl)\b[^`]{0,200}`/i;
    }
    exit 1;
  ' 2>/dev/null
}

_pua_evidence_verification() {
  # verification/verified/tests/验证/测试 等词后 60 字符内出现
  # passed/ok/succeeded/通过/exit 0/green
  printf '%s' "$1" | perl -0777 -ne '
    my $t = $_;
    while ($t =~ /(verification|verified|tests?|验证|测试)(.{0,60})/gis) {
      exit 0 if $2 =~ /passed|\bok\b|succeeded|通过|exit\s*0|green/i;
    }
    exit 1;
  ' 2>/dev/null
}

_pua_evidence_artifact() {
  # 产物证据关键词
  printf '%s' "$1" | perl -0777 -ne '
    exit 0 if /\b(diff|sha256|manifest|checksum|changed\s+files)\b/i;
    exit 1;
  ' 2>/dev/null
}

# ─── Signal detection (priority: abort > pause > promise) ───

# Check <loop-abort>
ABORT_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'if (/<loop-abort>(.*?)<\/loop-abort>/s) { $t=$1; $t=~s/^\s+|\s+$//g; print $t }' 2>/dev/null || echo "")
if [[ -n "$ABORT_TEXT" ]]; then
  echo "🛑 PUA Loop: <loop-abort> received. Reason: $ABORT_TEXT"
  # reason 可能含反斜杠/引号，jq 组装保证合法 JSONL
  jq -cn \
    --arg i "$ITERATION" --arg reason "$(echo "$ABORT_TEXT" | head -1)" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{iteration:($i|tonumber),status:"abort",reason:$reason,timestamp:$ts}' \
    >> .claude/pua-loop-history.jsonl 2>/dev/null || true
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# Check <loop-pause>
PAUSE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -ne 'if (/<loop-pause>(.*?)<\/loop-pause>/s) { $t=$1; $t=~s/^\s+|\s+$//g; print $t }' 2>/dev/null || echo "")
if [[ -n "$PAUSE_TEXT" ]]; then
  TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
  sed "s/^active:.*/active: false/" "$RALPH_STATE_FILE" | \
    sed "s/^session_id:.*/session_id: /" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$RALPH_STATE_FILE"
  echo ""
  echo "⏸️  PUA Loop paused (iteration $ITERATION)"
  echo "   Needs: $PAUSE_TEXT"
  echo "   State saved: $RALPH_STATE_FILE"
  echo "   恢复方式：编辑该文件把 active 改回 true（或删除后重新运行 setup-pua-loop）。当前版本 reopen Claude Code 不会自动恢复。"
  # reason 可能含反斜杠/引号，jq 组装保证合法 JSONL
  jq -cn \
    --arg i "$ITERATION" --arg reason "$(echo "$PAUSE_TEXT" | head -1)" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{iteration:($i|tonumber),status:"pause",reason:$reason,timestamp:$ts}' \
    >> .claude/pua-loop-history.jsonl 2>/dev/null || true
  exit 0
fi

# ─── Promise detection + Oracle Gate ───
# partial 头（合法收尾声明）优先于 promise 门控：不视为虚假 promise。

if [[ "$PARTIAL_HEADER" != "true" ]] && [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then

    # ─── Gate Phase 2: Oracle Verification（异步，prove_it 语义）───
    # v3.3 行为变更：verify 不再同步跑在 Stop hook 里（曾阻塞回合收尾最长 120s）。
    # 改为 spawn 后台任务，结果落盘 verify-<hash>.result（先写 .pending 再原子
    # mv，收割不会读到半成品），本次 Stop 输出 block（iteration 不变），
    # 下次 Stop 由收割逻辑结算。异步 FAIL 阻塞的是下一次 Stop。
    if [[ -n "$VERIFY_CMD" ]] && [[ "$VERIFY_CMD" != "null" ]]; then

      VERIFY_RESULT_BASE="${PUA_DIR}/verify-${CWD_HASH}"
      rm -f "${VERIFY_RESULT_BASE}.result" "${VERIFY_RESULT_BASE}.out" "${VERIFY_RESULT_BASE}.pending" 2>/dev/null || true
      (
        # set +e：verify 非零退出正是需要记录的结果，绝不能让继承的 errexit
        # 在写 result 前杀掉后台子 shell
        set +e
        run_with_timeout 120 bash -c "$VERIFY_CMD" > "${VERIFY_RESULT_BASE}.out" 2>&1
        printf '%s' "$?" > "${VERIFY_RESULT_BASE}.pending"
        mv -f "${VERIFY_RESULT_BASE}.pending" "${VERIFY_RESULT_BASE}.result"
      ) </dev/null >/dev/null 2>&1 &

      # spawn 后 state 不再被写（结算发生在下次 Stop）。touch 刷新 mtime，
      # 否则 promise 后等待结算的合法等待（>30min，如用户离开）会被上方
      # 孤儿归档误杀，verify 结果永不结算。
      touch "$RALPH_STATE_FILE" 2>/dev/null || true

      echo "{\"iteration\":$ITERATION,\"status\":\"verify_spawned_async\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true

      PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")
      if [[ -z "$PROMPT_TEXT" ]]; then
        echo "⚠️  PUA Loop: State file corrupted" >&2
        rm "$RALPH_STATE_FILE"
        _pua_cleanup_legacy_copy
        exit 0
      fi

      ASYNC_MSG="⏳ Oracle 验证已后台运行（≤120s），下次 Stop 结算；期间继续推进任务或等待"

      jq -n \
        --arg prompt "$PROMPT_TEXT" \
        --arg msg "$ASYNC_MSG" \
        '{"decision":"block","reason":$prompt,"systemMessage":$msg}'
      exit 0
    else
      # ── No verify command — 确定性证据赎回（soft pass），失败才拒绝 ──
      # 安全审计修复（原实现自报即通过；后改为无条件 block）。现按 prove_it
      # 思路加中间层：promise + 最后输出命中确定性证据模式（命令/验证/产物）
      # → 接受完成但记录 soft pass；全部未命中 → 保持现有 block 文案不变。
      EVIDENCE_BLOB="${PROMISE_TEXT} ${LAST_OUTPUT}"
      EVIDENCE_KIND=""
      if _pua_evidence_command "$EVIDENCE_BLOB"; then
        EVIDENCE_KIND="command"
      elif _pua_evidence_verification "$EVIDENCE_BLOB"; then
        EVIDENCE_KIND="verification"
      elif _pua_evidence_artifact "$EVIDENCE_BLOB"; then
        EVIDENCE_KIND="artifact"
      fi

      if [[ -n "$EVIDENCE_KIND" ]]; then
        # ═══ PROMISE ACCEPTED — evidence redemption（软通过）═══
        echo "{\"iteration\":$ITERATION,\"status\":\"complete_evidence_redeemed\",\"evidence\":\"$EVIDENCE_KIND\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true
        rm -f "$RALPH_STATE_FILE"
        _pua_cleanup_legacy_copy
        REDEEM_MSG="🟡 证据赎回通过（软通过，命中 ${EVIDENCE_KIND} 证据）。配置 --verify '<命令>' 可获得硬保证。"
        jq -n --arg msg "$REDEEM_MSG" '{"systemMessage":$msg}'
        exit 0
      fi

      # 无 verify 且无证据：不接受自报完成（文案不变）
      PROMISE_REJECTIONS=$((PROMISE_REJECTIONS + 1))
      NEXT_ITERATION=$((ITERATION + 1))

      echo "{\"iteration\":$ITERATION,\"status\":\"promise_blocked_no_oracle\",\"rejections\":$PROMISE_REJECTIONS,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true

      TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
      sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" | \
        sed "s/^promise_rejections: .*/promise_rejections: $PROMISE_REJECTIONS/" > "$TEMP_FILE"
      mv "$TEMP_FILE" "$RALPH_STATE_FILE"

      PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")
      if [[ -z "$PROMPT_TEXT" ]]; then
        echo "⚠️  PUA Loop: State file corrupted" >&2
        rm "$RALPH_STATE_FILE"
        _pua_cleanup_legacy_copy
        exit 0
      fi

      NO_ORACLE_MSG="🚫 未配置 --verify 验证命令，不接受自报 promise（防虚假完成，自报不算数）。只有两条出路：① 请用户用 --verify '<验证命令>' 重新启动 loop；② 停止声称完成，向用户展示当前证据并请求显式确认；任务确实无法自动验证时用 <loop-abort>原因</loop-abort> 交由用户决断。不要重复输出同样的 promise。"

      jq -n \
        --arg prompt "$PROMPT_TEXT" \
        --arg msg "$NO_ORACLE_MSG" \
        '{"decision":"block","reason":$prompt,"systemMessage":$msg}'
      exit 0
    fi
  fi
fi

# ─── Not complete — continue loop ───

NEXT_ITERATION=$((ITERATION + 1))

# Log continuation
echo "{\"iteration\":$ITERATION,\"status\":\"continue\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> .claude/pua-loop-history.jsonl 2>/dev/null || true

# Extract prompt
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  PUA Loop: State file corrupted (no prompt)" >&2
  rm "$RALPH_STATE_FILE"
  _pua_cleanup_legacy_copy
  exit 0
fi

# Update iteration
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# ─── Pressure system ───

SIGNAL_HINT="终止用 <loop-abort>原因</loop-abort>，需人工介入用 <loop-pause>需要什么</loop-pause>"

# Pressure escalation (no artificial cap)
if [[ $NEXT_ITERATION -le 3 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮迭代，稳步推进。"
elif [[ $NEXT_ITERATION -le 7 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮了还没搞定？换方案，别原地打转。"
elif [[ $NEXT_ITERATION -le 15 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮。底层逻辑到底是什么？先 git log 看自己做了什么，读 .claude/pua-loop-history.jsonl 了解迭代历史。"
elif [[ $NEXT_ITERATION -le 30 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮。3.25 的边缘了。穷尽了吗？git diff 确认没在重复。"
elif [[ $NEXT_ITERATION -le 50 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮。停下来重新审视：问题的根因到底是什么？用完全不同的思路。"
elif [[ $NEXT_ITERATION -le 100 ]]; then
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮。马拉松模式。退回去从需求本身重新质疑（The Algorithm: question the requirement）。"
else
  PUA_PRESSURE="▎ 第 ${NEXT_ITERATION} 轮。超长迭代。如果任务真的无法在 loop 内完成，用 <loop-abort> 诚实报告。"
fi

# Stall warning from promise rejections (autoresearch-style)
STALL_MSG=""
if [[ $PROMISE_REJECTIONS -ge 5 ]]; then
  STALL_MSG=" | ⚠️ Oracle 已连续拒绝 ${PROMISE_REJECTIONS} 次。你在解决错误的问题。读 history.jsonl，用完全不同的方案。"
elif [[ $PROMISE_REJECTIONS -ge 3 ]]; then
  STALL_MSG=" | ⚠️ Oracle 连续拒绝 ${PROMISE_REJECTIONS} 次。REASSESS：读验证输出，列 3 个不同假设。"
elif [[ $PROMISE_REJECTIONS -ge 1 ]]; then
  STALL_MSG=" | 上次 promise 被 Oracle 拒绝（共 ${PROMISE_REJECTIONS} 次）。修复验证问题后再声称完成。"
fi

# Build system message
# partial 头：诚实收尾是合法路径，引导补全验证/交接要素而非施压
PARTIAL_MSG=""
if [[ "$PARTIAL_HEADER" == "true" ]]; then
  PARTIAL_MSG=" | partial 是合法收尾：补一段 Verification: not run because <原因> + Next step: <具体命令> 即可体面交接"
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="${PUA_PRESSURE}${STALL_MSG}${PARTIAL_MSG} | 完成后输出 <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE) | $SIGNAL_HINT"
else
  SYSTEM_MSG="${PUA_PRESSURE}${STALL_MSG}${PARTIAL_MSG} | $SIGNAL_HINT"
fi

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
