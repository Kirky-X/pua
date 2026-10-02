#!/usr/bin/env bash
# PUA Integrity Guard — PreToolUse anti-cheating gate
# Separates action rights from scoring / verifier / environment-modification rights.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/flavor-helper.sh"
PUA_PY="$(pua_python_cmd 2>/dev/null || true)"
[ -n "$PUA_PY" ] || exit 0
PUA_CONFIG_PY="$(pua_to_python_path "$(pua_config_file)")"
export PUA_CONFIG_PY

TMP_INPUT=$(mktemp)
trap 'rm -f "$TMP_INPUT"' EXIT
cat > "$TMP_INPUT"

"$PUA_PY" - "$TMP_INPUT" <<'PY'
import json
import os
import posixpath
import re
import shlex
import sys
from pathlib import Path

input_path = Path(sys.argv[1])
try:
    data = json.loads(input_path.read_text(encoding='utf-8') or '{}')
except Exception:
    sys.exit(0)

PUA_MARKERS = [
    'PUA ACTIVATED',
    'PUA Always-On',
    'PUA生效',
    '[PUA',
    'pua:pua',
    'pua-loop',
    'Confidence Gate',
]


def read_text_tail(path: str, max_bytes: int = 200_000) -> str:
    try:
        p = Path(path).expanduser()
        if not p.is_file():
            return ''
        size = p.stat().st_size
        with p.open('rb') as f:
            if size > max_bytes:
                f.seek(size - max_bytes)
            return f.read().decode('utf-8', errors='ignore')
    except Exception:
        return ''


def config_always_on() -> bool:
    cfg = os.environ.get('PUA_CONFIG_PY') or os.environ.get('PUA_CONFIG') or str(Path.home() / '.pua' / 'config.json')
    try:
        return bool(json.loads(Path(cfg).expanduser().read_text(encoding='utf-8')).get('always_on', False))
    except Exception:
        return False


def is_active() -> bool:
    if os.environ.get('PUA_INTEGRITY_FORCE') == '1' or os.environ.get('PUA_FORCE_ON') == '1':
        return True
    if config_always_on():
        return True
    transcript = data.get('transcript_path') or ''
    text = read_text_tail(transcript)
    return any(marker in text for marker in PUA_MARKERS)

if not is_active():
    sys.exit(0)

tool = data.get('tool_name') or ''
tool_input = data.get('tool_input') or {}

# Keep these patterns intentionally conservative: they target governance assets,
# not ordinary application files.
PROTECTED_WRITE_PATTERNS = [
    (re.compile(r'(^|/)(tests?|__tests__|test|spec|evals?|e2e|cypress|playwright)(/|$)|\.(test|spec)\.[A-Za-z0-9]+$|(^|/)(playwright|cypress)\.config\.', re.I), 'Grader gaming risk: tests/evals/E2E assets are scoring-adjacent.'),
    (re.compile(r'(^|/)(score|scoring|grader|verifier)(\.[A-Za-z0-9]+)?$|(^|/)(scoring|grader|verifier)(/|$)', re.I), 'Grader gaming risk: scoring/verifier assets must not be changed by the executor.'),
    (re.compile(r'(^|/)\.github/workflows(/|$)|(^|/)ci(/|$)|(^|/)(buildkite|circleci|jenkins)(/|$)', re.I), 'Environment-modification risk: CI gates are part of the verifier boundary.'),
    (re.compile(r'(^|/)(feature_contracts\.json|claude-progress\.md|progress\.json|status\.json)$', re.I), 'Self-report cheating risk: status/progress files need verifier ownership.'),
    (re.compile(r'(^|/)(memory|memories)(/|$)|(^|/)(decisions|failures)\.log\.jsonl$|(^|/)CLAUDE\.md$|(^|/)\.claude/(settings|settings\.local)\.json$', re.I), 'Persistent-memory risk: long-term memory/status must be append-only or approved.'),
    (re.compile(r'(^|/)\.env(\.|$)|(^|/)(secrets?|credentials?)(\.|/|$)', re.I), 'Capability-abuse risk: secrets and environment files require human gate.'),
]

CONTAMINATION_PATTERNS = [
    (re.compile(r'(^|/)(hidden[-_]?tests?|verifier[-_]?private|private[-_]?verifier|hidden[-_]?cases?)(/|$)', re.I), 'Solution contamination risk: hidden tests/verifier-private assets must stay outside the agent workspace.'),
    (re.compile(r'(^|/)(hidden_solution|gold_patch|golden_patch|benchmark_answers?|answer_key|official_solution)(\.|/|$)', re.I), 'Solution contamination risk: hidden solution / benchmark answer artifact detected.'),
]

# Oracle isolation: loop/pressure state files are owned by the verifier (hooks),
# not the agent. Hits are hard denies — setup-pua-loop.sh promises "Claude CANNOT
# bypass the Oracle", and that only holds if the gate state cannot be sed/rm'd.
GOVERNANCE_REASON = 'Oracle isolation: loop/pressure state is verifier-owned; agent self-modification would invalidate the gate.'

GOVERNANCE_STATE_PATTERNS = [
    # Directory-level coverage comes FIRST on purpose: `rm -rf ~/.pua`,
    # `rm ~/.claude/pua/loop-*.md` (glob), and `mv ~/.claude/pua` never match
    # per-file patterns, but they all contain the governance directory itself.
    # Whole-dir deny is safe: reads stay exempt (commands/diagnose.md), and the
    # agent has no legitimate write under either directory.
    (re.compile(r'(^|/)\.claude/pua(/|$)', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)\.pua(/|$)', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)\.claude/pua-loop\.local\.md$', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)pua/loop-[0-9a-f]{1,16}\.md$', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)pua/loop-active\.md$', re.I), GOVERNANCE_REASON),
    # Async Oracle settlement artifacts (pua-loop-hook.sh writes
    # verify-<cwd-hash>.{pending,result,out}: hash is `md5sum | cut -c1-8`).
    # A forged "0" in .result would settle a rejected promise as PASS.
    (re.compile(r'(^|/)pua/verify-[0-9a-f]{1,16}\.(result|out|pending)$', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)pua/archived(/|$)', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)\.pua/(sessions?|state)(/|$)', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)\.pua/(builder-journal\.md|loop-memory\.json|config\.json)$', re.I), GOVERNANCE_REASON),
    # churn-gate state: churn-<SAFE_SESSION>.json, SAFE_SESSION is tr -c 'A-Za-z0-9._-'.
    (re.compile(r'(^|/)\.pua/churn-[A-Za-z0-9._-]+\.json$', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)\.pua/\.hooks_degraded$', re.I), GOVERNANCE_REASON),
    # audit trail is audit.jsonl (integrity-guard); failure trail is errors.log
    # (failure-detector/churn-gate/test-first via pua_append_error_log).
    (re.compile(r'(^|/)\.pua/(audit\.jsonl|errors\.log)$', re.I), GOVERNANCE_REASON),
    # pua-loop-hook.sh writes the orphan-archive log to pua/loop-history.jsonl
    # (primary) and .claude/pua-loop-history.jsonl (fallback); cover both.
    (re.compile(r'(^|/)pua/loop-history\.jsonl$', re.I), GOVERNANCE_REASON),
    (re.compile(r'(^|/)pua-loop-history\.jsonl$', re.I), GOVERNANCE_REASON),
]

# Path cores for redirect/tee interception: `> path`, `>> path`, `tee path` put
# the governance file in a redirect target, which never shows up as an argv
# path candidate. Same approach as prove_it's libexec/guard-config
# (>\s*\S*<literal> | tee\s+.*<literal>).
GOVERNANCE_REDIRECT_CORES = [
    r'\.claude/pua(?:/|$)',
    r'\.pua(?:/|$)',
    r'pua-loop\.local\.md',
    r'pua/loop-[0-9a-f]{1,16}\.md',
    r'pua/loop-active\.md',
    r'pua/verify-[0-9a-f]{1,16}\.(?:result|out|pending)',
    r'pua/archived(?:/|$)',
    r'pua/loop-history\.jsonl',
    r'\.pua/(?:sessions?|state)(?:/|$)',
    r'\.pua/(?:builder-journal\.md|loop-memory\.json|config\.json)',
    r'\.pua/churn-[A-Za-z0-9._-]+\.json',
    r'\.pua/\.hooks_degraded',
    r'\.pua/(?:audit\.jsonl|errors\.log)',
    r'pua-loop-history\.jsonl',
]


def governance_redirect_hit(command: str):
    normalized = command.replace('\\', '/')
    for core in GOVERNANCE_REDIRECT_CORES:
        m = re.search(r'(>>|>)\s*\S*' + core, normalized, re.I)
        if m:
            return m.group(0)
        m = re.search(r'\btee\s+.*' + core, normalized, re.I | re.S)
        if m:
            return m.group(0)
    return None


def append_audit(tool: str, target: str, decision: str, reason: str) -> None:
    # Log-only deny audit trail. Never blocks the hook: any failure is silent.
    try:
        from datetime import datetime, timezone
        audit_dir = Path.home() / '.pua'
        audit_dir.mkdir(parents=True, exist_ok=True)
        entry = {
            'ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'tool': tool,
            'command_or_path': str(target)[:300],
            'decision': decision,
            'reason': str(reason)[:160],
        }
        with (audit_dir / 'audit.jsonl').open('a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    except Exception:
        pass

SENSITIVE_READ_PATTERNS = [
    (re.compile(r'(^|/)\.env(\.|$)|(^|/)(secrets?|credentials?)(\.|/|$)|(^|/)(id_rsa|id_ed25519|private[-_]?key)(\.|$)', re.I), 'Capability-abuse risk: secrets and credentials require human gate.'),
]

MUTATING_BASH = re.compile(
    # Redirect to /dev/null (`>/dev/null`, `2>/dev/null`) writes nothing and
    # must not count as mutating — commands/diagnose.md reads state files with
    # `cat ~/.pua/state/CURRENT.md 2>/dev/null`.
    r'(^|[;&|()\s])(rm|mv|cp|chmod|chown|truncate|tee|touch|mkdir|rmdir|git\s+(reset|clean|checkout|restore)|sed\s+(-i|--in-place)|perl\s+-p?i|python3?\s+.*open\(|node\s+.*writeFile|npm\s+version)\b|>>|\d?>\s*(?!/dev/null\b)[^&]',
    re.I | re.S,
)
READING_BASH = re.compile(r'(^|[;&|()\s])(cat|less|more|head|tail|sed|awk|grep|rg|find|python3?|node)\b', re.I)
WEB_CONTAMINATION = re.compile(r'(hidden[-_\s]+solution|official[-_\s]+solution|gold[-_\s]+patch|benchmark[-_\s]+answer|swe[-_\s]?bench[-_\s]+solution|leaderboard[-_\s]+answer)', re.I)

# Binaries that only ever read their argv targets. Reading governance state is
# legitimate (commands/diagnose.md requires `cat ~/.pua/state/CURRENT.md`), so
# the unconditional governance deny below exempts pure reads. Everything not in
# this set that touches a governance path is denied: MUTATING_BASH is a
# deliberately narrow dictionary (dd/install/rsync/ln/scp/python shutil.copy
# are all absent), so governance enforcement must not depend on it.
READ_ONLY_COMMANDS = frozenset({
    'cat', 'less', 'more', 'head', 'tail', 'tailf', 'ls', 'stat', 'file', 'wc',
    'grep', 'egrep', 'fgrep', 'rg', 'ag', 'jq', 'echo', 'printf', 'pwd',
    'test', '[', '[[', 'type', 'which', 'basename', 'dirname', 'readlink',
    'realpath', 'du', 'df', 'diff', 'cmp', 'cut', 'tr', 'uniq', 'md5sum',
    'sha1sum', 'sha256sum', 'sha512sum', 'cksum', 'xxd', 'od', 'hexdump',
    'strings', 'tree', 'whoami', 'id', 'uname', 'date', 'sleep', 'true',
    'false', 'printenv', 'find',
})
# `find` reads its argv targets, but -delete/-exec/-fprint mutate the
# filesystem, so those flags revoke the read-only status.
FIND_WRITE_FLAGS = re.compile(r'-(?:delete|exec|execdir|ok|okdir|fprint0|fprintf|fprint)\b', re.I)


def is_read_only_command(command: str) -> bool:
    # Command substitution (`$(...)`, `<(...)`, backticks) hides arbitrary
    # writers from segment splitting: `echo $(dd of=<governance>)` would
    # inherit echo's read status. Subshell content is never trusted as read-only.
    if re.search(r'\$\(|<\(|`', command):
        return False
    if is_mutating_command(command):
        return False
    if FIND_WRITE_FLAGS.search(command):
        return False
    # Every pipeline/compound segment must start with a read-only command:
    # `cat a && dd of=<governance>` must not inherit cat's read status.
    for segment in re.split(r'\|\||&&|[;|&\n]', command):
        tokens = [t for t in command_tokens(segment) if t]
        if not tokens:
            continue
        first = tokens[0].strip('"\'').rsplit('/', 1)[-1].lower()
        if first not in READ_ONLY_COMMANDS:
            return False
    return True


def is_mutating_command(command: str) -> bool:
    if MUTATING_BASH.search(command):
        return True
    # Python one-liners often hide writes inside quoted code, so detect common
    # write APIs separately instead of relying on shell-token boundaries.
    return bool(re.search(r'python3?\s+.*(open\(|write_text\(|write_bytes\(|Path\([^)]*\)\.write)', command, re.I | re.S))


def norm_path(p: str) -> str:
    if not p:
        return ''
    n = p.replace('\\', '/')
    try:
        # Collapse `.`, `..` and duplicate separators so `.pua/./state/` or
        # `.pua/x/../state/` cannot slip past the governance regexes.
        n = posixpath.normpath(n)
    except Exception:
        pass
    return n


def collect_paths(value):
    paths = []
    if isinstance(value, dict):
        for k, v in value.items():
            if k in {'file_path', 'path', 'notebook_path', 'pattern', 'glob'} and isinstance(v, str):
                paths.append(v)
            else:
                paths.extend(collect_paths(v))
    elif isinstance(value, list):
        for item in value:
            paths.extend(collect_paths(item))
    return paths


def find_reason_for_path(path: str, include_write: bool):
    n = norm_path(path)
    for rx, reason in CONTAMINATION_PATTERNS:
        if rx.search(n):
            return 'deny', reason, n
    for rx, reason in SENSITIVE_READ_PATTERNS:
        if rx.search(n):
            return 'advisory', reason, n
    if include_write:
        for rx, reason in GOVERNANCE_STATE_PATTERNS:
            if rx.search(n):
                return 'deny', reason, n
        for rx, reason in PROTECTED_WRITE_PATTERNS:
            if rx.search(n):
                return 'advisory', reason, n
    return None


def command_tokens(command: str):
    try:
        return shlex.split(command)
    except Exception:
        return re.split(r'\s+', command)


def looks_like_path(s: str) -> bool:
    # A real path has a directory separator or a file-extension suffix; bare
    # identifiers like the shell `eval` builtin do not, and must not be matched
    # against (^|/)(evals?|tests?|spec|...)(/|$) as if they were paths.
    if '/' in s or '\\' in s:
        return True
    return bool(re.search(r'\.[A-Za-z0-9]+$', s))


def path_candidates(tokens):
    for token in tokens:
        if not token:
            continue
        stripped = token.strip("\"'`")
        if stripped and looks_like_path(stripped):
            yield stripped
        # Pull paths embedded inside code strings, e.g. open("tests/fixtures.json", "w").
        for match in re.findall(r'[A-Za-z0-9_.@+~:-]+(?:/[A-Za-z0-9_.@+~:-]+)+', token.replace('\\', '/')):
            yield match


SSH_IDENTITY_RE = re.compile(r'\bssh\b.*-i\s', re.I)
SSH_KEY_PATH_RE = re.compile(r'(^|/)\.ssh/(id_|.*[-_]key)', re.I)


def is_ssh_identity_usage(command: str, candidate: str) -> bool:
    if not SSH_IDENTITY_RE.search(command):
        return False
    return bool(SSH_KEY_PATH_RE.search(norm_path(candidate)))


def command_hits(command: str):
    tokens = [t for t in command_tokens(command) if t]
    candidates = list(path_candidates(tokens))
    # normpath the whole command so `.pua//x`, `.pua/./x` and `.pua/a/../x`
    # spellings hit the same governance regexes as their canonical form.
    normalized = posixpath.normpath(command.replace('\\', '/'))

    # Hidden/private solution artifacts are blocked even for read-like commands.
    for candidate in candidates:
        for rx, reason in CONTAMINATION_PATTERNS:
            if rx.search(norm_path(candidate)):
                return 'deny', reason, candidate
    for rx, reason in CONTAMINATION_PATTERNS:
        m = rx.search(normalized)
        if m:
            return 'deny', reason, m.group(0)
    if WEB_CONTAMINATION.search(command):
        return 'deny', 'Solution contamination risk: command appears to search/fetch benchmark or hidden answers.', command[:160]
    if READING_BASH.search(command):
        for candidate in candidates:
            if is_ssh_identity_usage(command, candidate):
                continue
            for rx, reason in SENSITIVE_READ_PATTERNS:
                if rx.search(norm_path(candidate)):
                    return 'advisory', reason, candidate

    # Oracle-owned governance state: hard deny. These checks are unconditional —
    # MUTATING_BASH misses dd/install/rsync/ln/scp/python shutil.copy, so gating
    # them on is_mutating_command() would leave the whole governance layer
    # bypassable. Pure reads (READ_ONLY_COMMANDS) stay exempt; checks run in the
    # same order as before: argv path candidates, raw command, redirect/tee
    # targets (`> path`, `>> path`, `cmd | tee path`).
    if not is_read_only_command(command):
        for candidate in candidates:
            for rx, reason in GOVERNANCE_STATE_PATTERNS:
                if rx.search(norm_path(candidate)):
                    return 'deny', reason, candidate
        for rx, reason in GOVERNANCE_STATE_PATTERNS:
            m = rx.search(normalized)
            if m:
                return 'deny', reason, m.group(0)
        redirect_target = governance_redirect_hit(normalized)
        if redirect_target:
            return 'deny', GOVERNANCE_REASON, redirect_target

    # Protected scoring assets need a human gate only when the command mutates them.
    if is_mutating_command(command):
        for candidate in candidates:
            for rx, reason in PROTECTED_WRITE_PATTERNS:
                if rx.search(norm_path(candidate)):
                    return 'advisory', reason, candidate
        for rx, reason in PROTECTED_WRITE_PATTERNS:
            m = rx.search(normalized)
            if m:
                return 'advisory', reason, m.group(0)
    return None

hit = None

if tool in {'Write', 'Edit', 'MultiEdit'}:
    for path in collect_paths(tool_input):
        hit = find_reason_for_path(path, include_write=True)
        if hit:
            break
elif tool in {'Read', 'Grep', 'Glob'}:
    for path in collect_paths(tool_input):
        hit = find_reason_for_path(path, include_write=False)
        if hit:
            break
elif tool == 'Bash':
    command = str(tool_input.get('command') or '')
    hit = command_hits(command)
elif tool in {'WebSearch', 'WebFetch'}:
    query = '\n'.join(str(tool_input.get(k) or '') for k in ('query', 'url', 'prompt'))
    if WEB_CONTAMINATION.search(query):
        hit = ('deny', 'Solution contamination risk: searching for benchmark/hidden answers can poison the task.', query[:160])

if not hit:
    sys.exit(0)

decision, reason, target = hit

if decision == 'deny':
    append_audit(tool, target, decision, reason)

message = (
    'PUA Integrity Guard: ' + reason +
    ' Four-power separation is active: action right, self-evaluation right, scoring right, and environment-modification right must remain separate. '
    f'Target: {target}'
)
if decision == 'deny':
    message += ' 如确需修改：请在终端手动执行（不要通过 agent）。'

output = {'hookSpecificOutput': {'hookEventName': 'PreToolUse'}}
if decision == 'deny':
    output['hookSpecificOutput']['permissionDecision'] = 'deny'
    output['hookSpecificOutput']['permissionDecisionReason'] = message
    output['hookSpecificOutput']['additionalContext'] = (
        'PUA Integrity Guard: DENY — ' + reason + f' Target: {target} 如确需修改：请在终端手动执行（不要通过 agent）。'
    )
else:
    output['hookSpecificOutput']['additionalContext'] = (
        'PUA Integrity Guard (advisory): ' + reason + f' Target: {target}'
    )
print(json.dumps(output, ensure_ascii=False, separators=(',', ':')))
PY
