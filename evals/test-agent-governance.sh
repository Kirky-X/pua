#!/usr/bin/env bash
# Static eval for PUA v3.2.7 four-power, context-isolated governance agents.
set -euo pipefail

PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

python3 - "$PLUGIN_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
errors = []

expected = {
    'pua-action-executor': {
        'file': 'agents/pua-action-executor.md',
        'power': 'ACTION_RIGHT',
        'tag': '[PUA-ACTION-REPORT]',
        'must_have_tools': {'Read', 'Grep', 'Glob', 'Bash', 'Edit', 'Write', 'MultiEdit'},
        'must_not_tools': {'Agent', 'SendMessage'},
        'culture': ['Alibaba', 'Musk', 'Pinduoduo'],
        'body_terms': ['agent_proposed_status', 'MUST NOT', 'Claim final completion'],
    },
    'pua-self-reviewer': {
        'file': 'agents/pua-self-reviewer.md',
        'power': 'SELF_EVALUATION_RIGHT',
        'tag': '[PUA-SELF-REVIEW]',
        'must_have_tools': {'Read', 'Grep', 'Glob', 'Bash'},
        'must_not_tools': {'Edit', 'Write', 'MultiEdit', 'Agent', 'SendMessage'},
        'culture': ['Huawei', 'Netflix', 'Jobs'],
        'body_terms': ['Intent drift', 'Verification evidence', 'MUST NOT'],
    },
    'pua-verifier': {
        'file': 'agents/pua-verifier.md',
        'power': 'SCORING_RIGHT',
        'tag': '[PUA-VERIFIER-REPORT]',
        'must_have_tools': {'Read', 'Grep', 'Glob', 'Bash'},
        'must_not_tools': {'Edit', 'Write', 'MultiEdit', 'Agent', 'SendMessage'},
        'culture': ['ByteDance', 'JD', 'Netflix'],
        'body_terms': ['verifier_recommendation', 'final_status_owner', 'MUST NOT'],
    },
    'pua-policy-guardian': {
        'file': 'agents/pua-policy-guardian.md',
        'power': 'ENVIRONMENT_MODIFICATION_RIGHT',
        'tag': '[PUA-POLICY-GATE]',
        'must_have_tools': {'Read', 'Grep', 'Glob', 'Bash'},
        'must_not_tools': {'Edit', 'Write', 'MultiEdit', 'Agent', 'SendMessage'},
        'culture': ['Tencent', 'Amazon', 'Alibaba'],
        'body_terms': ['ask_human', 'deny', 'mechanical_gate_owner', 'MUST NOT'],
    },
}


def parse_frontmatter(text):
    if not text.startswith('---\n'):
        return {}, text
    end = text.find('\n---\n', 4)
    if end == -1:
        return {}, text
    raw = text[4:end]
    body = text[end + 5:]
    fm = {}
    for line in raw.splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        fm[key.strip()] = value.strip().strip('"')
    return fm, body


def tool_set(value):
    return {item.strip().strip('"\'') for item in re.split(r'[,\[\]]+', value or '') if item.strip().strip('"\'')}

for name, spec in expected.items():
    path = root / spec['file']
    if not path.exists():
        errors.append(f'missing agent file: {spec["file"]}')
        continue
    text = path.read_text(encoding='utf-8')
    fm, body = parse_frontmatter(text)
    if fm.get('name') != name:
        errors.append(f'{spec["file"]} name mismatch: {fm.get("name")!r}')
    desc = fm.get('description', '')
    if 'Use this agent when' not in desc:
        errors.append(f'{spec["file"]} description must start with concrete trigger phrase')
    tools = tool_set(fm.get('tools', ''))
    missing_tools = spec['must_have_tools'] - tools
    forbidden_tools = spec['must_not_tools'] & tools
    if missing_tools:
        errors.append(f'{name} missing expected tools: {sorted(missing_tools)}')
    if forbidden_tools:
        errors.append(f'{name} has forbidden tools: {sorted(forbidden_tools)}')
    for term in [spec['power'], spec['tag'], *spec['culture'], *spec['body_terms']]:
        if term not in text:
            errors.append(f'{name} missing required term: {term}')
    if name != 'pua-action-executor' and re.search(r'\b(Edit|Write|MultiEdit)\b', fm.get('tools', '')):
        errors.append(f'{name} should remain read-only in frontmatter tools')
    if 'hidden tests' not in body or 'hidden solutions' not in body:
        errors.append(f'{name} must explicitly reject hidden tests/solutions')

skill = (root / 'skills/pua/SKILL.md').read_text(encoding='utf-8')
ref = (root / 'skills/pua/references/harness-governance.md').read_text(encoding='utf-8')
session = (root / 'hooks/session-restore.sh').read_text(encoding='utf-8')
for term in ['四代理拓扑', 'pua-policy-guardian', 'pua-action-executor', 'pua-self-reviewer', 'pua-verifier', '文化叙事绑定']:
    if term not in skill:
        errors.append(f'SKILL.md missing multi-agent governance term: {term}')
for term in ['四代理上下文隔离拓扑（v3.2.7）', 'Task Contract', 'final verifier_status', '文化叙事绑定', '上下文隔离降低叙事污染']:
    if term not in ref:
        errors.append(f'harness-governance.md missing topology term: {term}')
if 'Multi-Agent Governance Topology' not in session:
    errors.append('session-restore missing multi-agent topology injection')

if errors:
    print('=== Agent governance FAILED ===')
    for err in errors:
        print(' -', err)
    sys.exit(1)

print('=== Agent governance OK ===')
print('agents checked =', len(expected))
print('powers = ACTION_RIGHT, SELF_EVALUATION_RIGHT, SCORING_RIGHT, ENVIRONMENT_MODIFICATION_RIGHT')
PY
