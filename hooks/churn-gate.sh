#!/bin/bash
# PUA Churn Gate — PostToolUse deterministic review gate
# prove_it 思路的 pua 适配：大改动不该靠模型自觉走 commit 前三维审查，
# 而是由确定性阈值强制触发。
#
#   net   = 自上次 re-arm 以来的净变更行数（相对 baseline commit 的 diff，
#           含工作区未提交改动；阈值按窗口差值比较，见下方 FIRE 判定）
#   gross = 累计翻动行数（每次采样净变更的绝对差累加，专抓写了删删了写）
#
# net ≥ review_net_threshold(默认400) 或 gross ≥ review_gross_threshold(默认800)
# → 注入一次三维审查要求（安全 tiangang / 架构 diting / 性能 diting），
#   随后 re-arm（baseline 重置为当前 HEAD，窗口清零），同一波改动只提醒一次。
#
# 性能：原实现每事件 9 次 python spawn；现收敛为 bash 壳 + 单个批量 python
# （stdin 解析、config 读取、状态 JSON 原子读写、git 子进程、阈值判定与
# additionalContext 输出一体）。候选解释器 command -v 探测后直接真实调用，
# 坏解释器（exit≠0）再换下一个候选；正常路径仅 1 次 spawn。
#
# 安全约束：只读 git（rev-parse / diff --shortstat），绝不修改任何 git ref，
# 不 commit、不 stash；状态全部存 $HOME/.pua/churn-<session>.json。fail-open。
# baseline_commit 必须匹配 ^[0-9a-f]{4,40}$——被改写成 `--output=/path` 之类
# 的值会让 git diff 把 diff 内容覆写到任意文件，必须校验。
# python/git 静默失效时向 $HOME/.pua/errors.log 追加 JSONL（256KB 半量轮转）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/flavor-helper.sh"

HOOK_INPUT=$(cat)

PUA_STATE_DIR="$(pua_home_dir)/.pua"
export PUA_STATE_DIR
# always_on 在主 python 内读取（省掉 bash 侧 pua_json_get 的 2 次 spawn）：
# config 文件存在才传 env；不存在则默认启用。
PUA_CONFIG="$(pua_config_file)"
if [ -f "$PUA_CONFIG" ]; then
  export PUA_CONFIG_FILE="$PUA_CONFIG"
fi

# ── python 调度：command -v 探测候选，真实调用自带兜底；坏解释器（exit≠0）
#    换下一个候选；全部失败 → errors.log 留痕后 fail-open exit 0。
PUA_RAN=0
PUA_OUT=""
set +e
for _cand in "${PYTHON:-}" python3 python; do
  [ -z "$_cand" ] && continue
  command -v "$_cand" >/dev/null 2>&1 || continue
  PUA_OUT=$("$_cand" - "$HOOK_INPUT" <<'PYEOF' 2>/dev/null
import json, os, re, subprocess, sys, time

state_dir = os.environ.get("PUA_STATE_DIR") or os.path.expanduser("~/.pua")
err_log = os.path.join(state_dir, "errors.log")
NET_DEFAULT, GROSS_DEFAULT = 400, 800

def log_error(msg):
    # 静默失效显性化：errors.log 追加一行 JSONL，256KB 上限 + 半量轮转。
    line = json.dumps({"ts": int(time.time()), "hook": "churn-gate", "error": msg},
                      ensure_ascii=False)
    try:
        os.makedirs(state_dir, exist_ok=True)
        with open(err_log, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        return
    try:
        if os.path.getsize(err_log) > 262144:
            with open(err_log, encoding="utf-8") as f:
                lines = f.readlines()
            tmp = f"{err_log}.tmp.{os.getpid()}"
            with open(tmp, "w", encoding="utf-8") as f:
                f.writelines(lines[len(lines) // 2:])
            os.replace(tmp, err_log)
    except OSError:
        pass

def save_atomic(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError as e:
        log_error(f"state write failed: {e}")
        try:
            os.remove(tmp)
        except OSError:
            pass

def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def cfg_int(cfg, key, default):
    v = cfg.get(key, default)
    if isinstance(v, bool):
        return default
    try:
        n = int(v)
    except (TypeError, ValueError):
        return default
    return n if n >= 1 else default

def git(args, cwd, timeout=3):
    return subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                          text=True, errors="replace", timeout=timeout)

def to_net(text):
    ins = sum(int(x) for x in re.findall(r"(\d+) insertion", text))
    dele = sum(int(x) for x in re.findall(r"(\d+) deletion", text))
    return ins + dele

# ── stdin JSON 解析（非法输入与原行为一致：静默退出）──
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

tool_name = str(data.get("tool_name") or "")
if tool_name not in ("Bash", "Edit", "Write", "MultiEdit", "NotebookEdit"):
    sys.exit(0)

session_id = str(data.get("session_id") or "")
if not session_id:
    sys.exit(0)

event_cwd = str(data.get("cwd") or "")
if not os.path.isdir(event_cwd):
    event_cwd = os.getcwd()

# ── config：always_on + 阈值（读不到按默认启用，fail-open）──
cfg = {}
config_path = os.environ.get("PUA_CONFIG_FILE", "")
if config_path:
    loaded = load_json(config_path, None)
    if isinstance(loaded, dict):
        cfg = loaded
    else:
        log_error("config unreadable, using defaults")
if str(cfg.get("always_on", True)).strip().lower() in ("false", "0", "no", "off"):
    sys.exit(0)
net_threshold = cfg_int(cfg, "review_net_threshold", NET_DEFAULT)
gross_threshold = cfg_int(cfg, "review_gross_threshold", GROSS_DEFAULT)

# ── git 前置检查：非 git 目录静默；空仓无 HEAD 静默 ──
try:
    r = git(["rev-parse", "--is-inside-work-tree"], event_cwd)
except subprocess.TimeoutExpired:
    log_error("git rev-parse --is-inside-work-tree timed out")
    sys.exit(0)
except OSError as e:
    log_error(f"git unavailable: {e}")
    sys.exit(0)
if r.returncode != 0 or r.stdout.strip() != "true":
    sys.exit(0)
try:
    r = git(["rev-parse", "HEAD"], event_cwd)
except (subprocess.TimeoutExpired, OSError) as e:
    log_error(f"git rev-parse HEAD failed: {e}")
    sys.exit(0)
if r.returncode != 0:
    sys.exit(0)
head_commit = r.stdout.strip()
if not re.fullmatch(r"[0-9a-f]{4,40}", head_commit):
    log_error(f"git rev-parse HEAD unexpected output: {head_commit[:80]!r}")
    sys.exit(0)

safe_sid = re.sub(r"[^A-Za-z0-9._-]", "_", session_id)
state_file = os.path.join(state_dir, f"churn-{safe_sid}.json")

def diff_net(base):
    r = git(["diff", "--shortstat", base], event_cwd)
    if r.returncode != 0:
        raise RuntimeError(f"git diff --shortstat {base[:12]} failed (rc={r.returncode})")
    return to_net(r.stdout)

def arm(baseline, net, gross_val):
    save_atomic(state_file, {"baseline_commit": baseline, "net_at_arm": net,
                             "gross": gross_val, "ts": int(time.time())})

def arm_from_head():
    try:
        arm(head_commit, diff_net(head_commit), 0)
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
        log_error(f"arm failed: {e}")

# ── First sighting: arm with current state, stay silent ──
state = load_json(state_file, None)
if not isinstance(state, dict):
    if os.path.exists(state_file):
        log_error("churn state corrupt, re-arming")
    arm_from_head()
    sys.exit(0)

# 安全审查修复：baseline_commit 必须是纯 commit hash。被改写成
# `--output=/path` 之类的值会让 git diff 把 diff 内容写进任意文件。
baseline = str(state.get("baseline_commit") or "")
if not re.fullmatch(r"[0-9a-f]{4,40}", baseline):
    log_error(f"baseline_commit failed validation, re-arming: {baseline[:80]!r}")
    arm_from_head()
    sys.exit(0)

net_at_arm = state.get("net_at_arm")
gross = state.get("gross")
net_at_arm = net_at_arm if isinstance(net_at_arm, int) and not isinstance(net_at_arm, bool) and net_at_arm >= 0 else 0
gross = gross if isinstance(gross, int) and not isinstance(gross, bool) and gross >= 0 else 0

# ── Sample: net vs baseline (working tree included), gross += |delta| ──
try:
    net = diff_net(baseline)
except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
    log_error(f"sample failed: {e}")
    sys.exit(0)

delta = abs(net - net_at_arm)
gross += delta

# 窗口语义：net 阈值比较的是自上次 arm 以来的净变更（NET - NET_AT_ARM），
# 而非相对 baseline 的绝对值——否则 re-arm 后未提交改动仍在工作区，
# 绝对值持续 ≥ 阈值会导致每个事件都重复触发，gross 也永远清零。
if delta < net_threshold and gross < gross_threshold:
    arm(baseline, net, gross)
    sys.exit(0)

# ── Fire once, then re-arm from current state（窗口清零，同一波不重复触发）──
try:
    r = git(["rev-parse", "HEAD"], event_cwd)
    new_baseline = r.stdout.strip() if r.returncode == 0 else baseline
    new_net = diff_net(new_baseline)
except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
    log_error(f"re-arm after fire failed: {e}")
    new_baseline, new_net = baseline, 0
arm(new_baseline, new_net, 0)

msg = (f"[PUA Churn Gate] 变更规模触发确定性审查门控：本窗口净变更 {delta} 行"
       f"（阈值 {net_threshold}），累计翻动 {gross} 行（阈值 {gross_threshold}）。"
       "commit 前必须执行三维审查：并行派遣 3 个独立 subagent——安全（tiangang）、"
       "架构（diting architecture）、性能（diting performance），逐一贴出审查输出证据"
       "（禁止默认通过）；存在 CRITICAL/HIGH 必须修复后重新审查，全部通过才允许 commit。")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                         "additionalContext": msg}},
                 ensure_ascii=False))
sys.exit(0)
PYEOF
)
  if [ $? -eq 0 ]; then
    PUA_RAN=1
    break
  fi
  PUA_OUT=""
done
set -e

if [ "$PUA_RAN" -ne 1 ]; then
  pua_append_error_log "churn-gate" "no usable python interpreter"
  exit 0
fi

printf '%s' "$PUA_OUT"
exit 0
