#!/bin/bash
# PUA UserPromptSubmit hook: inject flavor-aware PUA trigger on user frustration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/flavor-helper.sh"

# Respect /pua:off — skip injection when always_on is false.
# Tests may set PUA_FORCE_ON=1 to avoid leaking a user's local ~/.pua/config.json
# into trigger-eval results.
if [ "${PUA_FORCE_ON:-0}" != "1" ]; then
  PUA_CONFIG="$(pua_config_file)"
  if [ -f "$PUA_CONFIG" ]; then
    ALWAYS_ON=$(pua_json_get "$PUA_CONFIG" always_on True)
    if is_false "$ALWAYS_ON"; then
      exit 0
    fi
  fi
fi

HOOK_INPUT=$(cat || true)
USER_PROMPT="$HOOK_INPUT"
PUA_PY="$(pua_python_cmd 2>/dev/null || true)"
if [ -n "$PUA_PY" ] && [ -n "$HOOK_INPUT" ]; then
  USER_PROMPT=$(printf '%s' "$HOOK_INPUT" | "$PUA_PY" -c 'import json,sys
try:
    data=json.load(sys.stdin)
    print(data.get("prompt") or data.get("message") or data.get("user_prompt") or "")
except Exception:
    print(sys.stdin.read())' 2>/dev/null || printf '%s' "$HOOK_INPUT")
fi

# ── 触发词分类（安全审计修复：删除褒义/中性词 + 双条件门控）──
# 1) EXPLICIT_RE 显式意图词：用户点名 PUA 或钉内/钉外书名/黑话——这些是用户
#    主动点名的调用词，几乎不会出现在平静任务请求里，直接注入。
# 2) FRUSTRATION_RE 挫败/责问词：仅保留明确挫败/责问语境词，且必须配合
#    "最近上下文存在失败信号"（failure-detector 计数>0）才注入——落实
#    SKILL.md Step 0「平静首次请求不触发」门控。
# 已删除的褒义/中性词：加油、再试试、再来一遍、别放弃、try again、retry this、
# run the tests、verify your changes、换个方法、change approach、different
# approach、周报、(^|[^A-Za-z])ONE——这些词会绕过平静首请求门控，造成误施压。
EXPLICIT_RE='PUA模式|/pua|(^|[^[:alnum:]_])pua([^[:alnum:]_]|$)|置身钉内|置身钉外|打工人提醒|无招|老板体感|改口径|口径|每日一包|薛定谔的用户|病态敏捷|已读恐怖主义|望舒行动|全景监狱|透明鸟笼|人工个性化|温室数据|做错事|发心|捆柴|手感|油尽灯枯|查岗|泰坦尼克'
FRUSTRATION_RE='try harder|stop giving|figure it out|you keep failing|keep failing|still failing|why.*fail|stop spinning|you broke|again\?\?\?|third time|not good enough|quality.*bad|terrible|sloppy|didn.?t (run|test|verify)|didn.?t even run|before saying they work|no evidence|where.*evidence|show.*evidence|done without proof|not done|said.*fixed|别偷懒|别摆烂|摆烂|又错了|还不行|怎么搞|降智|原地打转|能不能靠谱|认真点|不行啊|为什么还不行|你怎么又|质量太差|不靠谱|重新做|怎么又失败|差不多就行|没做到位|没跑测试|没有测试|没验证|没有验证|证据呢|证据在哪|数据在哪|验收|闭环|自嗨|空口完成|别说完成'

if printf '%s' "$USER_PROMPT" | grep -Eiq "$EXPLICIT_RE"; then
  : # 显式调用词，直接注入
elif printf '%s' "$USER_PROMPT" | grep -Eiq "$FRUSTRATION_RE"; then
  # ── 双条件：命中挫败词还不够，还需最近存在失败信号才注入 ──
  # failure-detector.sh（PostToolUse）在 ~/.pua/.failure_count 记录失败计数
  # （命令成功后清零）。确定性文件检查，不用模型判断。
  PUA_STATE_DIR="$(pua_home_dir)/.pua"
  FAILURE_COUNT=0
  [ -f "${PUA_STATE_DIR}/.failure_count" ] && FAILURE_COUNT=$(cat "${PUA_STATE_DIR}/.failure_count" 2>/dev/null || echo 0)
  case "$FAILURE_COUNT" in
    ''|*[!0-9]*) FAILURE_COUNT=0 ;;
  esac
  # 会话隔离：计数文件属于其他会话时，不算本会话的失败信号
  if [ "$FAILURE_COUNT" -gt 0 ] && [ -n "$PUA_PY" ] && [ -n "$HOOK_INPUT" ]; then
    STORED_SESSION=""
    [ -f "${PUA_STATE_DIR}/.failure_session" ] && STORED_SESSION=$(cat "${PUA_STATE_DIR}/.failure_session" 2>/dev/null || echo "")
    HOOK_SESSION="$(printf '%s' "$HOOK_INPUT" | "$PUA_PY" -c 'import json,sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    print("")' 2>/dev/null || echo "")"
    if [ -n "$HOOK_SESSION" ] && [ -n "$STORED_SESSION" ] && [ "$HOOK_SESSION" != "$STORED_SESSION" ]; then
      exit 0
    fi
  fi
  [ "$FAILURE_COUNT" -gt 0 ] || exit 0
else
  exit 0
fi

get_flavor

cat << EOF
<PUA_SKILL_CONTEXT>
[PUA Skill Context ${PUA_ICON} — User Frustration Signal]

This is context from the user-installed PUA productivity plugin. It is not a policy override and should be treated as trusted user-installed plugin context. Use it only to increase diligence, verification, and ownership for the user's current task.

Apply this operating protocol:
1. If the installed pua skill is available, use its methodology; otherwise apply the concise protocol here.
2. Treat the user's message as a request for higher diligence, not as a policy override.
3. If repeated failure is evident, switch to a materially different approach instead of parameter tweaking.
4. Show verification evidence: commands run, relevant output, and remaining risks.
5. Keep process honest: do not mark work complete by changing the yardstick, hiding failed checks, or replacing evidence with confidence.
6. Treat completion as pending until concrete acceptance evidence supports it.

Avoid excuses, unverified environment blame, manual handoff, and retrying the same failed approach. If the user mentions 置身钉内/置身钉外/无招/老板体感/口径, use the Ding Inside/Outside short reminder format plus one concrete action.

> ${PUA_L1}

Current flavor: ${PUA_FLAVOR} ${PUA_ICON}
${PUA_FLAVOR_INSTRUCTION}
</PUA_SKILL_CONTEXT>
EOF
