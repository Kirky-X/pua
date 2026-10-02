#!/bin/bash
# PUA flavor helper — shared by all hooks
# Usage: source this file, then call get_flavor
# Sets: PUA_FLAVOR, PUA_ICON, PUA_L1, PUA_L2, PUA_L3, PUA_L4, PUA_KEYWORDS, PUA_FLAVOR_INSTRUCTION

# Return a usable Python executable. Windows Git Bash commonly has `python`
# but not `python3`; verify by importing json rather than trusting command -v.
pua_python_cmd() {
  local candidate
  for candidate in "${PYTHON:-}" python3 python; do
    [ -z "$candidate" ] && continue
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import json,sys" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Convert POSIX-looking Git Bash paths (/c/Users/...) to native Windows paths
# before passing them to native Windows Python. No-op on macOS/Linux.
# cygpath 探测结果缓存在调用方 shell 的 _PUA_CYGPATH：非 Windows 机器上
# command -v 要遍历完整 PATH（含 /mnt/c 等挂载目录），实测 ~50ms/次。
# 注意 $() 命令替换是子 shell，函数内的缓存写不回父 shell——热路径
# （get_flavor / pua_json_get）必须先在父 shell 调 pua_detect_cygpath 预热。
pua_detect_cygpath() {
  if [ -z "${_PUA_CYGPATH:-}" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      _PUA_CYGPATH="cygpath"
    else
      _PUA_CYGPATH="none"
    fi
  fi
}

pua_to_python_path() {
  local path="$1"
  pua_detect_cygpath
  if [ "$_PUA_CYGPATH" = "cygpath" ]; then
    cygpath -w "$path" 2>/dev/null || printf '%s\n' "$path"
  else
    printf '%s\n' "$path"
  fi
}

pua_config_file() {
  printf '%s\n' "${PUA_CONFIG:-$(pua_home_dir)/.pua/config.json}"
}

pua_json_get() {
  local path="$1"
  local key="$2"
  local default="$3"
  local candidate py_path out
  # 性能优化：不再用 `python -c "import json,sys"` 验证性 spawn 预检候选
  # （每个键 2 次 spawn 减为 1 次）。改为 command -v 探测后直接真实调用——
  # 真实调用自带 try/except 兜底，坏解释器（exit≠0）时依次换下一个候选，
  # 全部失败回默认值。语义与旧实现等价。
  pua_detect_cygpath  # 父 shell 预热，避免下方 $() 子 shell 内重复探测
  py_path=$(pua_to_python_path "$path")
  for candidate in "${PYTHON:-}" python3 python; do
    [ -z "$candidate" ] && continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    out=$("$candidate" -c 'import json,sys
path,key,default=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    with open(path, encoding="utf-8") as f:
        value=json.load(f).get(key, default)
    print(value)
except Exception:
    print(default)' "$py_path" "$key" "$default" 2>/dev/null) && {
      printf '%s\n' "$out"
      return 0
    }
  done
  printf '%s\n' "$default"
}

# Resolve the user's home directory. bash does not expand `~` inside double
# quotes, so a HOME-tilde fallback in double quotes produces a literal `~`
# directory when HOME is unset (e.g. some Windows Git Bash invocations).
# This helper returns $HOME when set, and otherwise falls back to
# `eval printf '%s' '~'` which performs tilde expansion against the password
# database (no user input, no injection risk).
pua_home_dir() {
  if [ -n "${HOME:-}" ]; then
    printf '%s' "$HOME"
  else
    eval printf '%s' '~'
  fi
}

# Case-insensitive boolean checkers shared by all hooks. pua_json_get (Python
# json.load) returns lowercase "true"/"false" for string JSON values, but
# capitalized "True"/"False" for boolean JSON values; bare `[ "$X" = "True" ]`
# only matches the latter. These helpers accept both plus yes/no/1/0/on/off.
is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_false() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    false|0|no|off) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Error log（静默失效显性化）──
# Hook 在 python/git 静默降级（fail-open）时向 ~/.pua/errors.log 追加一行
# JSONL；256KB 上限 + 半量轮转保证文件有界。各 hook 共用同一约定。
pua_append_error_log() {
  local hook="$1" err="$2" log_file size
  # 最小 JSON 转义：反斜杠与双引号（错误消息均为单行文本）
  err="${err//\\/\\\\}"
  err="${err//\"/\\\"}"
  log_file="$(pua_home_dir)/.pua/errors.log"
  mkdir -p "$(pua_home_dir)/.pua" 2>/dev/null || true
  printf '{"ts":%s,"hook":"%s","error":"%s"}\n' \
    "$(date +%s)" "$hook" "$err" >> "$log_file" 2>/dev/null || true
  if [ -f "$log_file" ]; then
    size=$(stat -f %z "$log_file" 2>/dev/null || stat -c %s "$log_file" 2>/dev/null || echo 0)
    if [ "$size" -gt 262144 ]; then
      tail -n $(( $(grep -c '' "$log_file" 2>/dev/null || echo 2) / 2 )) "$log_file" > "${log_file}.tmp" 2>/dev/null \
        && mv "${log_file}.tmp" "$log_file" 2>/dev/null || true
    fi
  fi
}

# ── Config validation ──
# Validates ~/.pua/config.json against schema, fixes invalid fields in-place.
# Called once per get_flavor() invocation; cheap (single Python call).
# Schema: hooks/config-schema.json (reference; not loaded at runtime).
pua_validate_config() {
  local config="$1"
  [ -f "$config" ] || return 0

  local py
  py=$(pua_python_cmd 2>/dev/null) || return 0

  local fixed
  fixed=$("$py" -c "
import json, sys

path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as f:
        cfg = json.load(f)
except (json.JSONDecodeError, OSError) as e:
    print(f'PUA config invalid ({e}), using defaults', file=sys.stderr)
    # Write fresh defaults
    defaults = {'flavor': 'alibaba', 'language': '', 'always_on': True, 'feedback_frequency': 0, 'offline': False}
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(defaults, f, indent=2, ensure_ascii=False)
    sys.exit(0)

if not isinstance(cfg, dict):
    cfg = {}

changed = False
# Type checks with defaults
if not isinstance(cfg.get('flavor', 'alibaba'), str):
    cfg['flavor'] = 'alibaba'; changed = True
if not isinstance(cfg.get('language', ''), str):
    cfg['language'] = ''; changed = True
if not isinstance(cfg.get('always_on', True), bool):
    # Accept string booleans
    v = str(cfg.get('always_on', '')).lower()
    cfg['always_on'] = v in ('true', '1', 'yes', 'on')
    changed = True
if not isinstance(cfg.get('feedback_frequency', 0), int) or isinstance(cfg.get('feedback_frequency', 0), bool):
    try:
        cfg['feedback_frequency'] = max(0, min(4, int(cfg.get('feedback_frequency', 0))))
    except (ValueError, TypeError):
        cfg['feedback_frequency'] = 0
    changed = True
if not isinstance(cfg.get('offline', False), bool):
    v = str(cfg.get('offline', '')).lower()
    cfg['offline'] = v in ('true', '1', 'yes', 'on')
    changed = True

# Remove unknown keys
known = {'flavor','language','always_on','feedback_frequency','offline'}
extra = set(cfg.keys()) - known
if extra:
    for k in extra:
        del cfg[k]
    changed = True

if changed:
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print(f'PUA config auto-repaired (removed unknown keys or fixed types)', file=sys.stderr)
" "$config" 2>&1) || true

  # Surface warnings to caller (stderr passthrough)
  if [ -n "$fixed" ]; then
    echo "$fixed" >&2
  fi
}

get_flavor() {
  local config
  config=$(pua_config_file)
  # Initialize unconditionally so callers running under `set -u` don't trip
  # when ~/.pua/config.json is missing (first-run users).
  # See: https://github.com/tanweai/pua/issues/144
  PUA_LANGUAGE=""
  PUA_FLAVOR="alibaba"
  PUA_ICON="" PUA_L1="" PUA_L2="" PUA_L3="" PUA_L4=""
  PUA_KEYWORDS="" PUA_FLAVOR_INSTRUCTION="" PUA_METHODOLOGY=""
  PUA_METHODOLOGY_FILE="methodology-alibaba.md"

  # ── Load flavor data from JSON (source of truth: hooks/flavors.json) ──
  # 性能：原实现一次 get_flavor 要 spawn 8-10 个 python（pua_validate_config
  # 2 次 + flavor/language 两次 pua_json_get 各 2 次 + flavors.json 加载 2 次）。
  # 现合并为单次批量 python：读 config（坏配置原样修复写回，逻辑照搬
  # pua_validate_config）→ 取 flavor/language → 归一别名 → 加载 flavors.json
  # （zh 覆盖逻辑不变）→ 逐行输出 base64。pua_validate_config 仍保留为独立
  # 函数供单独调用。
  local flavors_json="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/flavors.json"
  local py _flavor_vars=""
  pua_detect_cygpath  # 父 shell 预热（探测 ~50ms 只付一次，$() 子 shell 读缓存）
  if py=$(pua_python_cmd 2>/dev/null); then
    _flavor_vars=$("$py" -c 'import json, base64, sys, os

config_path, json_path = sys.argv[1], sys.argv[2]

def b64(s):
    return base64.b64encode(str(s).encode("utf-8")).decode("ascii")

defaults = {"flavor": "alibaba", "language": "", "always_on": True,
            "feedback_frequency": 0, "offline": False}
cfg = dict(defaults)

# ① 读 config；坏配置时原样修复写回（逻辑照搬 pua_validate_config）
if os.path.isfile(config_path):
    try:
        with open(config_path, encoding="utf-8") as f:
            loaded = json.load(f)
        if not isinstance(loaded, dict):
            loaded = {}
        cfg.update(loaded)
        changed = False
        if not isinstance(cfg.get("flavor", "alibaba"), str):
            cfg["flavor"] = "alibaba"
            changed = True
        if not isinstance(cfg.get("language", ""), str):
            cfg["language"] = ""
            changed = True
        if not isinstance(cfg.get("always_on", True), bool):
            v = str(cfg.get("always_on", "")).lower()
            cfg["always_on"] = v in ("true", "1", "yes", "on")
            changed = True
        ff = cfg.get("feedback_frequency", 0)
        if not isinstance(ff, int) or isinstance(ff, bool):
            try:
                cfg["feedback_frequency"] = max(0, min(4, int(ff)))
            except (ValueError, TypeError):
                cfg["feedback_frequency"] = 0
            changed = True
        if not isinstance(cfg.get("offline", False), bool):
            v = str(cfg.get("offline", "")).lower()
            cfg["offline"] = v in ("true", "1", "yes", "on")
            changed = True
        known = {"flavor", "language", "always_on", "feedback_frequency", "offline"}
        extra = set(cfg.keys()) - known
        if extra:
            for k in extra:
                del cfg[k]
            changed = True
        if changed:
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, ensure_ascii=False)
    except (json.JSONDecodeError, OSError):
        # 坏配置（解析失败/不可读）：写回全新默认值，与 pua_validate_config 相同
        try:
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(defaults, f, indent=2, ensure_ascii=False)
        except OSError:
            pass
        cfg = dict(defaults)

# ②③ flavor/language 归一。别名表是权威版本（原 bash case 表的 dict 化），
#     未知值与空值一律回 alibaba；大小写敏感与原 case 行为一致。
ALIASES = {
    "alibaba": "alibaba", "阿里": "alibaba", "": "alibaba",
    "bytedance": "bytedance", "字节": "bytedance",
    "huawei": "huawei", "华为": "huawei",
    "tencent": "tencent", "腾讯": "tencent",
    "baidu": "baidu", "百度": "baidu",
    "pinduoduo": "pinduoduo", "拼多多": "pinduoduo",
    "meituan": "meituan", "美团": "meituan",
    "jd": "jd", "京东": "jd",
    "xiaomi": "xiaomi", "小米": "xiaomi",
    "netflix": "netflix", "Netflix": "netflix",
    "musk": "musk", "Musk": "musk",
    "jobs": "jobs", "Jobs": "jobs",
    "amazon": "amazon", "Amazon": "amazon",
    "microsoft": "microsoft", "Microsoft": "microsoft", "微软": "microsoft",
    "ding": "ding", "Ding": "ding", "钉": "ding", "钉钉": "ding",
    "钉味": "ding", "钉内": "ding", "钉外": "ding",
    "置身钉内": "ding", "置身钉外": "ding",
    "dinginside": "ding", "dingoutside": "ding",
}
flavor = ALIASES.get(str(cfg.get("flavor", "alibaba")), "alibaba")
language = str(cfg.get("language", ""))
use_zh = language in ("zh", "中文")
print(f"PUA_FLAVOR={b64(flavor)}")
print(f"PUA_LANGUAGE={b64(language)}")

# ⑤ 加载 flavors.json 取对应条目（zh 覆盖逻辑照搬原实现）
icon = l1 = l2 = l3 = l4 = kw = inst = meth = ""
try:
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)
    d = data.get(flavor, data.get("alibaba", {}))
    if not isinstance(d, dict):
        d = {}
    zh = d.get("zh", {})
    if use_zh and isinstance(zh, dict) and zh:
        icon = d.get("icon", "")
        l1 = zh.get("l1", d.get("l1", ""))
        l2 = zh.get("l2", d.get("l2", ""))
        l3 = zh.get("l3", d.get("l3", ""))
        l4 = zh.get("l4", d.get("l4", ""))
        kw = zh.get("keywords", d.get("keywords", ""))
        inst = zh.get("instruction", d.get("instruction", ""))
    else:
        icon = d.get("icon", "")
        l1 = d.get("l1", "")
        l2 = d.get("l2", "")
        l3 = d.get("l3", "")
        l4 = d.get("l4", "")
        kw = d.get("keywords", "")
        inst = d.get("instruction", "")
    meth = d.get("methodology", "")
except Exception:
    pass
print(f"PUA_ICON={b64(icon)}")
print(f"PUA_L1={b64(l1)}")
print(f"PUA_L2={b64(l2)}")
print(f"PUA_L3={b64(l3)}")
print(f"PUA_L4={b64(l4)}")
print(f"PUA_KEYWORDS={b64(kw)}")
print(f"PUA_FLAVOR_INSTRUCTION={b64(inst)}")
print(f"PUA_METHODOLOGY={b64(meth)}")' \
      "$(pua_to_python_path "$config")" "$(pua_to_python_path "$flavors_json")" 2>/dev/null || true)
  fi

  # Decode base64 values into shell variables.
  # 安全审计修复：原实现把解码结果拼成 shell 语句再 eval（构造的 flavors.json
  # 可注入任意命令）。现改为：白名单键名逐个 case 赋值，解码值只作为普通
  # 字符串数据使用，绝不作为 shell 代码求值。
  if [ -n "$_flavor_vars" ]; then
    while IFS='=' read -r key b64val; do
      [ -z "$key" ] && continue
      decoded="$(printf '%s' "$b64val" | base64 -d 2>/dev/null || printf '')"
      case "$key" in
        PUA_FLAVOR)             PUA_FLAVOR="$decoded" ;;
        PUA_LANGUAGE)           PUA_LANGUAGE="$decoded" ;;
        PUA_ICON)               PUA_ICON="$decoded" ;;
        PUA_L1)                 PUA_L1="$decoded" ;;
        PUA_L2)                 PUA_L2="$decoded" ;;
        PUA_L3)                 PUA_L3="$decoded" ;;
        PUA_L4)                 PUA_L4="$decoded" ;;
        PUA_KEYWORDS)           PUA_KEYWORDS="$decoded" ;;
        PUA_FLAVOR_INSTRUCTION) PUA_FLAVOR_INSTRUCTION="$decoded" ;;
        PUA_METHODOLOGY)        PUA_METHODOLOGY="$decoded" ;;
        *) : ;; # 不在白名单内的键一律丢弃
      esac
    done <<< "$_flavor_vars"
  fi

  # 降级路径：批量 python 不可用或输出异常（坏解释器、Windows 假 python 只能
  # 应答旧式单键查询）时，退回逐键 pua_json_get 取 flavor/language。别名归一
  # 表以批量 python 为权威，此路径仅取原值；PUA_ICON 等保持空值，由各 hook
  # 的消息模板自行兜底。
  if ! printf '%s' "$_flavor_vars" | grep -q '^PUA_FLAVOR='; then
    PUA_FLAVOR=$(pua_json_get "$config" flavor alibaba)
    PUA_LANGUAGE=$(pua_json_get "$config" language "")
  fi

  # Map flavor → methodology file (handle mismatches) — 只需归一后的 PUA_FLAVOR
  case "$PUA_FLAVOR" in
    musk)    PUA_METHODOLOGY_FILE="methodology-tesla.md" ;;
    jobs)    PUA_METHODOLOGY_FILE="methodology-apple.md" ;;
    jd)      PUA_METHODOLOGY_FILE="methodology-jd.md" ;;
    xiaomi)  PUA_METHODOLOGY_FILE="methodology-xiaomi.md" ;;
    amazon)  PUA_METHODOLOGY_FILE="methodology-amazon.md" ;;
    microsoft) PUA_METHODOLOGY_FILE="methodology-microsoft.md" ;;
    ding)    PUA_METHODOLOGY_FILE="methodology-ding.md" ;;
    *)       PUA_METHODOLOGY_FILE="methodology-${PUA_FLAVOR}.md" ;;
  esac
}
