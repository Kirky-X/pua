#!/bin/bash
# PUA state snapshot hook (command-type) — deterministic compaction state writer.
# Replaces the prompt-only PreCompact hook: instead of asking the model to write
# ~/.pua/builder-journal.md (state is lost when the model skips it), this hook
# snapshots verifiable state to ~/.pua/state/CURRENT.md on every compaction.
# Contract: fail-open. Any failure degrades explicitly via ~/.pua/.hooks_degraded
# and exits 0 — a crashing hook must never block compaction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flavor-helper.sh" || exit 0

PUA_HOME="$(pua_home_dir)/.pua"
STATE_DIR="${PUA_HOME}/state"
DEGRADED_FILE="${PUA_HOME}/.hooks_degraded"

degrade() {
  { mkdir -p "${PUA_HOME}" && printf '%s state-snapshot: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$DEGRADED_FILE"; } 2>/dev/null || true
  exit 0
}

PY="$(pua_python_cmd 2>/dev/null)" || degrade "no usable python for JSON parsing"

INPUT_FILE="$(mktemp 2>/dev/null)" || degrade "mktemp failed"
cleanup() { rm -f "$INPUT_FILE" 2>/dev/null || true; }
trap cleanup EXIT

# Hook payload may be absent (manual run) or empty; all JSON fields are optional.
if [ -t 0 ]; then
  printf '{}\n' > "$INPUT_FILE"
else
  cat > "$INPUT_FILE" 2>/dev/null || true
  [ -s "$INPUT_FILE" ] || printf '{}\n' > "$INPUT_FILE"
fi

get_flavor >/dev/null 2>&1 || true
FLAVOR="${PUA_FLAVOR:-unknown}"
SUBCOMMAND="${1:-}"

"$PY" - "$PUA_HOME" "$STATE_DIR" "$DEGRADED_FILE" "$INPUT_FILE" "$FLAVOR" "$SUBCOMMAND" <<'PYEOF'
import collections
import datetime
import json
import math
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
from collections import Counter

PUA_HOME = pathlib.Path(sys.argv[1])
STATE_DIR = pathlib.Path(sys.argv[2])
DEGRADED_FILE = pathlib.Path(sys.argv[3])
INPUT_FILE = pathlib.Path(sys.argv[4])
FLAVOR = sys.argv[5]
SUBCOMMAND = sys.argv[6]

CURRENT = STATE_DIR / "CURRENT.md"
SNAPSHOTS_DIR = STATE_DIR / "snapshots"
EVENTS_DIR = STATE_DIR / "events"
JOURNAL = PUA_HOME / "builder-journal.md"


def degrade(reason):
    # 显性降级：原因必须落盘，SessionStart 恢复时会向用户宣告，绝不静默丢失。
    try:
        DEGRADED_FILE.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with DEGRADED_FILE.open("a", encoding="utf-8") as fh:
            fh.write("%s state-snapshot: %s\n" % (ts, redact(reason)))
    except OSError:
        pass
    sys.exit(0)


def read_input():
    try:
        raw = INPUT_FILE.read_text(encoding="utf-8", errors="replace")
        data = json.loads(raw) if raw.strip() else {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


# ── Redaction ────────────────────────────────────────────────────────────────
# 硬约束：脱敏先于落盘。所有内容（compact summary、transcript 尾部、git status、
# runtime 状态、降级原因）写入 CURRENT.md / 快照 / 事件行之前必须经过 redact()。
_PURE_HEX_RE = re.compile(r"^[0-9a-fA-F]+$")
_HIGH_ENTROPY_TOKEN_RE = re.compile(r"[A-Za-z0-9+/=_\-]{32,}")
# 高价值形态对照 sanitize-session.sh 的已审正则表内联同步（JWT/Bearer/AIza/npm_/
# LTAI/PEM 私钥块）。不直接共享那张表，是因为 sanitize-session.sh 是行为稳定、
# 已过安全审查的独立工具（上传前手动清洗路径），本 hook 不改动它，以免扰动已审
# 行为；两表在此按值同步，各自演进时以各自的审查为准。
_KNOWN_SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{16,}"),
    re.compile(r"gh[po]_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"AKIA[A-Z0-9]{16}"),
    re.compile(r"xox[baprs]\-[A-Za-z0-9\-]+"),
    re.compile(r"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"),
    re.compile(r"AIza[0-9A-Za-z_\-]{35}"),
    re.compile(r"npm_[A-Za-z0-9]{36}"),
    re.compile(r"LTAI[A-Za-z0-9]{16,20}"),
    re.compile(r"(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"),
]
# Authorization/Bearer 头：保留 "Bearer " 前缀维持快照可读性，仅抹掉头值。
# 放在已知形态之后执行——"Bearer <JWT>" 先被三段式整段替换，此处不再命中。
_BEARER_HEADER_RE = re.compile(r"(?i)(bearer\s+)[A-Za-z0-9_./\-]{10,}")


def _shannon_entropy(s):
    n = len(s)
    freq = Counter(s)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


def redact(text):
    if not text:
        return ""
    text = str(text)
    for pattern in _KNOWN_SECRET_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    text = _BEARER_HEADER_RE.sub(r"\1[REDACTED]", text)

    def _sub(match):
        token = match.group()
        if _PURE_HEX_RE.match(token):
            # 随机纯 hex 实测熵 3.4-4.0，4.1 阈值下全部漏网；≥40 位的纯 hex 直接
            # 替换。代价是 git full hash（恰为 40 位 hex）会被误伤，但快照是给
            # compaction 恢复用的，完整 hash 无恢复价值，而 40 位 hex 形态的密钥
            # 泄漏风险更大。32-39 位 hex 仍走熵判定，保住 git 短 hash/UUID。
            if len(token) >= 40:
                return "[REDACTED]"
            threshold = 4.1
        else:
            # 非 hex 高熵串（base64 等）理论熵更高，3.5 已足够保守。
            threshold = 3.5
        return "[REDACTED]" if _shannon_entropy(token) > threshold else token

    return _HIGH_ENTROPY_TOKEN_RE.sub(_sub, text)


def truncate(text, limit):
    t = str(text or "").strip()
    if len(t) <= limit:
        return t
    return t[:limit].rstrip() + "\n...[truncated]"


def extract_text(value, depth=0):
    if depth > 4 or value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = [extract_text(v, depth + 1) for v in value]
        return "\n".join(p for p in parts if p)
    if isinstance(value, dict):
        if value.get("type") == "tool_result":
            return ""
        if isinstance(value.get("text"), str):
            return value["text"]
        for key in ("content", "message"):
            if key in value:
                nested = extract_text(value[key], depth + 1)
                if nested:
                    return nested
    return ""


TRANSCRIPT_TAIL_BYTES = 262144


def last_transcript_message(path_value, limit=120):
    if not path_value:
        return ""
    transcript = pathlib.Path(path_value)
    if not transcript.is_file():
        return ""
    lines = collections.deque(maxlen=limit)
    try:
        size = transcript.stat().st_size
        # 大文件只读尾部 256KB：为取末 120 行迭代整个文件，500MB transcript 会逼近
        # hook timeout。seek 落点落在行中间时先丢弃截断的半行；文件不大于窗口时
        # 从头读，行为与全文件迭代一致。
        with transcript.open("rb") as fh:
            if size > TRANSCRIPT_TAIL_BYTES:
                fh.seek(size - TRANSCRIPT_TAIL_BYTES)
                fh.readline()
            for raw in fh.read().split(b"\n"):
                if raw:
                    lines.append(raw.decode("utf-8", errors="replace"))
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            item = json.loads(line)
        except Exception:
            continue
        if not isinstance(item, dict):
            continue
        message = item.get("message") if isinstance(item.get("message"), dict) else item
        role = message.get("role") or item.get("type") or ""
        if role not in ("user", "assistant"):
            continue
        text = extract_text(message.get("content"))
        if text:
            return text
    return ""


def git_status(root):
    try:
        result = subprocess.run(
            ["git", "status", "--short"],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""
    return result.stdout.decode("utf-8", errors="replace").strip()


def pua_runtime_lines(session_id):
    lines = []
    if session_id and "/" not in session_id and ".." not in session_id:
        session_file = PUA_HOME / "sessions" / (session_id + ".json")
        if session_file.is_file():
            try:
                data = json.loads(session_file.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    # failure-detector 的会话状态键是 count/score/peak_level（无 level）。
                    bits = ["%s=%s" % (k, data[k]) for k in ("count", "score", "peak_level") if k in data]
                    if bits:
                        lines.append("session state: " + ", ".join(bits))
            except Exception:
                pass
    loop_memory = PUA_HOME / "loop-memory.json"
    if loop_memory.is_file():
        try:
            data = json.loads(loop_memory.read_text(encoding="utf-8"))
            # loop-memory.json 顶层是 {"patterns": {...}}，条目数按 patterns 计；
            # 旧版/畸形的 list 形态按自身长度兜底。
            if isinstance(data, dict):
                lines.append("loop-memory entries: %d" % len(data.get("patterns", {})))
            elif isinstance(data, list):
                lines.append("loop-memory entries: %d" % len(data))
        except Exception:
            pass
    lines.append("flavor: " + FLAVOR)
    return lines


def legacy_journal_section():
    if not JOURNAL.is_file():
        return ""
    try:
        mtime = JOURNAL.stat().st_mtime
    except OSError:
        return ""
    if time.time() - mtime > 2 * 3600:
        return ""
    try:
        content = JOURNAL.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return "\n".join(content.splitlines()[:50]).strip()


def build_markdown(input_data):
    now = datetime.datetime.now(datetime.timezone.utc)
    event = input_data.get("hook_event_name") or SUBCOMMAND or "snapshot"
    session_id = str(input_data.get("session_id") or "unknown")
    source = str(input_data.get("source") or "")
    compact_summary = str(input_data.get("compact_summary") or "").strip()
    compact = truncate(compact_summary, 3500) if compact_summary else "none recorded"
    transcript_tail = truncate(last_transcript_message(input_data.get("transcript_path") or ""), 2000) or "none captured"
    status = git_status(os.getcwd())
    journal = legacy_journal_section()

    sections = [
        "# PUA State Snapshot",
        "",
        "generated_at: " + now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "event: " + str(event),
        "session_id: " + session_id,
    ]
    if source:
        sections.append("source: " + source)
    sections.append("flavor: " + FLAVOR)
    sections.extend([
        "",
        "## Compact Summary",
        compact,
        "",
        "## Last Transcript Message",
        transcript_tail,
        "",
        "## Git Status",
        "```text",
        status if status else "(not a git repo or clean)",
        "```",
        "",
        "## PUA Runtime State",
    ])
    sections.extend("- " + line for line in pua_runtime_lines(session_id))
    if journal:
        sections.extend([
            "",
            "## Legacy Journal (builder-journal.md, written <2h ago)",
            journal,
        ])
    sections.append("")
    return "\n".join(sections)


def _prune_dir(directory, pattern, keep):
    # 文件名内嵌 UTC 时间戳/日期（快照 %Y%m%dT%H%M%SZ、事件 YYYY-MM-DD），字典序即
    # 时间序；保留最近 keep 份，防每次 compaction 复制一份导致无限累积。
    try:
        files = sorted(directory.glob(pattern))
    except OSError:
        return
    for stale in files[:-keep]:
        try:
            stale.unlink()
        except OSError:
            pass


def prune_state_dirs():
    # 裁剪是维护性清理：失败不丢任何状态（只是没删旧文件），故不计入 degrade——
    # fail-open 契约只覆盖写入路径，写路径失败仍由 errors → degrade 上报。
    _prune_dir(SNAPSHOTS_DIR, "*.md", 20)
    _prune_dir(EVENTS_DIR, "*.jsonl", 30)


def write_outputs(text, event, session_id):
    errors = []
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    # PID-unique tmp：同一 compaction 触发多个 hook 注册点时，避免一个进程的
    # replace 消耗掉另一个进程尚未完成 rename 的 tmp 文件。
    tmp = CURRENT.with_name("CURRENT.%d.tmp" % os.getpid())
    tmp.write_text(text, encoding="utf-8")
    try:
        os.replace(str(tmp), str(CURRENT))
    except (FileNotFoundError, OSError):
        # 并发写冲突：另一写者已把它的 tmp 换入 CURRENT——视为已写，静默放行。
        try:
            tmp.unlink()
        except OSError:
            pass
    now = datetime.datetime.now(datetime.timezone.utc)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    # 折叠分隔符与连续点：/ 换成 - 防目录穿越，.. 折叠防 ..-形态的误导性文件名
    session_slug = re.sub(r"\.{2,}", ".", re.sub(r"[^A-Za-z0-9_.\-]+", "-", session_id))[:80] or "unknown"
    snapshot_path = SNAPSHOTS_DIR / ("%s-%s-%d.md" % (stamp, session_slug, os.getpid()))
    try:
        shutil.copy2(str(CURRENT), str(snapshot_path))
    except OSError:
        errors.append("snapshot archive failed")
    try:
        EVENTS_DIR.mkdir(parents=True, exist_ok=True)
        event_line = {"ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "event": str(event), "session": session_id}
        events_file = EVENTS_DIR / (now.date().isoformat() + ".jsonl")
        with events_file.open("a", encoding="utf-8") as fh:
            fh.write(redact(json.dumps(event_line, ensure_ascii=False)) + "\n")
    except OSError:
        errors.append("event append failed")
    prune_state_dirs()
    return errors


def main():
    input_data = read_input()
    text = redact(build_markdown(input_data))
    event = input_data.get("hook_event_name") or SUBCOMMAND or "snapshot"
    session_id = str(input_data.get("session_id") or "unknown")
    errors = write_outputs(text, event, session_id)
    if errors:
        degrade("; ".join(errors))
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except Exception as exc:
    degrade("%s: %s" % (type(exc).__name__, exc))
PYEOF

# Python 已在失败路径上显性降级；此处无论结果如何都按 hook 契约退出 0。
exit 0
