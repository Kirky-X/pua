#!/usr/bin/env bash
# Test: validate YAML frontmatter in all SKILL.md files (#147)
# Ensures description fields with colons are properly quoted
set -euo pipefail

PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PASS=0
FAIL=0

echo "=== YAML Frontmatter Validation ==="
echo ""

while IFS= read -r file; do
    rel="${file#$PLUGIN_DIR/}"

    frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')
    if [ -z "$frontmatter" ]; then
        echo "  ⚠  SKIP: $rel (no frontmatter)"
        continue
    fi

    desc_line=$(echo "$frontmatter" | grep '^description:' || true)
    if [ -z "$desc_line" ]; then
        echo "  ⚠  SKIP: $rel (no description field)"
        continue
    fi

    desc_value="${desc_line#description: }"
    if [[ "$desc_value" == \"*\" ]]; then
        echo "  ✅ PASS: $rel"
        PASS=$((PASS+1))
    elif echo "$desc_value" | grep -q ':'; then
        echo "  ❌ FAIL: $rel — description contains ':' but is NOT quoted"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ PASS: $rel (no colon, quoting optional)"
        PASS=$((PASS+1))
    fi
done < <(find "$PLUGIN_DIR" -name 'SKILL.md' -not -path '*/node_modules/*')

echo ""
echo "==========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
echo "==========================================="

[ "$FAIL" -eq 0 ] || exit 1
