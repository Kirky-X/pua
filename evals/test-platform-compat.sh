#!/usr/bin/env bash
# Cross-platform packaging gates for Codex + pi.dev adapters.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL+1)); }
assert_file() { local p="$1" n="$2"; [ -f "$ROOT/$p" ] && pass "$n" || fail "$n"; }
assert_grep() { local pat="$1" file="$2" n="$3"; grep -qE "$pat" "$ROOT/$file" && pass "$n" || fail "$n"; }

python_check() {
  python3 - "$ROOT" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
errors = []

# Codex must be a real SKILL.md pack, not only pasteable rules.
for rel, expected_name in [
    ('.codex/skills/pua/SKILL.md', 'pua'),
    ('.codex/skills/pua-en/SKILL.md', 'pua-en'),
    ('.codex/skills/pua-codex/SKILL.md', 'pua-codex'),
]:
    path = root / rel
    if not path.exists():
        errors.append(f'missing {rel}')
        continue
    text = path.read_text(encoding='utf-8')
    if not text.startswith('---\n'):
        errors.append(f'{rel} missing YAML frontmatter')
        continue
    fm = text.split('---', 2)[1]
    if f'name: {expected_name}' not in fm:
        errors.append(f'{rel} name must be {expected_name}')
    if 'description:' not in fm:
        errors.append(f'{rel} missing description')
    body = text.split('---', 2)[2]
    for term in ['行动权', '自我评价权', '评分权', '环境修改权', 'PUA-DIAGNOSIS', '事实上的 100%', '文化叙事']:
        if term not in body:
            errors.append(f'{rel} missing Codex governance/culture term: {term}')

# Codex documentation must tell users both marketplace/CLI and manual paths.
install = (root / 'codex/INSTALL.md').read_text(encoding='utf-8')
for term in ['npx skills add', '--skill pua-codex', '-a codex', '~/.codex/skills/', '~/.codex-cn/skills/', '.codex/skills/']:
    if term not in install:
        errors.append(f'codex install guide missing {term}')

# Difference doc makes the Claude Code vs Codex boundary explicit.
diff = root / 'codex/DIFF.md'
if not diff.exists():
    errors.append('missing codex/DIFF.md')
else:
    diff_text = diff.read_text(encoding='utf-8')
    for term in ['Claude Code', 'Codex', 'hooks', 'commands', 'agents', 'SKILL.md', 'npx skills']:
        if term not in diff_text:
            errors.append(f'codex diff missing {term}')

# pi.dev package must use official package manifest shape.
pkg_path = root / 'pi/package/package.json'
if not pkg_path.exists():
    errors.append('missing pi/package/package.json')
else:
    pkg = json.loads(pkg_path.read_text(encoding='utf-8'))
    if 'pi-package' not in pkg.get('keywords', []):
        errors.append('pi package missing pi-package keyword')
    pi = pkg.get('pi') or {}
    if './extensions/pua/index.ts' not in pi.get('extensions', []):
        errors.append('pi manifest missing ./extensions/pua/index.ts')
    if './skills' not in pi.get('skills', []):
        errors.append('pi manifest missing ./skills')
    peers = pkg.get('peerDependencies', {})
    if peers.get('@earendil-works/pi-coding-agent') != '*':
        errors.append('pi package peerDependencies must include @earendil-works/pi-coding-agent:*')

for rel in ['pi/package/extensions/pua/index.ts', 'pi/package/skills/pua/SKILL.md', 'pi/package/README.md']:
    if not (root / rel).exists():
        errors.append(f'missing {rel}')

if errors:
    print('=== Platform compat FAILED ===')
    for e in errors:
        print(' -', e)
    sys.exit(1)
print('=== Platform compat static OK ===')
PY
}

echo "=== Platform Compatibility Gates ==="
python_check && pass "Codex + pi.dev package structure is valid" || fail "Codex + pi.dev package structure is valid"

if [ -f "$ROOT/pi/package/package.json" ]; then
  (cd "$ROOT/pi/package" && npm pack --dry-run --json >/tmp/pua-pi-pack.json) && pass "pi package can be packed by npm" || fail "pi package can be packed by npm"
else
  fail "pi package can be packed by npm"
fi

echo "======================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "======================================"
[ "$FAIL" -eq 0 ] || exit 1
