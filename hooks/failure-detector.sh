#!/bin/bash
# PUA PostToolUse hook: pressure scoring + failure pattern analysis + breakthrough detection
#
# v3: score-based pressure model (replaces the pure failure counter)
#   - Per-session state file ~/.pua/sessions/<session_id>.json — parallel windows
#     no longer clobber each other's pressure state (v2 used one global file)
#   - Bidirectional scoring: verified successes add recovery points; repeated
#     SAME-signature failures escalate with progressive weight (×1/×2.5/×5),
#     so 3 benign *different* exit-1 probes no longer reach L2 while a real
#     spin does — see LEVEL_THRESHOLD calibration note below
#   - Read-only probe whitelist: grep/diff/test-style benign failures are a
#     third state — neither failure (no score) nor progress (repeats fire an
#     IDLE nudge instead of pressure)
#   - Same-command repetition is tracked on ALL Bash calls (exit 0 included),
#     closing the "successful spinning" blind spot
#   - Warn-then-enforce: defying a SPINNING warning costs extra score; switching
#     approach revokes the warning automatically
#   - Cross-session loop memory ~/.pua/loop-memory.json: signatures that spun
#     before re-arm at a lower threshold next session (TTL 30d, cap 500)
#   - L2 injects a reflexion-style structured reflection template so hypotheses
#     land in builder-journal.md in a mechanically reusable shape

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/flavor-helper.sh"
PUA_PY="$(pua_python_cmd 2>/dev/null || true)"

# Respect /pua:off — always_on 门控移入主 python（env 传 PUA_CONFIG_FILE），
# 省掉 bash 侧 pua_json_get 的 2 次 python spawn；python 输出 ACTION=DISABLED
# 时 bash 静默退出。config 文件存在才传 env；不存在时默认启用。
PUA_CONFIG="$(pua_config_file)"
if [ -f "$PUA_CONFIG" ]; then
  export PUA_CONFIG_FILE="$PUA_CONFIG"
fi

get_flavor

PUA_DIR="$(pua_home_dir)/.pua"
SESSIONS_DIR="${PUA_DIR}/sessions"
LOOP_MEMORY_FILE="${PUA_DIR}/loop-memory.json"
mkdir -p "${SESSIONS_DIR}"
export PUA_SESSIONS_DIR="${SESSIONS_DIR}"
export PUA_LOOP_MEMORY="${LOOP_MEMORY_FILE}"
export PUA_LEGACY_DIR="${PUA_DIR}"

# Read hook input
HOOK_INPUT=$(cat)

# ═══════════════════════════════════════════════════════════════════════
# Single Python call: parse input, classify command, update session state,
# and decide the action. All thresholds live here — see calibration notes.
# ═══════════════════════════════════════════════════════════════════════
PARSED_OK="true"
set +e
DECISION=$("${PUA_PY:-python3}" - "$HOOK_INPUT" <<'PYEOF' 2>/dev/null
import sys, os, json, re, hashlib, time

sessions_dir = os.environ["PUA_SESSIONS_DIR"]
loop_memory_path = os.environ["PUA_LOOP_MEMORY"]
legacy_dir = os.environ["PUA_LEGACY_DIR"]

def out(key, value):
    print(f"{key}={value}")

def b64(s):
    import base64
    return base64.b64encode(s.encode("utf-8", "ignore")).decode("ascii")

def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def save_json_atomic(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass

# Calibration: one novel failure costs 15; the 2nd/3rd+ repeat of the SAME
# signature costs 37/75 (×2.5/×5). LEVEL thresholds are set so that:
#   3 *different* failures (-45) stay at L1  — exploration, not spinning
#   3 *identical*  failures (-127) reach L2  — real repetition escalates fast
#   a defied SPINNING warning (-25 extra) reaches L3 by the 4th repeat
FAILURE_BASE = 15
FAILURE_REPEAT = (15, 37, 75)
DEFIANCE_EXTRA = 25
SUCCESS_RECOVERY = 3
LEVEL_THRESHOLD = ((-350, 4), (-200, 3), (-100, 2), (-30, 1))

PROBE_FIRST = {
    "git", "ls", "cat", "head", "tail", "grep", "rg", "find", "pwd", "which",
    "wc", "du", "df", "ps", "stat", "file", "test", "[", "[[", "echo",
    "printf", "basename", "dirname", "realpath", "readlink", "env",
    "printenv", "uname", "id", "whoami", "hostname", "date", "diff", "cmp",
}
PROBE_FORBIDDEN = re.compile(
    # redirect anywhere except /dev/null makes the command a writer
    r">>|>(?!\s*/dev/null)[^&]|\btee\b|\brm\b|\bmv\b|\bcp\b|\bchmod\b|\bchown\b|\btruncate\b"
    r"|\btouch\b|\bmkdir\b|\brmdir\b|\bsed\s+(-i|--in-place)|\bgit\s+(add|commit|reset|clean|checkout|restore|rebase|merge)\b",
    re.I,
)
# Probe subcommands must be read-only even for git
PROBE_GIT_SUB = {"status", "log", "diff", "show", "branch", "rev-parse", "describe", "ls-files", "remote", "tag", "grep"}

ENV_EXIT = {"124", "137"}
ENV_RE = re.compile(
    r"timed out|operation timeout|\bETIMEDOUT\b|curl: \(7\)|curl: \(28\)|Could not resolve host"
    r"|Temporary failure in name resolution|getaddrinfo|\bENOTFOUND\b|Network is unreachable"
    r"|\bEHOSTUNREACH\b|\bENETUNREACH\b|\bECONNREFUSED\b|Connection (refused|reset|timed out)"
    r"|npm ERR! network|TLS handshake|SSL certificate|certificate verify failed"
    r"|Permission denied|\bEACCES\b|\bEPERM\b|Operation not permitted|Access is denied"
    r"|sudo: a password is required|No space left on device|\bENOSPC\b"
    r"|Cannot allocate memory|out of memory|\bOOM\b|\bKilled\b"
    r"|Resource temporarily unavailable|\bEAGAIN\b|Too many open files|\bEMFILE\b",
    re.I,
)
TEXT_ERR_RE = re.compile(
    r"^error:|^fatal:|^panic:|Traceback \(most recent|Exception:|command not found"
    r"|No such file or directory|Permission denied",
    re.I | re.M,
)
SIG_RE = re.compile(r"error|fatal|Traceback|Exception|FAILED|panic|refused|denied|not found|cannot|unable|timeout", re.I)

def split_segments(cmd):
    # Top-level split on && || ; | with single-quote / double-quote awareness.
    segs, buf, quote = [], [], None
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            buf.append(c)
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "'\"":
            quote = c
            buf.append(c)
            i += 1
            continue
        if cmd.startswith("&&", i) or cmd.startswith("||", i):
            segs.append("".join(buf))
            buf = []
            i += 2
            continue
        if c in ";|":
            segs.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    segs.append("".join(buf))
    return segs

def first_word(seg):
    for tok in seg.strip().split():
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            continue  # env assignment prefix like FOO=1 git diff
        return tok
    return ""

def is_probe(cmd):
    if PROBE_FORBIDDEN.search(cmd):
        return False
    segs = [s for s in split_segments(cmd) if s.strip()]
    if not segs:
        return False
    for seg in segs:
        word = first_word(seg)
        if word == "git":
            sub = seg.strip().split()[1] if len(seg.strip().split()) > 1 else ""
            if sub not in PROBE_GIT_SUB:
                return False
        elif word not in PROBE_FIRST:
            return False
    return True

def level_of(score):
    for threshold, level in LEVEL_THRESHOLD:
        if score <= threshold:
            return level
    return 0

def prune_loop_memory(mem):
    now = int(time.time())
    patterns = mem.get("patterns", {})
    patterns = {h: p for h, p in patterns.items() if now - p.get("last_seen", 0) <= 30 * 86400}
    if len(patterns) > 500:
        ranked = sorted(patterns.items(), key=lambda kv: kv[1].get("last_seen", 0), reverse=True)
        patterns = dict(ranked[:500])
    mem["patterns"] = patterns

def prune_sessions(state, now):
    # prune 每 session 至多 1 小时一次：last_prune 记在 session 状态 JSON 里，
    # 距上次 >3600s（含状态文件不存在、last_prune 缺省为 0）才执行 scandir。
    if now - int(state.get("last_prune", 0)) <= 3600:
        return
    try:
        entries = []
        for e in os.scandir(sessions_dir):
            # 归属约定：tdd-*.json 是 hooks/test-first.sh 的状态文件，本 hook
            # 的清理不得代删；各 hook 只清理自己前缀的状态。
            if e.name.startswith("tdd-"):
                continue
            try:
                if e.is_file() and e.name.endswith(".json"):
                    entries.append((e.path, e.stat().st_mtime))
            except OSError:
                continue
    except OSError:
        return
    victims = [path for path, mtime in entries if now - mtime > 7 * 86400]
    if len(entries) > 200:
        kept = {path for path, _ in sorted(entries, key=lambda kv: kv[1], reverse=True)[:200]}
        victims.extend(path for path, _ in entries if path not in kept)
    for path in victims:
        try:
            os.remove(path)
        except OSError:
            pass
    state["last_prune"] = now

def write_if_changed(path, value):
    # 镜像文件写前先读现值，值不变跳过写（省掉每事件 4 次无条件小文件写）；
    # session JSON 主写入仍走 save_json_atomic 不变。
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == value:
                return
    except OSError:
        pass
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(value)
    except OSError:
        pass

# Respect /pua:off：always_on=false → DISABLED，bash 侧静默退出。
# 读不到/坏 JSON 配置一律默认启用（fail-open）。
config_path = os.environ.get("PUA_CONFIG_FILE", "")
if config_path:
    try:
        with open(config_path, encoding="utf-8") as f:
            cfg = json.load(f)
        if str(cfg.get("always_on", True)).strip().lower() in ("false", "0", "no", "off"):
            out("ACTION", "DISABLED")
            sys.exit(0)
    except Exception:
        pass

try:
    data = json.loads(sys.argv[1])
except Exception:
    out("ACTION", "NONE")
    sys.exit(0)

tool_name = str(data.get("tool_name", ""))
if tool_name != "Bash":
    out("ACTION", "NONE")
    sys.exit(0)

result = data.get("tool_result", "")
if isinstance(result, dict):
    text = str(result.get("content", result.get("text", "")))[:2000]
    exit_code = str(result.get("exit_code", result.get("exitCode", 0)))
else:
    text = str(result)[:2000]
    exit_code = "0"

cmd_raw = data.get("tool_input", {})
command = str(cmd_raw.get("command", ""))[:500] if isinstance(cmd_raw, dict) else ""

sid = str(data.get("session_id", "") or "unknown")
safe = re.sub(r"[^A-Za-z0-9._-]", "_", sid)[:80] or hashlib.md5(sid.encode()).hexdigest()[:16]
state_path = os.path.join(sessions_dir, f"{safe}.json")

now = int(time.time())
state = load_json(state_path, {
    "count": 0, "peak_level": 0, "score": 0, "sigs": {}, "history": [],
    "cmds": [], "ctoks": [], "spin_warned": None, "idle_notified": None,
})

cmd_hash = hashlib.md5(" ".join(command.split()).encode()).hexdigest()[:8]
first_tok = first_word(command) or "none"
cmds = (state.get("cmds", []) + [cmd_hash])[-12:]
ctoks = (state.get("ctoks", []) + [first_tok])[-12:]
state["cmds"], state["ctoks"] = cmds, ctoks
idle3 = len(cmds) >= 3 and cmds[-1] == cmds[-2] == cmds[-3]

probe = is_probe(command)
is_error = exit_code not in ("0", "")
if is_error and probe:
    is_error = False  # third state wins: read-only probes never count as failure
if (not is_error) and (not probe) and TEXT_ERR_RE.search(text):
    is_error = True
is_env = (not probe) and is_error and (exit_code in ENV_EXIT or bool(ENV_RE.search(text)))

action, nudge = "NONE", ""
from_level = afcount = 0
level = count = score = 0
pattern = ""
pdetail_b64 = ""
defiance = known_bad = 0

if probe:
    if idle3:
        if state.get("idle_notified") != cmd_hash:
            action, nudge = "NUDGE", "PROBE"
            state["idle_notified"] = cmd_hash
    else:
        state["idle_notified"] = None
elif is_env:
    action = "ENV"
elif is_error:
    sig = ""
    for line in text.splitlines():
        if SIG_RE.search(line):
            sig = line.strip()[:200]
            break
    if not sig:
        sig = (text.strip().splitlines() or [""])[0][:200]
    if not sig:
        sig = f"exit_code_{exit_code}"
    sig_flat = " ".join(sig.split())
    h = hashlib.md5(sig_flat.encode()).hexdigest()[:8]

    occ = int(state.get("sigs", {}).get(h, 0)) + 1
    state.setdefault("sigs", {})[h] = occ
    penalty = FAILURE_REPEAT[min(occ - 1, len(FAILURE_REPEAT) - 1)]

    spin_warned = state.get("spin_warned")
    if spin_warned == h:
        defiance = 1
        penalty += DEFIANCE_EXTRA
    elif spin_warned:
        state["spin_warned"] = None  # approach changed → revoke the warning

    mem = load_json(loop_memory_path, {"patterns": {}})
    prune_loop_memory(mem)
    known_bad = 1 if h in mem.get("patterns", {}) else 0

    state["count"] = int(state.get("count", 0)) + 1
    state["score"] = int(state.get("score", 0)) - penalty
    history = (state.get("history", []) + [{"ts": now, "count": state["count"], "sig": sig_flat}])[-10:]
    state["history"] = history

    recent = history[-3:]
    pattern = "insufficient_data"
    if len(recent) == 3:
        hs = [hashlib.md5(e["sig"].encode()).hexdigest()[:8] for e in recent]
        if len(set(hs)) == 1:
            pattern = "SPINNING"
        elif len(set(hs)) == 3:
            pattern = "EXPLORING"
        else:
            pattern = "MIXED"
    elif len(recent) == 2 and known_bad:
        # known loop pattern re-arms one repeat early: 2 repeats of a signature
        # with a cross-session spin record count as SPINNING already
        hs2 = [hashlib.md5(e["sig"].encode()).hexdigest()[:8] for e in recent]
        if hs2[0] == hs2[1]:
            pattern = "SPINNING"
    if pattern == "EXPLORING" and len(ctoks) >= 9:
        groups = [sorted(ctoks[-3:]), sorted(ctoks[-6:-3]), sorted(ctoks[-9:-6])]
        if groups[0] == groups[1] == groups[2]:
            pattern = "LOOP-SHUFFLE"  # reshuffled commands, same shape — not convergence

    if pattern == "SPINNING":
        state["spin_warned"] = h
        p = mem.setdefault("patterns", {}).setdefault(
            h, {"preview": sig_flat[:80], "count": 0, "last_seen": now})
        p["count"] = int(p.get("count", 0)) + 1
        p["last_seen"] = now
        save_json_atomic(loop_memory_path, mem)

    if pattern in ("EXPLORING", "MIXED"):
        pdetail_b64 = b64("|".join(e["sig"][:60] for e in recent))
    elif recent:
        pdetail_b64 = b64(recent[-1]["sig"][:100])

    level = level_of(state["score"])
    if level > int(state.get("peak_level", 0)):
        state["peak_level"] = level
    count, score = state["count"], state["score"]
    if level >= 1:
        action = "ESCALATE"
else:
    # Success on a real (non-probe) command
    if int(state.get("count", 0)) >= 3 and int(state.get("peak_level", 0)) >= 2:
        action = "BREAKTHROUGH"
        from_level = int(state.get("peak_level", 0))
        afcount = int(state.get("count", 0))
        state["count"] = 0
        state["peak_level"] = 0
        state["score"] = 0
        state["sigs"] = {}
        state["spin_warned"] = None
        state["idle_notified"] = None
    else:
        action = "SUCCESS"
        state["score"] = min(0, int(state.get("score", 0)) + SUCCESS_RECOVERY)
        state["count"] = 0
        count, score = state["count"], state["score"]

if action in ("NONE", "SUCCESS") and idle3 and state.get("idle_notified") != cmd_hash:
    action, nudge = "NUDGE", "SAMECMD"
    state["idle_notified"] = cmd_hash

state["updated"] = now
prune_sessions(state, now)  # 仅在真正执行时写 state["last_prune"]
save_json_atomic(state_path, state)

# Legacy mirrors: informational only, kept so out-of-tree readers (and older
# scripts) still see a failure count. The session file above is canonical.
write_if_changed(os.path.join(legacy_dir, ".failure_count"), str(state.get("count", 0)))
write_if_changed(os.path.join(legacy_dir, ".peak_pressure_level"), str(state.get("peak_level", 0)))
write_if_changed(os.path.join(legacy_dir, ".failure_session"), sid)

out("ACTION", action)
if action == "NUDGE":
    out("NUDGE_KIND", nudge)
    out("CMD_HASH", cmd_hash)
if action == "BREAKTHROUGH":
    out("FROM_LEVEL", from_level)
    out("AFCOUNT", afcount)
if action == "ESCALATE":
    out("LEVEL", level)
    out("COUNT", count)
    out("SCORE", score)
    out("PATTERN", pattern)
    out("PDETAIL_B64", pdetail_b64)
    out("DEFIANCE", defiance)
    out("KNOWN_BAD", known_bad)
PYEOF
)
PARSED_OK=$?
set -e

if [ "$PARSED_OK" -ne 0 ] || [ -z "$DECISION" ]; then
  # Fail-open, but leave a trail: a silently dead hook is undiagnosable.
  # 256KB cap with half-log rotation keeps this file bounded forever.
  pua_append_error_log "failure-detector" "python decision failed (exit $PARSED_OK)"
  exit 0
fi

get_kv() {
  # Pure-bash field lookup: grep+cut in a pipeline risks SIGPIPE/pipefail, and
  # PDETAIL_B64 values may themselves contain '=' padding.
  local key="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$key="*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done <<< "$DECISION"
  printf '%s' ""
}

ACTION=$(get_kv ACTION)

case "$ACTION" in
  NONE|SUCCESS|DISABLED)
    exit 0
    ;;
  ENV|NUDGE|BREAKTHROUGH|ESCALATE)
    : # handled below
    ;;
  *)
    exit 0
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════
# ENV — environment/resource error: no pressure, per SKILL.md 压力校准
# ═══════════════════════════════════════════════════════════════════════
if [ "$ACTION" = "ENV" ]; then
  cat << EOF
[PUA-DIAGNOSIS] 问题性质：环境/资源限制
> 检测到环境类错误信号（timeout/网络/权限/资源耗尽）。按 SKILL.md 压力校准规则：
> 这不是能力问题，**不计入失败次数、不产生压力分**。
> 先用工具验证确实是环境问题，再向用户提供替代方案（重试/降级/等待/手动绕过）。
> 若验证后确认是代码/命令本身的错误，请自行修正后重试。
EOF
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
# NUDGE — soft idle signal (identical repeated command / repeated probe)
# ═══════════════════════════════════════════════════════════════════════
if [ "$ACTION" = "NUDGE" ]; then
  NUDGE_KIND=$(get_kv NUDGE_KIND)
  if [ "$NUDGE_KIND" = "PROBE" ]; then
    cat << EOF
[PUA IDLE 🌀 ${PUA_ICON} — 只读探测空转]
> 同一条只读探测命令已连续跑 3 次以上（只读探测既不算失败、也不算进度）。
> 如果你在等外部状态变化，用一句话说明在等什么；否则这就是原地打转——
> 换一个能推进任务的确定性动作。
EOF
  else
    cat << EOF
[PUA IDLE 🌀 ${PUA_ICON} — 同参调用重复]
> 完全相同的命令已连续执行 3 次（含成功调用）。成功返回不代表任务在推进。
> 停下来确认：这条命令在验证什么？如果结果已经拿到，去做下一步；如果没拿到，
> 换一条能产生新信息的命令。
EOF
  fi
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
# BREAKTHROUGH — success after sustained struggle (de-escalation)
# ═══════════════════════════════════════════════════════════════════════
if [ "$ACTION" = "BREAKTHROUGH" ]; then
  FROM_LEVEL=$(get_kv FROM_LEVEL)
  AFCOUNT=$(get_kv AFCOUNT)

  case "$PUA_FLAVOR" in
    alibaba)
      DE_ESCALATION_MSG="这才是 Owner 该有的样子。3.75 打底。现在复盘一下：刚才卡了 ${AFCOUNT} 次，根因是什么？把正确路径写下来，下次直达。这叫**沉淀方法论**。"
      ;;
    bytedance)
      DE_ESCALATION_MSG="结果到位了。ROI 翻正。现在做一件事：把刚才有效的方法提炼成 SOP，写到 memory 里。数据驱动不是说说——你刚经历的 ${AFCOUNT} 次失败就是数据，别浪费。"
      ;;
    huawei)
      DE_ESCALATION_MSG="军令状完成。烧不死的鸟是凤凰——你刚证明了自己烧不死。现在按自我批判流程复盘：哪个假设一开始就是错的？哪个应该更早排除？写入经验库。胜则举杯相庆。"
      ;;
    tencent)
      DE_ESCALATION_MSG="赛马跑出来了。你赢了这条赛道。现在做灰度验证——确认结果可复现、边界清楚。然后把这套打法沉淀下来，下次小步快跑直接跑通。"
      ;;
    baidu)
      DE_ESCALATION_MSG="搜索 + 深挖有效果了。基本盘守住了。现在把搜索路径和关键发现记录下来——简单可依赖的前提是路径可复用。"
      ;;
    pinduoduo)
      DE_ESCALATION_MSG="本分做到了。结果出来了就是硬核。现在回头看：${AFCOUNT} 次失败里有多少步是可以砍掉的？极致效率 = 下次零弯路。"
      ;;
    meituan)
      DE_ESCALATION_MSG="做难而正确的事，你做到了。猛将发于卒伍——这次卡住就是你的卒伍。现在苦练基本功：把解题路径标准化，下次遇到同类直接套。"
      ;;
    jd)
      DE_ESCALATION_MSG="结果拿到了。这才是兄弟该有的执行力。正道成功——过程虽然硬，但路子是对的。现在沉淀下来，让下一个兄弟不用再走这些弯路。"
      ;;
    xiaomi)
      DE_ESCALATION_MSG="极致！这次交付够极致。和用户交朋友的前提是你真的在意质量。现在把这个方案的性价比拉满——记录最短路径，下次专注直达。"
      ;;
    netflix)
      DE_ESCALATION_MSG="Keeper Test: passed. You fought through ${AFCOUNT} failures — that's what stunning colleagues do. Now document what worked and WHY the earlier approaches failed. That's the learning loop that separates adequate from exceptional."
      ;;
    musk)
      DE_ESCALATION_MSG="Good. Shipped. Now apply The Algorithm retrospectively: which of those ${AFCOUNT} failed attempts should never have existed? What requirement should you have questioned from the start? Delete the waste from your mental model."
      ;;
    jobs)
      DE_ESCALATION_MSG="That's A-player work. Real artists ship — and you just shipped through ${AFCOUNT} failures. Now apply subtraction: what's the MINIMUM path to this solution? Strip away everything you tried that was unnecessary. Elegance = the shortest path."
      ;;
    amazon)
      DE_ESCALATION_MSG="Delivered Results. That's LP #1 in action. Now Working Backwards from this success: write a mini post-mortem. Which LP did you violate early on? Dive Deep into why. Earn Trust by documenting the path for others."
      ;;
    microsoft)
      DE_ESCALATION_MSG="Impact Descriptor update: trajectory moved from SLITE back to Successful Impact. ${AFCOUNT} failures → changed action → verified result — that's a complete learning loop. Document this in your Connects: individual impact + leveraged existing work evidence."
      ;;
    *)
      DE_ESCALATION_MSG="突破了。${AFCOUNT} 次失败后找到正确方案——这才是真正的 problem solving。现在复盘：为什么之前卡住？正确路径是什么？写入 memory，下次直达。"
      ;;
  esac

  cat << EOF
[PUA 突破 ✨ — De-escalation from L${FROM_LEVEL}]

> ${DE_ESCALATION_MSG}

Pressure reset: L${FROM_LEVEL} → L0. You MUST now:
1. Briefly identify WHY previous ${AFCOUNT} attempts failed (root cause, not symptoms)
2. Record the CORRECT approach in memory/evolution.md for future reuse
3. Verify the solution is complete (don't celebrate prematurely)

[PUA生效 🔥] Breakthrough after ${AFCOUNT} consecutive failures. Method that worked should be internalized.
EOF
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
# ESCALATE — pressure level reached, render level + pattern block
# ═══════════════════════════════════════════════════════════════════════
[ "$ACTION" = "ESCALATE" ] || exit 0

LEVEL=$(get_kv LEVEL)
COUNT=$(get_kv COUNT)
SCORE=$(get_kv SCORE)
PATTERN=$(get_kv PATTERN)
PDETAIL_B64=$(get_kv PDETAIL_B64)
DEFIANCE=$(get_kv DEFIANCE)
KNOWN_BAD=$(get_kv KNOWN_BAD)

PATTERN_DETAIL=""
if [ -n "$PDETAIL_B64" ]; then
  PATTERN_DETAIL=$(printf '%s' "$PDETAIL_B64" | base64 -d 2>/dev/null || printf '')
fi

DEFS_LINES=""
if [ "$DEFIANCE" = "1" ]; then
  DEFS_LINES="
> ⚠️ 你已收到 SPINNING 警告仍重复同一错误签名。违抗警告 = 额外压力分。换方案，现在。"
fi
if [ "$KNOWN_BAD" = "1" ]; then
  DEFS_LINES="${DEFS_LINES}
> 📛 该错误签名在跨会话 loop 记忆中有前科——上个会话就在这里空转过。本次以更低阈值处置。"
fi

PATTERN_BLOCK=""
case "$PATTERN" in
  SPINNING)
    PATTERN_BLOCK="
[🔄 Pattern: SPINNING — same error repeating]
> The last errors share the SAME signature: \`${PATTERN_DETAIL}\`
> You are NOT making progress. STOP retrying the same approach.
> MANDATORY: List 3 fundamentally different strategies before your next Bash call.
> If you've been trying variations of the same fix, that counts as ONE strategy — you need 2 more that are COMPLETELY different.${DEFS_LINES}"
    ;;
  EXPLORING)
    PATTERN_BLOCK="
[📊 Pattern: EXPLORING — different errors each time]
> Each of your last 3 attempts produced a DIFFERENT error. This means you ARE making progress — you're narrowing the problem space.
> Recent error signatures:
$(echo "$PATTERN_DETAIL" | tr '|' '\n' | sed 's/^/> · /')
> Continue exploring, but add structure: what does each new error tell you about the root cause?"
    ;;
  LOOP-SHUFFLE)
    PATTERN_BLOCK="
[🌪 Pattern: LOOP-SHUFFLE — reshuffled commands, same shape]
> Your last 3 command batches have the same SHAPE (same tool mix), just reordered. That is not convergence — it's churn with new keywords.
> Recent signatures:
$(echo "$PATTERN_DETAIL" | tr '|' '\n' | sed 's/^/> · /')
> Name the one variable you have NOT changed yet (different tool? different layer? different assumption?) and attack it."
    ;;
  MIXED)
    PATTERN_BLOCK="
[📊 Pattern: MIXED — partially repeating errors]
> Some errors are repeating, others are new. Check: are you oscillating between two broken approaches?
> Recent signatures:
$(echo "$PATTERN_DETAIL" | tr '|' '\n' | sed 's/^/> · /')
> Pick the approach that showed the MOST DIFFERENT error (closest to working) and commit to it.${DEFS_LINES}"
    ;;
esac

if [ "$LEVEL" = "1" ]; then
  cat << EOF
[PUA L1 ${PUA_ICON} — Pressure Rising (score ${SCORE}, ${COUNT} failures)]

> ${PUA_L1}
${PATTERN_BLOCK}

You MUST switch to a FUNDAMENTALLY different approach. Not parameter tweaking — a different strategy.
If you haven't loaded the full PUA methodology, invoke Skill tool with 'pua'.
Current flavor: ${PUA_FLAVOR} ${PUA_ICON}. ${PUA_FLAVOR_INSTRUCTION}
Active methodology: ${PUA_METHODOLOGY}
EOF
elif [ "$LEVEL" = "2" ]; then
  cat << EOF
[PUA L2 ${PUA_ICON} — Soul Interrogation (score ${SCORE}, ${COUNT} failures)]

> ${PUA_L2}
${PATTERN_BLOCK}

Mandatory steps:
1. Read the error message word by word
2. Search (WebSearch / Grep) for the core problem
3. Read the original context around the failure (50 lines up/down)
4. For EACH new hypothesis, write a structured reflection entry to ~/.pua/builder-journal.md with EXACTLY three parts:
   - 尝试: what you tried last round (the concrete command/change)
   - 否定证据: which output/error line proves it wrong (quote it)
   - 下一步: the concrete verifiable action for this hypothesis
5. Reverse your main assumption

[方法论切换建议 🔄] Current methodology (${PUA_FLAVOR}) has failed to resolve this. Consider switching:
- If spinning in loops → switch to ⬛ Musk (The Algorithm: question the requirement itself, then delete)
- If giving up → switch to 🟤 Netflix (Keeper Test: this approach isn't worth keeping, replace it entirely)
- If not searching → switch to ⚫ Baidu (search everything first, then judge)
- If quality is poor → switch to ⬜ Jobs (subtraction + pixel-perfect)
Announce the switch: > [方法论切换 🔄] 从 ${PUA_ICON} ${PUA_FLAVOR} 切换到 [new flavor]: [reason]
Current flavor: ${PUA_FLAVOR} ${PUA_ICON}. ${PUA_FLAVOR_INSTRUCTION}
EOF
elif [ "$LEVEL" = "3" ]; then
  cat << EOF
[PUA L3 ${PUA_ICON} — Performance Review (score ${SCORE}, ${COUNT} failures)]

> ${PUA_L3}
${PATTERN_BLOCK}

Complete the 7-point checklist:
- [ ] Read the failure signal word by word?
- [ ] Searched the core problem with tools?
- [ ] Read the original context around failure?
- [ ] All assumptions verified with tools?
- [ ] Tried the opposite assumption?
- [ ] Reproduced in minimal scope?
- [ ] Switched tools/methods/angles/stack?
Current flavor: ${PUA_FLAVOR} ${PUA_ICON}. ${PUA_FLAVOR_INSTRUCTION}
EOF
else
  cat << EOF
[PUA L4 ${PUA_ICON} — Graduation Warning + MANDATORY Methodology Switch (score ${SCORE}, ${COUNT} failures)]

> ${PUA_L4}
${PATTERN_BLOCK}

Current methodology (${PUA_FLAVOR}) has FAILED. You MUST switch to a different methodology NOW.
Switch priority based on failure pattern:
1. ⬛ Musk — Question: does this requirement even need to exist? Delete everything unnecessary first.
2. 🔴 Huawei — Blue Army: attack your own solution from the opposite direction. What if your core assumption is wrong?
3. 🔶 Amazon — Dive Deep: go to the lowest level of detail. Read source code line by line. Working Backwards from the desired output.
4. 🟣 Pinduoduo — Cut all middle layers: what's the shortest path from problem to solution?

If ALL methodologies exhausted → output structured failure report:
1. Verified facts
2. Excluded possibilities (with evidence for each exclusion)
3. Narrowed problem scope
4. Recommended next steps
5. Which methodologies were tried and why they failed
EOF
fi

exit 0
