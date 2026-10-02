#!/bin/bash
# PUA Test-First hook (PostToolUse): red-green TDD state machine
# Adapted from prove_it's libexec/test-first, compact form:
#   idle --source edits x3--> needs_test --test written--> needs_red
#   needs_red --test FAILS--> needs_green --test PASSES--> idle
# Guards against the two classic fakes:
#   - a test that passes while still in needs_red may be vacuous → warn to
#     verify it fails with the fix reverted (red-green)
#   - source edits without ever seeing red skip the red step → remind

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/flavor-helper.sh"
PUA_PY="$(pua_python_cmd 2>/dev/null || true)"

PUA_CONFIG="$(pua_config_file)"
if [ -f "$PUA_CONFIG" ]; then
  ALWAYS_ON=$(pua_json_get "$PUA_CONFIG" always_on True)
  if is_false "$ALWAYS_ON"; then
    exit 0
  fi
fi
[ -n "$PUA_PY" ] || exit 0

PUA_DIR="$(pua_home_dir)/.pua"
export PUA_TDD_DIR="${PUA_DIR}/sessions"
mkdir -p "${PUA_TDD_DIR}"

HOOK_INPUT=$(cat)
[ -n "$HOOK_INPUT" ] || exit 0

set +e
DECISION=$("$PUA_PY" - "$HOOK_INPUT" <<'PYEOF' 2>/dev/null
import sys, os, json, re, hashlib, time, base64

tdd_dir = os.environ["PUA_TDD_DIR"]

def out(k, v):
    print(f"{k}={v}")

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

tool = str(data.get("tool_name", ""))
sid = str(data.get("session_id", "") or "unknown")
safe = re.sub(r"[^A-Za-z0-9._-]", "_", sid)[:80] or "unknown"
state_path = os.path.join(tdd_dir, f"tdd-{safe}.json")

try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    state = {"phase": "idle", "src_edits": 0}

TEST_COMMAND_RE = re.compile(
    r"(^|[;&|()\s])(npm|pnpm|yarn|bun)\s+(run\s+)?test\b|(^|[;&|()\s])(jest|vitest|pytest|py\.test|mocha|rake|gradle|mvn|phpunit|deno)\b"
    r"|(^|[;&|()\s])(cargo|go|mix|swift|dotnet|flutter)\s+test\b|(^|[;&|()\s])python3?\s+-m\s+pytest\b"
    r"|(^|[;&|()\s])make\s+(test|check)\b|(^|[;&|()\s])go\s+(\w[/\\])?test\b",
    re.I,
)
CODE_EXT_RE = re.compile(
    r"\.(js|mjs|cjs|jsx|ts|tsx|py|rs|go|java|kt|kts|rb|php|c|h|cc|cpp|hpp|cs|swift|dart|vue|svelte|scala|ex|exs|zig|lua|sol)$", re.I,
)
TEST_PATH_RE = re.compile(
    r"(^|/)(tests?|__tests__|spec)(/|[^/]*\.)|(^|/)test_[^/]*\.py$|_test\.(go|py)$|\.(test|spec)\.[A-Za-z0-9]+$",
    re.I,
)

result = data.get("tool_result", "")
exit_code = str(result.get("exit_code", result.get("exitCode", 0))) if isinstance(result, dict) else "0"

now = int(time.time())
phase = state.get("phase", "idle")
msg = None

if tool == "Bash":
    cmd = str((data.get("tool_input", {}) or {}).get("command", ""))[:500]
    if not TEST_COMMAND_RE.search(cmd):
        sys.exit(0)
    test_failed = exit_code not in ("0", "")
    if phase == "needs_red":
        if test_failed:
            phase = "needs_green"
            msg = "[PUA TDD 🔴→🟢] 红已见到。现在实现修复，让这个测试转绿——别改测试迁就实现。"
        else:
            msg = ("[PUA TDD ⚠️ 空洞测试嫌疑] 测试没见到红就直接过了。"
                   "验证它真的在测东西：暂时还原你的修复，这个测试必须失败（red-green）；"
                   "还原后依然绿 = 测试没咬合，重写。")
    elif phase == "needs_green":
        if test_failed:
            msg = "[PUA TDD 🟢] 还没绿。继续修，或确认失败原因不是测试本身脆弱。"
        else:
            phase = "idle"
            state["src_edits"] = 0
            msg = "[PUA TDD ✅ 红→绿闭环完成，回归保护就位。]"
    else:
        state["phase"] = phase
        state["updated"] = now
        try:
            with open(state_path, "w", encoding="utf-8") as f:
                json.dump(state, f, ensure_ascii=False)
        except OSError:
            pass
        sys.exit(0)
elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    ti = data.get("tool_input", {}) or {}
    path = str(ti.get("file_path", ti.get("notebook_path", "")))
    if not path:
        sys.exit(0)
    norm = path.replace("\\", "/")
    if TEST_PATH_RE.search(norm):
        if phase in ("idle", "needs_test"):
            phase = "needs_red"  # quiet transition; the requirement surfaces at run time
    elif CODE_EXT_RE.search(norm):
        if phase == "idle":
            state["src_edits"] = int(state.get("src_edits", 0)) + 1
            if state["src_edits"] >= 3:
                phase = "needs_test"
                state["src_edits"] = 0
                msg = ("[PUA TDD 🟡] 连续 3 次源码改动没见到测试。补一个能失败的测试再继续——"
                       "没测过的改动等于没改完。")
        elif phase == "needs_green":
            phase = "needs_test"
            state["src_edits"] = 0
            msg = "[PUA TDD 🟡] 新改动开始。下一个测试要先见红。"
    else:
        sys.exit(0)
else:
    sys.exit(0)

state["phase"] = phase
state["updated"] = now
try:
    tmp = f"{state_path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)
    os.replace(tmp, state_path)
except OSError:
    pass

# Own-state hygiene: tdd-*.json files belong to this hook (failure-detector's
# prune skips the tdd- prefix by convention), so stale ones are pruned here.
try:
    for name in os.listdir(tdd_dir):
        if not name.startswith("tdd-") or not name.endswith(".json"):
            continue
        p = os.path.join(tdd_dir, name)
        try:
            if now - os.stat(p).st_mtime > 7 * 86400:
                os.remove(p)
        except OSError:
            continue
except OSError:
    pass

out("ACTION", "MSG")
if msg:
    out("MSG_B64", base64.b64encode(msg.encode("utf-8")).decode("ascii"))
PYEOF
)
TF_RC=$?
set -e

if [ -z "$DECISION" ] && [ "$TF_RC" -ne 0 ]; then
  # 显性降级：python 崩溃时留痕后 fail-open（exit 0），
  # 同 failure-detector 的 256KB 半量轮转约定。
  pua_append_error_log "test-first" "python decision failed (exit $TF_RC)"
  exit 0
fi

if [ -z "$DECISION" ]; then
  exit 0
fi

ACTION=""
MSG_B64=""
while IFS= read -r line; do
  case "$line" in
    ACTION=*) ACTION="${line#ACTION=}" ;;
    MSG_B64=*) MSG_B64="${line#MSG_B64=}" ;;
  esac
done <<< "$DECISION"

if [ "$ACTION" = "MSG" ] && [ -n "$MSG_B64" ]; then
  printf '%s' "$MSG_B64" | base64 -d 2>/dev/null || true
  printf '\n'
fi
exit 0
