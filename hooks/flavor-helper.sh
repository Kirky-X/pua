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
pua_to_python_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
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
  local py py_path
  py=$(pua_python_cmd 2>/dev/null) || { printf '%s\n' "$default"; return 0; }
  py_path=$(pua_to_python_path "$path")
  "$py" -c 'import json,sys
path,key,default=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    with open(path, encoding="utf-8") as f:
        value=json.load(f).get(key, default)
    print(value)
except Exception:
    print(default)' "$py_path" "$key" "$default" 2>/dev/null || printf '%s\n' "$default"
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
  local raw_flavor=""
  # Initialize PUA_LANGUAGE unconditionally so callers running under
  # `set -u` don't trip when ~/.pua/config.json is missing (first-run users).
  # See: https://github.com/tanweai/pua/issues/144
  PUA_LANGUAGE=""

  if [ -f "$config" ]; then
    # Validate config against schema (auto-repair invalid fields)
    pua_validate_config "$config"
    raw_flavor=$(pua_json_get "$config" flavor alibaba)
    PUA_LANGUAGE=$(pua_json_get "$config" language "")
  fi

  # Normalize flavor name
  case "$raw_flavor" in
    alibaba|阿里|"") raw_flavor="alibaba" ;;
    bytedance|字节)  raw_flavor="bytedance" ;;
    huawei|华为)     raw_flavor="huawei" ;;
    tencent|腾讯)    raw_flavor="tencent" ;;
    baidu|百度)      raw_flavor="baidu" ;;
    pinduoduo|拼多多) raw_flavor="pinduoduo" ;;
    meituan|美团)    raw_flavor="meituan" ;;
    jd|京东)         raw_flavor="jd" ;;
    xiaomi|小米)     raw_flavor="xiaomi" ;;
    netflix|Netflix) raw_flavor="netflix" ;;
    musk|Musk)       raw_flavor="musk" ;;
    jobs|Jobs)       raw_flavor="jobs" ;;
    amazon|Amazon)   raw_flavor="amazon" ;;
    microsoft|Microsoft|微软) raw_flavor="microsoft" ;;
    ding|Ding|钉|钉钉|钉味|钉内|钉外|置身钉内|置身钉外|dinginside|dingoutside) raw_flavor="ding" ;;
    *)               raw_flavor="alibaba" ;;
  esac

  PUA_FLAVOR="$raw_flavor"

  # Map flavor → methodology file (handle mismatches)
  case "$raw_flavor" in
    musk)    PUA_METHODOLOGY_FILE="methodology-tesla.md" ;;
    jobs)    PUA_METHODOLOGY_FILE="methodology-apple.md" ;;
    jd)      PUA_METHODOLOGY_FILE="methodology-jd.md" ;;
    xiaomi)  PUA_METHODOLOGY_FILE="methodology-xiaomi.md" ;;
    amazon)  PUA_METHODOLOGY_FILE="methodology-amazon.md" ;;
    microsoft) PUA_METHODOLOGY_FILE="methodology-microsoft.md" ;;
    ding)    PUA_METHODOLOGY_FILE="methodology-ding.md" ;;
    *)       PUA_METHODOLOGY_FILE="methodology-${raw_flavor}.md" ;;
  esac

  # ── Load flavor data from JSON (source of truth: hooks/flavors.json) ──
  # Uses Python to parse JSON + base64 to safely transport values with special chars.
  # Falls back to empty values if JSON file is missing or Python fails.
  local flavors_json="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/flavors.json"
  local zh_flag="false"
  if [ "$PUA_LANGUAGE" = "zh" ] || [ "$PUA_LANGUAGE" = "中文" ]; then
    zh_flag="true"
  fi

  local _flavor_vars
  _flavor_vars=$("$(pua_python_cmd 2>/dev/null || echo python3)" -c "
import json, base64, sys

flavor = sys.argv[1]
json_path = sys.argv[2]
use_zh = sys.argv[3] == 'true'

def b64(s):
    return base64.b64encode(s.encode('utf-8')).decode('ascii')

try:
    with open(json_path, encoding='utf-8') as f:
        data = json.load(f)
    d = data.get(flavor, data.get('alibaba', {}))
    # Chinese overrides
    zh = d.get('zh', {})
    if use_zh and zh:
        icon = d.get('icon', '')
        l1 = zh.get('l1', d.get('l1', ''))
        l2 = zh.get('l2', d.get('l2', ''))
        l3 = zh.get('l3', d.get('l3', ''))
        l4 = zh.get('l4', d.get('l4', ''))
        kw = zh.get('keywords', d.get('keywords', ''))
        inst = zh.get('instruction', d.get('instruction', ''))
    else:
        icon = d.get('icon', '')
        l1 = d.get('l1', '')
        l2 = d.get('l2', '')
        l3 = d.get('l3', '')
        l4 = d.get('l4', '')
        kw = d.get('keywords', '')
        inst = d.get('instruction', '')
    meth = d.get('methodology', '')
    print(f'PUA_ICON={b64(icon)}')
    print(f'PUA_L1={b64(l1)}')
    print(f'PUA_L2={b64(l2)}')
    print(f'PUA_L3={b64(l3)}')
    print(f'PUA_L4={b64(l4)}')
    print(f'PUA_KEYWORDS={b64(kw)}')
    print(f'PUA_FLAVOR_INSTRUCTION={b64(inst)}')
    print(f'PUA_METHODOLOGY={b64(meth)}')
except Exception:
    for v in ['PUA_ICON','PUA_L1','PUA_L2','PUA_L3','PUA_L4','PUA_KEYWORDS','PUA_FLAVOR_INSTRUCTION','PUA_METHODOLOGY']:
        print(f'{v}={b64(\"\")}')
" "$raw_flavor" "$flavors_json" "$zh_flag" 2>/dev/null || echo "")

  # Decode base64 values into shell variables.
  # 安全审计修复：原实现把解码结果拼成 shell 语句再 eval（构造的 flavors.json
  # 可注入任意命令）。现改为：白名单键名逐个 case 赋值，解码值只作为普通
  # 字符串数据使用，绝不作为 shell 代码求值。
  PUA_ICON="" PUA_L1="" PUA_L2="" PUA_L3="" PUA_L4=""
  PUA_KEYWORDS="" PUA_FLAVOR_INSTRUCTION="" PUA_METHODOLOGY=""
  if [ -n "$_flavor_vars" ]; then
    while IFS='=' read -r key b64val; do
      [ -z "$key" ] && continue
      decoded="$(printf '%s' "$b64val" | base64 -d 2>/dev/null || printf '')"
      case "$key" in
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
}
